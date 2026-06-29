// lib/services/quant_space_api.dart
//
// QuantMessage — Backend API client (Supabase‑auth‑aware)
// -------------------------------------------------------
// Updated to:
//   • Read BACKEND_URL from .env (flutter_dotenv)
//   • Keep Dio‑MultipartFile disambiguation via `dio_pkg` alias
//   • Use the same default URL as the UploadService
//   • Preserve the original public API
// -------------------------------------------------------

import 'dart:convert';               // utf8, jsonDecode
import 'dart:typed_data';            // Uint8List
import 'dart:io' show Platform;

import 'package:dio/dio.dart' as dio_pkg;
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Convenience type aliases (keeps the rest of the file readable) ───────
typedef _Dio                       = dio_pkg.Dio;
typedef _BaseOptions               = dio_pkg.BaseOptions;
typedef _Options                   = dio_pkg.Options;
typedef _FormData                  = dio_pkg.FormData;
typedef _DioException              = dio_pkg.DioException;
typedef _ResponseBody              = dio_pkg.ResponseBody;
typedef _ResponseType              = dio_pkg.ResponseType;
typedef _RequestOptions            = dio_pkg.RequestOptions;
typedef _RequestInterceptorHandler = dio_pkg.RequestInterceptorHandler;
typedef _ErrorInterceptorHandler   = dio_pkg.ErrorInterceptorHandler;
// `dio_pkg.MultipartFile` is used explicitly wherever a multipart payload is built.
typedef _MultipartFile = dio_pkg.MultipartFile;

class QuantSpaceApi {
  // ── Instance fields ─────────────────────────────────────────────────────
  late final _Dio _dio;
  String? _sessionId;

  // The base URL is resolved once during construction.
  late final String baseUrl;

  // Default model used when the client does not specify one.
  static const String _defaultModel = 'gemini/gemini-1.5-flash';

  // ── Constructor ────────────────────────────────────────────────────────
  QuantSpaceApi() {
    // 1️⃣ Resolve the backend URL from the .env file.
    //    If the variable is missing we fall back to the same default
    //    used by `UploadService`.
    String calculatedBaseUrl =
        dotenv.maybeGet('BACKEND_URL') ??
            'https://your-app.up.railway.app/api/v1';

    // 2️⃣ Android emulator special‑case (10.0.2.2 points to host machine).
    if (!kIsWeb && Platform.isAndroid) {
      calculatedBaseUrl = dotenv.maybeGet('BACKEND_URL') ??
          'http://10.0.2.2:8000/api/v1';
    }

    baseUrl = calculatedBaseUrl;

    // ----------------------------------------------------------------------
    // Dio client configuration – JSON payloads + sensible time‑outs.
    // ----------------------------------------------------------------------
    _dio = _Dio(
      _BaseOptions(
        baseUrl: baseUrl,
        headers: {'Content-Type': 'application/json'},
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 60),
      ),
    );

