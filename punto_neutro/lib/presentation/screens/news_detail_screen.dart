import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // ✅ Provider oficial
import 'package:punto_neutro/domain/models/comment.dart';
import '../../view_models/news_detail_viewmodel.dart';
import '../viewmodels/auth_view_model.dart';
import '../../domain/repositories/news_repository.dart';
import '../../domain/models/news_item.dart';
import '../../core/analytics_service.dart';

class NewsDetailScreen extends StatelessWidget {
  final String news_item_id;
  final NewsRepository repository;

  const NewsDetailScreen({
    super.key,
    required this.news_item_id,
    required this.repository,
  });

  @override
  Widget build(BuildContext context) {
    final userProfileId = Provider.of<AuthViewModel>(context, listen: false).userProfileId?.toString() ?? '1';
    return ChangeNotifierProvider(
      create: (_) => NewsDetailViewModel(repository, news_item_id, userProfileId),
      child: const _NewsDetailContent(),
    );
  }
}

class _NewsDetailContent extends StatelessWidget {
  // Helper: Key-Value row (unused in this widget; removed to avoid analyzer warning)

  // Helper: Card container
  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: Colors.black12),
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );

  // Helper: Pill
  Widget _pill({
    required String text,
    required Color bg,
    required Color fg,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 4),
          ],
          Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // Helper: Bottom navigation bar
  Widget _buildBottomNavigationBar() {
    return BottomNavigationBar(
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.book_outlined),
          label: 'Guide',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_outline),
          label: 'Profile',
        ),
      ],
    );
  }

  // Helper: Share article
  void _shareArticle(BuildContext context, NewsItem news_item) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SizedBox(
        height: 200,
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Copy link'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Link copied to clipboard')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share via...'),
              onTap: () {
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  // Helper: Bookmark article
  void _bookmarkArticle(BuildContext context, NewsItem news_item) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Article bookmarked')),
    );
  }

  // Helper: Report article
  void _reportArticle(BuildContext context, NewsItem news_item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report Article'),
        content: const Text('Why are you reporting this article?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Article reported for review')),
              );
            },
            child: const Text('Report'),
          ),
        ],
      ),
    );
  }

  // Helper: Credibility card
  Widget _CredibilityCard({required NewsItem news_item}) {
    final percent = (news_item.average_reliability_score * 100).round();
    final cs = Colors.red; // fallback, not used for color in this card
    return _card(
      child: Column(
        children: [
          Center(
            child: Text(
              '$percent%',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: _getReliabilityColor(percent, cs),
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Center(
            child: Text(
              'Reliability score',
              style: TextStyle(color: Colors.black54),
            ),
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: news_item.average_reliability_score,
            minHeight: 8,
            backgroundColor: Colors.red.withOpacity(.2),
            color: _getReliabilityColor(percent, Colors.red),
            borderRadius: BorderRadius.circular(8),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              if (news_item.is_verified_source) _Check(label: 'Verified source'),
              if (news_item.is_verified_data) _Check(label: 'Verified data'),
              if (news_item.is_recognized_author) _Check(label: 'Recognized author'),
              if (!news_item.is_manipulated) _Check(label: 'No manipulation'),
            ],
          ),
        ],
      ),
    );
  }

  // Helper: Reliability color
  Color _getReliabilityColor(int percent, Color fallback) {
    if (percent >= 80) return Colors.green;
    if (percent >= 60) return Colors.orange;
    return fallback;
  }

  // Helper: Check label
  Widget _Check({required String label}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.green.shade50,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 16),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
      ],
    ),
  );
  const _NewsDetailContent();

  @override
  Widget build(BuildContext context) {
    return Consumer<NewsDetailViewModel>(
      builder: (context, viewModel, child) {
        final cs = Theme.of(context).colorScheme;

        if (viewModel.is_loading) {
          return Scaffold(
            backgroundColor: const Color(0xffFAFAFA),
            body: const Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final news_item = viewModel.news_item;
        if (news_item == null) {
          return Scaffold(
            backgroundColor: const Color(0xffFAFAFA),
            appBar: AppBar(
              elevation: 0,
              backgroundColor: const Color(0xffFAFAFA),
              surfaceTintColor: Colors.transparent,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                onPressed: () => Navigator.pop(context),
              ),
              title: const Text(
                'Back to feed',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            body: const Center(
              child: Text(
                'No hay datos offline para esta noticia.',
                style: TextStyle(color: Colors.black54, fontSize: 18),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final fake_percent = (news_item.average_reliability_score * 100).round();

        return Scaffold(
          backgroundColor: const Color(0xffFAFAFA),
          appBar: AppBar(
            elevation: 0,
            backgroundColor: const Color(0xffFAFAFA),
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              'Back to feed',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            actions: const [
              Icon(Icons.notifications_none_rounded),
              SizedBox(width: 4),
              Icon(Icons.ios_share_rounded),
              SizedBox(width: 8),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
            children: [
              Row(
                children: [
                  _pill(
                    text: news_item.category_id,
                    bg: cs.secondaryContainer,
                    fg: cs.onSecondaryContainer,
                  ),
                  const SizedBox(width: 8),
                  _pill(
                    text: '$fake_percent%',
                    icon: Icons.warning_amber_rounded,
                    bg: cs.errorContainer,
                    fg: cs.onErrorContainer,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                news_item.title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                news_item.short_description,
                style: TextStyle(
                  color: Colors.black.withOpacity(.7),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _shareArticle(context, news_item),
                    icon: const Icon(Icons.ios_share_rounded, size: 18),
                    label: const Text('Share'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _bookmarkArticle(context, news_item),
                    child: const Icon(Icons.bookmark_border_rounded),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _reportArticle(context, news_item),
                    child: const Icon(Icons.flag_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(news_item.image_url, fit: BoxFit.cover),
              ),
              const SizedBox(height: 16),
              _CredibilityCard(news_item: news_item),
              const SizedBox(height: 12),
              _card(
                child: Text(
                  news_item.long_description,
                  style: const TextStyle(height: 1.35),
                ),
              ),
              const SizedBox(height: 12),
              _RateCard(viewModel: viewModel),
              const SizedBox(height: 12),
              _SourceCard(news_item: news_item),
              const SizedBox(height: 12),
              _CommentSection(viewModel: viewModel),
            ],
          ),
          bottomNavigationBar: _buildBottomNavigationBar(),
        );
      },
    );
  }
}

class _RateCard extends StatefulWidget {
  final NewsDetailViewModel viewModel;

  const _RateCard({required this.viewModel});

  @override
  State<_RateCard> createState() => _RateCardState();
}

class _RateCardState extends State<_RateCard> {
  double _reliability_score = 0.5;
  final _comment_controller = TextEditingController();
  static const _max_chars = 500;

  String get _reliability_label {
    final pct = (_reliability_score * 100).round();
    if (pct <= 20) return 'Very unreliable';
    if (pct <= 40) return 'Unreliable';
    if (pct <= 60) return 'Neutral';
    if (pct <= 80) return 'Reliable';
    return 'Very reliable';
  }

  bool _eventTracked = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_eventTracked) {
      try {
        final newsItemId = widget.viewModel.news_item?.news_item_id;
        final userProfileId = widget.viewModel.userProfileId;
        if (newsItemId != null && userProfileId.isNotEmpty) {
          AnalyticsService().trackRatingStarted(int.tryParse(newsItemId) ?? 0, int.tryParse(userProfileId) ?? 0);
        }
      } catch (_) {}
      _eventTracked = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pct = (_reliability_score * 100).round();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.stars_rounded, size: 18),
              SizedBox(width: 8),
              Text(
                'Rate reliability',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Score preview
          Row(
            children: [
              Text(
                'Your score: ',
                style: TextStyle(color: Colors.black.withOpacity(.7)),
              ),
              Text(
                '$pct%',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: _getScoreColor(pct),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _reliability_label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Slider control
          Slider(
            value: _reliability_score,
            min: 0,
            max: 1,
            divisions: 20,
            label: '$pct%',
            activeColor: _getScoreColor(pct),
            onChanged: (v) => setState(() => _reliability_score = v),
          ),

          const SizedBox(height: 4),

          // Optional mini bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _reliability_score,
              minHeight: 8,
              backgroundColor: Colors.black12,
              color: _getScoreColor(pct),
            ),
          ),

          const SizedBox(height: 16),

          // Optional comment
          TextField(
            controller: _comment_controller,
            maxLines: 3,
            maxLength: _max_chars,
            decoration: InputDecoration(
              hintText: 'Add an optional comment (max $_max_chars chars)',
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              counterText:
                  '${_comment_controller.text.length}/$_max_chars',
            ),
            onChanged: (_) => setState(() {}),
          ),

          const SizedBox(height: 8),

          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _submitRating,
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('Submit rating'),
            ),
          ),
        ],
      ),
    );
  }

  Color _getScoreColor(int percent) {
    if (percent >= 80) return Colors.green;
    if (percent >= 60) return Colors.orange;
    return Colors.red;
  }

  void _submitRating() {
    final userProfileId = context.read<AuthViewModel>().userProfileId?.toString() ?? '1';
    widget.viewModel.submitRating(
      _reliability_score,
      _comment_controller.text.trim().isEmpty ? null : _comment_controller.text.trim(),
      userProfileId,
    ).then((_) {
      _comment_controller.clear();
      setState(() {});
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rating submitted successfully')),
      );
    });
  }

  @override
  void dispose() {
    _comment_controller.dispose();
    super.dispose();
  }
}

class _SourceCard extends StatelessWidget {
  final NewsItem news_item;

  const _SourceCard({required this.news_item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, size: 18),
              SizedBox(width: 8),
              Text(
                'Source Information',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            news_item.author_institution,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Internationally recognized technology research institute',
            style: TextStyle(color: Colors.black54),
          ),
          const Divider(height: 24),
          _kv('Founded:', '1995'),
          _kv('Location:', 'Madrid, Spain'),
          _kv('Type:', 'Academic institution'),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _openOriginalSource(context, news_item.original_source_url),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('View original source'),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(k, style: const TextStyle(color: Colors.black54)),
        ),
        Expanded(
          child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );

  void _openOriginalSource(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Open Original Source'),
        content: const Text('This will open the original article in your browser.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Opening: $url')),
              );
            },
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }
}

class _CommentSection extends StatefulWidget {
  final NewsDetailViewModel viewModel;

  const _CommentSection({required this.viewModel});

  @override
  State<_CommentSection> createState() => _CommentSectionState();
}

class _CommentSectionState extends State<_CommentSection> {
  final TextEditingController _comment_controller = TextEditingController();
  bool _hasText = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.comment_outlined, size: 18),
              SizedBox(width: 8),
              Text(
                'Comments',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // ✅ SE MUESTRA SIEMPRE LA LISTA DE COMENTARIOS
          _buildCommentsList(),
          
          const SizedBox(height: 16),
          
          _buildCommentInput(),
        ],
      ),
    );
  }

  Widget _buildCommentsList() {
    // ✅ SI NO HAY COMENTARIOS, MOSTRAR MENSAJE
    if (widget.viewModel.comments.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text(
              'No comments yet. Be the first to comment!',
              style: TextStyle(color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // ✅ SI HAY COMENTARIOS, MOSTRAR LA LISTA
    return Column(
      children: [
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: widget.viewModel.comments.length,
          separatorBuilder: (_, __) => const Divider(height: 20),
          itemBuilder: (context, index) {
            final comment = widget.viewModel.comments[index];
            return _buildCommentItem(comment);
          },
        ),
        const Divider(height: 20),
      ],
    );
  }

  Widget _buildCommentItem(Comment comment) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: Colors.grey.shade200,
            child: Icon(
              comment.user_name == 'You' ? Icons.person : Icons.person_outline,
              color: Colors.black,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      comment.user_name,
                      style: TextStyle(
                        fontWeight: comment.user_name == 'You' 
                            ? FontWeight.bold 
                            : FontWeight.normal,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      comment.time_ago,
                      style: const TextStyle(
                        fontSize: 12, 
                        color: Colors.grey
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  comment.content,
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _eventTracked = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_eventTracked) {
      try {
        final newsItemId = widget.viewModel.news_item?.news_item_id;
        final userProfileId = widget.viewModel.userProfileId;
        if (newsItemId != null && userProfileId.isNotEmpty) {
          AnalyticsService().trackCommentStarted(int.tryParse(newsItemId) ?? 0);
        }
      } catch (_) {}
      _eventTracked = true;
    }
  }

  Widget _buildCommentInput() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: _comment_controller,
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(
              hintText: 'Write a comment…',
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onChanged: (text) => setState(() => _hasText = text.trim().isNotEmpty),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _hasText ? _postComment : null,
          child: const Icon(Icons.send_rounded, size: 18),
        ),
      ],
    );
  }

  void _postComment() {
    final content = _comment_controller.text.trim();
    if (content.isEmpty) return;
    
    widget.viewModel.submitComment(content).then((_) {
      _comment_controller.clear();
      setState(() {
        _hasText = false;
      });
    });
  }

  @override
  void dispose() {
    _comment_controller.dispose();
    super.dispose();
  }
}
