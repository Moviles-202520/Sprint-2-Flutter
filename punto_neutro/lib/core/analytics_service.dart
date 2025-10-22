import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:device_info_plus/device_info_plus.dart';

class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._internal();
  factory AnalyticsService() => _instance;
  AnalyticsService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  int? _sessionId;
  DateTime? _sessionStart;

  Future<void> startSession(int userProfileId) async {
    _sessionStart = DateTime.now();
    _sessionId = null;
    final deviceInfo = DeviceInfoPlugin();
    String deviceType = 'unknown';
    String os = 'unknown';
    try {
      // Android
      final android = await deviceInfo.androidInfo;
      deviceType = 'mobile';
      os = 'Android ${android.version.release}';
    } catch (_) {
      try {
        // iOS
        final ios = await deviceInfo.iosInfo;
        deviceType = 'mobile';
        os = 'iOS ${ios.systemVersion}';
      } catch (_) {
        try {
          // Web
          final web = await deviceInfo.webBrowserInfo;
          deviceType = 'web';
          os = web.userAgent ?? 'web';
        } catch (_) {
          try {
            // Windows
            final windows = await deviceInfo.windowsInfo;
            deviceType = 'desktop';
            os = 'Windows ${windows.productName}';
          } catch (_) {
            try {
              // MacOS
              final mac = await deviceInfo.macOsInfo;
              deviceType = 'desktop';
              os = 'MacOS ${mac.osRelease}';
            } catch (_) {
              try {
                // Linux
                final linux = await deviceInfo.linuxInfo;
                deviceType = 'desktop';
                os = 'Linux ${linux.prettyName}';
              } catch (_) {
                deviceType = 'unknown';
                os = 'unknown';
              }
            }
          }
        }
      }
    }
    try {
      final response = await _supabase.from('user_sessions').insert({
        'user_profile_id': userProfileId,
        'start_time': _sessionStart!.toIso8601String(),
        'device_type': deviceType,
        'operating_system': os,
        'used_category_filter': false,
        'articles_viewed': 0,
      }).select('user_session_id');
      print('✅ [SESSION] Insert response: $response');
      if (response.isNotEmpty && response.first['user_session_id'] != null) {
        _sessionId = response.first['user_session_id'] as int;
        print('✅ [SESSION] Session started with ID: $_sessionId');
      } else {
        print('❌ [SESSION] No session_id returned. Response: $response');
      }
    } catch (e, st) {
      print('❌ [SESSION] Error inserting session: $e');
      print('❌ [SESSION] StackTrace: $st');
      print('❌ [SESSION] user_profile_id sent: $userProfileId');
    }
  }

  Future<void> endSession() async {
    print('🔔 [SESSION] endSession() llamado. sessionId: $_sessionId, sessionStart: $_sessionStart');
    if (_sessionId == null || _sessionStart == null) {
      print('⚠️ [SESSION] No hay sesión activa para cerrar.');
      return;
    }
    final endTime = DateTime.now();
    final duration = endTime.difference(_sessionStart!).inSeconds;
    print('📊 [SESSION] Actualizando: end_time=${endTime.toIso8601String()}, duration_seconds=$duration');
    await _supabase.from('user_sessions').update({
      'end_time': endTime.toIso8601String(),
      'duration_seconds': duration,
    }).eq('user_session_id', _sessionId!);
    print('✅ [SESSION] end_time y duration_seconds actualizados correctamente');
    _sessionId = null;
    _sessionStart = null;
  }

  Future<void> trackCommentStarted(int newsItemId) async {
    try {
      print('📝 [EVENT] trackCommentStarted - newsItemId: $newsItemId, sessionId: $_sessionId');
      final sessionId = _sessionId;
      await _supabase.from('engagement_events').insert({
        'user_profile_id': null,
        'user_session_id': sessionId,
        'news_item_id': newsItemId,
        'event_type': 'comment',
        'action': 'started',
      });
      print('✅ [EVENT] Comment started registrado exitosamente');
    } catch (e, st) {
      print('❌ [EVENT] Error en trackCommentStarted: $e');
      print(st);
    }
  }

  Future<void> trackCommentCompleted(int newsItemId, int userProfileId, String content) async {
    try {
      print('📝 [EVENT] trackCommentCompleted - newsItemId: $newsItemId, userId: $userProfileId, sessionId: $_sessionId');
      final now = DateTime.now().toUtc().toIso8601String();
      await _supabase.from('comments').insert({
        'news_item_id': newsItemId,
        'user_profile_id': userProfileId,
        'user_name': 'You',
        'content': content,
        'timestamp': now,
        'started_at': now,
        'completed_at': now,
        'is_completed': true,
      });
      await _supabase.from('engagement_events').insert({
        'user_profile_id': userProfileId,
        'user_session_id': _sessionId,
        'news_item_id': newsItemId,
        'event_type': 'comment',
        'action': 'completed',
      });
      print('✅ [EVENT] Comment completed registrado exitosamente');
    } catch (e, st) {
      print('❌ [EVENT] Error en trackCommentCompleted: $e');
      print(st);
    }
  }

  Future<void> trackFilterApplied(int categoryId) async {
    print('🔔 [FILTER] trackFilterApplied() llamado. categoryId: $categoryId, sessionId: $_sessionId');
    if (_sessionId == null) {
      print('⚠️ [FILTER] No hay sesión activa, no se puede registrar filtro.');
      return;
    }
    await _supabase.from('viewed_categories').insert({
      'category_id': categoryId,
      'user_session_id': _sessionId!,
    });
    await _supabase.from('user_sessions').update({
      'used_category_filter': true,
    }).eq('user_session_id', _sessionId!);
    print('✅ [FILTER] used_category_filter actualizado a TRUE para sessionId: $_sessionId');
  }

  Future<void> trackRatingGiven(int newsItemId, int userProfileId, double score, String comment) async {
    try {
      print('⭐ [EVENT] trackRatingGiven - newsItemId: $newsItemId, userId: $userProfileId, score: $score, sessionId: $_sessionId');
      final now = DateTime.now().toUtc().toIso8601String();
      await _supabase.from('rating_items').insert({
        'news_item_id': newsItemId,
        'user_profile_id': userProfileId,
        'assigned_reliability_score': score,
        'comment_text': comment,
        'rating_date': now,
        'started_at': now,
        'completed_at': now,
        'is_completed': true,
      });
      await _supabase.from('engagement_events').insert({
        'user_profile_id': userProfileId,
        'user_session_id': _sessionId,
        'news_item_id': newsItemId,
        'event_type': 'rating',
        'action': 'completed',
      });
      print('✅ [EVENT] Rating given registrado exitosamente');
    } catch (e, st) {
      print('❌ [EVENT] Error en trackRatingGiven: $e');
      print(st);
    }
  }

  Future<void> trackRatingStarted(int newsItemId, int userProfileId) async {
    try {
      print('⭐ [EVENT] trackRatingStarted - newsItemId: $newsItemId, userId: $userProfileId, sessionId: $_sessionId');
      await _supabase.from('engagement_events').insert({
        'user_profile_id': userProfileId,
        'user_session_id': _sessionId,
        'news_item_id': newsItemId,
        'event_type': 'rating',
        'action': 'started',
      });
      print('✅ [EVENT] Rating started registrado exitosamente');
    } catch (e, st) {
      print('❌ [EVENT] Error en trackRatingStarted: $e');
      print(st);
    }
  }

  Future<void> incrementArticlesViewed() async {
    if (_sessionId == null) return;
    final session = await _supabase.from('user_sessions').select('articles_viewed').eq('user_session_id', _sessionId!).single();
    final current = session['articles_viewed'] ?? 0;
    await _supabase.from('user_sessions').update({
      'articles_viewed': current + 1,
    }).eq('user_session_id', _sessionId!);
  }
}
