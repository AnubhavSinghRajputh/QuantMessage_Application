// lib/main.dart

import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';  // ← ADDED

import 'services/quant_space_api.dart';
import 'core/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/signin_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/app_bar.dart';
import 'screens/sidebar_panel/left_sidebar.dart';
import 'screens/animations/animation_effects/infinity_animation.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  App entry point — async + Supabase.initialize()
// ═══════════════════════════════════════════════════════════════════════════

Future<void> main() async {
  // ← 1. Required: bind Flutter to native engine
  WidgetsFlutterBinding.ensureInitialized();

  // ← 2. CRITICAL: Initialize Supabase BEFORE runApp()
  await Supabase.initialize(
    url: 'https://your-project.supabase.co',   // ← REPLACE with your URL
    anonKey: 'your-anon-key-here',              // ← REPLACE with your anon key
    debug: true,                                // ← set false in production
  );

  // ← 3. Now safe to start the app
  runApp(const ProviderScope(child: QuantSpaceApp()));
}

class QuantSpaceApp extends StatelessWidget {
  const QuantSpaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QuantCore.Ai',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: AppTheme.primaryRed,
        scaffoldBackgroundColor: AppTheme.backgroundBlack,
        textTheme:
        GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppTheme.primaryRed,
          brightness: Brightness.dark,
          surface: AppTheme.surfaceDark,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Data model
// ─────────────────────────────────────────────────────────────────────────────
class ChatMessage {
  final String text;
  final bool isUser;
  final String modelName;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.modelName = '',
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//  HomeScreen
// ─────────────────────────────────────────────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin {
  int _navIndex = 1;

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final QuantSpaceApi _api = QuantSpaceApi();
  final ImagePicker _picker = ImagePicker();
  final FocusNode _inputFocus = FocusNode();

  final List<ChatMessage> _messages = [];
  bool _isTyping = false;

  String _selectedModelName = 'Gemini 1.5 Flash';
  String _selectedModelId = 'gemini/gemini-1.5-flash';

  late final AnimationController _inputFocusCtrl;
  late final Animation<double> _inputBorderOpacity;

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
    {'name': 'Llama 3.1 8B (Groq)', 'id': 'groq/llama-3.1-8b-instant', 'icon': '🚀'},
    {'name': 'Mixtral 8x7B (Groq)', 'id': 'groq/mixtral-8x7b-32768', 'icon': '🔥'},
    {'name': 'DeepSeek Chat', 'id': 'openrouter/deepseek/deepseek-chat', 'icon': '🤖'},
  ];

