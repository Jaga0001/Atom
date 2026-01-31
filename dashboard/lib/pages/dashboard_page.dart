import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/csv_loader.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  CsvLoaderResult? data;
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

  @override
  void initState() {
    super.initState();
    _loadCsv();

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

  Future<void> _loadCsv() async {
    try {
      final result = await CsvLoader.loadFromAssets();
      if (mounted) {
        setState(() {
          data = result;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          loadError = 'Failed to load data: $e';
          isLoading = false;
        });
      }
    }
  }

  List<FlSpot> _buildSpots(String metricKey, int maxPoints) {
    if (data == null) return [];

    final spots = <FlSpot>[];
    final rows = data!.rows;

    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      final valueStr = row[metricKey] ?? '';
      final value = double.tryParse(valueStr);
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
    if (data == null) return {'min': 0, 'max': 0, 'avg': 0, 'current': 0};

    final values = data!.rows
        .map((r) => double.tryParse(r[metricKey] ?? ''))
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
        child: Stack(
          children: [
            _buildBody(),
            // Animated chat panel overlay
            _buildAnimatedChatOverlay(),
          ],
        ),
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

    if (data == null) {
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
                Navigator.pushNamed(context, '/analytics');
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.insights_rounded,
                      color: Color(0xFF8B5CF6),
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    const Text(
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
          onPressed: () {
            setState(() {
              isLoading = true;
            });
            _loadCsv();
          },
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
    final currentRisk = riskStats['current'] ?? 0;
    final avgRisk = riskStats['avg'] ?? 0;
    final maxRisk = riskStats['max'] ?? 0;
    final minRisk = riskStats['min'] ?? 0;

    final riskLevel = currentRisk > 0.7
        ? 'Critical'
        : currentRisk > 0.4
        ? 'Warning'
        : currentRisk > 0.2
        ? 'Moderate'
        : 'Normal';
    final riskColor = currentRisk > 0.7
        ? const Color(0xFFEF4444)
        : currentRisk > 0.4
        ? const Color(0xFFF59E0B)
        : currentRisk > 0.2
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
            // Header
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
                          value: currentRisk,
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
                            (currentRisk * 100).toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 42,
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
                          currentRisk > 0.7
                              ? Icons.dangerous_rounded
                              : currentRisk > 0.4
                              ? Icons.warning_amber_rounded
                              : currentRisk > 0.2
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
                      currentRisk > 0.7
                          ? 'Immediate attention required'
                          : currentRisk > 0.4
                          ? 'Monitor closely for issues'
                          : currentRisk > 0.2
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
          // Header
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
          // Messages scroll area
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
          // Input row
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
    // Auto-scroll to bottom
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
              '${(value * 100).toStringAsFixed(2)}%',
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
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFF141B24), const Color(0xFF0F1419)],
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
          // Dropdown Header (always visible)
          _buildDropdownHeader(metric, stats, isExpanded),
          // Expandable Content
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
              // Metric Icon
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
              // Metric Info
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
              // Current Value Badge
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
              // Dropdown Arrow
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
      // Desktop/Tablet: Graph on left, two data sections on right
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
              // Graph Section
              Expanded(
                flex: 3,
                child: _buildGraphSection(metric, spots, stats, chartHeight),
              ),
              const SizedBox(width: 20),
              // Data Sections
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
      // Mobile: Stacked layout
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

    // Calculate trend indicators
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
          // Trend Direction
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
          // Health Status
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
          // Range Bar
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
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF10B981),
                            const Color(0xFFF59E0B),
                            const Color(0xFFEF4444),
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

  // Old _buildMetricChart removed - now using dropdown cards

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
                _loadCsv();
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
