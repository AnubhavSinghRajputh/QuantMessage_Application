// lib/screens/widgets/attachment_thumbnail.dart

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../../core/chat_message.dart';
import '../../core/attachment_model.dart';

/// Renders a list of attachments inline within a chat message bubble.
class AttachmentList extends StatelessWidget {
  final List<Attachment> attachments;

  const AttachmentList({super.key, required this.attachments});

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children:
        attachments.map((a) => _AttachmentTile(attachment: a)).toList(),
      ),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  final Attachment attachment;
  const _AttachmentTile({required this.attachment});

  @override
  Widget build(BuildContext context) {
    if (attachment.isImage) return _buildImageTile(context);
    if (attachment.isPdf) return _buildPdfTile(context);
    return _buildGenericTile(context);
  }

  Widget _buildImageTile(BuildContext context) {
    final url = attachment.remoteUrl ?? attachment.thumbnailUrl;
    return GestureDetector(
      onTap: () {
        if (url != null) _showFullImage(context, url);
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(
            maxWidth: 260,
            maxHeight: 260,
          ),
          child: url != null
              ? CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            placeholder: (_, __) => _loadingBox(),
            errorWidget: (_, __, ___) =>
                _errorBox(Icons.broken_image_outlined),
          )
              : (attachment.localFile != null
              ? Image.file(attachment.localFile!, fit: BoxFit.cover)
              : _errorBox(Icons.broken_image_outlined)),
        ),
      ),
    );
  }

  Widget _buildPdfTile(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (attachment.remoteUrl != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => _PdfViewerPage(
                url: attachment.remoteUrl!,
                filename: attachment.filename,
              ),
            ),
          );
        }
      },
      child: Container(
        width: 240,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AttachmentColors.tileBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AttachmentColors.borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AttachmentColors.pdfBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.picture_as_pdf,
                  color: AttachmentColors.pdfIcon, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    attachment.filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    attachment.sizeFormatted,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.visibility_outlined,
                color: Colors.white.withOpacity(0.6), size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildGenericTile(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AttachmentColors.tileBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.insert_drive_file_outlined,
              color: Colors.white70, size: 16),
          const SizedBox(width: 6),
          Text(attachment.filename,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  void _showFullImage(BuildContext context, String url) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, __, ___) => _FullImageView(url: url),
      ),
    );
  }

  Widget _loadingBox() => Container(
    color: AttachmentColors.tileBg,
    child: const Center(
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );

  Widget _errorBox(IconData icon) => Container(
    color: AttachmentColors.tileBg,
    child: Icon(icon, color: Colors.white54),
  );
}

class _FullImageView extends StatelessWidget {
  final String url;
  const _FullImageView({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          InteractiveViewer(
            child: Center(
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                placeholder: (_, __) => const CircularProgressIndicator(),
              ),
            ),
          ),
          Positioned(
            top: 40,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _PdfViewerPage extends StatelessWidget {
  final String url;
  final String filename;
  const _PdfViewerPage({required this.url, required this.filename});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        title: Text(filename,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            overflow: TextOverflow.ellipsis),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SfPdfViewer.network(url),
    );
  }
}
