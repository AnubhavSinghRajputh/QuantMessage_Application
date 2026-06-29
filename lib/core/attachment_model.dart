// lib/core/attachment_model.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mime/mime.dart';               // ← new: MIME lookup
import 'package:path/path.dart' as p;          // ← new: path utilities

import 'chat_message.dart';

/// Convenience helpers for [Attachment].
extension AttachmentX on Attachment {
  /// Creates an [Attachment] instance from a local [File].
  ///
  /// The [mimeOverride] parameter can be used to force a specific MIME
  /// type (useful for files with ambiguous extensions).
  static Attachment fromFile(File file, {String? mimeOverride}) {
    // Use `path` to safely extract the filename.
    final filename = p.basename(file.path);

    // Resolve the MIME type: either the override or a lookup based on the path.
    final mime = mimeOverride ?? _mimeFromPath(file.path);

    // Determine the attachment type based on the MIME.
    final type = _typeFromMime(mime);

    return Attachment(
      filename: filename,
      type: type,
      mimeType: mime,
      sizeBytes: file.lengthSync(),
      localFile: file,
      status: UploadStatus.pending,
    );
  }

  /// Internal helper that maps a MIME string to an [AttachmentType].
  static AttachmentType _typeFromMime(String mime) {
    if (mime == 'application/pdf') {
      return AttachmentType.pdf;
    } else if (mime.startsWith('image/')) {
      return AttachmentType.image;
    } else if (mime.startsWith('text/')) {
      return AttachmentType.text;
    } else {
      return AttachmentType.unknown;
    }
  }

  /// Retrieves the MIME type for a given file path using the `mime` package.
  ///
  /// Falls back to `application/octet-stream` when the lookup fails.
  static String _mimeFromPath(String filePath) {
    return lookupMimeType(filePath) ?? 'application/octet-stream';
  }
}

/// Color palette used by attachment tiles (matches dark theme).
class AttachmentColors {
  static const pdfBg = Color(0xFF3A2418);
  static const pdfIcon = Color(0xFFE27457);
  static const tileBg = Color(0xFF2A2A2A);
  static const borderColor = Color(0x1AFFFFFF); // white.withOpacity(0.1)
}