import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  List<Map<String, dynamic>> analyticsData = [];
  String? loadError;
  bool isLoading = true;

  // Selected metric from dropdown (default to first metric)
  String? _selectedMetricKey;

  // Analytics metrics to display
  static const List<AnalyticsMetricConfig> analyticsMetrics = [
    AnalyticsMetricConfig(
      key: 'latency_slope',
      label: 'Latency Slope',
      unit: 'ms/s',
      color: Color(0xFF06B6D4),
      icon: Icons.trending_up_rounded,
      description: 'Rate of change in latency over time',
      insight:
          'Indicates how quickly latency is increasing or decreasing. Sustained positive slopes may predict future performance issues.',
    ),
    AnalyticsMetricConfig(
      key: 'memory_slope',
      label: 'Memory Slope',
      unit: '%/s',
      color: Color(0xFFF97316),
      icon: Icons.memory_rounded,
      description: 'Rate of change in memory usage',
      insight:
          'Tracks memory consumption trends. Persistent positive slopes could indicate memory leaks or resource exhaustion.',
    ),
    AnalyticsMetricConfig(
      key: 'error_trend',
      label: 'Error Trend',
      unit: '',
      color: Color(0xFFEC4899),
      icon: Icons.bug_report_rounded,
      description: 'Trend direction of error occurrences',
      insight:
          'Shows whether errors are increasing or decreasing over time. Useful for detecting emerging issues before they escalate.',
    ),
  ];

  late FirebaseFirestore _firestore;
  StreamSubscription<QuerySnapshot>? _analyticsSubscription;

  @override
  void initState() {
    super.initState();
    _firestore = FirebaseFirestore.instance;
    _selectedMetricKey = analyticsMetrics.first.key;
    _loadAnalyticsRealtime();
  }

  @override
  void dispose() {
    _analyticsSubscription?.cancel();
    super.dispose();
  }

  void _loadAnalyticsRealtime() {
    try {
      _analyticsSubscription = _firestore
          .collection('metrics')
          .orderBy('created_at', descending: true)
          .limit(500)
          .snapshots()
          .listen(
            (snapshot) {
              if (mounted) {
                setState(() {
                  analyticsData = snapshot.docs
                      .map((doc) => {...doc.data(), 'id': doc.id})
                      .toList()
                      .reversed
                      .toList();
                  isLoading = false;
                });
              }
            },
            onError: (e) {
              if (mounted) {
                setState(() {
                  loadError = 'Failed to load analytics data: $e';
                  isLoading = false;
                });
              }
            },
          );
    } catch (e) {
      if (mounted) {
        setState(() {
          loadError = 'Failed to load data: $e';
          isLoading = false;
        });
      }
    }
  }

  void _refreshAnalytics() {
    setState(() {
      isLoading = true;
      loadError = null;
    });
    _analyticsSubscription?.cancel();
    _loadAnalyticsRealtime();
  }

  double _sqrt(double value) {
    if (value <= 0) return 0;
    double guess = value / 2;
    for (int i = 0; i < 20; i++) {
      guess = (guess + value / guess) / 2;
    }
    return guess;
  }

  /// Safely extracts a numeric value from dynamic data, returning null for non-numeric types
  double? _getNumericValue(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    // Handle boolean or other non-numeric types
    return null;
  }

  List<FlSpot> _buildSpots(String metricKey, int maxPoints) {
    if (analyticsData.isEmpty) return [];

    final spots = <FlSpot>[];
    final rows = analyticsData;

    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      final value = _getNumericValue(row[metricKey]);
      if (value != null) {
        spots.add(FlSpot(i.toDouble(), value));
      }
    }

    // Downsample for performance
    if (spots.length <= maxPoints) return spots;

    final result = <FlSpot>[];
    final step = spots.length / maxPoints;
    for (double i = 0; i < spots.length; i += step) {
      result.add(spots[i.floor()]);
    }
    if (result.isNotEmpty && result.last != spots.last) {
      result.add(spots.last);
    }
    return result;
  }

  Map<String, double> _getMetricStats(String metricKey) {
    if (analyticsData.isEmpty)
      return {'min': 0, 'max': 0, 'avg': 0, 'current': 0, 'stdDev': 0};

    final values = analyticsData
        .map((r) => _getNumericValue(r[metricKey]))
        .where((v) => v != null)
        .cast<double>()
        .toList();

    if (values.isEmpty)
      return {'min': 0, 'max': 0, 'avg': 0, 'current': 0, 'stdDev': 0};

    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final avg = values.reduce((a, b) => a + b) / values.length;
    final current = values.last;

    // Calculate standard deviation
    final variance =
        values.map((v) => (v - avg) * (v - avg)).reduce((a, b) => a + b) /
        values.length;
    final stdDev = variance > 0 ? _sqrt(variance) : 0.0;

    return {
      'min': min,
      'max': max,
      'avg': avg,
      'current': current,
      'stdDev': stdDev,
    };
  }

  String _getTrendStatus(double current, double avg) {
    final diff = current - avg;
    if (diff.abs() < 0.01) return 'Stable';
    if (diff > 0) return 'Increasing';
    return 'Decreasing';
  }

  Color _getTrendColor(double current, double avg, String metricKey) {
    final diff = current - avg;
    if (diff.abs() < 0.01) return const Color(0xFF3B82F6);

    // For most metrics, increasing is bad
    if (metricKey == 'error_trend') {
      return diff > 0 ? const Color(0xFFEF4444) : const Color(0xFF10B981);
    }
    // For slopes, context matters
    if (diff.abs() > avg.abs() * 0.5) {
      return const Color(0xFFF59E0B);
    }
    return const Color(0xFF3B82F6);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E14),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (loadError != null) {
      return _buildErrorState();
    }

    if (isLoading) {
      return _buildLoadingState();
    }

    if (analyticsData.isEmpty) {
      return Center(
        child: Text(
          'No analytics data available',
          style: TextStyle(color: Colors.white.withOpacity(0.6)),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomScrollView(
          slivers: [
            _buildAppBar(),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverToBoxAdapter(
                child: _buildAnalyticsContent(constraints),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      floating: true,
      snap: true,
      backgroundColor: const Color(0xFF0A0E14),
      elevation: 0,
      leading: IconButton(
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF94A3B8)),
        tooltip: 'Back to Dashboard',
      ),
      centerTitle: true,
      toolbarHeight: 80,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.insights_rounded,
              color: Color(0xFF6366F1),
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'Advanced Analytics',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: _refreshAnalytics,
          icon: const Icon(Icons.refresh_rounded, color: Color(0xFF94A3B8)),
          tooltip: 'Refresh Data',
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildAnalyticsContent(BoxConstraints constraints) {
    final isWide = constraints.maxWidth > 900;
    final selectedMetric = analyticsMetrics.firstWhere(
      (m) => m.key == _selectedMetricKey,
      orElse: () => analyticsMetrics.first,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Dropdown Selector at the top
        _buildMetricDropdown(selectedMetric),
        const SizedBox(height: 24),
        // Main content: Graph + Info Panel
        if (isWide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: _buildSelectedGraph(selectedMetric, constraints),
              ),
              const SizedBox(width: 24),
              Expanded(flex: 2, child: _buildMetricInfoPanel(selectedMetric)),
            ],
          )
        else
          Column(
            children: [
              _buildSelectedGraph(selectedMetric, constraints),
              const SizedBox(height: 24),
              _buildMetricInfoPanel(selectedMetric),
            ],
          ),
      ],
    );
  }

  Widget _buildMetricDropdown(AnalyticsMetricConfig selectedMetric) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFF141B24), const Color(0xFF0F1419)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          // Label
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.analytics_rounded,
              color: Color(0xFF6366F1),
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select Metric',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Choose a metric to analyze',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: selectedMetric.color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selectedMetric.color.withOpacity(0.3)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedMetricKey,
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: selectedMetric.color,
                ),
                dropdownColor: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(14),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                items: analyticsMetrics.map((metric) {
                  return DropdownMenuItem<String>(
                    value: metric.key,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(metric.icon, color: metric.color, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          metric.label,
                          style: TextStyle(
                            color: _selectedMetricKey == metric.key
                                ? metric.color
                                : Colors.white,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedMetricKey = value;
                    });
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedGraph(
    AnalyticsMetricConfig metric,
    BoxConstraints constraints,
  ) {
    final spots = _buildSpots(metric.key, 100);
    final stats = _getMetricStats(metric.key);
    final isWide = constraints.maxWidth > 900;
    final chartHeight = isWide ? 400.0 : 300.0;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFF141B24), const Color(0xFF0F1419)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: metric.color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: metric.color.withOpacity(0.1),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: metric.color.withOpacity(0.15),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        metric.color.withOpacity(0.2),
                        metric.color.withOpacity(0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: metric.color.withOpacity(0.3)),
                  ),
                  child: Icon(metric.icon, color: metric.color, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        metric.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        metric.description,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                // Current value badge
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: metric.color,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: metric.color.withOpacity(0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Text(
                        stats['current']?.toStringAsFixed(3) ?? '0',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Current ${metric.unit}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Chart
          SizedBox(
            height: chartHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 24, 20, 16),
              child: spots.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.show_chart_rounded,
                            size: 48,
                            color: Colors.white.withOpacity(0.2),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No data available',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.3),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _buildLineChart(spots, metric, stats),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricInfoPanel(AnalyticsMetricConfig metric) {
    final stats = _getMetricStats(metric.key);
    final current = stats['current'] ?? 0;
    final avg = stats['avg'] ?? 0;
    final min = stats['min'] ?? 0;
    final max = stats['max'] ?? 0;
    final stdDev = stats['stdDev'] ?? 0;
    final trend = _getTrendStatus(current, avg);
    final trendColor = _getTrendColor(current, avg, metric.key);

    // Calculate additional insights
    final deviation = current - avg;
    final deviationPercent = avg != 0 ? (deviation / avg.abs() * 100) : 0.0;
    final range = max - min;
    final volatility = avg != 0 ? (stdDev / avg.abs() * 100) : 0.0;

    return Column(
      children: [
        // Statistics Section
        _buildInfoSection(
          title: 'Statistics',
          icon: Icons.bar_chart_rounded,
          color: metric.color,
          child: Column(
            children: [
              _buildStatRow(
                'Current Value',
                current,
                metric.unit,
                metric.color,
              ),
              const SizedBox(height: 12),
              _buildStatRow(
                'Average',
                avg,
                metric.unit,
                const Color(0xFF3B82F6),
              ),
              const SizedBox(height: 12),
              _buildStatRow(
                'Maximum',
                max,
                metric.unit,
                const Color(0xFFEF4444),
              ),
              const SizedBox(height: 12),
              _buildStatRow(
                'Minimum',
                min,
                metric.unit,
                const Color(0xFF10B981),
              ),
              const SizedBox(height: 12),
              _buildStatRow(
                'Std. Deviation',
                stdDev,
                '',
                const Color(0xFFF59E0B),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Trend Analysis Section
        _buildInfoSection(
          title: 'Trend Analysis',
          icon: Icons.trending_up_rounded,
          color: metric.color,
          child: Column(
            children: [
              // Trend Direction
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: trendColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: trendColor.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Icon(
                      trend == 'Increasing'
                          ? Icons.trending_up_rounded
                          : trend == 'Decreasing'
                          ? Icons.trending_down_rounded
                          : Icons.trending_flat_rounded,
                      color: trendColor,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            trend,
                            style: TextStyle(
                              color: trendColor,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${deviationPercent.abs().toStringAsFixed(1)}% from average',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Additional metrics
              Row(
                children: [
                  Expanded(
                    child: _buildMiniStatCard(
                      'Range',
                      range.toStringAsFixed(3),
                      const Color(0xFF8B5CF6),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildMiniStatCard(
                      'Volatility',
                      '${volatility.toStringAsFixed(1)}%',
                      const Color(0xFFEC4899),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Insight Section
        _buildInfoSection(
          title: 'Insight',
          icon: Icons.lightbulb_rounded,
          color: metric.color,
          child: Text(
            metric.insight,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 13,
              height: 1.6,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoSection({
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFF1E293B), const Color(0xFF0F172A)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, double value, String unit, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
        ),
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              '${value.toStringAsFixed(4)}${unit.isNotEmpty ? ' $unit' : ''}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMiniStatCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLineChart(
    List<FlSpot> spots,
    AnalyticsMetricConfig metric,
    Map<String, double> stats,
  ) {
    final minY = stats['min'] ?? 0;
    final maxY = stats['max'] ?? 1;
    final yRange = (maxY - minY).abs();
    final yInterval = yRange > 0 ? yRange / 4 : 1.0;
    final yPadding = yRange > 0 ? yRange * 0.15 : 1.0;

    return LineChart(
      LineChartData(
        minY: minY - yPadding,
        maxY: maxY + yPadding,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          drawHorizontalLine: true,
          horizontalInterval: yInterval,
          verticalInterval: spots.length / 5,
          getDrawingHorizontalLine: (value) =>
              FlLine(color: Colors.white.withOpacity(0.06), strokeWidth: 1),
          getDrawingVerticalLine: (value) =>
              FlLine(color: Colors.white.withOpacity(0.03), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              interval: yInterval,
              getTitlesWidget: (value, meta) {
                if (value == meta.min || value == meta.max) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    value.toStringAsFixed(1),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.3,
            preventCurveOverShooting: true,
            color: metric.color,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  metric.color.withOpacity(0.25),
                  metric.color.withOpacity(0.05),
                  metric.color.withOpacity(0.0),
                ],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            tooltipBorder: BorderSide(color: metric.color.withOpacity(0.2)),
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                return LineTooltipItem(
                  '${spot.y.toStringAsFixed(3)} ${metric.unit}',
                  const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                );
              }).toList();
            },
          ),
          getTouchedSpotIndicator: (barData, spotIndexes) {
            return spotIndexes.map((index) {
              return TouchedSpotIndicatorData(
                FlLine(
                  color: metric.color.withOpacity(0.3),
                  strokeWidth: 1,
                  dashArray: [5, 5],
                ),
                FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, barData, index) {
                    return FlDotCirclePainter(
                      radius: 6,
                      color: const Color(0xFF141B24),
                      strokeWidth: 2.5,
                      strokeColor: metric.color,
                    );
                  },
                ),
              );
            }).toList();
          },
        ),
      ),
      duration: const Duration(milliseconds: 200),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
            color: Color(0xFF6366F1),
            strokeWidth: 3,
          ),
          const SizedBox(height: 16),
          Text(
            'Loading analytics...',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withOpacity(0.15),
                borderRadius: BorderRadius.circular(50),
                border: Border.all(
                  color: const Color(0xFFEF4444).withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: Color(0xFFEF4444),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              loadError ?? 'An error occurred',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFEF4444), fontSize: 14),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _refreshAnalytics,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AnalyticsMetricConfig {
  final String key;
  final String label;
  final String unit;
  final Color color;
  final IconData icon;
  final String description;
  final String insight;

  const AnalyticsMetricConfig({
    required this.key,
    required this.label,
    required this.unit,
    required this.color,
    required this.icon,
    required this.description,
    required this.insight,
  });
}
