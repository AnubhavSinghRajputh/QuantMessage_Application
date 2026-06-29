// lib/core/attachment_model.dart

// lib/core/attachment_model.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'chat_message.dart';

/// Convenience helpers for [Attachment].
extension AttachmentX on Attachment {
  static Attachment fromFile(File file, {String? mimeOverride}) {
    final filename = file.path.split('/').last;
    final ext = filename.split('.').last.toLowerCase();
    final mime = mimeOverride ?? _mimeFromExt(ext);

    AttachmentType type;
    if (mime == 'application/pdf') {
      type = AttachmentType.pdf;
    } else if (mime.startsWith('image/')) {
      type = AttachmentType.image;
    } else if (mime.startsWith('text/')) {
      type = AttachmentType.text;
    } else {
      type = AttachmentType.unknown;
    }

    return Attachment(
      filename: filename,
      type: type,
      mimeType: mime,
      sizeBytes: file.lengthSync(),
      localFile: file,
      status: UploadStatus.pending,
    );
  }

  static String _mimeFromExt(String ext) {
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }
}

/// Color palette used by attachment tiles (matches dark theme).
class AttachmentColors {
  static const pdfBg = Color(0xFF3A2418);
  static const pdfIcon = Color(0xFFE27457);
  static const tileBg = Color(0xFF2A2A2A);
  static const borderColor = Color(0x1AFFFFFF); // white.withOpacity(0.1)
}
