import 'package:flutter/material.dart';
import '../domain/repositories/news_repository.dart';
import '../domain/models/news_item.dart';
import '../domain/models/rating_item.dart';
import '../domain/models/comment.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/analytics_service.dart';

class NewsDetailViewModel extends ChangeNotifier {
  // Lleva registro de eventos 'started' disparados por noticia y tipo
  bool _ratingStarted = false;
  bool _ratingCompleted = false;
  bool _commentStarted = false;
  bool _commentCompleted = false;
  final NewsRepository _repository;
  final String news_item_id;
  final String userProfileId;

  NewsItem? _news_item;
  List<Comment> _comments = [];
  bool _is_loading = true;
  bool _is_submitting_rating = false;
  bool _is_submitting_comment = false;

  NewsDetailViewModel(this._repository, this.news_item_id, this.userProfileId) {
    _loadData();
  }

  NewsItem? get news_item => _news_item;
  List<Comment> get comments => _comments;
  bool get is_loading => _is_loading;
  bool get is_submitting_rating => _is_submitting_rating;
  bool get is_submitting_comment => _is_submitting_comment;

  Future<void> _loadData() async {
    try {
      _is_loading = true;
      notifyListeners();
      
      _news_item = await _repository.getNewsDetail(news_item_id);
      _comments = await _repository.getComments(news_item_id);
    } catch (e) {
      print('Error loading data: $e');
    } finally {
      _is_loading = false;
      notifyListeners();
    }
  }

  Future<void> submitRating(double score, String? comment_text, String userProfileId) async {
    _ratingStarted = true;
    _is_submitting_rating = true;
    notifyListeners();

    try {
      // DEBUG: Verificar estado de autenticación
      final currentUser = Supabase.instance.client.auth.currentUser;
      final currentSession = Supabase.instance.client.auth.currentSession;
      print('🔐 [DEBUG] Supabase currentUser: $currentUser');
      print('🔐 [DEBUG] Supabase currentUser?.id: ${currentUser?.id}');
      print('🔐 [DEBUG] Supabase currentSession: ${currentSession != null ? "EXISTS" : "NULL"}');
      print('🔐 [DEBUG] Auth role: ${currentSession?.user.role}');
      

  // userProfileId ya viene como argumento desde el widget
      final rating_item = RatingItem(
        rating_item_id: 'rating_${DateTime.now().millisecondsSinceEpoch}',
        news_item_id: news_item_id,
        user_profile_id: userProfileId,
        assigned_reliability_score: score,
        comment_text: comment_text ?? '',
        rating_date: DateTime.now(),
        is_completed: true,
      );

      print('📤 [DEBUG] Enviando rating con user_profile_id: ${rating_item.user_profile_id}');
      print('📤 [DEBUG] news_item_id: ${rating_item.news_item_id}');
      
  // El insert lo realiza AnalyticsService.trackRatingGiven
      
      // Track rating completed event for BQ1
      await AnalyticsService().trackRatingGiven(
        int.tryParse(news_item_id) ?? 0,
        int.tryParse(userProfileId) ?? 0,
        score,
        comment_text ?? '',
      );
      _ratingCompleted = true;
      
      print('✅ [DEBUG] Rating enviado exitosamente');
    } catch (e, stackTrace) {
      print('❌ Error submitting rating: $e');
      print('❌ StackTrace: $stackTrace');
    } finally {
      _is_submitting_rating = false;
      notifyListeners();
    }
  }

  Future<void> submitComment(String content) async {
    _commentStarted = true;

    _is_submitting_comment = true;
    notifyListeners();

    try {
      final comment = Comment(
        comment_id: DateTime.now().millisecondsSinceEpoch.toString(),
        news_item_id: news_item_id,
        user_profile_id: userProfileId,
        user_name: 'You',
        content: content,
        timestamp: DateTime.now(),
      );
  // El insert lo realiza AnalyticsService.trackCommentCompleted
      
      // Track comment completed event for BQ1
      await AnalyticsService().trackCommentCompleted(
        int.tryParse(news_item_id) ?? 0,
        int.tryParse(userProfileId) ?? 0,
        content,
      );
      _commentCompleted = true;
  @override
  void dispose() {
    // Si el usuario inició pero NO completó rating, registrar 'started'
    if (_ratingStarted && !_ratingCompleted) {
      AnalyticsService().trackRatingStarted(int.tryParse(news_item_id) ?? 0, int.tryParse(userProfileId) ?? 0);
    }
    // Si el usuario inició pero NO completó comentario, registrar 'started'
    if (_commentStarted && !_commentCompleted) {
      AnalyticsService().trackCommentStarted(int.tryParse(news_item_id) ?? 0);
    }
    super.dispose();
  }
      
      _comments.insert(0, comment);
    } catch (e) {
      print('Error submitting comment: $e');
    } finally {
      _is_submitting_comment = false;
      notifyListeners();
    }
  }
}