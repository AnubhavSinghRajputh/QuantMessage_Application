// lib/screens/widgets/attachment_preview.dart

import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/chat_message.dart';
import '../../core/attachment_model.dart';

/// Horizontal scrollable strip of pending attachments above the input.
class AttachmentPreviewStrip extends StatelessWidget {
  final List<Attachment> attachments;
  final ValueChanged<int> onRemove;

  const AttachmentPreviewStrip({
    super.key,
    required this.attachments,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        height: 80,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          itemCount: attachments.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            return _AttachmentChip(
              attachment: attachments[index],
              onRemove: () => onRemove(index),
            );
          },
        ),
      ),
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  final Attachment attachment;
  final VoidCallback onRemove;

  const _AttachmentChip({required this.attachment, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: AttachmentColors.tileBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AttachmentColors.borderColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: _buildThumbnail(),
        ),

        // Remove (×) button
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: Colors.black,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
              ),
              child: const Icon(Icons.close,
                  size: 12, color: Colors.white),
            ),
          ),
        ),

        // Upload overlay
        if (attachment.status == UploadStatus.uploading ||
            attachment.status == UploadStatus.processing)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: attachment.status == UploadStatus.uploading
                        ? attachment.progress
                        : null,
                    valueColor:
                    const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            ),
          ),

        // Failed badge
        if (attachment.status == UploadStatus.failed)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Icon(Icons.error_outline,
                    color: Colors.white, size: 20),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildThumbnail() {
    if (attachment.type == AttachmentType.image) {
      if (attachment.localFile != null) {
        return Image.file(attachment.localFile!, fit: BoxFit.cover);
      }
      if (attachment.thumbnailUrl != null) {
        return CachedNetworkImage(
          imageUrl: attachment.thumbnailUrl!,
          fit: BoxFit.cover,
          placeholder: (_, __) => _placeholder(Icons.image_outlined),
          errorWidget: (_, __, ___) =>
              _placeholder(Icons.broken_image_outlined),
        );
      }
    }

    if (attachment.type == AttachmentType.pdf) {
      return Container(
        color: AttachmentColors.pdfBg,
        child: const Center(
          child: Icon(Icons.picture_as_pdf,
              color: AttachmentColors.pdfIcon, size: 28),
        ),
      );
    }

    return _placeholder(Icons.insert_drive_file_outlined);
  }

  Widget _placeholder(IconData icon) {
    return Container(
      color: AttachmentColors.tileBg,
      child: Center(child: Icon(icon, color: Colors.white54, size: 24)),
    );
  }
}
