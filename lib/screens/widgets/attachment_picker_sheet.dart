// lib/screens/widgets/attachment_picker_sheet.dart

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

typedef AttachmentSelected = void Function(File file, String mimeType);

class AttachmentPickerSheet extends StatelessWidget {
  final AttachmentSelected onSelected;
  const AttachmentPickerSheet({super.key, required this.onSelected});

  static Future<void> show(
      BuildContext context, {
        required AttachmentSelected onSelected,
      }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => AttachmentPickerSheet(onSelected: onSelected),
    );
  }

  Future<void> _pickFromGallery(BuildContext context) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2400,
      imageQuality: 85,
    );
    if (image != null && context.mounted) {
      onSelected(File(image.path), 'image/${image.path.split('.').last}');
      Navigator.pop(context);
    }
  }

  Future<void> _takePhoto(BuildContext context) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 2400,
      imageQuality: 85,
    );
    if (image != null && context.mounted) {
      onSelected(File(image.path), 'image/jpeg');
      Navigator.pop(context);
    }
  }

  Future<void> _pickFile(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'txt', 'doc', 'docx'],
      withData: false,
    );
    if (result != null && result.files.single.path != null && context.mounted) {
      final file = File(result.files.single.path!);
      onSelected(file, _mimeFromExt(file.path));
      Navigator.pop(context);
    }
  }

  String _mimeFromExt(String path) {
    final ext = path.split('.').last.toLowerCase();
    return {
      'pdf': 'application/pdf',
      'txt': 'text/plain',
      'doc': 'application/msword',
      'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    }[ext] ??
        'application/octet-stream';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add to chat',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Upload an image or document for the AI to analyze',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 24),
            _buildOption(
              context,
              icon: Icons.image_outlined,
              title: 'Photo from Gallery',
              subtitle: 'JPG, PNG, WebP, GIF',
              onTap: () => _pickFromGallery(context),
            ),
            _buildOption(
              context,
              icon: Icons.camera_alt_outlined,
              title: 'Take a Photo',
              subtitle: 'Use your camera to capture something',
              onTap: () => _takePhoto(context),
            ),
            _buildOption(
              context,
              icon: Icons.picture_as_pdf_outlined,
              title: 'Document (PDF)',
              subtitle: 'Upload a PDF for analysis',
              onTap: () => _pickFile(context),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildOption(
      BuildContext context, {
        required IconData icon,
        required String title,
        required String subtitle,
        required VoidCallback onTap,
      }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                      )),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: Colors.white.withOpacity(0.3)),
          ],
        ),
      ),
    );
  }
}
