import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> metricsData = [];
  String? loadError;
  bool isLoading = true;
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

  // Main metrics to display - Latency, Memory, Error Rate, CPU
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

  late FirebaseFirestore _firestore;
  late StreamSubscription<QuerySnapshot> _metricsSubscription;

  @override
  void initState() {
    super.initState();
    _firestore = FirebaseFirestore.instance;
    _loadMetricsRealtime();

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
    _metricsSubscription.cancel();
    super.dispose();
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
                      .toList(); // Reverse to get chronological order
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

  void _refreshMetrics() {
    setState(() {
      isLoading = true;
    });
    _loadMetricsRealtime();
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
    if (metricsData.isEmpty)
      return {'min': 0, 'max': 0, 'avg': 0, 'current': 0};

    final values = metricsData
        .map((r) => (r[metricKey] as num?)?.toDouble())
        .where((v) => v != null)
        .cast<double>()
        .toList();

    if (values.isEmpty) return {'min': 0, 'max': 0, 'avg': 0, 'current': 0};

    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final avg = values.reduce((a, b) => a + b) / values.length;
    final current = values.last;

    return {'min': min, 'max': max, 'avg': avg, 'current': current};
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
      // Desktop: Graphs (2x2) on left, Risk Score panel on right (removed chat from here)
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
      // Tablet: Graphs (2x2) on top, Risk Score below
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildChartsGrid(isWide, isMedium, constraints),
          const SizedBox(height: 20),
          _buildRiskScorePanel(),
        ],
      );
    } else {
      // Mobile: Single column with graphs stacked, Risk Score at bottom
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

  Widget _buildRiskScorePanel() {
    final riskStats = _getMetricStats('risk_score');
    final rawCurrent = riskStats['current'] ?? 0;
    final rawAvg = riskStats['avg'] ?? 0;
    final rawMax = riskStats['max'] ?? 0;
    final rawMin = riskStats['min'] ?? 0;

    // risk_score is already 0-1, multiply by 100 for percentage
    final currentRisk = rawCurrent; // 0-100%
    final avgRisk = rawAvg;
    final maxRisk = rawMax;
    final minRisk = rawMin;

    // Thresholds based on actual risk percentage (0-100%)
    // >70% = Critical, >40% = Warning, >20% = Moderate, <=20% = Normal
    final riskLevel = currentRisk > 70
        ? 'Critical'
        : currentRisk > 40
        ? 'Warning'
        : currentRisk > 20
        ? 'Moderate'
        : 'Normal';

    final riskColor = currentRisk > 70
        ? const Color(0xFFEF4444)
        : currentRisk > 40
        ? const Color(0xFFF59E0B)
        : currentRisk > 20
        ? const Color(0xFF3B82F6)
        : const Color(0xFF10B981);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFF1E293B), const Color(0xFF0F172A)],
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
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Risk Assessment',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'System Health Monitor',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // Main Risk Score Display
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
                          value: currentRisk / 100, // needs 0-1 range
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
                            '${currentRisk.toStringAsFixed(1)}%', // Show as percentage
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 38,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -1,
                            ),
                          ),
                          Text(
                            'Risk Score',
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

                  // Risk Level Badge
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
                          currentRisk > 70
                              ? Icons.dangerous_rounded
                              : currentRisk > 40
                              ? Icons.warning_amber_rounded
                              : currentRisk > 20
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

            // Divider
            Container(height: 1, color: Colors.white.withOpacity(0.1)),
            const SizedBox(height: 20),

            // Statistics
            _buildRiskStatRow('Average', avgRisk, const Color(0xFF3B82F6)),
            const SizedBox(height: 12),
            _buildRiskStatRow('Maximum', maxRisk, const Color(0xFFEF4444)),
            const SizedBox(height: 12),
            _buildRiskStatRow('Minimum', minRisk, const Color(0xFF10B981)),
            const SizedBox(height: 24),

            // Status Indicator
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
                      currentRisk > 0.007
                          ? 'Immediate attention required'
                          : currentRisk > 0.004
                          ? 'Monitor closely for issues'
                          : currentRisk > 0.002
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
                // Close button in header
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
              itemCount: _messages.length,
              itemBuilder: (context, index) {
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
                    style: const TextStyle(color: Colors.white),
                    onSubmitted: (_) => _sendMessage(),
                    decoration: InputDecoration(
                      hintText: 'Ask the ATOM assistant…',
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
                  onPressed: _sendMessage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Row(
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

  void _sendMessage() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(_ChatMessage(role: ChatRole.user, text: text));
      _chatController.clear();
    });
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

  Widget _buildRiskStatRow(String label, double value, Color color) {
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
              '${value.toStringAsFixed(1)}%', // Show as percentage with 1 decimal
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

  Widget _buildChartsGrid(
    bool isWide,
    bool isMedium,
    BoxConstraints constraints,
  ) {
    // 2x2 grid for desktop/tablet, single column for mobile
    final crossAxisCount = isMedium ? 2 : 1;
    final chartHeight = isWide ? 240.0 : (isMedium ? 220.0 : 200.0);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        mainAxisExtent: chartHeight + 80,
      ),
      itemCount: mainMetrics.length,
      itemBuilder: (context, index) {
        final metric = mainMetrics[index];
        return _buildMetricChart(metric, chartHeight);
      },
    );
  }

  Widget _buildMetricChart(MetricConfig metric, double chartHeight) {
    final spots = _buildSpots(metric.key, 80);
    final stats = _getMetricStats(metric.key);

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [const Color(0xFF141B24), const Color(0xFF0F1419)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.05), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with metric info and stats
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withOpacity(0.06),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          metric.color.withOpacity(0.2),
                          metric.color.withOpacity(0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: metric.color.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Icon(metric.icon, color: metric.color, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          metric.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              'Current: ',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.4),
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              '${stats['current']?.toStringAsFixed(2)} ${metric.unit}',
                              style: TextStyle(
                                color: metric.color,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Avg: ',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.4),
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              '${stats['avg']?.toStringAsFixed(2)} ${metric.unit}',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Current value badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
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
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Chart
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 16, 12),
                child: spots.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.show_chart_rounded,
                              size: 40,
                              color: Colors.white.withOpacity(0.2),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'No data available',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.3),
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
      ),
    );
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
                  TextStyle(
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
              onPressed: () {
                setState(() {
                  isLoading = true;
                  loadError = null;
                });
                _refreshMetrics();
              },
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
