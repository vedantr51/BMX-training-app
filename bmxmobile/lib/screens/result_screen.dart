import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/rider.dart';
import '../models/session_result.dart';
import '../screens/gate_screen.dart';
import '../services/profile_service.dart';
import '../services/websocket_server_service.dart';
import 'home_screen.dart';

class ResultScreen extends StatefulWidget {
  final Rider rider;
  final SessionResult result;
  final List<SessionResult> sessionRuns;

  const ResultScreen({
    super.key,
    required this.rider,
    required this.result,
    this.sessionRuns = const [],
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  @override
  void initState() {
    super.initState();
    _saveResult();
  }

  Future<void> _saveResult() async {
    final profileService = Provider.of<ProfileService>(context, listen: false);
    final websocketServer = Provider.of<WebSocketServerService>(
      context,
      listen: false,
    );

    await profileService.updateRiderResult(
      rider: widget.rider,
      reactionTime: widget.result.reactionTimeSeconds,
      score: widget.result.score,
      startType: widget.result.startType,
    );

    await websocketServer.sendRunResult(
      riderName: widget.rider.name,
      reactionTime: widget.result.reactionTimeSeconds,
      score: widget.result.score,
      startType: widget.result.startType,
    );
  }

  String _startTypeLabel(StartType type) {
    switch (type) {
      case StartType.falseStart:
        return 'False Start';
      case StartType.lateStart:
        return 'Late Start';
      case StartType.valid:
        return 'Valid Start';
    }
  }

  String _reactionFeedback(double reactionSeconds) {
    if (reactionSeconds >= 0.18 && reactionSeconds <= 0.25) {
      return 'Elite';
    }
    if (reactionSeconds > 0.25 && reactionSeconds <= 0.35) {
      return 'Good';
    }
    if (reactionSeconds > 0.35 && reactionSeconds <= 0.45) {
      return 'Average';
    }
    return 'Slow';
  }

  @override
  Widget build(BuildContext context) {
    final reactionMs = (widget.result.reactionTimeSeconds * 1000)
        .toStringAsFixed(0);
    final score = widget.result.score;
    final typeLabel = _startTypeLabel(widget.result.startType);
    final feedback = widget.result.startType == StartType.valid
        ? _reactionFeedback(widget.result.reactionTimeSeconds)
        : 'N/A';

    final sessionRuns = widget.sessionRuns;
    final validRuns = sessionRuns
        .where((run) => run.startType == StartType.valid)
        .toList();
    final bestSession = validRuns.isEmpty
        ? null
        : validRuns.map((e) => e.reactionTimeSeconds).reduce(min);
    final averageSession = validRuns.isEmpty
        ? null
        : validRuns.map((e) => e.reactionTimeSeconds).reduce((a, b) => a + b) /
              validRuns.length;

    final profileService = Provider.of<ProfileService>(context);
    final averageMs = (profileService.averageReaction * 1000).toStringAsFixed(
      0,
    );
    final history = profileService.sessionHistory;

    final maxHistoryMs = history.isEmpty
        ? 600.0
        : history.map((e) => e.reactionTimeSeconds * 1000).reduce(max);
    final chartMaxY = max(600.0, maxHistoryMs * 1.2);
    final chartWidth = max(
      MediaQuery.of(context).size.width - 40,
      history.length * 34.0,
    );
    final xLabelStep = max(1, (history.length / 6).ceil());
    final yInterval = max(100.0, (chartMaxY / 6).ceilToDouble());
    final showDots = history.length <= 15;

    return Scaffold(
      appBar: AppBar(title: const Text('Result')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Rider: ${widget.rider.name}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 18),
            Card(
              elevation: 2,
              color: Colors.black,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Reaction Time',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$reactionMs ms',
                      style: const TextStyle(
                        fontSize: 46,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Score',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$score / 100',
                      style: const TextStyle(
                        fontSize: 32,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Start Type',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      typeLabel,
                      style: const TextStyle(
                        fontSize: 24,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Feedback',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      feedback,
                      style: const TextStyle(
                        fontSize: 24,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Card(
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Session Stats',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 8),
                    Text('Total runs: ${sessionRuns.length}'),
                    Text(
                      'Best reaction: ${bestSession == null ? '--' : (bestSession * 1000).toStringAsFixed(0)} ms',
                    ),
                    Text(
                      'Average reaction: ${averageSession == null ? '--' : (averageSession * 1000).toStringAsFixed(0)} ms',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (history.isNotEmpty) ...[
              Text(
                'Reaction Trend',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 210,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: chartWidth,
                    child: LineChart(
                      LineChartData(
                        minY: 0,
                        maxY: chartMaxY,
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 46,
                              interval: yInterval,
                              getTitlesWidget: (value, meta) {
                                return Text(
                                  '${value.toInt()}ms',
                                  style: const TextStyle(fontSize: 10),
                                );
                              },
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              interval: xLabelStep.toDouble(),
                              reservedSize: 28,
                              getTitlesWidget: (value, meta) {
                                final index = value.toInt();
                                if (index < 0 || index >= history.length) {
                                  return const SizedBox.shrink();
                                }
                                if (index % xLabelStep != 0 &&
                                    index != history.length - 1) {
                                  return const SizedBox.shrink();
                                }
                                return Text(
                                  '${index + 1}',
                                  style: const TextStyle(fontSize: 10),
                                );
                              },
                            ),
                          ),
                          topTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: yInterval,
                        ),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: history
                                .asMap()
                                .entries
                                .map(
                                  (e) => FlSpot(
                                    e.key.toDouble(),
                                    e.value.reactionTimeSeconds * 1000,
                                  ),
                                )
                                .toList(),
                            isCurved: true,
                            barWidth: 3,
                            dotData: FlDotData(show: showDots),
                            belowBarData: BarAreaData(
                              show: true,
                              color: Colors.blue.withValues(alpha: 0.16),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Run number',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
            ],
            Text(
              'Session history (last ${history.length})',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            if (history.isEmpty)
              const Text('No history yet')
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Average: $averageMs ms',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 120,
                    child: ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: history.length,
                      itemBuilder: (context, index) {
                        final record = history[index];
                        final timeMs = (record.reactionTimeSeconds * 1000)
                            .toStringAsFixed(0);
                        final label = _startTypeLabel(record.startType);
                        return ListTile(
                          dense: true,
                          title: Text('$timeMs ms - ${record.score}/100'),
                          subtitle: Text(label),
                        );
                      },
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => GateScreen(
                      rider: widget.rider,
                      sessionRuns: sessionRuns,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.replay),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('Quick Repeat'),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                  (route) => false,
                );
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('End Session'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
