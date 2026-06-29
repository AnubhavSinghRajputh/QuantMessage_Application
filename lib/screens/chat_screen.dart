// lib/screens/chat_screen.dart

import 'dart:async';
import 'dart:io';                      // ← FIX: added this missing import
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/app_theme.dart';
import '../core/chat_message.dart';
import '../core/attachment_model.dart';
import '../services/quant_space_api.dart';
import '../services/upload_service.dart';
import 'animations/animation_effects/infinity_animation.dart';
import 'sidebar_panel/left_sidebar.dart';
import 'widgets/attachment_preview.dart';
import 'widgets/attachment_thumbnail.dart';
import 'widgets/attachment_picker_sheet.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  Fade-in animation (unchanged)
// ═══════════════════════════════════════════════════════════════════════════

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
  _FadeInAnimationState createState() => _FadeInAnimationState();
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
    final curve = CurvedAnimation(parent: _controller, curve: widget.curve);
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
    return FadeTransition(opacity: _opacityAnimation, child: widget.child);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Typing text animation (unchanged)
// ═══════════════════════════════════════════════════════════════════════════

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
    this.typingSpeed = const Duration(milliseconds: 20),
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
            style: widget.style ?? DefaultTextStyle.of(context).style,
          ),
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

// ═══════════════════════════════════════════════════════════════════════════
//  Chat screen
// ═══════════════════════════════════════════════════════════════════════════

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final QuantSpaceApi _api = QuantSpaceApi();
  final UploadService _uploader = UploadService();
  final FocusNode _inputFocus = FocusNode();

  final List<ChatMessage> _messages = [];
  bool _isTyping = false;

  String? _activeConversationId;
  final List<Attachment> _pendingAttachments = [];

  String _selectedModelName = 'Gemini 1.5 Flash';
  String _selectedModelId = 'gemini/gemini-1.5-flash';

  late final AnimationController _inputFocusCtrl;
  late final Animation<double> _inputGlow;
  late final AnimationController _sendBtnCtrl;
  late final Animation<double> _sendBtnScale;
  late final AnimationController _emptyCtrl;
  late final Animation<double> _emptyOpacity;
  late final Animation<double> _emptyScale;

  final List<Map<String, String>> _aiModels = [
    {'name': 'Gemini 1.5 Flash', 'id': 'gemini/gemini-1.5-flash', 'icon': '✨'},
    {'name': 'GPT-4o', 'id': 'openai/gpt-4o', 'icon': '🧠'},
    {'name': 'Claude 3.5 Sonnet', 'id': 'openrouter/anthropic/claude-3.5-sonnet', 'icon': '🎭'},
    {'name': 'QuantCore 1.0', 'id': 'groq/llama-3.1-70b-versatile', 'icon': '⚡'},
    {'name': 'Llama 3.1 8B', 'id': 'groq/llama-3.1-8b-instant', 'icon': '🚀'},
    {'name': 'Mixtral 8x7B', 'id': 'groq/mixtral-8x7b-32768', 'icon': '🔥'},
    {'name': 'DeepSeek Chat', 'id': 'openrouter/deepseek/deepseek-chat', 'icon': '🤖'},
  ];

  @override
  void initState() {
    super.initState();
    _inputFocusCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 260));
    _inputGlow = CurvedAnimation(parent: _inputFocusCtrl, curve: Curves.easeOut);
    _inputFocus.addListener(() {
      _inputFocus.hasFocus ? _inputFocusCtrl.forward() : _inputFocusCtrl.reverse();
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
    _emptyOpacity = CurvedAnimation(parent: _emptyCtrl, curve: Curves.easeOut);
    _emptyScale = Tween<double>(begin: 0.96, end: 1.0).animate(
        CurvedAnimation(parent: _emptyCtrl, curve: Curves.easeOutBack));
    _emptyCtrl.forward();
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

  Future<Attachment> _uploadPendingAttachment(Attachment att) async {
    _ensureConversationId();

    setState(() {
      final idx = _pendingAttachments.indexOf(att);
      if (idx != -1) {
        _pendingAttachments[idx] =
            att.copyWith(status: UploadStatus.uploading, progress: 0.1);
      }
    });

    try {
      final uploaded = await _uploader.uploadFile(
        file: att.localFile!,
        conversationId: _activeConversationId!,
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

      if (!mounted) return uploaded;
      setState(() {
        final i = _pendingAttachments.indexOf(att);
        if (i != -1) _pendingAttachments[i] = uploaded;
      });
      return uploaded;
    } catch (e) {
      if (!mounted) return att;
      setState(() {
        final i = _pendingAttachments.indexOf(att);
        if (i != -1) {
          _pendingAttachments[i] =
              att.copyWith(status: UploadStatus.failed);
        }
      });
      rethrow;
    }
  }

  void _ensureConversationId() {
    _activeConversationId ??= DateTime.now().millisecondsSinceEpoch.toString();
  }

  // ── Send handler ─────────────────────────────────────────────────────────
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
      _ensureConversationId();

      // Upload any pending local files
      final uploaded = <Attachment>[];
      for (final att in pendingSnapshot) {
        if (att.isReady) {
          uploaded.add(att);
        } else if (att.localFile != null) {
          uploaded.add(await _uploadPendingAttachment(att));
        }
      }

      final response = await _uploader.sendMessageWithAttachments(
        message: text.isEmpty
            ? 'Please analyze the attached file(s).'
            : text,
        attachments: uploaded,
        conversationId: _activeConversationId,
      );

      if (!mounted) return;
      setState(() {
        _activeConversationId =
            response['conversation_id'] as String? ?? _activeConversationId;
        _messages.add(ChatMessage(
          text: response['content'] as String? ?? '',
          isUser: false,
          modelName: _selectedModelName,
        ));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages.add(ChatMessage(
        text: "🚨 Error: ${e.toString()}",
        isUser: false,
      )));
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
          duration: const Duration(milliseconds: 480),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundBlack,
      body: Row(
        children: [
          LeftSidebar(
            onNewChat: () {
              setState(() {
                _messages.clear();
                _activeConversationId = null;
                _pendingAttachments.clear();
                _emptyCtrl.forward(from: 0.0);
              });
            },
          ),
          Expanded(
            child: Stack(
              children: [
                const _ParticleBackground(count: 22),
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
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _buildGreeting(),
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
                          child: _buildInputBox(),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGreeting() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 90,
              height: 46,
              child: InfinityAnimation(
                size: 90,
                color: const Color(0xFFE27457),
                duration: const Duration(seconds: 5),
              ),
            ),
            const SizedBox(width: 16),
            Flexible(
              child: Text(
                "< Welcome Back >",
                style: GoogleFonts.outfit(
                  color: const Color(0xFFE8E8E8),
                  fontSize: 56,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          "< How May You be Helped >",
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            color: AppTheme.textSecondary.withOpacity(0.5),
            fontSize: 18,
            fontWeight: FontWeight.w300,
          ),
        ),
      ],
    );
  }

  Widget _buildChatThread() {
    return ListView.builder(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(top: 20, bottom: 20),
      itemCount: _messages.length + (_isTyping ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length) return _buildTypingIndicator();
        return _AnimatedMessageRow(message: _messages[index]);
      },
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          _buildAvatar("⚡", AppTheme.primaryWhite),
          const SizedBox(width: 15),
          _ThinkingDots(),
        ],
      ),
    );
  }

  Widget _buildAvatar(String icon, Color color) {
    return Container(
      height: 32,
      width: 32,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Center(child: Text(icon, style: const TextStyle(fontSize: 14))),
    );
  }

  // ── Input box with attachments ───────────────────────────────────────────
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
              width: 1.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 15,
              offset: const Offset(0, 8),
            )
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
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(
                hintText: _pendingAttachments.isNotEmpty
                    ? "Describe what you want to know about the file(s)..."
                    : "Type a message...",
                hintStyle: GoogleFonts.outfit(
                    color: Colors.white38, fontSize: 16),
                border: InputBorder.none,
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                      icon: Icons.add,
                      onTap: _onAttachmentButtonPressed,
                    ),
                    const SizedBox(width: 8),
                    AnimatedDropdown(
                      backgroundColor: const Color(0xFF3B3B3B),
                      dropdownWidth: 260,
                      items: _aiModels.map((model) {
                        return DropdownMenuItemData(
                          title: model['name']!,
                          subtitle:
                          "Powered by ${model['id']!.split('/').last}",
                          trailing: Text(model['icon']!,
                              style: const TextStyle(fontSize: 16)),
                          onTap: () => setState(() {
                            _selectedModelName = model['name']!;
                            _selectedModelId = model['id']!;
                          }),
                        );
                      }).toList(),
                      child: _AnimatedHoverDropdownButton(
                          text: _selectedModelName),
                    ),
                    const SizedBox(width: 8),
                    _AnimatedHoverIcon(icon: Icons.mic_none, onTap: () {}),
                    const SizedBox(width: 8),
                    _AnimatedHoverIcon(icon: Icons.graphic_eq, onTap: () {}),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTapDown: (_) => _sendBtnCtrl.forward(),
                      onTapUp: (_) async {
                        await _sendBtnCtrl.reverse();
                        _handleSend();
                      },
                      onTapCancel: () => _sendBtnCtrl.reverse(),
                      child: ScaleTransition(
                          scale: _sendBtnScale,
                          child: _AnimatedHoverSendButton()),
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
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        _SuggestionPill(Icons.edit_outlined, "Write"),
        _SuggestionPill(Icons.school_outlined, "Learn"),
        _SuggestionPill(Icons.code, "Code"),
        _SuggestionPill(Icons.coffee_outlined, "Life stuff"),
        _SuggestionPill(Icons.lightbulb_outline, " Something New"),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Animated Message Row (renders attachments)
// ═══════════════════════════════════════════════════════════════════════════

class _AnimatedMessageRow extends StatefulWidget {
  final ChatMessage message;
  const _AnimatedMessageRow({required this.message});

  @override
  State<_AnimatedMessageRow> createState() => _AnimatedMessageRowState();
}

class _AnimatedMessageRowState extends State<_AnimatedMessageRow> {
  bool _isTypingComplete = false;

  @override
  Widget build(BuildContext context) {
    final msg = widget.message;
    final hasAttachments = msg.hasAttachments;
    final hasText = msg.hasText;

    return FadeInAnimation(
      duration: const Duration(milliseconds: 400),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
        decoration: BoxDecoration(
          color: msg.isUser
              ? Colors.transparent
              : AppTheme.surfaceDark.withOpacity(0.3),
          border: Border(
            bottom: BorderSide(color: Colors.white.withOpacity(0.03)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: msg.isUser ? Colors.white10 : Colors.blueAccent,
              child: Text(
                msg.isUser ? "👤" : "🤖",
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    msg.isUser ? "USER" : msg.modelName.toUpperCase(),
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 10, color: Colors.white38),
                  ),
                  const SizedBox(height: 5),

                  if (hasAttachments)
                    AttachmentList(attachments: msg.attachments),

                  if (hasText)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.8),
                      child: msg.isUser
                          ? MarkdownBody(
                          data: msg.text,
                          styleSheet: MarkdownStyleSheet(
                              p: GoogleFonts.outfit(
                                  color: Colors.white, fontSize: 15)))
                          : _buildAIContent(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAIContent() {
    return _isTypingComplete
        ? MarkdownBody(
        data: widget.message.text,
        styleSheet: MarkdownStyleSheet(
            p: GoogleFonts.outfit(color: Colors.white, fontSize: 15)))
        : TypingText(
      text: widget.message.text,
      style: GoogleFonts.outfit(color: Colors.white, fontSize: 15),
      onComplete: () {
        if (mounted) setState(() => _isTypingComplete = true);
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Other UI components (unchanged)
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon,
                color: _isHovered ? Colors.white : Colors.white70, size: 16),
            const SizedBox(width: 6),
            Text(widget.label,
                style: GoogleFonts.outfit(
                    color: _isHovered ? Colors.white : Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ],
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
  bool _isHovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: _isHovered
                  ? Colors.white.withOpacity(0.05)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8)),
          child: Icon(widget.icon,
              color: _isHovered ? Colors.white : Colors.white70, size: 20),
        ),
      ),
    );
  }
}

class _AnimatedHoverDropdownButton extends StatefulWidget {
  final String text;
  const _AnimatedHoverDropdownButton({required this.text});
  @override
  State<_AnimatedHoverDropdownButton> createState() =>
      _AnimatedHoverDropdownButtonState();
}

class _AnimatedHoverDropdownButtonState
    extends State<_AnimatedHoverDropdownButton> {
  bool _isHovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: _isHovered
                ? Colors.white.withOpacity(0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.text,
                style: GoogleFonts.outfit(
                    color: _isHovered ? Colors.white : Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down,
                color: _isHovered ? Colors.white : Colors.white54, size: 16),
          ],
        ),
      ),
    );
  }
}

