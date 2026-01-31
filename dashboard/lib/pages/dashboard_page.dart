import 'dart:async';
import 'dart:convert';
import 'dart:math'; // Add this import for Random

import 'package:dashboard/pages/analytics_page.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> metricsData = [];
  Map<String, dynamic>? forecastData;
  String? loadError;
  bool isLoading = true;

  // Dropdown expansion state for each metric
  final Map<String, bool> _expandedMetrics = {};

  // Chat agent state
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  final List<_ChatMessage> _messages = [
    const _ChatMessage(
      role: ChatRole.assistant,
      text: 'Hi! I\'m your ATOM assistant. How can I help?',
    ),
  ];

  // Chat panel visibility state
  bool _isChatOpen = false;
  late AnimationController _chatAnimationController;
  late Animation<Offset> _chatSlideAnimation;
  late Animation<double> _chatFadeAnimation;

  // Main metrics to display - Latency, Memory, Error FRate, CPU
  static const List<MetricConfig> mainMetrics = [
    MetricConfig(
      key: 'latency',
      label: 'Latency',
      unit: 'ms',
      color: Color(0xFF6366F1),
      icon: Icons.speed_rounded,
    ),
    MetricConfig(
      key: 'memory',
      label: 'Memory Usage',
      unit: '%',
      color: Color(0xFFF59E0B),
      icon: Icons.memory_rounded,
    ),
    MetricConfig(
      key: 'error_rate',
      label: 'Error Rate',
      unit: '%',
      color: Color(0xFFEF4444),
      icon: Icons.error_outline_rounded,
    ),
    MetricConfig(
      key: 'cpu',
      label: 'CPU Usage',
      unit: '%',
      color: Color(0xFF10B981),
      icon: Icons.developer_board_rounded,
    ),
  ];

  // Chat API configuration
  static const String _chatApiUrl = 'https://atom-agentic.onrender.com';
  bool _isSendingMessage = false;

  late FirebaseFirestore _firestore;
  StreamSubscription<QuerySnapshot>? _metricsSubscription;
  StreamSubscription<DocumentSnapshot>? _forecastSubscription;

  // Forecast timer state
  Timer? _forecastTimer;
  Duration _timeUntilNextForecast = Duration.zero;

  // Recommendations data
  static const List<Map<String, String>> _riskRecommendations = [
    {
      'cause': 'High CPU utilization detected',
      'recommendation':
          'Consider scaling horizontally by adding more instances or optimizing CPU-intensive operations. Review recent deployments for resource-heavy processes.',
    },
    {
      'cause': 'Memory pressure increasing',
      'recommendation':
          'Analyze memory allocation patterns and check for potential memory leaks. Consider implementing garbage collection optimization or increasing instance memory.',
    },
    {
      'cause': 'Elevated error rate observed',
      'recommendation':
          'Review application logs for recurring exceptions. Implement circuit breakers and retry mechanisms for external service calls.',
    },
    {
      'cause': 'Latency spikes detected',
      'recommendation':
          'Optimize database queries and consider implementing caching strategies. Review network configurations and check for downstream service bottlenecks.',
    },
    {
      'cause': 'Resource contention identified',
      'recommendation':
          'Implement request throttling and load balancing. Consider async processing for non-critical operations to reduce system load.',
    },
    {
      'cause': 'Anomalous traffic patterns',
      'recommendation':
          'Enable auto-scaling policies and review rate limiting configurations. Monitor for potential DDoS patterns and validate traffic sources.',
    },
    {
      'cause': 'Service degradation warning',
      'recommendation':
          'Check health of dependent services and database connections. Implement fallback mechanisms and graceful degradation strategies.',
    },
  ];

  int _currentRecommendationIndex = 0;

  @override
  void initState() {
    super.initState();
    _firestore = FirebaseFirestore.instance;
    _loadMetricsRealtime();
    _loadForecastRealtime();
    _startForecastTimer();
    _currentRecommendationIndex = Random().nextInt(_riskRecommendations.length);

    // Initialize chat animation controller
    _chatAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _chatSlideAnimation =
        Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _chatAnimationController,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        );

    _chatFadeAnimation = CurvedAnimation(
      parent: _chatAnimationController,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _chatController.dispose();
    _chatScrollController.dispose();
    _chatAnimationController.dispose();
    _metricsSubscription?.cancel();
    _forecastSubscription?.cancel();
    _forecastTimer?.cancel();
    super.dispose();
  }

  void _startForecastTimer() {
    _updateTimeUntilNextForecast();
    _forecastTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateTimeUntilNextForecast();
    });
  }

  void _updateTimeUntilNextForecast() {
    final now = DateTime.now();
    // Forecasts run at the top of every hour
    final nextHour = DateTime(now.year, now.month, now.day, now.hour + 1, 0, 0);
    final newTimeUntilNextForecast = nextHour.difference(now);

    // Check if we just crossed the hour boundary (timer was > 0 and now would be <= 0 or wrapped)
    if (_timeUntilNextForecast.inSeconds > 0 &&
        _timeUntilNextForecast.inSeconds <= 2 &&
        newTimeUntilNextForecast.inMinutes > 58) {
      // Timer just reset - trigger full reload
      _performFullStateReload();
    }

    if (mounted) {
      setState(() {
        _timeUntilNextForecast = newTimeUntilNextForecast;
      });
    }
  }

  void _performFullStateReload() {
    // Cancel existing subscriptions
    _metricsSubscription?.cancel();
    _forecastSubscription?.cancel();

    // Reset state
    if (mounted) {
      setState(() {
        isLoading = true;
        loadError = null;
        metricsData = [];
        forecastData = null;
        // Rotate to next recommendation
        _currentRecommendationIndex =
            (_currentRecommendationIndex + 1) % _riskRecommendations.length;
      });
    }

    // Reload all data
    _loadMetricsRealtime();
    _loadForecastRealtime();
  }

  void _toggleChat() {
    setState(() {
      _isChatOpen = !_isChatOpen;
    });
    if (_isChatOpen) {
      _chatAnimationController.forward();
    } else {
      _chatAnimationController.reverse();
    }
  }

  void _loadMetricsRealtime() {
    try {
      _metricsSubscription = _firestore
          .collection('metrics')
          .orderBy('created_at', descending: true)
          .limit(500)
          .snapshots()
          .listen(
            (snapshot) {
              if (mounted) {
                setState(() {
                  metricsData = snapshot.docs
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
                  loadError = 'Failed to load data: $e';
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

  void _loadForecastRealtime() {
    try {
      _forecastSubscription = _firestore
          .collection('forecasts')
          .doc('latest')
          .snapshots()
          .listen(
            (snapshot) {
              if (mounted && snapshot.exists) {
                setState(() {
                  forecastData = snapshot.data();
                });
              }
            },
            onError: (e) {
              print('Failed to load forecast: $e');
            },
          );
    } catch (e) {
      print('Failed to load forecast: $e');
    }
  }

  void _refreshMetrics() {
    setState(() {
      isLoading = true;
      loadError = null;
    });
    _metricsSubscription?.cancel();
    _forecastSubscription?.cancel();
    _loadMetricsRealtime();
    _loadForecastRealtime();
  }

  List<FlSpot> _buildSpots(String metricKey, int maxPoints) {
    if (metricsData.isEmpty) return [];

    final spots = <FlSpot>[];
    final rows = metricsData;

    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      final value = (row[metricKey] as num?)?.toDouble();
      if (value != null) {
        spots.add(FlSpot(i.toDouble(), value));
      }
    }

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
    if (metricsData.isEmpty) {
      return {'min': 0, 'max': 0, 'avg': 0, 'current': 0};
    }

    final values = metricsData
        .map((r) => (r[metricKey] as num?)?.toDouble())
        .where((v) => v != null)
        .cast<double>()
        .toList();

    if (values.isEmpty) {
      return {'min': 0, 'max': 0, 'avg': 0, 'current': 0};
    }

    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final avg = values.reduce((a, b) => a + b) / values.length;
    final current = values.last;

    return {'min': min, 'max': max, 'avg': avg, 'current': current};
  }

  Map<String, dynamic> _getForecastedRiskScore() {
    // Debug: Print forecast data structure
    if (forecastData != null) {
      print('Forecast data keys: ${forecastData!.keys.toList()}');
      if (forecastData!['risk_score'] != null) {
        print('risk_score type: ${forecastData!['risk_score'].runtimeType}');
        print('risk_score value: ${forecastData!['risk_score']}');
      }
    }

    // Try to get forecasted risk_score first
    // Path: forecasts -> latest -> risk_score
    if (forecastData != null && forecastData!['risk_score'] != null) {
      final riskScoreData = forecastData!['risk_score'];

      // Case 1: risk_score is a direct list of values [41, 47.6, ...]
      if (riskScoreData is List && riskScoreData.isNotEmpty) {
        final values = riskScoreData.map((v) => (v as num).toDouble()).toList();
        final current =
            values.last; // Use last value as current (most recent prediction)
        final avg = values.reduce((a, b) => a + b) / values.length;
        final max = values.reduce((a, b) => a > b ? a : b);
        final min = values.reduce((a, b) => a < b ? a : b);

        return {
          'current': current,
          'avgPredicted': avg,
          'maxPredicted': max,
          'minPredicted': min,
          'predictedValues': values,
          'hasForecast': true,
        };
      }

      // Case 2: risk_score is a Map with nested structure
      if (riskScoreData is Map<String, dynamic>) {
        // Try 'value' field first
        final valueData = riskScoreData['value'] ?? riskScoreData['values'];

        if (valueData is List && valueData.isNotEmpty) {
          final values = valueData.map((v) => (v as num).toDouble()).toList();
          final current = values.last;
          final avg = values.reduce((a, b) => a + b) / values.length;
          final max = values.reduce((a, b) => a > b ? a : b);
          final min = values.reduce((a, b) => a < b ? a : b);

          return {
            'current': current,
            'avgPredicted': avg,
            'maxPredicted': max,
            'minPredicted': min,
            'predictedValues': values,
            'hasForecast': true,
          };
        }

        // Single value in 'value' field
        if (valueData is num) {
          final value = valueData.toDouble();
          return {
            'current': value,
            'avgPredicted': value,
            'maxPredicted': value,
            'minPredicted': value,
            'predictedValues': <double>[value],
            'hasForecast': true,
          };
        }
      }

      // Case 3: risk_score is a single number
      if (riskScoreData is num) {
        final value = riskScoreData.toDouble();
        return {
          'current': value,
          'avgPredicted': value,
          'maxPredicted': value,
          'minPredicted': value,
          'predictedValues': <double>[value],
          'hasForecast': true,
        };
      }
    }

    // Fallback to historical data from metrics collection
    // Note: risk_score in metrics is stored as decimal (0-1), so multiply by 100 for percentage
    final riskStats = _getMetricStats('risk_score');
    final current = (riskStats['current'] ?? 0);
    final avg = (riskStats['avg'] ?? 0);
    final max = (riskStats['max'] ?? 0);
    final min = (riskStats['min'] ?? 0);

    // Check if values are already in percentage format (> 1) or decimal format (0-1)
    final isDecimalFormat = current <= 1 && avg <= 1 && max <= 1;
    final multiplier = isDecimalFormat ? 100.0 : 1.0;

    return {
      'current': current * multiplier,
      'avgPredicted': avg * multiplier,
      'maxPredicted': max * multiplier,
      'minPredicted': min * multiplier,
      'predictedValues': <double>[],
      'hasForecast': false,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E14),
      body: SafeArea(
        child: Stack(children: [_buildBody(), _buildAnimatedChatOverlay()]),
      ),
      floatingActionButton: _buildChatFAB(),
    );
  }

  Widget _buildChatFAB() {
    return FloatingActionButton.extended(
      onPressed: _toggleChat,
      backgroundColor: _isChatOpen
          ? const Color(0xFFEF4444)
          : const Color(0xFF6366F1),
      icon: AnimatedRotation(
        turns: _isChatOpen ? 0.125 : 0,
        duration: const Duration(milliseconds: 200),
        child: Icon(
          _isChatOpen ? Icons.close_rounded : Icons.chat_bubble_rounded,
          color: Colors.white,
        ),
      ),
      label: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        child: Text(
          _isChatOpen ? 'Close' : 'Chat with me',
          key: ValueKey(_isChatOpen),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedChatOverlay() {
    return Positioned(
      right: 16,
      bottom: 80,
      child: AnimatedBuilder(
        animation: _chatAnimationController,
        builder: (context, child) {
          if (_chatAnimationController.isDismissed) {
            return const SizedBox.shrink();
          }
          return child!;
        },
        child: SlideTransition(
          position: _chatSlideAnimation,
          child: FadeTransition(
            opacity: _chatFadeAnimation,
            child: _buildChatAgentPanel(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (loadError != null) {
      return _buildErrorState();
    }

    if (isLoading) {
      return _buildLoadingState();
    }

    if (metricsData.isEmpty) {
      return Center(
        child: Text(
          'No data available',
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
                child: _buildDashboardContent(constraints),
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
      centerTitle: true,
      toolbarHeight: 80,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        title: Image.asset('assets/logo.png', height: 50, fit: BoxFit.contain),
      ),
      actions: [
        // Analytics Button
        Container(
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF8B5CF6).withOpacity(0.2),
                const Color(0xFF6366F1).withOpacity(0.2),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.3)),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => AnalyticsPage()),
                );
              },
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.insights_rounded,
                      color: Color(0xFF8B5CF6),
                      size: 18,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Analytics',
                      style: TextStyle(
                        color: Color(0xFF8B5CF6),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: _refreshMetrics,
          icon: const Icon(Icons.refresh_rounded, color: Color(0xFF94A3B8)),
          tooltip: 'Refresh Data',
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildDashboardContent(BoxConstraints constraints) {
    final isWide = constraints.maxWidth > 1200;
    final isMedium = constraints.maxWidth > 800;

    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: _buildChartsGrid(isWide, isMedium, constraints),
          ),
          const SizedBox(width: 20),
          SizedBox(width: 360, child: _buildRiskScorePanel()),
        ],
      );
    } else if (isMedium) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildChartsGrid(isWide, isMedium, constraints),
          const SizedBox(height: 20),
          _buildRiskScorePanel(),
        ],
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildChartsGrid(isWide, isMedium, constraints),
          const SizedBox(height: 16),
          _buildRiskScorePanel(),
        ],
      );
    }
  }

  Widget _buildChartsGrid(
    bool isWide,
    bool isMedium,
    BoxConstraints constraints,
  ) {
    final chartHeight = isWide ? 280.0 : (isMedium ? 260.0 : 240.0);

    return Column(
      children: mainMetrics.map((metric) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildMetricDropdownCard(
            metric,
            chartHeight,
            isWide,
            isMedium,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMetricDropdownCard(
    MetricConfig metric,
    double chartHeight,
    bool isWide,
    bool isMedium,
  ) {
    final isExpanded = _expandedMetrics[metric.key] ?? false;
    final stats = _getMetricStats(metric.key);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF141B24), Color(0xFF0F1419)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isExpanded
              ? metric.color.withOpacity(0.3)
              : Colors.white.withOpacity(0.05),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isExpanded
                ? metric.color.withOpacity(0.15)
                : Colors.black.withOpacity(0.3),
            blurRadius: isExpanded ? 30 : 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildDropdownHeader(metric, stats, isExpanded),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 300),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: _buildExpandedContent(
              metric,
              chartHeight,
              stats,
              isWide,
              isMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownHeader(
    MetricConfig metric,
    Map<String, double> stats,
    bool isExpanded,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _expandedMetrics[metric.key] = !isExpanded;
          });
        },
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(20),
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
                  border: Border.all(
                    color: metric.color.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Icon(metric.icon, color: metric.color, size: 24),
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
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _buildQuickStat(
                          'Current',
                          stats['current']?.toStringAsFixed(2) ?? '0',
                          metric.unit,
                          metric.color,
                        ),
                        const SizedBox(width: 16),
                        _buildQuickStat(
                          'Avg',
                          stats['avg']?.toStringAsFixed(2) ?? '0',
                          metric.unit,
                          Colors.white54,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
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
                  '${stats['current']?.toStringAsFixed(1)}${metric.unit}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              AnimatedRotation(
                turns: isExpanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: isExpanded ? metric.color : Colors.white54,
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickStat(
    String label,
    String value,
    String unit,
    Color valueColor,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
        ),
        Text(
          '$value $unit',
          style: TextStyle(
            color: valueColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildExpandedContent(
    MetricConfig metric,
    double chartHeight,
    Map<String, double> stats,
    bool isWide,
    bool isMedium,
  ) {
    final spots = _buildSpots(metric.key, 80);

    if (isWide || isMedium) {
      return Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: metric.color.withOpacity(0.15), width: 1),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: _buildGraphSection(metric, spots, stats, chartHeight),
              ),
              const SizedBox(width: 20),
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    _buildStatisticsSection(metric, stats),
                    const SizedBox(height: 16),
                    _buildTrendAnalysisSection(metric, stats),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      return Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: metric.color.withOpacity(0.15), width: 1),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildGraphSection(metric, spots, stats, chartHeight - 40),
              const SizedBox(height: 16),
              _buildStatisticsSection(metric, stats),
              const SizedBox(height: 16),
              _buildTrendAnalysisSection(metric, stats),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildGraphSection(
    MetricConfig metric,
    List<FlSpot> spots,
    Map<String, double> stats,
    double height,
  ) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.show_chart_rounded, color: metric.color, size: 18),
              const SizedBox(width: 8),
              Text(
                'Trend Graph',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: spots.isEmpty
                ? Center(
                    child: Text(
                      'No data available',
                      style: TextStyle(color: Colors.white.withOpacity(0.3)),
                    ),
                  )
                : _buildLineChart(spots, metric, stats),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsSection(
    MetricConfig metric,
    Map<String, double> stats,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.analytics_outlined, color: metric.color, size: 18),
              const SizedBox(width: 8),
              Text(
                'Statistics',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildStatRow(
            'Current Value',
            '${stats['current']?.toStringAsFixed(3)} ${metric.unit}',
            metric.color,
          ),
          const SizedBox(height: 12),
          _buildStatRow(
            'Average',
            '${stats['avg']?.toStringAsFixed(3)} ${metric.unit}',
            const Color(0xFF3B82F6),
          ),
          const SizedBox(height: 12),
          _buildStatRow(
            'Maximum',
            '${stats['max']?.toStringAsFixed(3)} ${metric.unit}',
            const Color(0xFFEF4444),
          ),
          const SizedBox(height: 12),
          _buildStatRow(
            'Minimum',
            '${stats['min']?.toStringAsFixed(3)} ${metric.unit}',
            const Color(0xFF10B981),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
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
              value,
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

  Widget _buildTrendAnalysisSection(
    MetricConfig metric,
    Map<String, double> stats,
  ) {
    final current = stats['current'] ?? 0;
    final avg = stats['avg'] ?? 0;
    final max = stats['max'] ?? 0;
    final min = stats['min'] ?? 0;

    final deviation = current - avg;
    final deviationPercent = avg != 0 ? (deviation / avg * 100) : 0.0;
    final range = max - min;
    final normalizedPosition = range != 0
        ? ((current - min) / range * 100)
        : 50.0;

    final isAboveAvg = current > avg;
    final trendIcon = isAboveAvg ? Icons.trending_up : Icons.trending_down;
    final trendColor = isAboveAvg
        ? const Color(0xFFEF4444)
        : const Color(0xFF10B981);

    String healthStatus;
    Color healthColor;
    IconData healthIcon;

    if (normalizedPosition > 80) {
      healthStatus = 'Critical';
      healthColor = const Color(0xFFEF4444);
      healthIcon = Icons.dangerous_rounded;
    } else if (normalizedPosition > 60) {
      healthStatus = 'Warning';
      healthColor = const Color(0xFFF59E0B);
      healthIcon = Icons.warning_amber_rounded;
    } else if (normalizedPosition > 40) {
      healthStatus = 'Normal';
      healthColor = const Color(0xFF3B82F6);
      healthIcon = Icons.info_rounded;
    } else {
      healthStatus = 'Optimal';
      healthColor = const Color(0xFF10B981);
      healthIcon = Icons.check_circle_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_rounded, color: metric.color, size: 18),
              const SizedBox(width: 8),
              Text(
                'Trend Analysis',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: trendColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: trendColor.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Icon(trendIcon, color: trendColor, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAboveAvg ? 'Above Average' : 'Below Average',
                        style: TextStyle(
                          color: trendColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${deviationPercent.abs().toStringAsFixed(1)}% ${isAboveAvg ? 'higher' : 'lower'}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: healthColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: healthColor.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Icon(healthIcon, color: healthColor, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        healthStatus,
                        style: TextStyle(
                          color: healthColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Position: ${normalizedPosition.toStringAsFixed(1)}% of range',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Range Position',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    '${min.toStringAsFixed(1)} - ${max.toStringAsFixed(1)} ${metric.unit}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Stack(
                children: [
                  Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: (normalizedPosition / 100).clamp(0.0, 1.0),
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF10B981),
                            Color(0xFFF59E0B),
                            Color(0xFFEF4444),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRiskScorePanel() {
    final forecastedRiskData = _getForecastedRiskScore();
    final currentRisk = forecastedRiskData['current'] as double;
    final predictedValues =
        forecastedRiskData['predictedValues'] as List<double>;
    final avgPredicted = forecastedRiskData['avgPredicted'] as double;
    final maxPredicted = forecastedRiskData['maxPredicted'] as double;
    final minPredicted = forecastedRiskData['minPredicted'] as double;
    final hasForecast = forecastedRiskData['hasForecast'] as bool;

    // Use average as the main display value
    final displayRisk = avgPredicted;

    final riskLevel = displayRisk > 70
        ? 'Critical'
        : displayRisk > 40
        ? 'Warning'
        : displayRisk > 20
        ? 'Moderate'
        : 'Normal';

    final riskColor = displayRisk > 70
        ? const Color(0xFFEF4444)
        : displayRisk > 40
        ? const Color(0xFFF59E0B)
        : displayRisk > 20
        ? const Color(0xFF3B82F6)
        : const Color(0xFF10B981);

    final isRiskElevated = displayRisk > 20;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E293B).withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: riskColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.analytics_rounded,
                    color: riskColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Risk Assessment',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        children: [
                          Icon(
                            hasForecast
                                ? Icons.auto_graph_rounded
                                : Icons.history_rounded,
                            color: hasForecast
                                ? const Color(0xFF8B5CF6)
                                : Colors.white54,
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            hasForecast ? 'AI Predicted' : 'Historical Data',
                            style: TextStyle(
                              color: hasForecast
                                  ? const Color(0xFF8B5CF6)
                                  : Colors.white54,
                              fontSize: 12,
                              fontWeight: hasForecast
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Next Forecast Timer Widget
            _buildNextForecastTimer(),
            const SizedBox(height: 24),
            Center(
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 160,
                        height: 160,
                        child: CircularProgressIndicator(
                          value: (displayRisk / 100).clamp(0.0, 1.0),
                          strokeWidth: 12,
                          backgroundColor: Colors.white.withOpacity(0.1),
                          valueColor: AlwaysStoppedAnimation<Color>(riskColor),
                          strokeCap: StrokeCap.round,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            displayRisk.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 42,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -1,
                            ),
                          ),
                          Text(
                            hasForecast
                                ? 'Avg Predicted Risk'
                                : 'Avg Risk Score',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: riskColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: riskColor.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          displayRisk > 70
                              ? Icons.dangerous_rounded
                              : displayRisk > 40
                              ? Icons.warning_amber_rounded
                              : displayRisk > 20
                              ? Icons.info_rounded
                              : Icons.check_circle_rounded,
                          color: riskColor,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          riskLevel,
                          style: TextStyle(
                            color: riskColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Container(height: 1, color: Colors.white.withOpacity(0.1)),
            const SizedBox(height: 20),
            // Show recommendation alert if risk is elevated, otherwise show "All Good"
            if (isRiskElevated)
              _buildRiskAlertCard(displayRisk, riskColor)
            else
              _buildAllGoodCard(),
            const SizedBox(height: 20),
            // ...existing code for stats rows...
            if (hasForecast) ...[
              _buildRiskStatRow(
                'Current',
                currentRisk,
                const Color(0xFF8B5CF6),
              ),
              const SizedBox(height: 12),
              _buildRiskStatRow(
                'Max Predicted',
                maxPredicted,
                const Color(0xFFEF4444),
              ),
              const SizedBox(height: 12),
              _buildRiskStatRow(
                'Min Predicted',
                minPredicted,
                const Color(0xFF10B981),
              ),
              const SizedBox(height: 12),
              _buildRiskStatRow(
                'Forecast Points',
                predictedValues.length.toDouble(),
                const Color(0xFF3B82F6),
                isCount: true,
              ),
            ] else ...[
              _buildRiskStatRow(
                'Current',
                currentRisk,
                const Color(0xFF8B5CF6),
              ),
              const SizedBox(height: 12),
              _buildRiskStatRow(
                'Maximum',
                maxPredicted,
                const Color(0xFFEF4444),
              ),
              const SizedBox(height: 12),
              _buildRiskStatRow(
                'Minimum',
                minPredicted,
                const Color(0xFF10B981),
              ),
            ],
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: riskColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: riskColor.withOpacity(0.5),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      displayRisk > 70
                          ? 'Immediate attention required'
                          : displayRisk > 40
                          ? 'Monitor closely for issues'
                          : displayRisk > 20
                          ? 'System operating normally'
                          : 'All systems optimal',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNextForecastTimer() {
    final minutes = _timeUntilNextForecast.inMinutes;
    final seconds = _timeUntilNextForecast.inSeconds % 60;
    final totalSeconds = _timeUntilNextForecast.inSeconds;
    final progress = 1.0 - (totalSeconds / 3600.0); // Progress through the hour

    final isImminent = minutes < 5;
    final isVerySoon = minutes < 1;

    final timerColor = isVerySoon
        ? const Color(0xFF10B981)
        : isImminent
        ? const Color(0xFFF59E0B)
        : const Color(0xFF8B5CF6);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [timerColor.withOpacity(0.12), timerColor.withOpacity(0.04)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: timerColor.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: timerColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isVerySoon
                      ? Icons.rocket_launch_rounded
                      : isImminent
                      ? Icons.timelapse_rounded
                      : Icons.schedule_rounded,
                  color: timerColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Next Forcast',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        if (isImminent)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: timerColor.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isVerySoon)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: SizedBox(
                                      width: 8,
                                      height: 8,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                        color: timerColor,
                                      ),
                                    ),
                                  ),
                                Text(
                                  isVerySoon ? 'Imminent' : 'Soon',
                                  style: TextStyle(
                                    color: timerColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          minutes.toString().padLeft(2, '0'),
                          style: TextStyle(
                            color: timerColor,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Text(
                            ':',
                            style: TextStyle(
                              color: timerColor.withOpacity(0.7),
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          seconds.toString().padLeft(2, '0'),
                          style: TextStyle(
                            color: timerColor,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            'remaining',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.4),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Progress bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [],
              ),
              const SizedBox(height: 6),
              Stack(
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: progress.clamp(0.0, 1.0),
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [timerColor.withOpacity(0.6), timerColor],
                        ),
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: [
                          BoxShadow(
                            color: timerColor.withOpacity(0.4),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRiskAlertCard(double displayRisk, Color riskColor) {
    final recommendation = _riskRecommendations[_currentRecommendationIndex];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: riskColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: riskColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: riskColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  recommendation['cause'] ?? 'Risk Detected',
                  style: TextStyle(
                    color: riskColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            recommendation['recommendation'] ?? '',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllGoodCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF10B981),
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'All Systems Healthy',
                  style: TextStyle(
                    color: Color(0xFF10B981),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'No immediate concerns detected. Continue monitoring.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskStatRow(
    String label,
    double value,
    Color color, {
    bool isCount = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
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
              isCount
                  ? value.toInt().toString()
                  : '${value.toStringAsFixed(2)}%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildChatAgentPanel() {
    return Container(
      width: 360,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF141B24), Color(0xFF0F1419)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: const Color(0xFF6366F1).withOpacity(0.1),
            blurRadius: 40,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.chat_bubble_rounded,
                    color: Color(0xFF6366F1),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'ATOM Assistant',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _toggleChat,
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Colors.white54,
                    size: 20,
                  ),
                  splashRadius: 20,
                ),
              ],
            ),
          ),
          SizedBox(
            height: 320,
            child: ListView.builder(
              controller: _chatScrollController,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              itemCount: _messages.length + (_isSendingMessage ? 1 : 0),
              itemBuilder: (context, index) {
                // Show typing indicator while waiting for response
                if (_isSendingMessage && index == _messages.length) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 6,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: const Color(0xFF6366F1).withOpacity(0.7),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Thinking...',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final msg = _messages[index];
                final isAssistant = msg.role == ChatRole.assistant;
                return Align(
                  alignment: isAssistant
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 6,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    constraints: const BoxConstraints(maxWidth: 280),
                    decoration: BoxDecoration(
                      color: isAssistant
                          ? Colors.white.withOpacity(0.06)
                          : const Color(0xFF6366F1).withOpacity(0.25),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.08),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      msg.text,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    minLines: 1,
                    maxLines: 4,
                    enabled: !_isSendingMessage,
                    style: const TextStyle(color: Colors.white),
                    onSubmitted: (_) => _sendMessage(),
                    decoration: InputDecoration(
                      hintText: _isSendingMessage
                          ? 'Waiting for response...'
                          : 'Ask the ATOM assistant…',
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                      ),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.06),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.white.withOpacity(0.08),
                          width: 1,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.white.withOpacity(0.08),
                          width: 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF6366F1),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _isSendingMessage ? null : _sendMessage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isSendingMessage
                        ? const Color(0xFF6366F1).withOpacity(0.5)
                        : const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSendingMessage
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.send_rounded, size: 18),
                            SizedBox(width: 6),
                            Text('Send'),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty || _isSendingMessage) return;

    setState(() {
      _messages.add(_ChatMessage(role: ChatRole.user, text: text));
      _chatController.clear();
      _isSendingMessage = true;
    });

    _scrollToBottom();

    try {
      final response = await http
          .post(
            Uri.parse(_chatApiUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'question': text}),
          )
          .timeout(const Duration(seconds: 30));

      if (mounted) {
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final answer =
              data['answer'] ?? data['response'] ?? 'No response received.';
          setState(() {
            _messages.add(_ChatMessage(role: ChatRole.assistant, text: answer));
          });
        } else {
          setState(() {
            _messages.add(
              _ChatMessage(
                role: ChatRole.assistant,
                text:
                    'Sorry, I encountered an error (${response.statusCode}). Please try again.',
              ),
            );
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(
            _ChatMessage(
              role: ChatRole.assistant,
              text:
                  'Sorry, I couldn\'t connect to the server. Please check your connection and try again.',
            ),
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSendingMessage = false;
        });
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildLineChart(
    List<FlSpot> spots,
    MetricConfig metric,
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
          verticalInterval: spots.length / 6,
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
              reservedSize: 48,
              interval: yInterval,
              getTitlesWidget: (value, meta) {
                if (value == meta.min || value == meta.max) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    value.toStringAsFixed(1),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 10,
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
            barWidth: 2.5,
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
              horizontal: 12,
              vertical: 8,
            ),
            tooltipBorder: BorderSide(color: metric.color.withOpacity(0.2)),
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                return LineTooltipItem(
                  '${spot.y.toStringAsFixed(2)} ${metric.unit}',
                  const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
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
                      radius: 7,
                      color: const Color(0xFF141B24),
                      strokeWidth: 3,
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
            'Loading metrics...',
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
              onPressed: _refreshMetrics,
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

class MetricConfig {
  final String key;
  final String label;
  final String unit;
  final Color color;
  final IconData icon;

  const MetricConfig({
    required this.key,
    required this.label,
    required this.unit,
    required this.color,
    required this.icon,
  });
}

enum ChatRole { user, assistant }

class _ChatMessage {
  final ChatRole role;
  final String text;

  const _ChatMessage({required this.role, required this.text});
}