  @override
  void initState() {
    super.initState();

    _inputFocusCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 260));
    _inputBorderOpacity =
        CurvedAnimation(parent: _inputFocusCtrl, curve: Curves.easeOut);
    _inputFocus.addListener(() => _inputFocus.hasFocus
        ? _inputFocusCtrl.forward()
        : _inputFocusCtrl.reverse());

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
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    _inputFocusCtrl.dispose();
    _sendBtnCtrl.dispose();
    _emptyCtrl.dispose();
    super.dispose();
  }

  // ── Tools ─────────────────────────────────────────────────────────────────
  void _showToolsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ToolsSheet(
        onWeather: () {
          _controller.text =
          'Tell me the current weather and forecast for my location.';
        },
        onQR: _startQRScanner,
        onImageSearch: _pickImageAndSearch,
        onAnalyze: _pickImageAndAnalyze,
        onGenImage: _pickPromptAndGenerateImage,
      ),
    );
  }

  void _startQRScanner() async {
    final status = await Permission.camera.request();
    if (!status.isGranted || !mounted) return;
    showDialog(
      context: context,
      builder: (_) => Scaffold(
        appBar: AppBar(
          title: Text('Scan QR Code', style: GoogleFonts.outfit()),
          backgroundColor: AppTheme.backgroundBlack,
        ),
        body: MobileScanner(
          onDetect: (capture) {
            final barcodes = capture.barcodes;
            if (barcodes.isNotEmpty) {
              _controller.text =
              'Analyze this data: ${barcodes.first.rawValue ?? ''}';
              Navigator.pop(context);
            }
          },
        ),
      ),
    );
  }

  void _pickImageAndSearch() async {
    final XFile? img = await _picker.pickImage(source: ImageSource.gallery);
    if (img != null) {
      _controller.text =
      'Search the web for details about this image...';
      _handleSend();
    }
  }

  void _pickImageAndAnalyze() async {
    final XFile? img = await _picker.pickImage(source: ImageSource.gallery);
    if (img != null) {
      _controller.text =
      'Perform a multi-point technical analysis on this chart image.';
      _handleSend();
    }
  }

  void _pickPromptAndGenerateImage() {
    showDialog(
      context: context,
      builder: (_) {
        final promptCtrl = TextEditingController();
        return AlertDialog(
          backgroundColor: AppTheme.surfaceDark,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: Text('AI Image Generator',
              style: GoogleFonts.outfit(
                  color: AppTheme.primaryRed,
                  fontWeight: FontWeight.bold)),
          content: TextField(
            controller: promptCtrl,
            style: GoogleFonts.outfit(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'Enter an image description...',
              hintStyle: GoogleFonts.outfit(
                  color: AppTheme.textSecondary.withOpacity(0.4)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel',
                  style:
                  GoogleFonts.outfit(color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () {
                final prompt = promptCtrl.text.trim();
                Navigator.pop(context);
                if (prompt.isNotEmpty) {
                  _controller.text =
                  'Generate a high-quality AI image: $prompt';
                  _handleSend();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryRed,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Generate', style: GoogleFonts.outfit()),
            ),
          ],
        );
      },
    );
  }

  // ── Send ───────────────────────────────────────────────────────────────────
  void _handleSend() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isTyping) return;

    _emptyCtrl.reset();
    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _isTyping = true;
    });
    _controller.clear();
    _scrollToBottom();

    try {
      if (text.startsWith('Generate a high-quality AI image:')) {
        final prompt =
        text.replaceFirst('Generate a high-quality AI image:', '').trim();
        final imageUrl = await _api.generateImage(prompt);
        setState(() {
          _messages.add(ChatMessage(
            text: imageUrl != null && imageUrl.startsWith('http')
                ? '### Result:\n![Generated AI Image]($imageUrl)'
                : 'Failed to generate image. Please try again.',
            isUser: false,
            modelName: 'IMAGE ENGINE',
          ));
        });
      } else {
        final response =
        await _api.chat(text, model: _selectedModelId);
        setState(() {
          _messages.add(ChatMessage(
            text: response['content'],
            isUser: false,
            modelName: _selectedModelName,
          ));
        });
      }
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(
          text: '🚨 **Error**: Connection failed. ${e.toString()}',
          isUser: false,
        ));
      });
    } finally {
      setState(() => _isTyping = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 480),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  String _getModelIcon(String name) {
    try {
      return _aiModels.firstWhere((m) => m['name'] == name)['icon'] ?? '⚡';
    } catch (_) {
      return '⚡';
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth > 600;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: AppTheme.backgroundBlack,
      appBar: _buildBlurredAppBar(),
      body: Row(
        children: [
          LeftSidebar(
            onNewChat: () {
              setState(() {
                _messages.clear();
                _emptyCtrl.forward(from: 0.0);
              });
            },
          ),
          Expanded(
            child: Stack(
              children: [
                const _ParticleBackground(count: 22),
                if (_messages.isEmpty)
                  _buildEmptyState()
                else
                  Column(
                    children: [
                      Expanded(child: _buildChatThread()),
                      Padding(
                        padding: const EdgeInsets.only(
                            bottom: 20, left: 20, right: 20),
                        child: _buildInputBox(),
                      ),
                    ],
                  ),
                if (_messages.isEmpty)
                  Positioned(
                    left: 0, right: 0, bottom: 0,
                    child: _buildFloatingInput(),
                  ),
                if (!isDesktop)
                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: CustomAppBar(
                      selectedIndex: _navIndex,
                      onItemSelected: (i) =>
                          setState(() => _navIndex = i),
                    ),
                  ),
                if (isDesktop)
                  Positioned(
                    top: 0, left: 0,
                    child: CustomAppBar(
                      selectedIndex: _navIndex,
                      onItemSelected: (i) =>
                          setState(() => _navIndex = i),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildBlurredAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(64),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: AppBar(
            backgroundColor:
            AppTheme.backgroundBlack.withOpacity(0.45),
            elevation: 0,
            automaticallyImplyLeading: false,
            title: Row(
              children: [
                Text(
                  'QuantCore',
                  style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    color: AppTheme.primaryRed,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(width: 14),
                AnimatedDropdown(
                  backgroundColor: const Color(0xFF2D2D2D),
                  dropdownWidth: 280,
                  items: _aiModels.map((m) {
                    return DropdownMenuItemData(
                      title: m['name']!,
                      subtitle: 'Powered by ${m['id']!.split('/').last}',
                      trailing: Text(m['icon']!,
                          style: const TextStyle(fontSize: 16)),
                      onTap: () => setState(() {
                        _selectedModelName = m['name']!;
                        _selectedModelId = m['id']!;
                      }),
                    );
                  }).toList(),
                  child: _ModelChip(
                    name: _selectedModelName,
                    icon: _getModelIcon(_selectedModelName),
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.history_rounded,
                    color: Colors.white38),
                onPressed: () {},
              ),
              IconButton(
                icon: const Icon(Icons.delete_sweep_rounded,
                    color: Colors.white24),
                onPressed: () {
                  setState(() => _messages.clear());
                  _api.resetSession();
                  _emptyCtrl
                    ..reset()
                    ..forward();
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return FadeTransition(
      opacity: _emptyOpacity,
      child: ScaleTransition(
        scale: _emptyScale,
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 90, height: 46,
                      child: InfinityAnimation(
                        size: 90,
                        color: AppTheme.primaryRed,
                        duration: const Duration(seconds: 5),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Flexible(
                      child: Text(
                        '< Welcome Back >',
                        style: GoogleFonts.outfit(
                          color: const Color(0xFFE8E8E8),
                          fontSize: 46,
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
                  '< How May You be Helped >',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: AppTheme.textSecondary.withOpacity(0.5),
                    fontSize: 18,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                const SizedBox(height: 40),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _AnimatedButton(
                      label: 'Sign In',
                      filled: true,
                      onTap: () => Navigator.push(
                          context, _smoothRoute(const SignInScreen())),
                    ),
                    const SizedBox(width: 16),
                    _AnimatedButton(
                      label: 'Sign Up',
                      filled: false,
                      onTap: () => Navigator.push(
                          context, _smoothRoute(const SignUpScreen())),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                _buildSuggestionPills(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionPills() {
    return Wrap(
      spacing: 8, runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        _SuggestionPill(Icons.edit_outlined, 'Write'),
        _SuggestionPill(Icons.school_outlined, 'Learn'),
        _SuggestionPill(Icons.code, 'Code'),
        _SuggestionPill(Icons.coffee_outlined, 'Life stuff'),
        _SuggestionPill(Icons.lightbulb_outline, 'Something New'),
      ],
    );
  }

  Widget _buildChatThread() {
    return ListView.builder(
      controller: _scrollCtrl,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(top: 80, bottom: 20),
      itemCount: _messages.length + (_isTyping ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length) return _buildTypingIndicator();
        return _AnimatedMessageRow(
          message: _messages[index],
          index: index,
          getModelIcon: _getModelIcon,
        );
      },
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          _buildAvatar('⚡', AppTheme.primaryRed),
          const SizedBox(width: 15),
          _ThinkingDots(),
        ],
      ),
    );
  }

  Widget _buildAvatar(String icon, Color color) {
    return Container(
      height: 32, width: 32,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Center(
          child: Text(icon, style: const TextStyle(fontSize: 14))),
    );
  }

  Widget _buildInputBox() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 800),
      child: AnimatedBuilder(
        animation: _inputBorderOpacity,
        builder: (_, child) => Container(
          decoration: BoxDecoration(
            color: const Color(0xFF2F2F2F),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Color.lerp(
                  Colors.white10, Colors.white24,
                  _inputBorderOpacity.value)!,
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 15,
                  offset: const Offset(0, 8))
            ],
          ),
          child: child,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _controller,
                focusNode: _inputFocus,
                maxLines: 4, minLines: 1,
                style: GoogleFonts.outfit(
                    color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Ask anything to QuantCore...',
                  hintStyle: GoogleFonts.outfit(
                      color: Colors.white38, fontSize: 16),
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
                          icon: Icons.auto_awesome_mosaic_rounded,
                          onTap: _showToolsMenu),
                      const SizedBox(width: 8),
                      AnimatedDropdown(
                        backgroundColor: const Color(0xFF3B3B3B),
                        dropdownWidth: 260,
                        items: _aiModels.map((m) {
                          return DropdownMenuItemData(
                            title: m['name']!,
                            subtitle: 'Powered by ${m['id']!.split('/').last}',
                            trailing: Text(m['icon']!,
                                style: const TextStyle(fontSize: 16)),
                            onTap: () => setState(() {
                              _selectedModelName = m['name']!;
                              _selectedModelId = m['id']!;
                            }),
                          );
                        }).toList(),
                        child: _AnimatedHoverDropdownButton(
                            text: _selectedModelName),
                      ),
                      const SizedBox(width: 8),
                      _AnimatedHoverIcon(
                          icon: Icons.mic_none, onTap: () {}),
                      const SizedBox(width: 8),
                      _AnimatedHoverIcon(
                          icon: Icons.graphic_eq, onTap: () {}),
                      const SizedBox(width: 12),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        switchInCurve: Curves.easeOutBack,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, anim) =>
                            ScaleTransition(
                                scale: anim,
                                child: FadeTransition(
                                    opacity: anim, child: child)),
                        child: _isTyping
                            ? const Padding(
                          key: ValueKey('loading'),
                          padding: EdgeInsets.symmetric(
                              horizontal: 12),
                          child: SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppTheme.primaryRed,
                            ),
                          ),
                        )
                            : Padding(
                          key: const ValueKey('send'),
                          padding: const EdgeInsets.all(4),
                          child: GestureDetector(
                            onTapDown: (_) =>
                                _sendBtnCtrl.forward(),
                            onTapUp: (_) async {
                              await _sendBtnCtrl.reverse();
                              _handleSend();
                            },
                            onTapCancel: () =>
                                _sendBtnCtrl.reverse(),
                            child: ScaleTransition(
                              scale: _sendBtnScale,
                              child: _AnimatedHoverSendButton(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingInput() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.backgroundBlack.withOpacity(0),
            AppTheme.backgroundBlack.withOpacity(0.85),
            AppTheme.backgroundBlack,
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Center(child: _buildInputBox()),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Model chip
// ═══════════════════════════════════════════════════════════════════════════

class _ModelChip extends StatefulWidget {
  final String name;
  final String icon;
  const _ModelChip({required this.name, required this.icon});

  @override
  State<_ModelChip> createState() => _ModelChipState();
}

class _ModelChipState extends State<_ModelChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _hovered
              ? Colors.white.withOpacity(0.10)
              : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: Colors.white.withOpacity(_hovered ? 0.14 : 0.08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.icon, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
            Text(
              widget.name,
              style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white),
            ),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down,
                size: 15,
                color: Colors.white.withOpacity(0.55)),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Animated message row
// ═══════════════════════════════════════════════════════════════════════════

class _AnimatedMessageRow extends StatefulWidget {
  final ChatMessage message;
  final int index;
  final String Function(String) getModelIcon;

  const _AnimatedMessageRow({
    required this.message,
    required this.index,
    required this.getModelIcon,
  });

  @override
  State<_AnimatedMessageRow> createState() => _AnimatedMessageRowState();
}

class _AnimatedMessageRowState extends State<_AnimatedMessageRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 380));
    _opacity =
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: Offset(widget.message.isUser ? 0.04 : -0.04, 0.06),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final msg = widget.message;
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
              vertical: 20, horizontal: 20),
          decoration: BoxDecoration(
            color: msg.isUser
                ? Colors.transparent
                : Colors.white.withOpacity(0.012),
            border: Border(
                bottom: BorderSide(
                    color: Colors.white.withOpacity(0.03))),
          ),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 850),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAvatar(
                    msg.isUser
                        ? '👤'
                        : widget.getModelIcon(msg.modelName),
                    msg.isUser
                        ? Colors.blueGrey
                        : AppTheme.primaryRed,
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          msg.isUser
                              ? 'YOU'
                              : msg.modelName.toUpperCase(),
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                            color: Colors.white38,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        MarkdownBody(
                          data: msg.text,
                          selectable: true,
                          styleSheet: MarkdownStyleSheet(
                            p: GoogleFonts.outfit(
                                fontSize: 16,
                                height: 1.6,
                                color: AppTheme.textPrimary),
                            h1: GoogleFonts.outfit(
                                color: AppTheme.primaryRed,
                                fontSize: 22,
                                fontWeight: FontWeight.bold),
                            code: GoogleFonts.outfit(
                                backgroundColor:
                                const Color(0xFF1E1E1E),
                                color: Colors.orangeAccent,
                                fontSize: 14),
                            codeblockDecoration: BoxDecoration(
                              color: const Color(0xFF1E1E1E),
                              borderRadius: BorderRadius.circular(12),
                              border:
                              Border.all(color: Colors.white10),
                            ),
                            blockquote: GoogleFonts.outfit(
                                color: Colors.white60,
                                fontStyle: FontStyle.italic),
                            blockquoteDecoration: const BoxDecoration(
                              border: Border(
                                left: BorderSide(
                                    color: AppTheme.primaryRed,
                                    width: 4),
                              ),
                            ),
                            img: const TextStyle(fontSize: 0),
                          ),
                          imageBuilder: (uri, title, alt) =>
                              _buildGeneratedImage(uri.toString()),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(String icon, Color color) {
    return Container(
      height: 34, width: 34,
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Center(
          child: Text(icon, style: const TextStyle(fontSize: 14))),
    );
  }

  Widget _buildGeneratedImage(String url) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Image.network(
              url,
              fit: BoxFit.cover,
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return Container(
                  height: 300, width: double.infinity,
                  color: Colors.white.withOpacity(0.05),
                  child: const Center(
                    child: CircularProgressIndicator(
                        color: AppTheme.primaryRed),
                  ),
                );
              },
              errorBuilder: (_, __, ___) => Container(
                height: 200, width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.broken_image_rounded,
                        color: Colors.white24, size: 40),
                    const SizedBox(height: 12),
                    Text('Image load blocked by provider',
                        style: GoogleFonts.outfit(
                            color: Colors.white38, fontSize: 12)),
                    TextButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.open_in_new_rounded,
                          size: 14, color: AppTheme.primaryRed),
                      label: Text('Open in Browser',
                          style: GoogleFonts.outfit(
                              color: AppTheme.primaryRed)),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 12, right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('GEN AI',
                    style: GoogleFonts.outfit(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white70)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Suggestion pill
// ═══════════════════════════════════════════════════════════════════════════

class _SuggestionPill extends StatefulWidget {
  final IconData icon;
  final String label;
  const _SuggestionPill(this.icon, this.label);

  @override
  State<_SuggestionPill> createState() => _SuggestionPillState();
}

class _SuggestionPillState extends State<_SuggestionPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: _hovered
              ? Colors.white.withOpacity(0.1)
              : const Color(0xFF2F2F2F),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: _hovered ? Colors.white54 : Colors.white10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon,
                color: _hovered ? Colors.white : Colors.white70,
                size: 16),
            const SizedBox(width: 6),
            Text(widget.label,
                style: GoogleFonts.outfit(
                    color: _hovered ? Colors.white : Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Thinking dots
// ═══════════════════════════════════════════════════════════════════════════

class _ThinkingDots extends StatefulWidget {
  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
    with TickerProviderStateMixin {
  late final List<AnimationController> _ctrls;
  late final List<Animation<double>> _scales;

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(
        3,
            (i) => AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 500)));
    _scales = _ctrls
        .map((c) => Tween<double>(begin: 0.4, end: 1.0).animate(
        CurvedAnimation(parent: c, curve: Curves.easeInOut)))
        .toList();
    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 160), () {
        if (mounted) _ctrls[i].repeat(reverse: true);
      });
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(3, (i) {
        return ScaleTransition(
          scale: _scales[i],
          child: Container(
            width: 8, height: 8,
            margin: const EdgeInsets.only(right: 6),
            decoration: const BoxDecoration(
                color: Colors.white38, shape: BoxShape.circle),
          ),
        );
      }),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Particle background
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
    final rng = math.Random(42);
    for (int i = 0; i < count; i++) {
      canvas.drawCircle(
        Offset(rng.nextDouble() * size.width,
            rng.nextDouble() * size.height),
        1.5, paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ═══════════════════════════════════════════════════════════════════════════
//  Hover icon
// ═══════════════════════════════════════════════════════════════════════════

class _AnimatedHoverIcon extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _AnimatedHoverIcon({required this.icon, required this.onTap});

  @override
  State<_AnimatedHoverIcon> createState() => _AnimatedHoverIconState();
}

class _AnimatedHoverIconState extends State<_AnimatedHoverIcon> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: _hovered
                  ? Colors.white.withOpacity(0.05)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8)),
          child: Icon(widget.icon,
              color: _hovered ? Colors.white : Colors.white70,
              size: 20),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Hover dropdown
// ═══════════════════════════════════════════════════════════════════════════

class _AnimatedHoverDropdownButton extends StatefulWidget {
  final String text;
  const _AnimatedHoverDropdownButton({required this.text});

  @override
  State<_AnimatedHoverDropdownButton> createState() =>
      _AnimatedHoverDropdownButtonState();
}

class _AnimatedHoverDropdownButtonState
    extends State<_AnimatedHoverDropdownButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: _hovered
                ? Colors.white.withOpacity(0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.text,
                style: GoogleFonts.outfit(
                    color: _hovered ? Colors.white : Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down,
                color: _hovered ? Colors.white : Colors.white54,
                size: 16),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Send button
// ═══════════════════════════════════════════════════════════════════════════

class _AnimatedHoverSendButton extends StatefulWidget {
  @override
  State<_AnimatedHoverSendButton> createState() =>
      _AnimatedHoverSendButtonState();
}

class _AnimatedHoverSendButtonState
    extends State<_AnimatedHoverSendButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: _hovered ? Colors.white : Colors.white24,
            shape: BoxShape.circle),
        child: Icon(Icons.arrow_upward_rounded,
            color: _hovered ? Colors.black : Colors.white,
            size: 20),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Animated button (Sign In / Sign Up)
// ═══════════════════════════════════════════════════════════════════════════

class _AnimatedButton extends StatefulWidget {
  final String label;
  final bool filled;
  final VoidCallback onTap;
  const _AnimatedButton(
      {required this.label,
        required this.filled,
        required this.onTap});

  @override
  State<_AnimatedButton> createState() => _AnimatedButtonState();
}

class _AnimatedButtonState extends State<_AnimatedButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 100),
        lowerBound: 0.0, upperBound: 1.0);
    _scale = Tween<double>(begin: 1.0, end: 0.94).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) async {
        await _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: widget.filled
            ? Container(
          padding: const EdgeInsets.symmetric(
              vertical: 12, horizontal: 24),
          decoration: BoxDecoration(
            color: AppTheme.primaryRed,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(widget.label,
              style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
        )
            : Container(
          padding: const EdgeInsets.symmetric(
              vertical: 12, horizontal: 24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: Colors.white.withOpacity(0.15),
                width: 1.5),
          ),
          child: Text(widget.label,
              style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary)),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  AnimatedDropdown (kept identical to chat_screen.dart)
// ═══════════════════════════════════════════════════════════════════════════

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
  late final AnimationController _animCtrl;
  late final Animation<double> _expandAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 300));
    _expandAnim = CurvedAnimation(
        parent: _animCtrl, curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _toggle() => _isOpen ? _close() : _show();

  void _show() {
    if (_overlayEntry != null) return;
    final box = context.findRenderObject() as RenderBox;
    final size = box.size;
    _overlayEntry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _close,
              child: Container(color: Colors.transparent),
            ),
          ),
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: Offset(0, size.height + 8),
            child: Material(
              color: Colors.transparent,
              child: SizeTransition(
                sizeFactor: _expandAnim,
                axisAlignment: -1.0,
                child: Container(
                  width: widget.dropdownWidth,
                  decoration: BoxDecoration(
                    color: widget.backgroundColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.1)),
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
                      constraints:
                      const BoxConstraints(maxHeight: 300),
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: widget.items.map((item) {
                            if (item.isDivider) {
                              return Divider(
                                height: 1,
                                color: Colors.white.withOpacity(0.1),
                                indent: 16,
                                endIndent: 16,
                              );
                            }
                            return _DropdownItemWidget(
                              item: item,
                              onItemTapped: () {
                                if (item.onTap != null) item.onTap!();
                                if (item.closeOnTap) _close();
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
    _animCtrl.forward();
  }

  void _close() async {
    await _animCtrl.reverse();
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
      child: GestureDetector(onTap: _toggle, child: widget.child),
    );
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
      {Key? key,
        required this.item,
        required this.onItemTapped})
      : super(key: key);

  @override
  State<_DropdownItemWidget> createState() =>
      _DropdownItemWidgetState();
}

class _DropdownItemWidgetState extends State<_DropdownItemWidget> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        if (!widget.item.isDisabled)
          setState(() => _hovered = true);
      },
      onExit: (_) {
        if (!widget.item.isDisabled)
          setState(() => _hovered = false);
      },
      cursor: widget.item.isDisabled
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.item.isDisabled ? null : widget.onItemTapped,
        child: Container(
          color: _hovered
              ? Colors.white.withOpacity(0.05)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 12),
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
                        widget.item.titleTrailing!,
                      ],
                    ]),
                    if (widget.item.subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(widget.item.subtitle!,
                          style: TextStyle(
                              color: widget.item.isDisabled
                                  ? Colors.white.withOpacity(0.3)
                                  : Colors.white.withOpacity(0.5),
                              fontSize: 13)),
                    ],
                  ],
                ),
              ),
              if (widget.item.trailing != null) ...[
                const SizedBox(width: 12),
                widget.item.trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Tools sheet
// ═══════════════════════════════════════════════════════════════════════════

class _ToolsSheet extends StatefulWidget {
  final VoidCallback onWeather;
  final VoidCallback onQR;
  final VoidCallback onImageSearch;
  final VoidCallback onAnalyze;
  final VoidCallback onGenImage;

  const _ToolsSheet({
    required this.onWeather,
    required this.onQR,
    required this.onImageSearch,
    required this.onAnalyze,
    required this.onGenImage,
  });

  @override
  State<_ToolsSheet> createState() => _ToolsSheetState();
}

class _ToolsSheetState extends State<_ToolsSheet>
    with TickerProviderStateMixin {
  late final List<AnimationController> _itemCtrls;
  late final List<Animation<double>> _itemOpacities;
  late final List<Animation<Offset>> _itemSlides;

  static const _items = [
    (Icons.wb_sunny_rounded, 'Check Weather', 'Get real-time weather & forecast'),
    (Icons.qr_code_scanner_rounded, 'Scan QR Code', 'Analyze data from QR codes'),
    (Icons.image_search_rounded, 'Search by Image', 'Ask about a photo from gallery'),
    (Icons.analytics_rounded, 'Analyze Chart', 'Perform technical chart analysis'),
    (Icons.brush_rounded, 'Generate AI Image', 'Create unique images using free AI'),
  ];

  @override
  void initState() {
    super.initState();
    _itemCtrls = List.generate(
      _items.length,
          (i) => AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 350)),
    );
    _itemOpacities = _itemCtrls
        .map((c) => CurvedAnimation(parent: c, curve: Curves.easeOut))
        .toList();
    _itemSlides = _itemCtrls
        .map((c) => Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: c, curve: Curves.easeOutCubic)))
        .toList();
    for (int i = 0; i < _itemCtrls.length; i++) {
      Future.delayed(Duration(milliseconds: 60 * i),
              () { if (mounted) _itemCtrls[i].forward(); });
    }
  }

  @override
  void dispose() {
    for (final c in _itemCtrls) c.dispose();
    super.dispose();
  }

  void _onTap(int i) {
    Navigator.pop(context);
    [
      widget.onWeather,
      widget.onQR,
      widget.onImageSearch,
      widget.onAnalyze,
      widget.onGenImage,
    ][i]();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 360,
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark,
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(32)),
        border: Border.all(
            color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 40,
              spreadRadius: 10),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 48, height: 5,
            decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(10)),
          ),
          const SizedBox(height: 20),
          Text('Tools & Actions',
              style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 12),
          ...List.generate(_items.length, (i) {
            final (icon, title, subtitle) = _items[i];
            return FadeTransition(
              opacity: _itemOpacities[i],
              child: SlideTransition(
                position: _itemSlides[i],
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryRed.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon,
                        color: AppTheme.primaryRed, size: 22),
                  ),
                  title: Text(title,
                      style: GoogleFonts.outfit(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600)),
                  subtitle: Text(subtitle,
                      style: GoogleFonts.outfit(
                          color: AppTheme.textSecondary,
                          fontSize: 12)),
                  onTap: () => _onTap(i),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Smooth page route
// ═══════════════════════════════════════════════════════════════════════════

PageRouteBuilder _smoothRoute(Widget page) {
  return PageRouteBuilder(
    transitionDuration: const Duration(milliseconds: 450),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) => FadeTransition(
      opacity: CurvedAnimation(
          parent: animation, curve: Curves.easeOut),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.05),
          end: Offset.zero,
        ).animate(CurvedAnimation(
            parent: animation, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
  );
}
