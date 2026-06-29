// lib/services/upload_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/chat_message.dart';

/// Talks to the FastAPI backend for file uploads + multimodal messages.
class UploadService {
  /// ⚠️ Change this to your Railway URL once deployed.
  static const String _baseUrl =
      'https://your-app.up.railway.app/api/v1';

  final SupabaseClient _supabase;
  final http.Client _client;

  UploadService({SupabaseClient? supabase, http.Client? client})
      : _supabase = supabase ?? Supabase.instance.client,
        _client = client ?? http.Client();

  Map<String, String> _authHeaders() {
    final session = _supabase.auth.currentSession;
    if (session == null) {
      throw Exception('Not authenticated. Please sign in again.');
    }
    return {
      'Authorization': 'Bearer ${session.accessToken}',
    };
  }

  /// Upload a single file. Returns the [Attachment] in its completed state.
  Future<Attachment> uploadFile({
    required File file,
    required String conversationId,
    void Function(double progress)? onProgress,
  }) async {
    final filename = file.path.split('/').last;

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/chat/upload'),
    );
    request.headers.addAll(_authHeaders());
    request.fields['conversation_id'] = conversationId;
    request.files.add(
      await http.MultipartFile.fromPath('file', file.path,
          filename: filename),
    );

    onProgress?.call(0.1);
    final streamed = await _client.send(request);

    // Best-effort progress simulation for now — http package doesn't expose
    // true streaming progress for multipart; backend reports completion.
    onProgress?.call(0.5);

    final response = await http.Response.fromStream(streamed);

    if (response.statusCode >= 400) {
      throw Exception(
          'Upload failed (${response.statusCode}): ${response.body}');
    }

    onProgress?.call(1.0);

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    return Attachment(
      id: body['attachment_id'] as String?,
      filename: body['filename'] as String? ?? filename,
      type: _parseType(body['file_type'] as String?),
      mimeType: body['mime_type'] as String? ?? 'application/octet-stream',
      sizeBytes: body['file_size_bytes'] as int? ?? 0,
      remoteUrl: body['public_url'] as String?,
      thumbnailUrl: body['thumbnail_url'] as String?,
      extractedText: body['extracted_text'] as String?,
      status: UploadStatus.completed,
      progress: 1.0,
    );
  }

  /// Send a chat message that references one or more uploaded attachments.
  Future<Map<String, dynamic>> sendMessageWithAttachments({
    required String message,
    required List<Attachment> attachments,
    String? conversationId,
    bool isIncognito = false,
    String? agentOverride,
  }) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/chat/'),
      headers: {
        ..._authHeaders(),
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'message': message,
        'conversation_id': conversationId,
        'is_incognito': isIncognito,
        if (agentOverride != null) 'agent_override': agentOverride,
        'attachments': attachments
            .where((a) => a.id != null)
            .map((a) => {
          'id': a.id,
          'type': a.type.name,
          'filename': a.filename,
        })
            .toList(),
      }),
    );

    if (response.statusCode >= 400) {
      throw Exception(
          'Chat API error (${response.statusCode}): ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  AttachmentType _parseType(String? t) {
    switch (t) {
      case 'pdf':
        return AttachmentType.pdf;
      case 'image':
        return AttachmentType.image;
      case 'text':
        return AttachmentType.text;
      default:
        return AttachmentType.unknown;
    }
  }
}
