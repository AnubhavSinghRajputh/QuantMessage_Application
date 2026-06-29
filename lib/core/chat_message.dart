// lib/core/chat_message.dart
//
// QuantMessage — Chat data models
//

import 'dart:io';

/// Type of attached file.
enum AttachmentType { pdf, image, text, unknown }

/// Upload lifecycle for a single attachment.
enum UploadStatus {
  pending,
  uploading,
  processing,
  completed,
  failed,
}

/// Represents a file attached to a chat message.
class Attachment {
  final String? id;
  final String filename;
  final AttachmentType type;
  final String mimeType;
  final int sizeBytes;
  File? localFile;
  String? remoteUrl;
  String? thumbnailUrl;
  String? extractedText;
  UploadStatus status;
  double progress;

  Attachment({
    this.id,
    required this.filename,
    required this.type,
    required this.mimeType,
    required this.sizeBytes,
    this.localFile,
    this.remoteUrl,
    this.thumbnailUrl,
    this.extractedText,
    this.status = UploadStatus.pending,
    this.progress = 0.0,
  });

  String get sizeFormatted {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  bool get isImage => type == AttachmentType.image;
  bool get isPdf => type == AttachmentType.pdf;
  bool get isReady =>
      status == UploadStatus.completed && remoteUrl != null;

  /// Clamped progress update.
  Attachment withProgress(double newProgress) {
    final clamped = newProgress.clamp(0.0, 1.0);
    return copyWith(progress: clamped);
  }

  /// Mark this attachment as failed (for retry UI).
  Attachment markFailed() => copyWith(status: UploadStatus.failed);

  /// Returns a copy with selected fields replaced.
  /// Now PUBLIC (no underscore) and includes `localFile`.
  Attachment copyWith({
    String? id,
    String? filename,
    AttachmentType? type,
    String? mimeType,
    int? sizeBytes,
    File? localFile,
    String? remoteUrl,
    String? thumbnailUrl,
    String? extractedText,
    UploadStatus? status,
    double? progress,
  }) {
    return Attachment(
      id: id ?? this.id,
      filename: filename ?? this.filename,
      type: type ?? this.type,
      mimeType: mimeType ?? this.mimeType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      localFile: localFile ?? this.localFile,
      remoteUrl: remoteUrl ?? this.remoteUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      extractedText: extractedText ?? this.extractedText,
      status: status ?? this.status,
      progress: progress ?? this.progress,
    );
  }
}

/// The single source of truth for a chat bubble.
class ChatMessage {
  final String text;
  final bool isUser;
  final String modelName;
  final List<Attachment> attachments;
  final bool isStreaming;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.modelName = "",
    this.attachments = const [],
    this.isStreaming = false,
  });

  bool get hasAttachments => attachments.isNotEmpty;
  bool get hasText => text.trim().isNotEmpty;

  ChatMessage copyWith({
    String? text,
    List<Attachment>? attachments,
    bool? isStreaming,
  }) {
    return ChatMessage(
      text: text ?? this.text,
      isUser: isUser,
      modelName: modelName,
      attachments: attachments ?? this.attachments,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }
}
