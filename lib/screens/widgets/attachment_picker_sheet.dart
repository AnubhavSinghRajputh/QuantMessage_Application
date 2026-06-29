// lib/screens/widgets/attachment_picker_sheet.dart
// ------------------------------------------------------------
//   Cross‑platform attachment picker (mobile + web)
//   Updated to use the `mime` package from pubspec.yaml for
//   reliable MIME‑type detection.
// ------------------------------------------------------------

import 'dart:io' show File;               // Tree‑shaken on web
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart'; // ← New import for MIME lookup

/// Signature for the callback that receives the selected attachment.
///
/// * **bytes** – raw file bytes (already read from the picker).
/// * **filename** – original file name (including extension).
/// * **mimeType** – detected MIME type (e.g. `image/jpeg`).
typedef AttachmentSelected = void Function(
    Uint8List bytes,
    String filename,
    String mimeType,
    );

class AttachmentPickerSheet extends StatefulWidget {
  final AttachmentSelected onSelected;
  const AttachmentPickerSheet({super.key, required this.onSelected});

  /// Convenience helper to present the bottom‑sheet.
  static Future<void> show(
      BuildContext context, {
        required AttachmentSelected onSelected,
      }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.55),
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => AttachmentPickerSheet(onSelected: onSelected),
    );
  }

  @override
  State<AttachmentPickerSheet> createState() => _AttachmentPickerSheetState();
}

class _AttachmentPickerSheetState extends State<AttachmentPickerSheet>
    with SingleTickerProviderStateMixin {
  // ── Animations ─────────────────────────────────────────────────────────
  late final AnimationController _entryCtrl;
  late final Animation<double> _slideAnim;
  late final Animation<double> _fadeAnim;

  // ── UI state ───────────────────────────────────────────────────────────
  bool _busy = false;

  // ── Allowed extensions (kept in one place for easy updates) ────────
  static const List<String> _allowedExtensions = [
    'pdf',
    'txt',
    'doc',
    'docx',
    'png',
    'jpg',
    'jpeg',
    'webp',
    'gif',
  ];

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slideAnim =
        CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic);
    _fadeAnim = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _entryCtrl.forward();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  // ── ── ── PICKERS (cross‑platform) ── ── ────────────────────────────────

  Future<void> _pickFromGallery() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2400,
        imageQuality: 85,
      );
      if (image != null && mounted) {
        final bytes = await image.readAsBytes();
        widget.onSelected(bytes, image.name, _guessMime(image.name));
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      _showError('Could not pick image: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _takePhoto() async {
    if (_busy) return;
    if (kIsWeb) {
      _showError('📷 Camera is only available on mobile devices.');
      return;
    }
    setState(() => _busy = true);
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 2400,
        imageQuality: 85,
      );
      if (image != null && mounted) {
        final bytes = await image.readAsBytes();
        // For a freshly captured photo we can safely assume JPEG.
        widget.onSelected(bytes, image.name, 'image/jpeg');
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      _showError('Camera error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFile() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _allowedExtensions,
        withData: true, // gives us `bytes` on web & desktop
      );

      if (result == null || result.files.isEmpty) return;

      final PlatformFile picked = result.files.single;
      Uint8List? bytes = picked.bytes;

      // Mobile fallback – read the file from the native file system.
      if (bytes == null && picked.path != null) {
        final file = File(picked.path!);
        bytes = await file.readAsBytes();
      }

      if (bytes != null && mounted) {
        widget.onSelected(bytes, picked.name, _guessMime(picked.name));
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      _showError('File picker error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── MIME‑type helper (uses `mime` package) ────────────────────────
  String _guessMime(String filename) {
    // `lookupMimeType` returns `null` if it cannot guess – we fallback
    // to a generic binary type.
    return lookupMimeType(filename) ?? 'application/octet-stream';
  }

  // ── UI helpers ───────────────────────────────────────────────────────
  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF2A2A2A),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Build UI ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
          .animate(_slideAnim),
      child: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          top: false,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E).withOpacity(0.98),
              borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withOpacity(0.08),
                  width: 1,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 30,
                  offset: const Offset(0, -10),
                ),
              ],
            ),
            child: Padding(
              padding:
              const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Drag‑handle ───────────────────────────────────────
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),

                  // ── Header ─────────────────────────────────────────────
                  const Row(
                    children: [
                      Icon(Icons.add_circle_outline,
                          color: Color(0xFFE27457), size: 22),
                      SizedBox(width: 10),
                      Text(
                        'Add to chat',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    kIsWeb
                        ? 'Pick from your computer — images, PDFs, docs'
                        : 'Upload an image or document for the AI to analyze',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Options ───────────────────────────────────────────────
                  _OptionTile(
                    icon: Icons.image_outlined,
                    title: kIsWeb ? 'Image from Computer' : 'Photo from Gallery',
                    subtitle: 'JPG, PNG, WebP, GIF',
                    onTap: _pickFromGallery,
                    enabled: !_busy,
                  ),
                  _OptionTile(
                    icon: Icons.camera_alt_outlined,
                    title: 'Take a Photo',
                    subtitle: kIsWeb ? '📷 Mobile only' : 'Use your camera',
                    onTap: _takePhoto,
                    enabled: !_busy && !kIsWeb,
                  ),
                  _OptionTile(
                    icon: Icons.picture_as_pdf_outlined,
                    title: 'Document (PDF / File)',
                    subtitle: 'PDF, TXT, DOC, DOCX',
                    onTap: _pickFile,
                    enabled: !_busy,
                  ),

                  // ── Busy indicator ───────────────────────────────────────
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white70),
                          ),
                          SizedBox(width: 12),
                          Text('Opening file picker...',
                              style: TextStyle(color: Colors.white70)),
                        ],
                      ),
                    ),

                  // ── Web‑only tip ─────────────────────────────────────────────
                  if (kIsWeb)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 14, color: Colors.white24),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Tip: Ctrl+V (⌘+V) to paste images from clipboard',
                              style: TextStyle(
                                  color: Colors.white24, fontSize: 11),
                            ),
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
}

// ── Reusable tile widget ───────────────────────────────────────────────────
class _OptionTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;

  const _OptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  @override
  State<_OptionTile> createState() => _OptionTileState();
}

class _OptionTileState extends State<_OptionTile> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final Color baseColor =
    widget.enabled ? Colors.white : Colors.white.withOpacity(0.3);

    return MouseRegion(
      onEnter: (_) {
        if (widget.enabled) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (widget.enabled) setState(() => _hovered = false);
      },
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: widget.enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: widget.enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: _pressed
                ? Colors.white.withOpacity(0.10)
                : _hovered
                ? Colors.white.withOpacity(0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hovered
                  ? Colors.white.withOpacity(0.12)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFE27457).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(widget.icon, color: baseColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.title,
                        style: TextStyle(
                            color: baseColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(widget.subtitle,
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: Colors.white.withOpacity(0.3), size: 18),
            ],
          ),
        ),
      ),
    );
  }
}