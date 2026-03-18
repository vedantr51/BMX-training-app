import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/session_manager.dart';

class SessionScreen extends StatelessWidget {
  const SessionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SessionManager>(
      builder: (context, manager, child) {
        final runs = manager.analyzedRuns;

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SummaryCard(manager: manager),
              const SizedBox(height: 12),
              Text(
                'Stored Replay Runs (Last 5)',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: runs.isEmpty
                    ? const Center(child: Text('No analyzed runs yet.'))
                    : ListView.separated(
                        itemCount: runs.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final run = runs[index];
                          final reactionMs =
                              (run.result.reactionTime * 1000).toStringAsFixed(0);
                          final hasReplay = run.replayClip?.hasFrames ?? false;

                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(child: Text('${index + 1}')),
                              title: Text(run.result.rider),
                              subtitle: Text(
                                '${run.feedbackLabel} • ${run.result.startType} • ${run.result.timestamp.toLocal()}',
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('$reactionMs ms | ${run.result.score}'),
                                  Text(
                                    hasReplay ? 'Replay ready' : 'No replay',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: hasReplay
                                          ? Colors.green
                                          : Colors.orange,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.manager});

  final SessionManager manager;

  @override
  Widget build(BuildContext context) {
    final bestMs = (manager.bestTime * 1000).toStringAsFixed(0);
    final avgMs = (manager.averageTime * 1000).toStringAsFixed(0);
    final consistencyMs = (manager.consistency * 1000).toStringAsFixed(1);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Analysis Summary', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Runs analyzed: ${manager.totalRuns}'),
            Text('Best reaction: $bestMs ms'),
            Text('Average reaction: $avgMs ms'),
            Text('Consistency (std dev): +/-$consistencyMs ms'),
          ],
        ),
      ),
    );
  }
}
