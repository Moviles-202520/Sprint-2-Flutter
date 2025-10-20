import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';
import 'package:fl_chart/fl_chart.dart';

class AnalyticsDashboardScreen extends StatefulWidget {
  const AnalyticsDashboardScreen({super.key});

  @override
  State<AnalyticsDashboardScreen> createState() => _AnalyticsDashboardScreenState();
}

class _AnalyticsDashboardScreenState extends State<AnalyticsDashboardScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _loading = true;
  Map<String, dynamic> _metrics = {};

  @override
  void initState() {
    super.initState();
    _fetchMetrics();
  }

  Future<void> _fetchMetrics() async {
  setState(() => _loading = true);
  // BQ1: Funnel de iniciados vs completados usando engagement_events
  final events = await _supabase.from('engagement_events').select();
  final commentStarted = events.where((e) => e['event_type'] == 'comment' && e['action'] == 'started').length;
  final commentCompleted = events.where((e) => e['event_type'] == 'comment' && e['action'] == 'completed').length;
  final ratingStarted = events.where((e) => e['event_type'] == 'rating' && e['action'] == 'started').length;
  final ratingCompleted = events.where((e) => e['event_type'] == 'rating' && e['action'] == 'completed').length;
  // BQ2: Duración promedio de sesión con/sin filtro
  final sessions = await _supabase.from('user_sessions').select();
  final sessionsWithFilter = sessions.where((s) => s['used_category_filter'] == true).toList();
  final avgSessionDuration = _avg(sessions, 'duration_seconds');
  final avgSessionDurationWithFilter = _avg(sessionsWithFilter, 'duration_seconds');
  // Traer news_items y categories para joins
  final newsItems = await _supabase.from('news_items').select('news_item_id, category_id, publication_date');
  final categories = await _supabase.from('categories').select('category_id, name');

    // Mapas auxiliares
    final Map<int, int> newsToCategory = {
      for (final n in newsItems) (n['news_item_id'] as int): (n['category_id'] as int)
    };
    final Map<int, String> categoryNames = {
      for (final c in categories) (c['category_id'] as int): (c['name'] as String)
    };
    final Map<int, DateTime> newsPublishedAt = {
      for (final n in newsItems)
        (n['news_item_id'] as int): DateTime.parse((n['publication_date']).toString())
    };

    // Extraer solo eventos de rating completados para análisis de polarización y distribución
    final ratingEvents = events.where((e) => e['event_type'] == 'rating' && e['action'] == 'completed').toList();
    // Simular estructura de rating_items para compatibilidad con funciones existentes
    final ratingsRaw = ratingEvents.map((e) => {
      'news_item_id': e['news_item_id'],
      'assigned_reliability_score': e['score'] ?? 0,
      'rating_date': e['created_at'] ?? '',
    }).toList();
    // BQ3: Polarización por categoría (via join)
    final polarization = _polarizationByCategoryJoined(ratingsRaw, newsToCategory, categoryNames);

    // BQ4: Distribución de ratings por artículo y tiempo (ventanas respecto a publicación)
    final ratingsByArticle = _ratingsByArticleOverTimeFromPub(ratingsRaw, newsPublishedAt);
    // BQ5: Duración promedio de sesión por dispositivo
    final avgSessionByDevice = _avgSessionByDevice(sessions);
    setState(() {
      _metrics = {
        'commentStarted': commentStarted,
        'commentCompleted': commentCompleted,
        'ratingStarted': ratingStarted,
        'ratingCompleted': ratingCompleted,
        'avgSessionDuration': avgSessionDuration,
        'avgSessionDurationWithFilter': avgSessionDurationWithFilter,
        'polarization': polarization,
        'ratingsByArticle': ratingsByArticle,
        'avgSessionByDevice': avgSessionByDevice,
      };
      _loading = false;
    });
  }

  double _avg(List<dynamic> list, String key) {
    if (list.isEmpty) return 0;
    final vals = list.map((e) => (e[key] ?? 0) as num).toList();
    return vals.reduce((a, b) => a + b) / vals.length;
  }


  Map<String, double> _polarizationByCategoryJoined(
    List<dynamic> ratings,
    Map<int, int> newsToCategory,
    Map<int, String> categoryNames,
  ) {
    final Map<String, List<double>> byCat = {};
    for (var r in ratings) {
      final newsId = r['news_item_id'] as int?;
      if (newsId == null) continue;
      final catId = newsToCategory[newsId];
      final catName = catId != null ? (categoryNames[catId] ?? 'Unknown') : 'Unknown';
      final score = (r['assigned_reliability_score'] ?? 0).toDouble();
      byCat.putIfAbsent(catName, () => []).add(score);
    }
    return byCat.map((cat, scores) {
      final avg = scores.isEmpty ? 0 : scores.reduce((a, b) => a + b) / scores.length;
      final variance = scores.isEmpty ? 0 : (scores.map((s) => (s - avg) * (s - avg)).reduce((a, b) => a + b) / scores.length);
      final std = sqrt(variance);
      return MapEntry(cat, std);
    });
  }


  Map<String, Map<String, double>> _ratingsByArticleOverTimeFromPub(
    List<dynamic> ratings,
    Map<int, DateTime> newsPublishedAt,
  ) {
    final Map<String, Map<String, List<double>>> byArticle = {};
    for (var r in ratings) {
      final newsId = r['news_item_id'] as int?;
      if (newsId == null) continue;
      final article = newsId.toString();
      final pub = newsPublishedAt[newsId];
      if (pub == null) continue;
      final ts = DateTime.tryParse(r['rating_date'].toString()) ?? pub;
      final score = (r['assigned_reliability_score'] ?? 0).toDouble();
      final isFirst24h = ts.isBefore(pub.add(const Duration(hours: 24)));
      final isFirstWeek = ts.isBefore(pub.add(const Duration(days: 7)));
      byArticle.putIfAbsent(article, () => {'first_24h': [], 'first_week': []});
      if (isFirst24h) byArticle[article]!['first_24h']!.add(score);
      if (isFirstWeek) byArticle[article]!['first_week']!.add(score);
    }
    return byArticle.map((article, windows) => MapEntry(article, {
      'first_24h_avg': windows['first_24h']!.isEmpty ? 0 : windows['first_24h']!.reduce((a, b) => a + b) / windows['first_24h']!.length,
      'first_week_avg': windows['first_week']!.isEmpty ? 0 : windows['first_week']!.reduce((a, b) => a + b) / windows['first_week']!.length,
    }));
  }

  Map<String, double> _avgSessionByDevice(List<dynamic> sessions) {
    final Map<String, List<num>> byDevice = {};
    for (var s in sessions) {
      final device = s['device_type']?.toString() ?? 'unknown';
      final dur = (s['duration_seconds'] ?? 0) as num;
      byDevice.putIfAbsent(device, () => []).add(dur);
    }
    return byDevice.map((dev, durs) => MapEntry(dev, durs.isEmpty ? 0 : durs.reduce((a, b) => a + b) / durs.length));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Analytics Dashboard'),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    // Prepare chart data
  final commentStarted = (_metrics['commentStarted'] is int) ? _metrics['commentStarted'] : 0;
  final commentCompleted = (_metrics['commentCompleted'] is int) ? _metrics['commentCompleted'] : 0;
  final ratingStarted = (_metrics['ratingStarted'] is int) ? _metrics['ratingStarted'] : 0;
  final ratingCompleted = (_metrics['ratingCompleted'] is int) ? _metrics['ratingCompleted'] : 0;
    final avgSessionByDevice = Map<String, double>.from(_metrics['avgSessionByDevice'] ?? {});
    final polarization = Map<String, double>.from(_metrics['polarization'] ?? {});

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics Dashboard'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ChartCard(
            title: 'Funnel de Comentarios y Ratings',
            description: 'Comparativo de iniciados vs completados para comentarios y ratings.',
            xLabel: 'Tipo/Estado',
            yLabel: 'Cantidad',
            child: SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  gridData: FlGridData(show: true, drawVerticalLine: true),
                  alignment: BarChartAlignment.spaceAround,
                  barGroups: [
                    BarChartGroupData(x: 0, barRods: [BarChartRodData(toY: commentStarted.toDouble(), color: Colors.blue)], barsSpace: 4),
                    BarChartGroupData(x: 1, barRods: [BarChartRodData(toY: commentCompleted.toDouble(), color: Colors.green)], barsSpace: 4),
                    BarChartGroupData(x: 2, barRods: [BarChartRodData(toY: ratingStarted.toDouble(), color: Colors.orange)], barsSpace: 4),
                    BarChartGroupData(x: 3, barRods: [BarChartRodData(toY: ratingCompleted.toDouble(), color: Colors.purple)], barsSpace: 4),
                  ],
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          switch (value.toInt()) {
                            case 0:
                              return const Text('Comment Started');
                            case 1:
                              return const Text('Comment Completed');
                            case 2:
                              return const Text('Rating Started');
                            case 3:
                              return const Text('Rating Completed');
                          }
                          return const Text('');
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _ChartCard(
            title: 'Duración promedio de sesión por dispositivo',
            description: 'Promedio en segundos por tipo de dispositivo.',
            xLabel: 'Dispositivo',
            yLabel: 'Segundos',
            child: avgSessionByDevice.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('Sin datos'),
                  )
                : SizedBox(
                    height: 220,
                    child: BarChart(
                      BarChartData(
                        gridData: FlGridData(show: true),
                        alignment: BarChartAlignment.spaceAround,
                        barGroups: () {
                          final entries = avgSessionByDevice.entries.toList();
                          return [
                            for (var i = 0; i < entries.length; i++)
                              BarChartGroupData(
                                x: i,
                                barRods: [BarChartRodData(toY: entries[i].value, color: Colors.purple)],
                              ),
                          ];
                        }(),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                final entries = avgSessionByDevice.keys.toList();
                                final idx = value.toInt();
                                if (idx < 0 || idx >= entries.length) return const SizedBox();
                                return Text(entries[idx], overflow: TextOverflow.ellipsis);
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 24),
          _ChartCard(
            title: 'Polarización por categoría (STD)',
            description: 'Desviación estándar de los puntajes por categoría. Más alto = más dispersión.',
            xLabel: 'Categoría',
            yLabel: 'STD',
            child: polarization.isEmpty
                ? const Padding(padding: EdgeInsets.all(16), child: Text('Sin datos'))
                : SizedBox(
                    height: 220,
                    child: BarChart(
                      BarChartData(
                        gridData: FlGridData(show: true),
                        alignment: BarChartAlignment.spaceAround,
                        barGroups: [
                          for (var i = 0; i < polarization.entries.length; i++)
                            BarChartGroupData(
                              x: i,
                              barRods: [BarChartRodData(toY: polarization.values.elementAt(i), color: Colors.orange)],
                            ),
                        ],
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                if (value.toInt() < 0 || value.toInt() >= polarization.length) return const SizedBox();
                                final cat = polarization.keys.elementAt(value.toInt());
                                return Text(cat, overflow: TextOverflow.ellipsis);
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 24),
          // Otros datos en texto
          Text('Avg session duration: ${_metrics['avgSessionDuration']}s'),
          Text('Avg session duration (with filter): ${_metrics['avgSessionDurationWithFilter']}s'),
          Text('Ratings by article/time: ${_metrics['ratingsByArticle']}'),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final String description;
  final String xLabel;
  final String yLabel;
  final Widget child;

  const _ChartCard({
    Key? key,
    required this.title,
    required this.description,
    required this.xLabel,
    required this.yLabel,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(description, style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 12),
            child,
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Eje Y: $yLabel', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                Text('Eje X: $xLabel', style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
