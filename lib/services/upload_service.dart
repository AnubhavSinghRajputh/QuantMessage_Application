// lib/services/upload_service.dart
//
// QuantMessage — File upload + multimodal chat messages
//

import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;

import 'package:dio/dio.dart';   // ← Get MultipartFile from dio
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;   // ← Full import
import 'package:supabase_flutter/supabase_flutter.dart' hide MultipartFile;  // ← Hide from supabase

import '../core/chat_message.dart';

/// Handles file uploads + multimodal chat messages against the FastAPI backend.
class UploadService {
  // ── Configuration ────────────────────────────────────────────────────────

  static const String _defaultBaseUrl =
      'https://your-app.up.railway.app/api/v1';

  String get _baseUrl {
    const fromEnv = String.fromEnvironment('BACKEND_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    return _defaultBaseUrl;
  }

  // ── Dependencies ──────────────────────────────────────────────────────────

  final SupabaseClient _supabase;
  final Dio _dio;
  final http.Client _fallbackClient;

  UploadService({
    SupabaseClient? supabase,
    Dio? dio,
    http.Client? fallbackClient,
  })  : _supabase = supabase ?? Supabase.instance.client,
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 60),
              sendTimeout: const Duration(seconds: 60),
            )),
        _fallbackClient = fallbackClient ?? http.Client() {
    _dio.interceptors.add(_SupabaseAuthInterceptor(_supabase));
  }

  // ── Auth helpers ──────────────────────────────────────────────────────────

  String _accessToken() {
    final session = _supabase.auth.currentSession;
    if (session == null) {
      throw Exception('Not authenticated. Please sign in again.');
    }
    return session.accessToken;
  }

  Map<String, String> _jsonHeaders() => {
    'Authorization': 'Bearer ${_accessToken()}',
    'Content-Type': 'application/json',
  };

  // ═══════════════════════════════════════════════════════════════════════════
  //  UPLOAD (with real progress via dio)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Attachment> uploadFile({
    required File file,
    required String conversationId,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
    int maxRetries = 2,
  }) async {
    final filename = file.path.split('/').last;
    final mimeType = _guessMime(filename);

    onProgress?.call(0.0);

    // ← dio.MultipartFile (in scope from `import 'package:dio/dio.dart';`)
    final FormData formData = FormData.fromMap({
      'conversation_id': conversationId,
      'file': await MultipartFile.fromFile(
        file.path,
        filename: filename,
      ),
    });

    int attempt = 0;
    while (true) {
      attempt++;
      try {
        final response = await _dio.post(
          '$_baseUrl/chat/upload',
          data: formData,
          options: Options(
            headers: {'Authorization': 'Bearer ${_accessToken()}'},
            contentType: 'multipart/form-data',
          ),
          cancelToken: cancelToken,
          onSendProgress: (sent, total) {
            if (total > 0 && onProgress != null) {
              onProgress(sent / total);
            }
          },
        );

        if (response.statusCode != null && response.statusCode! >= 400) {
          throw Exception(
            'Upload failed (${response.statusCode}): ${response.data}',
          );
        }

        onProgress?.call(1.0);

        final body = response.data as Map<String, dynamic>;
        return _parseAttachment(
          body: body,
          fallbackFilename: filename,
          fallbackMime: mimeType,
        );
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) rethrow;

        if (e.response?.statusCode != null &&
            e.response!.statusCode! < 500) {
          throw Exception(
              'Upload failed: ${e.response?.data ?? e.message}');
        }

        if (attempt > maxRetries) {
          throw Exception(
              'Upload failed after $maxRetries retries: ${e.message}');
        }

        await Future.delayed(
            Duration(milliseconds: 500 * (1 << (attempt - 1))));
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  CHAT MESSAGE (with attachments)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> sendMessageWithAttachments({
    required String message,
    required List<Attachment> attachments,
    String? conversationId,
    bool isIncognito = false,
    String? agentOverride,
  }) async {
    final response = await _fallbackClient.post(
      Uri.parse('$_baseUrl/chat/'),
      headers: _jsonHeaders(),
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

  // ═══════════════════════════════════════════════════════════════════════════
  //  Streaming chat (SSE)
  // ═══════════════════════════════════════════════════════════════════════════

  Stream<Map<String, dynamic>> streamMessageWithAttachments({
    required String message,
    required List<Attachment> attachments,
    String? conversationId,
    bool isIncognito = false,
    String? agentOverride,
  }) async* {
    final request = http.Request(
      'POST',
      Uri.parse('$_baseUrl/chat/stream'),
    );
    request.headers.addAll(_jsonHeaders());
    request.body = jsonEncode({
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
    });

    final http.StreamedResponse response =
    await _fallbackClient.send(request);
    if (response.statusCode >= 400) {
      final errorBody = await response.stream.bytesToString();
      throw Exception(
          'Stream API error (${response.statusCode}): $errorBody');
    }

    final body = await response.stream.bytesToString();
    final lines = const LineSplitter().convert(body);
    for (final line in lines) {
      if (line.startsWith('data: ')) {
        try {
          final json = jsonDecode(line.substring(6));
          if (json is Map<String, dynamic>) yield json;
        } catch (_) {
          // Skip malformed lines
        }
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Voice transcription
  // ═══════════════════════════════════════════════════════════════════════════

  Future<String> transcribeAudio(File audioFile) async {
    final filename = audioFile.path.split('/').last;
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        audioFile.path,
        filename: filename,
      ),
    });

    final response = await _dio.post(
      '$_baseUrl/voice/transcribe',
      data: formData,
      options: Options(
        headers: {'Authorization': 'Bearer ${_accessToken()}'},
        contentType: 'multipart/form-data',
      ),
    );

    if (response.statusCode != null && response.statusCode! >= 400) {
      throw Exception('Transcription failed: ${response.data}');
    }

    final body = response.data as Map<String, dynamic>;
    return body['text'] as String? ?? '';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Conversation history
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getHistory({int limit = 50}) async {
    final response = await _fallbackClient.get(
      Uri.parse('$_baseUrl/conversations/?limit=$limit'),
      headers: _jsonHeaders(),
    );
    if (response.statusCode >= 400) {
      throw Exception('History fetch failed: ${response.body}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(body['conversations'] ?? []);
  }

  Future<Map<String, dynamic>> getConversation(String conversationId) async {
    final response = await _fallbackClient.get(
      Uri.parse('$_baseUrl/conversations/$conversationId'),
      headers: _jsonHeaders(),
    );
    if (response.statusCode >= 400) {
      throw Exception('Conversation fetch failed: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> deleteConversation(String conversationId) async {
    final response = await _fallbackClient.delete(
      Uri.parse('$_baseUrl/conversations/$conversationId'),
      headers: _jsonHeaders(),
    );
    if (response.statusCode >= 400) {
      throw Exception('Delete failed: ${response.body}');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Settings
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> getSettings() async {
    final response = await _fallbackClient.get(
      Uri.parse('$_baseUrl/settings/'),
      headers: _jsonHeaders(),
    );
    if (response.statusCode >= 400) {
      throw Exception('Settings fetch failed: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateSettings(
      Map<String, dynamic> settings) async {
    final response = await _fallbackClient.put(
      Uri.parse('$_baseUrl/settings/'),
      headers: _jsonHeaders(),
      body: jsonEncode(settings),
    );
    if (response.statusCode >= 400) {
      throw Exception('Settings update failed: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Agent registry
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> listAgents() async {
    final response = await _fallbackClient.get(
      Uri.parse('$_baseUrl/agents/'),
      headers: _jsonHeaders(),
    );
    if (response.statusCode >= 400) {
      throw Exception('Agents fetch failed: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Health check
  // ═══════════════════════════════════════════════════════════════════════════

  Future<bool> healthCheck() async {
    try {
      final response =
      await _fallbackClient.get(Uri.parse('$_baseUrl/health'));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Helpers
  // ═══════════════════════════════════════════════════════════════════════════

  Attachment _parseAttachment({
    required Map<String, dynamic> body,
    required String fallbackFilename,
    required String fallbackMime,
  }) {
    return Attachment(
      id: body['attachment_id'] as String?,
      filename: body['filename'] as String? ?? fallbackFilename,
      type: _parseType(body['file_type'] as String?),
      mimeType: body['mime_type'] as String? ?? fallbackMime,
      sizeBytes: body['file_size_bytes'] as int? ?? 0,
      remoteUrl: body['public_url'] as String?,
      thumbnailUrl: body['thumbnail_url'] as String?,
      extractedText: body['extracted_text'] as String?,
      status: UploadStatus.completed,
      progress: 1.0,
    );
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

  String _guessMime(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return {
      'pdf': 'application/pdf',
      'png': 'image/png',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'webp': 'image/webp',
      'gif': 'image/gif',
      'txt': 'text/plain',
      'mp3': 'audio/mpeg',
      'wav': 'audio/wav',
      'm4a': 'audio/mp4',
      'ogg': 'audio/ogg',
    }[ext] ??
        'application/octet-stream';
  }

  void dispose() {
    _fallbackClient.close();
    _dio.close();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Auth Interceptor — auto-attaches Supabase JWT to every Dio request
// ═══════════════════════════════════════════════════════════════════════════

class _SupabaseAuthInterceptor extends Interceptor {
  final SupabaseClient _supabase;
  _SupabaseAuthInterceptor(this._supabase);

  @override
  void onRequest(
      RequestOptions options,
      RequestInterceptorHandler handler,
      ) {
    try {
      final session = _supabase.auth.currentSession;
      if (session != null) {
        options.headers['Authorization'] = 'Bearer ${session.accessToken}';
      }
    } catch (e) {
      debugPrint('[UploadService] Auth interceptor: $e');
    }
    handler.next(options);
  }
}
