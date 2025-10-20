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
      final android = await deviceInfo.androidInfo;
      deviceType = 'mobile';
      os = 'Android ${android.version.release}';
    } catch (_) {
      try {
        final ios = await deviceInfo.iosInfo;
        deviceType = 'mobile';
        os = 'iOS ${ios.systemVersion}';
      } catch (_) {}
    }
    final response = await _supabase.from('user_sessions').insert({
      'user_profile_id': userProfileId,
      'start_time': _sessionStart!.toIso8601String(),
      'device_type': deviceType,
      'operating_system': os,
      'used_category_filter': false,
      'articles_viewed': 0,
    }).select('user_session_id');
    _sessionId = response.first['user_session_id'] as int;
  }

  Future<void> endSession() async {
    if (_sessionId == null || _sessionStart == null) return;
    final endTime = DateTime.now();
    final duration = endTime.difference(_sessionStart!).inSeconds;
    await _supabase.from('user_sessions').update({
      'end_time': endTime.toIso8601String(),
      'duration_seconds': duration,
    }).eq('user_session_id', _sessionId!);
    _sessionId = null;
    _sessionStart = null;
  }

  Future<void> trackCommentStarted(int newsItemId) async {
    // Log engagement event for BQ1
    final sessionId = _sessionId;
    await _supabase.from('engagement_events').insert({
      'user_profile_id': null, // optional, can be set by caller if needed
      'user_session_id': sessionId,
      'news_item_id': newsItemId,
      'event_type': 'comment',
      'action': 'started',
    });
  }

  Future<void> trackCommentCompleted(int newsItemId, int userProfileId, String content) async {
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
  }

  Future<void> trackFilterApplied(int categoryId) async {
    if (_sessionId == null) return;
    await _supabase.from('viewed_categories').insert({
      'category_id': categoryId,
      'user_session_id': _sessionId!,
    });
    await _supabase.from('user_sessions').update({
      'used_category_filter': true,
    }).eq('user_session_id', _sessionId!);
  }

  Future<void> trackRatingGiven(int newsItemId, int userProfileId, double score, String comment) async {
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
  }

  Future<void> trackRatingStarted(int newsItemId, int userProfileId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _supabase.from('rating_items').insert({
      'news_item_id': newsItemId,
      'user_profile_id': userProfileId,
      'rating_date': now,
      'started_at': now,
      'is_completed': false,
    });
    await _supabase.from('engagement_events').insert({
      'user_profile_id': userProfileId,
      'user_session_id': _sessionId,
      'news_item_id': newsItemId,
      'event_type': 'rating',
      'action': 'started',
    });
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
