// lib/services/upload_service.dart
//
// QuantMessage — File upload + multimodal chat messages
//
// -----------------------------------------------------------
// This file has been updated to:
//
// • Load the backend URL from a `.env` file (flutter_dotenv)
// • Use the `mime` package for MIME‑type detection
// • Add missing `http_parser` import for MediaType handling
// • Keep the same public API while improving readability
// -----------------------------------------------------------

import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart'; // <-- New import
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide MultipartFile;

import '../core/chat_message.dart';

/// Handles file uploads and multimodal chat interactions against the FastAPI backend.
class UploadService {
  // ── Configuration ────────────────────────────────────────────────────────

  /// Default backend URL – used only when the env var is missing.
  static const String _defaultBaseUrl = 'https://your-app.up.railway.app/api/v1';

  /// Resolve the base URL:
  ///   1. From the `.env` variable `BACKEND_URL` (optional).
  ///   2. If not set, fall back to the compile‑time constant [_defaultBaseUrl].
  ///
  /// **Important:** Call `await dotenv.load()` in `main()` before any widget
  /// runs, e.g.:
  ///
  /// ```dart
  /// Future<void> main() async {
  ///   WidgetsFlutterBinding.ensureInitialized();
  ///   await dotenv.load(fileName: ".env");
  ///   runApp(const MyApp());
  /// }
  /// ```
  String get _baseUrl {
    final envUrl = dotenv.maybeGet('BACKEND_URL');
    if (envUrl != null && envUrl.isNotEmpty) return envUrl;
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
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 30),
                receiveTimeout: const Duration(seconds: 60),
                sendTimeout: const Duration(seconds: 60),
              ),
            ),
        _fallbackClient = fallbackClient ?? http.Client() {
    // Attach the JWT automatically to all Dio requests.
    _dio.interceptors.add(_SupabaseAuthInterceptor(_supabase));
  }

  // ── Auth helpers ──────────────────────────────────────────────────────────

  /// Returns the current Supabase JWT or throws if the user is not logged in.
  String _accessToken() {
    final session = _supabase.auth.currentSession;
    if (session == null) {
      throw Exception('Not authenticated. Please sign in again.');
    }
    return session.accessToken;
  }

  /// JSON‑API request headers (auth + content‑type).
  Map<String, String> _jsonHeaders() => {
    'Authorization': 'Bearer ${_accessToken()}',
    'Content-Type': 'application/json',
  };

  // ═══════════════════════════════════════════════════════════════════════════
  //  UPLOAD (with real progress via Dio)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Uploads a file and returns an [Attachment] describing the remote resource.
  ///
  /// * **onProgress** – receives a value in the range `[0, 1]`.
  /// * **cancelToken** – optional Dio cancel token for user‑initiated aborts.
  /// * **maxRetries** – number of exponential‑backoff retries on transient errors.
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

    // Create multipart payload.
    final FormData formData = FormData.fromMap({
      'conversation_id': conversationId,
      'file': await MultipartFile.fromFile(
        file.path,
        filename: filename,
        contentType: MediaType.parse(mimeType), // MediaType from http_parser
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

        // Treat any 4xx/5xx as an error.
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
        // Propagate cancellations.
        if (CancelToken.isCancel(e)) rethrow;

        // Non‑retryable client errors (4xx) surface immediately.
        final code = e.response?.statusCode;
        if (code != null && code < 500) {
          throw Exception('Upload failed: ${e.response?.data ?? e.message}');
        }

        // Retry logic for transient / server errors.
        if (attempt > maxRetries) {
          throw Exception('Upload failed after $maxRetries retries: ${e.message}');
        }

        // Exponential back‑off with jitter.
        final delay = Duration(milliseconds: 500 * (1 << (attempt - 1)));
        await Future.delayed(delay);
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
          // Silently ignore malformed lines.
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
        contentType: MediaType.parse(_guessMime(filename)),
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

  /// Build an [Attachment] from the API response.
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

  /// Map the string token returned by the backend to the enum.
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

  /// Determine the MIME type for a filename.
  ///
  /// Uses the `mime` package, falling back to a generic binary MIME if the
  /// lookup fails.
  @visibleForTesting
  String _guessMime(String filename) {
    final mime = lookupMimeType(filename);
    return mime ?? 'application/octet-stream';
  }

  /// Close all underlying HTTP clients.
  void dispose() {
    _fallbackClient.close();
    _dio.close(force: true);
  }
}

// ───────────────────────────────────────────────────────────────────────────────
//  Auth Interceptor — auto‑attaches Supabase JWT to every Dio request
// ───────────────────────────────────────────────────────────────────────────────

class _SupabaseAuthInterceptor extends Interceptor {
  final SupabaseClient _supabase;

  _SupabaseAuthInterceptor(this._supabase);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    try {
      final session = _supabase.auth.currentSession;
      if (session != null) {
        options.headers['Authorization'] = 'Bearer ${session.accessToken}';
      }
    } catch (e) {
      // In production you might want to report this to an error‑tracking service.
      debugPrint('[UploadService] Auth interceptor error: $e');
    }
    handler.next(options);
  }
}