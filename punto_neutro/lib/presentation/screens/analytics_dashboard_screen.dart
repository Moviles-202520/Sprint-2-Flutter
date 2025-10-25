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
  try {
    print('📊 [ANALYTICS] Iniciando carga de métricas...');
    final current = _supabase.auth.currentUser;
    print('🔐 [AUTH] currentUser: ${current?.id ?? 'null'} (authenticated=${current != null})');
    
  // BQ1: Funnel de iniciados vs completados usando engagement_events
      final events = await _supabase.from('engagement_events').select();
    print('📊 [ANALYTICS] engagement_events count: ${events.length}');
  var commentStarted = events.where((e) => e['event_type'] == 'comment' && e['action'] == 'started').length;
  var commentCompleted = events.where((e) => e['event_type'] == 'comment' && e['action'] == 'completed').length;
  var ratingStarted = events.where((e) => e['event_type'] == 'rating' && e['action'] == 'started').length;
  var ratingCompleted = events.where((e) => e['event_type'] == 'rating' && e['action'] == 'completed').length;
    print('📊 [ANALYTICS] Comments: $commentStarted started, $commentCompleted completed');
    print('📊 [ANALYTICS] Ratings: $ratingStarted started, $ratingCompleted completed');
    
    // BQ2: Duración promedio de sesión con/sin filtro
    final sessionsRaw = await _supabase.from('user_sessions').select();
    print('📊 [ANALYTICS] user_sessions raw count: ${sessionsRaw.length}');
    // Solo filtrar sesiones con end_time (cerradas) para evitar sesiones abiertas
      final sessions = sessionsRaw.where((s) => s['end_time'] != null && s['start_time'] != null).map((s) {
        final Map<String, dynamic> m = Map<String, dynamic>.from(s);
        if (m['duration_seconds'] == null) {
          try {
            final start = DateTime.parse(m['start_time'].toString());
            final end = DateTime.parse(m['end_time'].toString());
            m['duration_seconds'] = end.difference(start).inSeconds;
          } catch (_) {
            m['duration_seconds'] = 0;
          }
        }
        return m;
      }).toList();
    print('📊 [ANALYTICS] user_sessions closed: ${sessions.length}');
  final sessionsWithFilter = sessions.where((s) => s['used_category_filter'] == true).toList();
  final sessionsWithoutFilter = sessions.where((s) => s['used_category_filter'] == false).toList();
    final avgSessionDuration = _avg(sessions, 'duration_seconds');
    final avgSessionDurationWithFilter = _avg(sessionsWithFilter, 'duration_seconds');
    final avgSessionDurationWithoutFilter = _avg(sessionsWithoutFilter, 'duration_seconds');
    print('📊 [ANALYTICS] Avg duration total: $avgSessionDuration, with filter: $avgSessionDurationWithFilter, without: $avgSessionDurationWithoutFilter');
    
    // Traer news_items y categories para joins
    final newsItems = await _supabase.from('news_items').select('news_item_id, category_id, publication_date, title');
    final categories = await _supabase.from('categories').select('category_id, name');
    print('📊 [ANALYTICS] news_items count: ${newsItems.length}');
    print('📊 [ANALYTICS] categories count: ${categories.length}');

    // Mapas auxiliares
    final Map<int, int> newsToCategory = {
      for (final n in newsItems) (n['news_item_id'] as int): (n['category_id'] as int)
    };
    final Map<int, String> categoryNames = {
      for (final c in categories) (c['category_id'] as int): (c['name'] as String)
    };
    final Map<int, String> newsItemTitles = {
      for (final n in newsItems) (n['news_item_id'] as int): (n['title'] as String)
    };
    final Map<int, DateTime> newsPublishedAt = {
      for (final n in newsItems)
        (n['news_item_id'] as int): DateTime.parse((n['publication_date']).toString())
    };

    // BQ3 & BQ4: Usar rating_items (tiene los scores reales)
  final ratingsRaw = await _supabase.from('rating_items').select('news_item_id, assigned_reliability_score, rating_date, is_completed');
    // Solo tomar ratings completados
    final ratings = ratingsRaw.where((r) => r['is_completed'] == true).toList();
    print('📊 [ANALYTICS] rating_items total: ${ratingsRaw.length}, completed: ${ratings.length}');

    // BQ1 fallback: si engagement_events está vacío (posible RLS), usar rating_items/comments para 'completed'
    try {
      final commentsRaw = await _supabase.from('comments').select('is_completed');
      final fbCommentCompleted = commentsRaw.where((c) => c['is_completed'] == true).length;
      final fbRatingCompleted = ratings.length;
      final totalEventsCompleted = commentCompleted + ratingCompleted;
      final totalFallbackCompleted = fbCommentCompleted + fbRatingCompleted;
      if (totalEventsCompleted == 0 && totalFallbackCompleted > 0) {
        print('ℹ️ [ANALYTICS] BQ1 usando fallback (comments/rating_items) para completados');
        commentCompleted = fbCommentCompleted;
        ratingCompleted = fbRatingCompleted;
        if (commentStarted == 0) commentStarted = commentCompleted;
        if (ratingStarted == 0) ratingStarted = ratingCompleted;
      }
    } catch (e) {
      print('⚠️ [ANALYTICS] BQ1 fallback error: $e');
    }
    
    // BQ3: Polarización por categoría (via join)
    final polarization = _polarizationByCategoryJoined(ratings, newsToCategory, categoryNames);
    print('📊 [ANALYTICS] Polarization by category: $polarization');

    // BQ4: Distribución de ratings por artículo y tiempo (ventanas respecto a publicación)
    final ratingsByArticle = _ratingsByArticleOverTimeFromPub(ratings, newsPublishedAt, newsItemTitles);
    print('📊 [ANALYTICS] Ratings by article over time calculated');
    
    // BQ5: Duración promedio de sesión por dispositivo y SO
    final avgSessionByDevice = _avgSessionByDevice(sessions);
    final avgSessionByOS = _avgSessionByOS(sessions);
    print('📊 [ANALYTICS] Avg session by device: $avgSessionByDevice');
    print('📊 [ANALYTICS] Avg session by OS: $avgSessionByOS');
    
    setState(() {
      _metrics = {
        'commentStarted': commentStarted,
        'commentCompleted': commentCompleted,
        'ratingStarted': ratingStarted,
        'ratingCompleted': ratingCompleted,
        'sessionsCount': sessions.length,
        'avgSessionDuration': avgSessionDuration,
        'avgSessionDurationWithFilter': avgSessionDurationWithFilter,
        'avgSessionDurationWithoutFilter': avgSessionDurationWithoutFilter,
        'sessionsWithFilterCount': sessionsWithFilter.length,
        'sessionsWithoutFilterCount': sessionsWithoutFilter.length,
        'polarization': polarization,
        'ratingsByArticle': ratingsByArticle,
        'avgSessionByDevice': avgSessionByDevice,
        'avgSessionByOS': avgSessionByOS,
      };
      _loading = false;
    });
    print('✅ [ANALYTICS] Métricas cargadas exitosamente');
  } catch (e, st) {
    print('❌ [ANALYTICS] Error fetching metrics: $e');
    print(st);
    setState(() => _loading = false);
  }
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
    Map<int, String> newsItemTitles,
  ) {
    final Map<String, Map<String, List<double>>> byArticle = {};
    for (var r in ratings) {
      final newsId = r['news_item_id'] as int?;
      if (newsId == null) continue;
      final articleTitle = newsItemTitles[newsId] ?? 'Article $newsId';
      final pub = newsPublishedAt[newsId];
      if (pub == null) continue;
      final ts = DateTime.tryParse(r['rating_date'].toString()) ?? pub;
      final score = (r['assigned_reliability_score'] ?? 0).toDouble();
      final isFirst24h = ts.isBefore(pub.add(const Duration(hours: 24)));
      final isFirstWeek = ts.isBefore(pub.add(const Duration(days: 7)));
      byArticle.putIfAbsent(articleTitle, () => {'first_24h': [], 'first_week': [], 'all_time': []});
      if (isFirst24h) byArticle[articleTitle]!['first_24h']!.add(score);
      if (isFirstWeek) byArticle[articleTitle]!['first_week']!.add(score);
      byArticle[articleTitle]!['all_time']!.add(score);
    }
    return byArticle.map((article, windows) => MapEntry(article, {
      'first_24h_avg': windows['first_24h']!.isEmpty ? 0 : windows['first_24h']!.reduce((a, b) => a + b) / windows['first_24h']!.length,
      'first_week_avg': windows['first_week']!.isEmpty ? 0 : windows['first_week']!.reduce((a, b) => a + b) / windows['first_week']!.length,
      'all_time_avg': windows['all_time']!.isEmpty ? 0 : windows['all_time']!.reduce((a, b) => a + b) / windows['all_time']!.length,
      'first_24h_count': windows['first_24h']!.length.toDouble(),
      'first_week_count': windows['first_week']!.length.toDouble(),
      'all_time_count': windows['all_time']!.length.toDouble(),
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

  Map<String, double> _avgSessionByOS(List<dynamic> sessions) {
    final Map<String, List<num>> byOS = {};
    for (var s in sessions) {
      final os = s['operating_system']?.toString() ?? 'Unknown';
      final dur = (s['duration_seconds'] ?? 0) as num;
      byOS.putIfAbsent(os, () => []).add(dur);
    }
    return byOS.map((os, durs) => MapEntry(os, durs.isEmpty ? 0 : durs.reduce((a, b) => a + b) / durs.length));
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
  final sessionsCount = (_metrics['sessionsCount'] is int) ? _metrics['sessionsCount'] : 0;
    final avgSessionByDevice = Map<String, double>.from(_metrics['avgSessionByDevice'] ?? {});
    final avgSessionByOS = Map<String, double>.from(_metrics['avgSessionByOS'] ?? {});
    final polarization = Map<String, double>.from(_metrics['polarization'] ?? {});
    final ratingsByArticle = Map<String, Map<String, double>>.from(
      (_metrics['ratingsByArticle'] ?? {}).map((k, v) => MapEntry(k as String, Map<String, double>.from(v)))
    );
    
    final avgWithFilter = (_metrics['avgSessionDurationWithFilter'] as num?)?.toDouble() ?? 0;
    final avgWithoutFilter = (_metrics['avgSessionDurationWithoutFilter'] as num?)?.toDouble() ?? 0;
    final sessionsWithFilterCount = (_metrics['sessionsWithFilterCount'] as int?) ?? 0;
    final sessionsWithoutFilterCount = (_metrics['sessionsWithoutFilterCount'] as int?) ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics Dashboard'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // BQ1: Funnel de Comentarios y Ratings
          _ChartCard(
            title: 'BQ1: Funnel de Comentarios y Ratings',
            description: 'Comparativo de eventos iniciados vs completados. Muestra tasa de conversión.',
            xLabel: 'Tipo/Estado',
            yLabel: 'Cantidad de eventos',
            child: SizedBox(
              height: 250,
              child: BarChart(
                BarChartData(
                  gridData: FlGridData(show: true, drawVerticalLine: false),
                  alignment: BarChartAlignment.spaceAround,
                  barGroups: [
                    BarChartGroupData(x: 0, barRods: [BarChartRodData(toY: commentStarted.toDouble(), color: Colors.blue, width: 20)]),
                    BarChartGroupData(x: 1, barRods: [BarChartRodData(toY: commentCompleted.toDouble(), color: Colors.green, width: 20)]),
                    BarChartGroupData(x: 2, barRods: [BarChartRodData(toY: ratingStarted.toDouble(), color: Colors.orange, width: 20)]),
                    BarChartGroupData(x: 3, barRods: [BarChartRodData(toY: ratingCompleted.toDouble(), color: Colors.purple, width: 20)]),
                  ],
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 60,
                        getTitlesWidget: (value, meta) {
                          final style = TextStyle(fontSize: 10, fontWeight: FontWeight.bold);
                          switch (value.toInt()) {
                            case 0:
                              return Padding(padding: EdgeInsets.only(top: 8), child: Text('Comment\nStarted', style: style));
                            case 1:
                              return Padding(padding: EdgeInsets.only(top: 8), child: Text('Comment\nCompleted', style: style));
                            case 2:
                              return Padding(padding: EdgeInsets.only(top: 8), child: Text('Rating\nStarted', style: style));
                            case 3:
                              return Padding(padding: EdgeInsets.only(top: 8), child: Text('Rating\nCompleted', style: style));
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
          
          // Tasas de conversión
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tasas de Conversión', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Builder(builder: (context) {
                    final total = commentStarted + commentCompleted;
                    final pct = total > 0 ? (commentCompleted / total * 100).clamp(0, 100) : 0;
                    return Text('• Comentarios: $commentCompleted completados de $total eventos (${pct.toStringAsFixed(1)}%)');
                  }),
                  Builder(builder: (context) {
                    final total = ratingStarted + ratingCompleted;
                    final pct = total > 0 ? (ratingCompleted / total * 100).clamp(0, 100) : 0;
                    return Text('• Ratings: $ratingCompleted completados de $total eventos (${pct.toStringAsFixed(1)}%)');
                  }),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // BQ2: Duración de sesión con/sin filtros
          _ChartCard(
            title: 'BQ2: Duración de Sesión con/sin Filtros',
            description: 'Comparación de duración promedio cuando se usa filtro de categoría vs sin filtro.',
            xLabel: 'Uso de filtro',
            yLabel: 'Segundos promedio',
            child: Column(
              children: [
                SizedBox(
                  height: 200,
                  child: BarChart(
                    BarChartData(
                      gridData: FlGridData(show: true),
                      alignment: BarChartAlignment.spaceAround,
                      barGroups: [
                        BarChartGroupData(
                          x: 0,
                          barRods: [BarChartRodData(toY: avgWithFilter, color: Colors.blue, width: 40)],
                        ),
                        BarChartGroupData(
                          x: 1,
                          barRods: [BarChartRodData(toY: avgWithoutFilter, color: Colors.red, width: 40)],
                        ),
                      ],
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 50)),
                        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              switch (value.toInt()) {
                                case 0:
                                  return Text('Con Filtro\n(n=$sessionsWithFilterCount)', textAlign: TextAlign.center, style: TextStyle(fontSize: 12));
                                case 1:
                                  return Text('Sin Filtro\n(n=$sessionsWithoutFilterCount)', textAlign: TextAlign.center, style: TextStyle(fontSize: 12));
                              }
                              return const SizedBox();
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                    'Diferencia: ${(avgWithFilter - avgWithoutFilter).toStringAsFixed(0)}s (${((avgWithFilter - avgWithoutFilter) * 100 / (avgWithoutFilter > 0 ? avgWithoutFilter : 1)).toStringAsFixed(1)}%)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (sessionsCount == 0)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text(
                      'Sin datos de sesiones. Verifica permisos RLS para SELECT en user_sessions (ver script 2025-10-24_open_select_for_analytics.sql).',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // BQ3: Polarización por categoría
          _ChartCard(
            title: 'BQ3: Polarización de Ratings por Categoría',
            description: 'Desviación estándar de los puntajes por categoría. Mayor valor = opiniones más divididas.',
            xLabel: 'Categoría',
            yLabel: 'Desviación estándar',
            child: polarization.isEmpty
                ? const Padding(padding: EdgeInsets.all(16), child: Text('Sin datos de ratings'))
                : SizedBox(
                    height: 240,
                    child: BarChart(
                      BarChartData(
                        gridData: FlGridData(show: true),
                        alignment: BarChartAlignment.spaceAround,
                        barGroups: [
                          for (var i = 0; i < polarization.entries.length; i++)
                            BarChartGroupData(
                              x: i,
                              barRods: [BarChartRodData(toY: polarization.values.elementAt(i), color: Colors.orange, width: 25)],
                            ),
                        ],
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 60,
                              getTitlesWidget: (value, meta) {
                                if (value.toInt() < 0 || value.toInt() >= polarization.length) return const SizedBox();
                                final cat = polarization.keys.elementAt(value.toInt());
                                return Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Text(cat, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10)),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          
          const SizedBox(height: 16),
          
          // BQ4: Evolución de ratings por artículo
          _ChartCard(
            title: 'BQ4: Evolución de Ratings por Artículo',
            description: 'Cómo cambian los ratings promedio en diferentes ventanas de tiempo desde publicación.',
            xLabel: 'Artículo',
            yLabel: 'Rating promedio',
            child: ratingsByArticle.isEmpty
                ? const Padding(padding: EdgeInsets.all(16), child: Text('Sin datos de ratings por artículo'))
                : Column(
                    children: [
                      SizedBox(
                        height: 300,
                        child: ListView.builder(
                          shrinkWrap: true,
                          physics: NeverScrollableScrollPhysics(),
                          itemCount: ratingsByArticle.length > 5 ? 5 : ratingsByArticle.length,
                          itemBuilder: (context, index) {
                            final entry = ratingsByArticle.entries.elementAt(index);
                            final article = entry.key;
                            final data = entry.value;
                            return Card(
                              margin: EdgeInsets.symmetric(vertical: 4),
                              child: Padding(
                                padding: EdgeInsets.all(8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(article.length > 40 ? '${article.substring(0, 40)}...' : article, 
                                         style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                    SizedBox(height: 4),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                                      children: [
                                        TimeWindowData('24h', data['first_24h_avg']!, data['first_24h_count']!.toInt(), Colors.blue),
                                        TimeWindowData('1 semana', data['first_week_avg']!, data['first_week_count']!.toInt(), Colors.green),
                                        TimeWindowData('Total', data['all_time_avg']!, data['all_time_count']!.toInt(), Colors.purple),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      if (ratingsByArticle.length > 5)
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('... y ${ratingsByArticle.length - 5} artículos más', style: TextStyle(fontStyle: FontStyle.italic)),
                        ),
                    ],
                  ),
          ),
          
          const SizedBox(height: 16),
          
          // BQ5: Duración por dispositivo
          _ChartCard(
            title: 'BQ5: Duración Promedio por Dispositivo',
            description: 'Promedio en segundos por tipo de dispositivo.',
            xLabel: 'Dispositivo',
            yLabel: 'Segundos',
            child: avgSessionByDevice.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('Sin datos de sesiones por dispositivo. Si persiste, revisa permisos RLS (SELECT en user_sessions).'),
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
                                barRods: [BarChartRodData(toY: entries[i].value, color: Colors.purple, width: 30)],
                              ),
                          ];
                        }(),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 50)),
                          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
          
          const SizedBox(height: 16),
          
          // BQ5 adicional: Duración por Sistema Operativo
          _ChartCard(
            title: 'BQ5: Duración Promedio por Sistema Operativo',
            description: 'Promedio en segundos por SO (top 10).',
            xLabel: 'Sistema Operativo',
            yLabel: 'Segundos',
            child: avgSessionByOS.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('Sin datos de sesiones por SO. Si persiste, revisa permisos RLS (SELECT en user_sessions).'),
                  )
                : SizedBox(
                    height: 250,
                    child: BarChart(
                      BarChartData(
                        gridData: FlGridData(show: true),
                        alignment: BarChartAlignment.spaceAround,
                        barGroups: () {
                          final entries = avgSessionByOS.entries.take(10).toList();
                          return [
                            for (var i = 0; i < entries.length; i++)
                              BarChartGroupData(
                                x: i,
                                barRods: [BarChartRodData(toY: entries[i].value, color: Colors.teal, width: 20)],
                              ),
                          ];
                        }(),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 50)),
                          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 80,
                              getTitlesWidget: (value, meta) {
                                final entries = avgSessionByOS.entries.take(10).toList();
                                final idx = value.toInt();
                                if (idx < 0 || idx >= entries.length) return const SizedBox();
                                return Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Text(
                                    entries[idx].key,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 9),
                                    textAlign: TextAlign.center,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

}

class TimeWindowData extends StatelessWidget {
  final String label;
  final double avg;
  final int count;
  final Color color;

  const TimeWindowData(this.label, this.avg, this.count, this.color);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
        Text(avg.toStringAsFixed(2), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
        Text('(n=$count)', style: const TextStyle(fontSize: 9, color: Colors.grey)),
      ],
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
