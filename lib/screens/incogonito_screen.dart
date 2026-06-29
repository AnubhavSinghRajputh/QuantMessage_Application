// lib/screens/incognito_screen.dart

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/gestures.dart';        // ← FIX: added this
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/app_theme.dart';
import '../core/chat_message.dart';
import '../core/attachment_model.dart';
import '../services/quant_space_api.dart';
import '../services/upload_service.dart';
import 'widgets/attachment_preview.dart';
import 'widgets/attachment_thumbnail.dart';
import 'widgets/attachment_picker_sheet.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  Main Screen
// ═══════════════════════════════════════════════════════════════════════════

class IncognitoScreen extends StatefulWidget {
  const IncognitoScreen({super.key});

  @override
  State<IncognitoScreen> createState() => _IncognitoScreenState();
}

class _IncognitoScreenState extends State<IncognitoScreen>
    with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final QuantSpaceApi _api = QuantSpaceApi();
  final UploadService _uploader = UploadService();
  final FocusNode _inputFocus = FocusNode();

  final List<ChatMessage> _messages = [];
  bool _isTyping = false;

  final List<Attachment> _pendingAttachments = [];
  String? _ephemeralSessionId;

  late final AnimationController _inputFocusCtrl;
  late final Animation<double> _inputGlow;
  late final AnimationController _sendBtnCtrl;
  late final Animation<double> _sendBtnScale;
  late final AnimationController _emptyCtrl;
  late final Animation<double> _emptyOpacity;
  late final Animation<double> _emptyScale;

  @override
  void initState() {
    super.initState();
    _inputFocusCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 260));
    _inputGlow =
        CurvedAnimation(parent: _inputFocusCtrl, curve: Curves.easeOut);
    _inputFocus.addListener(() {
      _inputFocus.hasFocus
          ? _inputFocusCtrl.forward()
          : _inputFocusCtrl.reverse();
    });

    _sendBtnCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 110),
        lowerBound: 0.0,
        upperBound: 1.0);
    _sendBtnScale = Tween<double>(begin: 1.0, end: 0.86).animate(
        CurvedAnimation(parent: _sendBtnCtrl, curve: Curves.easeInOut));

    _emptyCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 650));
    _emptyOpacity =
        CurvedAnimation(parent: _emptyCtrl, curve: Curves.easeOut);
    _emptyScale = Tween<double>(begin: 0.96, end: 1.0).animate(
        CurvedAnimation(parent: _emptyCtrl, curve: Curves.easeOutBack));
    _emptyCtrl.forward();

    _generateEphemeralId();
  }

  void _generateEphemeralId() {
    _ephemeralSessionId =
    'ghost_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(9999)}';
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    _inputFocusCtrl.dispose();
    _sendBtnCtrl.dispose();
    _emptyCtrl.dispose();
    super.dispose();
  }

  // ── Attachment handlers ──────────────────────────────────────────────────
  Future<void> _onAttachmentButtonPressed() async {
    await AttachmentPickerSheet.show(
      context,
      onSelected: _addAttachment,
    );
  }

  void _addAttachment(File file, String mimeType) {
    final attachment = AttachmentX.fromFile(file, mimeOverride: mimeType);
    setState(() => _pendingAttachments.add(attachment));
  }

  void _removePendingAttachment(int index) {
    setState(() => _pendingAttachments.removeAt(index));
  }

  Future<void> _handleSend() async {
    final text = _controller.text.trim();
    final hasAttachments = _pendingAttachments.isNotEmpty;
    if ((text.isEmpty && !hasAttachments) || _isTyping) return;

    _emptyCtrl.reset();

    final pendingSnapshot = List<Attachment>.from(_pendingAttachments);
    setState(() {
      _messages.add(ChatMessage(
        text: text,
        isUser: true,
        attachments: pendingSnapshot,
      ));
      _isTyping = true;
      _pendingAttachments.clear();
    });
    _controller.clear();
    _scrollToBottom();

    try {
      final uploaded = <Attachment>[];
      for (final att in pendingSnapshot) {
        if (att.isReady) {
          uploaded.add(att);
        } else if (att.localFile != null) {
          final result = await _uploader.uploadFile(
            file: att.localFile!,
            conversationId: _ephemeralSessionId!,
            onProgress: (p) {
              if (!mounted) return;
              setState(() {
                final i = _pendingAttachments.indexOf(att);
                if (i != -1) {
                  _pendingAttachments[i] =
                      _pendingAttachments[i].copyWith(progress: p);
                }
              });
            },
          );
          uploaded.add(result);
        }
      }

      final response = await _uploader.sendMessageWithAttachments(
        message: text.isEmpty
            ? 'Please analyze the attached file(s).'
            : text,
        attachments: uploaded,
        conversationId: _ephemeralSessionId,
        isIncognito: true,
      );

      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage(
          text: response['content'] as String? ?? '',
          isUser: false,
          modelName: 'GHOST AI',
        ));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage(
          text: "🚨 **System Error**: ${e.toString()}",
          isUser: false,
        ));
      });
    } finally {
      if (mounted) setState(() => _isTyping = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCirc,
        );
      }
    });
  }

  void _burnSession() {
    setState(() {
      _messages.clear();
      _pendingAttachments.clear();
      _generateEphemeralId();
    });
    _api.resetSession();
    _emptyCtrl.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: AppTheme.backgroundBlack,
      appBar: _buildBlurredAppBar(),
      body: Stack(
        children: [
          const _ParticleBackground(count: 25),

          if (_messages.isEmpty)
            Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 40),
                child: FadeTransition(
                  opacity: _emptyOpacity,
                  child: ScaleTransition(
                    scale: _emptyScale,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildEmptyStateGreeting(),
                        const SizedBox(height: 40),
                        _buildInputBox(),
                        const SizedBox(height: 16),
                        _buildSuggestionPills(),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else
            Column(
              children: [
                Expanded(child: _buildChatThread()),
                Padding(
                  padding: const EdgeInsets.only(
                      bottom: 20, left: 20, right: 20),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: FadeInAnimation(
                      duration: const Duration(milliseconds: 400),
                      child: _buildInputBox(),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildBlurredAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(70),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: AppBar(
            backgroundColor: AppTheme.backgroundBlack.withOpacity(0.6),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white70, size: 18),
              onPressed: () => Navigator.pop(context),
            ),
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.visibility_off_rounded,
                    color: AppTheme.accentGrey, size: 20),
                const SizedBox(width: 8),
                Text("INCOGNITO",
                    style: GoogleFonts.tinos(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppTheme.primaryWhite,
                        letterSpacing: 2.0)),
              ],
            ),
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.delete_sweep_rounded,
                    color: Colors.white38),
                tooltip: "Burn Session",
                onPressed: _burnSession,
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyStateGreeting() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FadeInAnimation(
          duration: const Duration(milliseconds: 600),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Text("Secure Session",
                style: GoogleFonts.tinos(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FadeInAnimation(
              duration: const Duration(milliseconds: 800),
              child: const Icon(Icons.security,
                  color: Color(0xFF6B7280), size: 36),
            ),
            const SizedBox(width: 12),
            TypingText(
              text: "< Gone Incognito >",
              style: GoogleFonts.tinos(
                color: const Color(0xFFE8E8E8),
                fontSize: 55,
                fontWeight: FontWeight.w900,
              ),
              typingSpeed: const Duration(milliseconds: 50),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          constraints: const BoxConstraints(maxWidth: 320),
          child: TypingText(
            text:
            "Ephemeral mode active. Conversations and uploads are end-to-end encrypted and will be purged upon exit.",
            style: GoogleFonts.tinos(
              color: AppTheme.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              height: 1.6,
            ),
            typingSpeed: const Duration(milliseconds: 25),
            delayBeforeStart: const Duration(milliseconds: 900),
          ),
        ),
      ],
    );
  }

  Widget _buildChatThread() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(top: 100, bottom: 20),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        return FadeInAnimation(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          child: _buildMessageRow(_messages[index]),
        );
      },
    );
  }

  Widget _buildMessageRow(ChatMessage msg) {
    final hasAttachments = msg.hasAttachments;
    final hasText = msg.hasText;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: msg.isUser
            ? Colors.transparent
            : AppTheme.surfaceDark.withOpacity(0.5),
        border: Border(
            bottom:
            BorderSide(color: Colors.white.withOpacity(0.05), width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAvatar(
            msg.isUser ? "🕵️" : "👻",
            msg.isUser ? Colors.white24 : AppTheme.accentGrey,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  msg.isUser ? "USER_GHOST" : msg.modelName.toUpperCase(),
                  style: GoogleFonts.tinos(
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                      color: AppTheme.textSecondary,
                      letterSpacing: 1.2),
                ),
                const SizedBox(height: 8),

                if (hasAttachments)
                  AttachmentList(attachments: msg.attachments),

                if (hasText)
                  MarkdownBody(
                    data: msg.text,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet(
                      p: GoogleFonts.tinos(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          height: 1.6,
                          color: AppTheme.textPrimary),
                      h1: GoogleFonts.tinos(
                          color: AppTheme.primaryWhite,
                          fontSize: 20,
                          fontWeight: FontWeight.bold),
                      code: GoogleFonts.tinos(
                        backgroundColor: AppTheme.surfaceMedium,
                        color: AppTheme.accentGrey,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: AppTheme.surfaceMedium,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      blockquote: GoogleFonts.tinos(
                          color: Colors.white60,
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.bold),
                      blockquoteDecoration: const BoxDecoration(
                        border: Border(
                            left: BorderSide(
                                color: AppTheme.accentGrey, width: 3)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(String icon, Color color) {
    return Container(
      height: 36,
      width: 36,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Center(child: Text(icon, style: const TextStyle(fontSize: 18))),
    );
  }

  Widget _buildInputBox() {
    return AnimatedBuilder(
      animation: _inputGlow,
      builder: (_, child) => Container(
        constraints: const BoxConstraints(maxWidth: 800),
        decoration: BoxDecoration(
          color: const Color(0xFF2F2F2F),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Color.lerp(
                Colors.white10, Colors.white24, _inputGlow.value)!,
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 15,
                offset: const Offset(0, 8)),
          ],
        ),
        child: child,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_pendingAttachments.isNotEmpty)
              AttachmentPreviewStrip(
                attachments: _pendingAttachments,
                onRemove: _removePendingAttachment,
              ),

            TextField(
              controller: _controller,
              focusNode: _inputFocus,
              maxLines: 4,
              minLines: 1,
              style: GoogleFonts.tinos(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: _pendingAttachments.isNotEmpty
                    ? "Add a note for the ghost..."
                    : "Transmit encrypted message...",
                hintStyle: GoogleFonts.tinos(
                    color: Colors.white38,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 8),
              ),
              onSubmitted: (_) => _handleSend(),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _AnimatedHoverIcon(
                      icon: Icons.attach_file_rounded,
                      onTap: _onAttachmentButtonPressed,
                    ),
                    const SizedBox(width: 8),
                    _AnimatedHoverIcon(
                      icon: Icons.vpn_key_outlined,
                      onTap: () {},
                    ),
                    const SizedBox(width: 8),
                    _AnimatedHoverIcon(
                      icon: Icons.lock_outline,
                      onTap: () {},
                    ),
                    const SizedBox(width: 12),
                    if (_isTyping)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8.0),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppTheme.accentGrey),
                        ),
                      )
                    else
                      ButtonBulge(
                        onPressed: _handleSend,
                        child: const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Icon(Icons.arrow_upward_rounded,
                              color: Colors.white, size: 20),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionPills() {
    return FadeInAnimation(
      duration: const Duration(milliseconds: 800),
      delay: const Duration(milliseconds: 300),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          _SuggestionPill(Icons.history_toggle_off, "Auto-burn"),
          _SuggestionPill(Icons.shield_outlined, "Trace bypass"),
          _SuggestionPill(Icons.fingerprint, "Ghost IP"),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Suggestion Pill (unchanged)
// ═══════════════════════════════════════════════════════════════════════════

class _SuggestionPill extends StatefulWidget {
  final IconData icon;
  final String label;
  const _SuggestionPill(this.icon, this.label);

  @override
  State<_SuggestionPill> createState() => _SuggestionPillState();
}

class _SuggestionPillState extends State<_SuggestionPill> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: _isHovered
              ? Colors.white.withOpacity(0.1)
              : const Color(0xFF2F2F2F),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: _isHovered ? Colors.white54 : Colors.white10),
        ),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: GoogleFonts.tinos(
            color: _isHovered ? Colors.white : Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon,
                  color: _isHovered ? Colors.white : Colors.white70,
                  size: 16),
              const SizedBox(width: 6),
              Text(widget.label),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimatedHoverIcon extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _AnimatedHoverIcon({required this.icon, required this.onTap});

  @override
  State<_AnimatedHoverIcon> createState() => _AnimatedHoverIconState();
}

class _AnimatedHoverIconState extends State<_AnimatedHoverIcon> {
  @override
  Widget build(BuildContext context) {
    return ButtonBulge(
      onPressed: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(widget.icon, color: Colors.white, size: 20),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Support widgets
// ═══════════════════════════════════════════════════════════════════════════

class _ParticleBackground extends StatelessWidget {
  final int count;
  const _ParticleBackground({required this.count});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.3,
      child: CustomPaint(
          painter: _ChatParticlePainter(0.0, count),
          size: MediaQuery.of(context).size),
    );
  }
}

class _ChatParticlePainter extends CustomPainter {
  final double progress;
  final int count;
  _ChatParticlePainter(this.progress, this.count);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white10;
    final random = math.Random(42);
    for (int i = 0; i < count; i++) {
      canvas.drawCircle(
          Offset(random.nextDouble() * size.width,
              random.nextDouble() * size.height),
          1.5,
          paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ButtonBulge extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final double? width;
  final double? height;

  const ButtonBulge({
    Key? key,
    required this.child,
    this.onPressed,
    this.width,
    this.height,
  }) : super(key: key);

  @override
  State<ButtonBulge> createState() => _ButtonBulgeState();
}

class _ButtonBulgeState extends State<ButtonBulge> {
  bool _hovered = false;
  bool _clicked = false;

  // ← Now these types resolve correctly thanks to the gestures import
  void _onEnter(PointerEnterEvent _) => setState(() => _hovered = true);
  void _onExit(PointerExitEvent _) => setState(() => _hovered = false);

  void _onTap() {
    setState(() => _clicked = true);
    if (widget.onPressed != null) widget.onPressed!();
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _clicked = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final double scale = _hovered ? 1.07 : 1.0;
    final Color backgroundColor = _clicked
        ? Colors.white.withOpacity(0.5)
        : Colors.white.withOpacity(0.1);

    return MouseRegion(
      onEnter: _onEnter,
      onExit: _onExit,
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _onTap,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: widget.width,
                height: widget.height,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FadeInAnimation extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Duration? delay;
  final Curve curve;

  const FadeInAnimation({
    Key? key,
    required this.child,
    this.duration = const Duration(milliseconds: 500),
    this.delay,
    this.curve = Curves.easeIn,
  }) : super(key: key);

  @override
  State<FadeInAnimation> createState() => _FadeInAnimationState();
}

class _FadeInAnimationState extends State<FadeInAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: widget.duration);
    final curve =
    CurvedAnimation(parent: _controller, curve: widget.curve);
    _opacityAnimation =
        Tween<double>(begin: 0.0, end: 1.0).animate(curve);

    if (widget.delay != null) {
      Future.delayed(widget.delay!, _controller.forward);
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacityAnimation,
      child: widget.child,
    );
  }
}

class TypingText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Duration typingSpeed;
  final Duration cursorSpeed;
  final bool showCursor;
  final VoidCallback? onComplete;
  final Duration delayBeforeStart;

  const TypingText({
    super.key,
    required this.text,
    this.style,
    this.typingSpeed = const Duration(milliseconds: 50),
    this.cursorSpeed = const Duration(milliseconds: 500),
    this.showCursor = true,
    this.onComplete,
    this.delayBeforeStart = Duration.zero,
  });

  @override
  State<TypingText> createState() => _TypingTextState();
}

class _TypingTextState extends State<TypingText> {
  String _displayedText = "";
  int _currentIndex = 0;
  bool _cursorVisible = true;
  Timer? _typingTimer;
  Timer? _cursorTimer;

  @override
  void initState() {
    super.initState();
    _startAnimation();
    _startCursorBlink();
  }

  void _startAnimation() {
    Future.delayed(widget.delayBeforeStart, () {
      if (!mounted) return;
      _typingTimer = Timer.periodic(widget.typingSpeed, (timer) {
        if (_currentIndex < widget.text.length) {
          setState(() {
            _displayedText += widget.text[_currentIndex];
            _currentIndex++;
          });
        } else {
          timer.cancel();
          if (widget.onComplete != null) widget.onComplete!();
        }
      });
    });
  }

  void _startCursorBlink() {
    _cursorTimer = Timer.periodic(widget.cursorSpeed, (timer) {
      if (mounted) setState(() => _cursorVisible = !_cursorVisible);
    });
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _cursorTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
              text: _displayedText,
              style: widget.style ?? DefaultTextStyle.of(context).style),
          if (widget.showCursor)
            WidgetSpan(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _cursorVisible ? 1.0 : 0.0,
                child: Container(
                  width: 2,
                  height: (widget.style?.fontSize ?? 14) * 1.2,
                  color: widget.style?.color ?? Colors.black,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
