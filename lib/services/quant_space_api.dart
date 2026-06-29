// lib/services/quant_space_api.dart
//
// QuantMessage — Backend API client (Supabase-auth-aware)
//

import 'dart:async';
import 'dart:convert';                              // ← utf8 + jsonDecode
import 'dart:io' show File, Platform;               // ← explicit imports

import 'package:dio/dio.dart' hide MultipartFile;  // ← hide dio's MultipartFile
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;            // ← use http's MultipartFile
import 'package:supabase_flutter/supabase_flutter.dart';

class QuantSpaceApi {
  late Dio _dio;
  String? _sessionId;

  late final String baseUrl;
  static const String _defaultModel = 'gemini/gemini-1.5-flash';

  QuantSpaceApi() {
    // ── Auto-discover backend URL ──────────────────────────────────────────
    String calculatedBaseUrl =
        dotenv.env['BACKEND_URL'] ?? 'http://localhost:8000/api/v1';

    if (!kIsWeb && Platform.isAndroid) {
      calculatedBaseUrl =
          dotenv.env['BACKEND_URL'] ?? 'http://10.0.2.2:8000/api/v1';
    }

    baseUrl = calculatedBaseUrl;

    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        headers: {
          'Content-Type': 'application/json',
        },
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 60),
      ),
    );

    // Add Supabase auth interceptor — attaches Bearer token to every request
    _dio.interceptors.add(_AuthInterceptor());
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Chat
  // ═══════════════════════════════════════════════════════════════════════════

  /// Send a chat message. Supports attachments via the [attachments] param.
  Future<Map<String, dynamic>> chat(
      String message, {
        String? model,
        List<Map<String, String>>? attachments,
        String? conversationId,
        bool isIncognito = false,
        String? agentOverride,
        bool stream = false,
      }) async {
    try {
      final response = await _dio.post(
        '/chat/',
        data: {
          'message': message,
          'model': model ?? _defaultModel,
          'conversation_id': conversationId ?? _sessionId,
          'is_incognito': isIncognito,
          if (agentOverride != null) 'agent_override': agentOverride,
          'stream': stream,
          'attachments': attachments ?? [],
          'session_id': _sessionId,
        },
      );

      // Persist session across multiple turns
      if (response.data['conversation_id'] != null) {
        _sessionId = response.data['conversation_id'];
      }

      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      debugPrint('[QuantSpace API] Chat Error: '
          '${e.response?.data ?? e.message}');
      rethrow;
    }
  }

  /// Backward-compatible simple chat (for main.dart HomeScreen)
  Future<Map<String, dynamic>> chatSimple(String text, {String? model}) async {
    final response = await chat(text, model: model);
    return {
      'content': response['content'] ?? '',
      'conversation_id': response['conversation_id'],
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Streaming chat (Server-Sent Events)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Stream chat via Server-Sent Events.
  /// Yields JSON chunks as they arrive from the server.
  Stream<Map<String, dynamic>> streamChat(
      String message, {
        String? model,
        List<Map<String, String>>? attachments,
        String? conversationId,
        bool isIncognito = false,
        String? agentOverride,
      }) async* {
    try {
      final response = await _dio.post<ResponseBody>(
        '/chat/stream',
        data: {
          'message': message,
          'model': model ?? _defaultModel,
          'conversation_id': conversationId ?? _sessionId,
          'is_incognito': isIncognito,
          if (agentOverride != null) 'agent_override': agentOverride,
          'attachments': attachments ?? [],
        },
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Accept': 'text/event-stream'},
        ),
      );

      final stream = response.data?.stream;
      if (stream == null) return;

      String buffer = '';

      // ← FIX 1: Cast to List<int> first, then decode
      await for (final chunk
      in stream.cast<List<int>>().transform(utf8.decoder)) {
        buffer += chunk;

        // SSE events are separated by \n\n
        while (buffer.contains('\n\n')) {
          final endIndex = buffer.indexOf('\n\n');
          final event = buffer.substring(0, endIndex);
          buffer = buffer.substring(endIndex + 2);

          if (event.startsWith('data: ')) {
            final jsonStr = event.substring(6).trim();
            if (jsonStr.isNotEmpty && jsonStr != '[DONE]') {
              try {
                // ← FIX 2: jsonDecode now works (dart:convert imported)
                final json = jsonDecode(jsonStr) as Map<String, dynamic>;
                yield json;

                // Update session id if present
                if (json['conversation_id'] != null) {
                  _sessionId = json['conversation_id'];
                }
              } catch (e) {
                debugPrint('[QuantSpace API] SSE parse error: $e');
              }
            }
          }
        }
      }
    } on DioException catch (e) {
      debugPrint('[QuantSpace API] Stream Error: ${e.message}');
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  File upload (uses http.MultipartFile to avoid clash)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Upload a file to the backend. Returns the attachment metadata.
  /// Pass [onProgress] for upload progress (0.0 → 1.0).
  Future<Map<String, dynamic>> uploadFile(
      String filePath, {
        required String conversationId,
        void Function(double progress)? onProgress,
      }) async {
    try {
      final filename = filePath.split('/').last;

      // ← FIX 3: Use http.MultipartFile explicitly
      final formData = FormData.fromMap({
        'conversation_id': conversationId,
        'file': await http.MultipartFile.fromPath(
          'file',
          filePath,
          filename: filename,
        ),
      });

      final response = await _dio.post(
        '/chat/upload',
        data: formData,
        onSendProgress: (sent, total) {
          if (total > 0 && onProgress != null) {
            onProgress(sent / total);
          }
        },
      );

      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      debugPrint('[QuantSpace API] Upload Error: ${e.message}');
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Conversations (history)
  // ═══════════════════════════════════════════════════════════════════════════

  /// List user's conversation history (excludes incognito).
  Future<List<Map<String, dynamic>>> getHistory({int limit = 50}) async {
    try {
      final response = await _dio.get(
        '/conversations/',
        queryParameters: {'limit': limit},
      );
      final list = response.data['conversations'] as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      debugPrint('[QuantSpace API] History Error: ${e.message}');
      return [];
    }
  }

  /// Get a single conversation with all its messages.
  Future<Map<String, dynamic>> getConversation(String conversationId) async {
    try {
      final response = await _dio.get('/conversations/$conversationId');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      debugPrint('[QuantSpace API] Conversation Error: ${e.message}');
      rethrow;
    }
  }

  /// Delete a conversation (cascades to messages and attachments).
  Future<void> deleteConversation(String conversationId) async {
    try {
      await _dio.delete('/conversations/$conversationId');
    } on DioException catch (e) {
      debugPrint('[QuantSpace API] Delete Error: ${e.message}');
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  User settings
  // ═══════════════════════════════════════════════════════════════════════════

  /// Fetch the user's saved settings.
  Future<Map<String, dynamic>> getSettings() async {
    try {
      final response = await _dio.get('/settings/');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      debugPrint('[QuantSpace API] Settings Error: ${e.message}');
      return {};
    }
  }

  /// Update user settings (partial update).
  Future<Map<String, dynamic>> updateSettings(
      Map<String, dynamic> settings) async {
    try {
      final response = await _dio.put(
        '/settings/',
        data: settings,
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      debugPrint('[QuantSpace API] UpdateSettings Error: ${e.message}');
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Agents
  // ═══════════════════════════════════════════════════════════════════════════

  /// List available AI agents.
  Future<Map<String, dynamic>> listAgents() async {
    try {
      final response = await _dio.get('/agents/');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      debugPrint('[QuantSpace API] Agents Error: ${e.message}');
      return {};
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Voice (STT / TTS)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Transcribe an audio file to text via the backend.
  Future<String> transcribeAudio(String audioFilePath) async {
    try {
      final filename = audioFilePath.split('/').last;
      final formData = FormData.fromMap({
        'file': await http.MultipartFile.fromPath(
          'file',
          audioFilePath,
          filename: filename,
        ),
      });
      final response = await _dio.post('/voice/transcribe', data: formData);
      return response.data['text'] as String? ?? '';
    } on DioException catch (e) {
      debugPrint('[QuantSpace API] Transcribe Error: ${e.message}');
      return '';
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Legacy methods (for backward compatibility with main.dart)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Fetches the dynamic list of models supported by the backend.
  Future<List<dynamic>> getModels() async {
    try {
      final response = await _dio.get('/models');
      return response.data as List<dynamic>;
    } on DioException catch (e) {
      debugPrint('[QuantSpace API] Model Fetch Error: ${e.message}');
      return [];
    }
  }

  /// Specialized: Fetch Weather data.
  Future<Map<String, dynamic>> getWeather(String location) async {
    try {
      final response = await _dio.get('/weather/$location');
      return response.data;
    } on DioException catch (e) {
      return {'error': 'Could not fetch weather: ${e.message}'};
    }
  }

  /// Specialized: Fetch Financial Indicators for charts.
  Future<Map<String, dynamic>> getIndicators(String ticker) async {
    try {
      final response = await _dio.get('/finance/stock/$ticker/indicators');
      return response.data['result'] ?? response.data;
    } catch (e) {
      debugPrint('[QuantSpace API] Finance Error: $e');
      rethrow;
    }
  }

  /// AI Image generation (legacy method used by HomeScreen).
  Future<String?> generateImage(String prompt) async {
    try {
      final response = await _dio.post('/chat/', data: {
        'message': 'Generate a high-quality AI image: $prompt',
        'model': _defaultModel,
      });

      final content = response.data['content'] as String? ?? '';
      final regExp = RegExp(r'!\[.*?\]\((.*?)\)');
      final match = regExp.firstMatch(content);

      return match?.group(1) ?? content;
    } catch (e) {
      debugPrint('[QuantSpace API] Image Gen Error: $e');
      return null;
    }
  }

  /// Clears the current conversation thread and server-side session.
  void resetSession() {
    _sessionId = null;
    debugPrint('[QuantSpace API] Session Reset Requested');
  }

  /// Health check — returns true if backend is reachable.
  Future<bool> healthCheck() async {
    try {
      final response = await _dio.get('/health');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Clean shutdown — closes the Dio client.
  void dispose() {
    _dio.close();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Auth Interceptor — attaches Supabase JWT to every request
// ═══════════════════════════════════════════════════════════════════════════

class _AuthInterceptor extends Interceptor {
  @override
  void onRequest(
      RequestOptions options,
      RequestInterceptorHandler handler,
      ) {
    // Attach the current Supabase user's access token
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session?.accessToken != null) {
        options.headers['Authorization'] =
        'Bearer ${session!.accessToken}';
      }
    } catch (e) {
      // Supabase not initialized yet — request will fail at backend
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401) {
      debugPrint('[QuantSpace API] 401 Unauthorized — token expired');
      // Optionally: Supabase.instance.client.auth.signOut();
    }
    handler.next(err);
  }
}
