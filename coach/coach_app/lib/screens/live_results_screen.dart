import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/run_analysis.dart';
import '../services/session_manager.dart';
import '../widgets/replay_player.dart';

class LiveResultsScreen extends StatelessWidget {
  const LiveResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SessionManager>(
      builder: (context, manager, child) {
        final selected = manager.selectedRun;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StatusBanner(
              stateLabel: manager.liveStateLabel,
              detectionWindow: manager.detectionWindowActive,
            ),
            const SizedBox(height: 10),
            _CameraPanel(
              controller: manager.cameraController,
              cameraStatus: manager.cameraStatusLabel,
              diffScore: manager.cameraDiffScore,
            ),
            const SizedBox(height: 12),
            _RunSelector(
              runs: manager.analyzedRuns,
              selected: selected,
              onChanged: (id) => manager.selectAnalyzedRun(id),
            ),
            const SizedBox(height: 10),
            if (selected == null)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: Text('Waiting for analyzed runs...'),
                  ),
                ),
              )
            else ...[
              _ResultHeader(run: selected),
              const SizedBox(height: 10),
              ReplayPlayer(clip: selected.replayClip),
              const SizedBox(height: 10),
              _TimelineCard(run: selected),
              const SizedBox(height: 10),
              _KeyFramesCard(run: selected),
            ],
          ],
        );
      },
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.stateLabel,
    required this.detectionWindow,
  });

  final String stateLabel;
  final bool detectionWindow;

  @override
  Widget build(BuildContext context) {
    final color = detectionWindow ? Colors.green : Colors.blueGrey;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        stateLabel,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

class _CameraPanel extends StatelessWidget {
  const _CameraPanel({
    required this.controller,
    required this.cameraStatus,
    required this.diffScore,
  });

  final CameraController? controller;
  final String cameraStatus;
  final double diffScore;

  @override
  Widget build(BuildContext context) {
    final hasPreview = controller != null && controller!.value.isInitialized;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Live Camera',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                height: 180,
                color: Colors.black,
                alignment: Alignment.center,
                child: hasPreview
                    ? AspectRatio(
                        aspectRatio: controller!.value.aspectRatio,
                        child: CameraPreview(controller!),
                      )
                    : const Text(
                        'Camera preview unavailable',
                        style: TextStyle(color: Colors.white70),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Text('Status: $cameraStatus'),
            Text('Motion diff score: ${diffScore.toStringAsFixed(3)}'),
          ],
        ),
      ),
    );
  }
}

class _RunSelector extends StatelessWidget {
  const _RunSelector({
    required this.runs,
    required this.selected,
    required this.onChanged,
  });

  final List<RunAnalysis> runs;
  final RunAnalysis? selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Replay Comparison (Last 5 Runs)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (runs.isEmpty)
              const Text('No replay runs yet.')
            else
              DropdownButtonFormField<String>(
                initialValue: selected?.id ?? runs.first.id,
                items: runs
                    .map(
                      (run) => DropdownMenuItem<String>(
                        value: run.id,
                        child: Text(
                          '${run.result.rider} - ${(run.result.reactionTime * 1000).toStringAsFixed(0)} ms',
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) {
                    onChanged(value);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ResultHeader extends StatelessWidget {
  const _ResultHeader({required this.run});

  final RunAnalysis run;

  @override
  Widget build(BuildContext context) {
    final reactionMs = (run.result.reactionTime * 1000).toStringAsFixed(0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            _MetricChip(label: 'Rider', value: run.result.rider),
            _MetricChip(label: 'Reaction', value: '$reactionMs ms'),
            _MetricChip(label: 'Score', value: '${run.result.score}'),
            _MetricChip(label: 'Start', value: run.result.startType),
            _MetricChip(label: 'Feedback', value: run.feedbackLabel),
          ],
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('$label: $value'),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.run});

  final RunAnalysis run;

  @override
  Widget build(BuildContext context) {
    final clip = run.replayClip;
    final reactionMs = (run.result.reactionTime * 1000).toStringAsFixed(0);
    final greenIndex = clip?.greenMarkerIndex ?? 0;
    final moveIndex = clip?.movementMarkerIndex ?? 0;
    final total = (clip?.framePaths.length ?? 1).toDouble();
    final greenPosition = (greenIndex / total).clamp(0.0, 1.0);
    final movePosition = (moveIndex / total).clamp(0.0, 1.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reaction Timeline',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                return Stack(
                  children: [
                    Container(
                      width: width,
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    Positioned(
                      left: width * greenPosition,
                      child: Container(width: 3, height: 20, color: Colors.green),
                    ),
                    Positioned(
                      left: width * movePosition,
                      child: Container(width: 3, height: 20, color: Colors.red),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            Text('GREEN -> MOVE = $reactionMs ms'),
          ],
        ),
      ),
    );
  }
}

class _KeyFramesCard extends StatelessWidget {
  const _KeyFramesCard({required this.run});

  final RunAnalysis run;

  @override
  Widget build(BuildContext context) {
    final clip = run.replayClip;
    if (clip == null || clip.greenFramePath == null || clip.movementFramePath == null) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Key Frames',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _FullscreenImageViewer(
                          title: 'Green Frame',
                          imagePath: clip.greenFramePath!,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.fullscreen),
                  tooltip: 'Open green frame fullscreen',
                ),
                IconButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _FullscreenImageViewer(
                          title: 'Movement Frame',
                          imagePath: clip.movementFramePath!,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.open_in_new),
                  tooltip: 'Open movement frame fullscreen',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _KeyFrameTile(
                    title: 'Green Frame',
                    imagePath: clip.greenFramePath!,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _KeyFrameTile(
                    title: 'Movement Frame',
                    imagePath: clip.movementFramePath!,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyFrameTile extends StatelessWidget {
  const _KeyFrameTile({required this.title, required this.imagePath});

  final String title;
  final String imagePath;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 4),
        InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _FullscreenImageViewer(
                  title: title,
                  imagePath: imagePath,
                ),
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 100,
              width: double.infinity,
              child: Image.file(
                File(imagePath),
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FullscreenImageViewer extends StatelessWidget {
  const _FullscreenImageViewer({
    required this.title,
    required this.imagePath,
  });

  final String title;
  final String imagePath;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Center(
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: Image.file(
              File(imagePath),
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