class _AnimatedHoverSendButton extends StatefulWidget {
  @override
  State<_AnimatedHoverSendButton> createState() =>
      _AnimatedHoverSendButtonState();
}

class _AnimatedHoverSendButtonState extends State<_AnimatedHoverSendButton> {
  bool _isHovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: _isHovered ? Colors.white : Colors.white24,
            shape: BoxShape.circle),
        child: Icon(Icons.arrow_upward_rounded,
            color: _isHovered ? Colors.black : Colors.white, size: 20),
      ),
    );
  }
}

class _ThinkingDots extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Row(children: [
      Text("...", style: TextStyle(color: Colors.white38, fontSize: 20))
    ]);
  }
}

class _ParticleBackground extends StatelessWidget {
  final int count;
  const _ParticleBackground({required this.count});
  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.3,
      child: CustomPaint(
        painter: _ChatParticlePainter(0.0, count),
        size: MediaQuery.of(context).size,
      ),
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
    for (int i = 0; i < count; i++) {
      canvas.drawCircle(
          Offset(math.Random().nextDouble() * size.width,
              math.Random().nextDouble() * size.height),
          1.5,
          paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class AnimatedDropdown extends StatefulWidget {
  final Widget child;
  final List<DropdownMenuItemData> items;
  final double dropdownWidth;
  final Color backgroundColor;
  const AnimatedDropdown({
    Key? key,
    required this.child,
    required this.items,
    this.dropdownWidth = 300,
    this.backgroundColor = const Color(0xFF2D2D2D),
  }) : super(key: key);

  @override
  State<AnimatedDropdown> createState() => _AnimatedDropdownState();
}

class _AnimatedDropdownState extends State<AnimatedDropdown>
    with SingleTickerProviderStateMixin {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;
  late AnimationController _animationController;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _expandAnimation = CurvedAnimation(
        parent: _animationController, curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _animationController.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _toggleDropdown() {
    _isOpen ? _closeDropdown() : _showDropdown();
  }

  void _showDropdown() {
    if (_overlayEntry != null) return;
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _closeDropdown,
                child: Container(color: Colors.transparent)),
          ),
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: Offset(0, size.height + 8),
            child: Material(
              color: Colors.transparent,
              child: SizeTransition(
                sizeFactor: _expandAnimation,
                axisAlignment: -1.0,
                child: Container(
                  width: widget.dropdownWidth,
                  decoration: BoxDecoration(
                    color: widget.backgroundColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 5))
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 300),
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: widget.items.map((item) {
                            if (item.isDivider)
                              return Divider(
                                height: 1,
                                color: Colors.white.withOpacity(0.1),
                                indent: 16,
                                endIndent: 16,
                              );
                            return _DropdownItemWidget(
                              item: item,
                              onItemTapped: () {
                                if (item.onTap != null) item.onTap!();
                                if (item.closeOnTap) _closeDropdown();
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
    _isOpen = true;
    _animationController.forward();
  }

  void _closeDropdown() async {
    await _animationController.reverse();
    _removeOverlay();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _isOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
        link: _layerLink,
        child: GestureDetector(onTap: _toggleDropdown, child: widget.child));
  }
}

class DropdownMenuItemData {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? titleTrailing;
  final VoidCallback? onTap;
  final bool closeOnTap;
  final bool isDivider;
  final bool isDisabled;

  DropdownMenuItemData({
    this.title = '',
    this.subtitle,
    this.trailing,
    this.titleTrailing,
    this.onTap,
    this.closeOnTap = true,
    this.isDivider = false,
    this.isDisabled = false,
  });

  factory DropdownMenuItemData.divider() =>
      DropdownMenuItemData(isDivider: true);
}

class _DropdownItemWidget extends StatefulWidget {
  final DropdownMenuItemData item;
  final VoidCallback onItemTapped;
  const _DropdownItemWidget(
      {Key? key, required this.item, required this.onItemTapped})
      : super(key: key);

  @override
  State<_DropdownItemWidget> createState() => _DropdownItemWidgetState();
}

class _DropdownItemWidgetState extends State<_DropdownItemWidget> {
  bool _isHovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        if (!widget.item.isDisabled) setState(() => _isHovered = true);
      },
      onExit: (_) {
        if (!widget.item.isDisabled) setState(() => _isHovered = false);
      },
      cursor: widget.item.isDisabled
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.item.isDisabled ? null : widget.onItemTapped,
        child: Container(
          color: _isHovered
              ? Colors.white.withOpacity(0.05)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(widget.item.title,
                          style: TextStyle(
                              color: widget.item.isDisabled
                                  ? Colors.white.withOpacity(0.3)
                                  : Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                      if (widget.item.titleTrailing != null) ...[
                        const SizedBox(width: 8),
                        widget.item.titleTrailing!
                      ],
                    ]),
                    if (widget.item.subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(widget.item.subtitle!,
                          style: TextStyle(
                              color: widget.item.isDisabled
                                  ? Colors.white.withOpacity(0.3)
                                  : Colors.white.withOpacity(0.5),
                              fontSize: 13))
                    ],
                  ],
                ),
              ),
              if (widget.item.trailing != null) ...[
                const SizedBox(width: 12),
                widget.item.trailing!
              ],
            ],
          ),
        ),
      ),
    );
  }
}
