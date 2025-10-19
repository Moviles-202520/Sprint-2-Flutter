import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:punto_neutro/data/repositories/hybrid_news_repository.dart';
import 'package:punto_neutro/domain/models/news_item.dart';
import 'package:punto_neutro/view_models/news_feed_viewmodel.dart';
import 'package:punto_neutro/data/repositories/supabase_news_repository.dart';
import 'news_detail_screen.dart';
import '../widgets/weather_widget.dart';
import '../viewmodels/weather_viewmodel.dart';
import '../../data/services/weather_service.dart';
import '../../data/repositories/weather_repository.dart';
import '../../core/location_service.dart';

class NewsFeedScreen extends StatelessWidget {
  const NewsFeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Crear WeatherService (pon tu API key aquí)
  final weatherService = WeatherService(apiKey: '44cbc6a126384edfba3161815251910');
    final weatherRepo = WeatherRepository(weatherService);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => NewsFeedViewModel(SupabaseNewsRepository())),
        ChangeNotifierProvider(create: (_) => WeatherViewModel(weatherRepo)),
      ],
      child: Builder(builder: (context) {
        // Cargar clima al abrir (usamos postFrameCallback para no notificar durante el build)
        final weatherVm = context.read<WeatherViewModel>();
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!weatherVm.isLoading && weatherVm.data == null) {
            try {
              final pos = await LocationService.instance.getCurrentPosition();
              final q = '${pos.latitude},${pos.longitude}';
              weatherVm.loadWeather(q);
            } catch (e) {
              // fallback
              weatherVm.loadWeather('Bogota,CO');
            }
          }
        });

        return Scaffold(
          backgroundColor: Colors.black,
          appBar: _buildAppBar(context),
          body: _buildBody(),
        );
      }),
    );
  }
  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.black,
      elevation: 0,
      title: const Text(
        'For You',
        style: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      centerTitle: true,
      leading: IconButton(
        icon: const Icon(Icons.search, color: Colors.white),
        onPressed: () {},
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.more_vert, color: Colors.white),
          onPressed: () {},
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: Align(alignment: Alignment.centerRight, child: WeatherWidget(city: 'Bogota,CO')),
        ),
      ],
    );
  }

  Widget _buildBody() {
    return Consumer<NewsFeedViewModel>(
      builder: (context, viewModel, child) {
        if (viewModel.isLoading) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }

        if (viewModel.newsItems.isEmpty) {
          return const Center(
            child: Text(
              'No hay noticias disponibles',
              style: TextStyle(color: Colors.white),
            ),
          );
        }

        return PageView.builder(
          itemCount: viewModel.newsItems.length,
          scrollDirection: Axis.vertical,
          onPageChanged: (index) {
            viewModel.setCurrentIndex(index);
          },
          itemBuilder: (context, index) {
            final news = viewModel.newsItems[index];
            return _NewsItemCard(news: news, index: index);
          },
        );
      },
    );
  }
}

class _NewsItemCard extends StatelessWidget {
  final NewsItem news;
  final int index;

  const _NewsItemCard({
    required this.news,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => NewsDetailScreen(
              news_item_id: news.news_item_id,
              repository: SupabaseNewsRepository(),
            ),
          ),
        );
      },
      child: Stack(
        children: [
          // Fondo con imagen
          _buildBackground(),
          
          // Gradiente oscuro para mejor legibilidad
          _buildGradient(),
          
          // Contenido de la noticia
          _buildContent(context),
          
          // Sidebar con acciones
          _buildActionSidebar(),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    return Positioned.fill(
      child: news.image_url.isNotEmpty
          ? Image.network(
              news.image_url,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(color: Colors.grey.shade800);
              },
            )
          : Container(color: Colors.grey.shade800),
    );
  }

  Widget _buildGradient() {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withOpacity(0.8),
              Colors.transparent,
              Colors.transparent,
              Colors.black.withOpacity(0.3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Positioned(
      left: 16,
      right: 80,
      bottom: 80,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Categoría y score de confiabilidad
          _buildCategoryRow(),
          
          const SizedBox(height: 12),
          
          // Título
          Text(
            news.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          
          const SizedBox(height: 8),
          
          // Descripción corta
          Text(
            news.short_description,
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 14,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          
          const SizedBox(height: 12),
          
          // Autor y fecha
          _buildAuthorInfo(),
        ],
      ),
    );
  }

  Widget _buildCategoryRow() {
    final reliabilityPercent = (news.average_reliability_score * 100).round();
    final reliabilityColor = reliabilityPercent >= 80
        ? Colors.green
        : reliabilityPercent >= 60
            ? Colors.orange
            : Colors.red;

    return Row(
      children: [
        // Categoría
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _getCategoryName(news.category_id),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        
        const SizedBox(width: 8),
        
        // Score de confiabilidad
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: reliabilityColor.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Icon(
                Icons.shield_outlined,
                size: 14,
                color: reliabilityColor,
              ),
              const SizedBox(width: 4),
              Text(
                '$reliabilityPercent%',
                style: TextStyle(
                  color: reliabilityColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAuthorInfo() {
    return Row(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: Colors.white.withOpacity(0.2),
          child: Icon(
            news.is_recognized_author 
                ? Icons.verified_user 
                : Icons.person,
            size: 16,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                news.author_institution,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                _formatDate(news.publication_date),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionSidebar() {
  return Positioned(
    right: 16,
    bottom: 100,
    child: Column(
      children: [
        // Avatar del autor
        _buildAuthorAvatar(),
        
        const SizedBox(height: 20),
        
        // Acciones con números fijos por ahora
        _buildActionButton(Icons.favorite_border, '1.2K', () {}),
        _buildActionButton(Icons.comment_outlined, '348', () {}),
        _buildActionButton(Icons.bookmark_border, 'Guardar', () {}),
        _buildActionButton(Icons.share_outlined, 'Compartir', () {}),
        
        const SizedBox(height: 20),
        
        // Indicador de progreso
        _buildProgressIndicator(),
      ],
    ),
  );
}

  Widget _buildAuthorAvatar() {
    return Column(
      children: [
        CircleAvatar(
          radius: 25,
          backgroundColor: Colors.white.withOpacity(0.2),
          child: Icon(
            news.is_recognized_author 
                ? Icons.verified_user 
                : Icons.person,
            size: 30,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        const Icon(Icons.favorite, color: Colors.red, size: 16),
      ],
    );
  }

  Widget _buildActionButton(IconData icon, String text, VoidCallback onTap) {
    return Column(
      children: [
        IconButton(
          icon: Icon(icon, color: Colors.white, size: 28),
          onPressed: onTap,
        ),
        Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildProgressIndicator() {
    return Consumer<NewsFeedViewModel>(
      builder: (context, viewModel, child) {
        return Container(
          height: 60,
          width: 4,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.3),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Stack(
            children: [
              // Progreso completado
              Container(
                height: (viewModel.currentIndex + 1) / viewModel.newsItems.length * 60,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _getCategoryName(String categoryId) {
    final categories = {
      '1': 'Política',
      '2': 'Deportes', 
      '3': 'Ciencia',
      '4': 'Economía',
      '5': 'Negocios',
      '6': 'Clima',
      '7': 'Conflicto',
      '8': 'Local',
    };
    return categories[categoryId] ?? 'Noticias';
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inMinutes < 1) return 'Ahora';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m';
    if (difference.inHours < 24) return '${difference.inHours}h';
    return '${difference.inDays}d';
  }
}