    // Attach JWT on every request.
    _dio.interceptors.add(_AuthInterceptor());
  }

  // ── ----------------------------------------------------------------------
  //  CHAT (single request)
  // ───────────────────────────────────────────────────────────────────────
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

      // Preserve session tracking for successive calls.
      if (response.data['conversation_id'] != null) {
        _sessionId = response.data['conversation_id'];
      }

      return response.data as Map<String, dynamic>;
    } on _DioException catch (e) {
      debugPrint(
        '[QuantSpace API] Chat Error: ${e.response?.data ?? e.message}',
      );
      rethrow;
    }
  }

  /// Backward‑compatible helper used by the HomeScreen.
  Future<Map<String, dynamic>> chatSimple(String text,
      {String? model}) async {
    final result = await chat(text, model: model);
    return {
      'content': result['content'] ?? '',
      'conversation_id': result['conversation_id'],
    };
  }

  // ── ----------------------------------------------------------------------
  //  STREAMING CHAT (Server‑Sent Events)
  // ───────────────────────────────────────────────────────────────────────
  Stream<Map<String, dynamic>> streamChat(
      String message, {
        String? model,
        List<Map<String, String>>? attachments,
        String? conversationId,
        bool isIncognito = false,
        String? agentOverride,
      }) async* {
    try {
      final response = await _dio.post<_ResponseBody>(
        '/chat/stream',
        data: {
          'message': message,
          'model': model ?? _defaultModel,
          'conversation_id': conversationId ?? _sessionId,
          'is_incognito': isIncognito,
          if (agentOverride != null) 'agent_override': agentOverride,
          'attachments': attachments ?? [],
        },
        options: _Options(
          responseType: _ResponseType.stream,
          headers: {'Accept': 'text/event-stream'},
        ),
      );

      final Stream<Uint8List>? byteStream = response.data?.stream;
      if (byteStream == null) return;

      // --------------------------------------------------------------------
      // 3️⃣ Decode each Uint8List chunk manually (utf8.decode accepts Uint8List).
      // --------------------------------------------------------------------
      String buffer = '';
      await for (final Uint8List chunk in byteStream) {
        buffer += utf8.decode(chunk, allowMalformed: true);

        // SSE events are separated by a double newline.
        while (buffer.contains('\n\n')) {
          final end = buffer.indexOf('\n\n');
          final rawEvent = buffer.substring(0, end);
          buffer = buffer.substring(end + 2);

          if (rawEvent.startsWith('data: ')) {
            final jsonStr = rawEvent.substring(6).trim();
            if (jsonStr.isNotEmpty && jsonStr != '[DONE]') {
              try {
                final Map<String, dynamic> json =
                jsonDecode(jsonStr) as Map<String, dynamic>;
                yield json;
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
    } on _DioException catch (e) {
      debugPrint('[QuantSpace API] Stream Error: ${e.message}');
      rethrow;
    }
  }

  // ── ----------------------------------------------------------------------
  //  FILE UPLOAD
  // ───────────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> uploadFile(
      String filePath, {
        required String conversationId,
        void Function(double progress)? onProgress,
      }) async {
    try {
      final formData = _FormData.fromMap({
        'conversation_id': conversationId,
        'file': await _MultipartFile.fromFile(filePath),
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
    } on _DioException catch (e) {
      debugPrint('[QuantSpace API] Upload Error: ${e.message}');
      rethrow;
    }
  }

  // ── ----------------------------------------------------------------------
  //  CONVERSATION HISTORY
  // ───────────────────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getHistory({int limit = 50}) async {
    try {
      final response = await _dio.get(
        '/conversations/',
        queryParameters: {'limit': limit},
      );
      final List<dynamic> list = response.data['conversations'] as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    } on _DioException catch (e) {
      debugPrint('[QuantSpace API] History Error: ${e.message}');
      return [];
    }
  }

  Future<Map<String, dynamic>> getConversation(String conversationId) async {
    try {
      final response = await _dio.get('/conversations/$conversationId');
      return response.data as Map<String, dynamic>;
    } on _DioException catch (e) {
      debugPrint('[QuantSpace API] Conversation Error: ${e.message}');
      rethrow;
    }
  }

  Future<void> deleteConversation(String conversationId) async {
    try {
      await _dio.delete('/conversations/$conversationId');
    } on _DioException catch (e) {
      debugPrint('[QuantSpace API] Delete Error: ${e.message}');
      rethrow;
    }
  }

  // ── ----------------------------------------------------------------------
  //  USER SETTINGS
  // ───────────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getSettings() async {
    try {
      final response = await _dio.get('/settings/');
      return response.data as Map<String, dynamic>;
    } on _DioException catch (e) {
      debugPrint('[QuantSpace API] Settings Error: ${e.message}');
      return {};
    }
  }

  Future<Map<String, dynamic>> updateSettings(
      Map<String, dynamic> settings,
      ) async {
    try {
      final response = await _dio.put('/settings/', data: settings);
      return response.data as Map<String, dynamic>;
    } on _DioException catch (e) {
      debugPrint('[QuantSpace API] UpdateSettings Error: ${e.message}');
      rethrow;
    }
  }

  // ── ----------------------------------------------------------------------
  //  AGENT REGISTRY
  // ───────────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> listAgents() async {
    try {
      final response = await _dio.get('/agents/');
      return response.data as Map<String, dynamic>;
    } on _DioException catch (e) {
      debugPrint('[QuantSpace API] Agents Error: ${e.message}');
      return {};
    }
  }

  // ── ----------------------------------------------------------------------
  //  VOICE TRANSCRIPTION
  // ───────────────────────────────────────────────────────────────────────
  Future<String> transcribeAudio(String audioFilePath) async {
    try {
      final formData = _FormData.fromMap({
        'file': await _MultipartFile.fromFile(audioFilePath),
      });
      final response = await _dio.post('/voice/transcribe', data: formData);
      return response.data['text'] as String? ?? '';
    } on _DioException catch (e) {
      debugPrint('[QuantSpace API] Transcribe Error: ${e.message}');
      return '';
    }
  }

  // ── ----------------------------------------------------------------------
  //  LEGACY / COMPATIBILITY ENDPOINTS
  // ───────────────────────────────────────────────────────────────────────
  Future<List<dynamic>> getModels() async {
    try {
      final response = await _dio.get('/models');
      return response.data as List<dynamic>;
    } on _DioException catch (e) {
      debugPrint('[QuantSpace API] Model Fetch Error: ${e.message}');
      return [];
    }
  }

  Future<Map<String, dynamic>> getWeather(String location) async {
    try {
      final response = await _dio.get('/weather/$location');
      return response.data as Map<String, dynamic>;
    } on _DioException catch (e) {
      return {'error': 'Could not fetch weather: ${e.message}'};
    }
  }

  Future<Map<String, dynamic>> getIndicators(String ticker) async {
    try {
      final response = await _dio.get('/finance/stock/$ticker/indicators');
      return response.data['result'] ?? response.data;
    } catch (e) {
      debugPrint('[QuantSpace API] Finance Error: $e');
      rethrow;
    }
  }

  Future<String?> generateImage(String prompt) async {
    try {
      final response = await _dio.post('/chat/', data: {
        'message':
        'Generate a high-quality AI image: $prompt',
        'model': _defaultModel,
      });

      final content = response.data['content'] as String? ?? '';
      final RegExp urlRegex = RegExp(r'!\[.*?\]\((.*?)\)');
      final Match? match = urlRegex.firstMatch(content);
      return match?.group(1) ?? content;
    } catch (e) {
      debugPrint('[QuantSpace API] Image Gen Error: $e');
      return null;
    }
  }

  // ── ----------------------------------------------------------------------
  //  SESSION / HEALTH utilities
  // ───────────────────────────────────────────────────────────────────────
  void resetSession() {
    _sessionId = null;
    debugPrint('[QuantSpace API] Session Reset Requested');
  }

  Future<bool> healthCheck() async {
    try {
      final response = await _dio.get('/health');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void dispose() => _dio.close();
}

// ─────────────────────────────────────────────────────────────────────────────
//  Auth Interceptor – adds the Supabase JWT to every request
// ─────────────────────────────────────────────────────────────────────────────
class _AuthInterceptor extends dio_pkg.Interceptor {
  @override
  void onRequest(
      _RequestOptions options,
      _RequestInterceptorHandler handler,
      ) {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session?.accessToken != null) {
        options.headers['Authorization'] =
        'Bearer ${session!.accessToken}';
      }
    } catch (_) {
      // Supabase may not be initialised yet – the request will simply be unauthenticated.
    }
    handler.next(options);
  }

  @override
  void onError(_DioException err, _ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401) {
      debugPrint('[QuantSpace API] 401 Unauthorized — token may have expired');
    }
    handler.next(err);
  }
}