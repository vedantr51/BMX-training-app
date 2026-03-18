import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/replay_clip.dart';

class ReplayPlayer extends StatefulWidget {
  const ReplayPlayer({
    super.key,
    required this.clip,
    this.height = 220,
  });

  final ReplayClip? clip;
  final double height;

  @override
  State<ReplayPlayer> createState() => _ReplayPlayerState();
}

class _ReplayPlayerState extends State<ReplayPlayer> {
  Timer? _timer;
  int _index = 0;
  bool _isPlaying = false;

  @override
  void didUpdateWidget(covariant ReplayPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clip?.generatedAt != widget.clip?.generatedAt) {
      _stopPlayback();
      _index = 0;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clip = widget.clip;
    if (clip == null || !clip.hasFrames) {
      return Container(
        height: widget.height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text(
          'Replay unavailable',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    final safeIndex = _index.clamp(0, clip.framePaths.length - 1);
    final framePath = clip.framePaths[safeIndex];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            children: [
              SizedBox(
                height: widget.height,
                width: double.infinity,
                child: Image.file(
                  File(framePath),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              ),
              Positioned(
                left: 10,
                top: 10,
                child: _MarkerChip(
                  label: 'Frame ${safeIndex + 1}/${clip.framePaths.length}',
                  color: Colors.black87,
                ),
              ),
              if (safeIndex == clip.greenMarkerIndex)
                const Positioned(
                  right: 10,
                  top: 10,
                  child: _MarkerChip(
                    label: 'Green Light',
                    color: Color(0xFF19A25B),
                  ),
                ),
              if (safeIndex == clip.movementMarkerIndex)
                const Positioned(
                  right: 10,
                  top: 42,
                  child: _MarkerChip(
                    label: 'Movement Detected',
                    color: Color(0xFFCC4B39),
                  ),
                ),
              Positioned(
                right: 10,
                bottom: 10,
                child: IconButton.filledTonal(
                  onPressed: () async {
                    _stopPlayback();
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _ReplayFullscreenScreen(
                          clip: clip,
                          initialIndex: safeIndex,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.fullscreen),
                  tooltip: 'View fullscreen',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Slider(
          value: safeIndex.toDouble(),
          min: 0,
          max: (clip.framePaths.length - 1).toDouble(),
          divisions: clip.framePaths.length - 1,
          onChanged: (value) {
            setState(() {
              _index = value.round();
            });
          },
        ),
        Row(
          children: [
            IconButton(
              onPressed: _isPlaying ? _stopPlayback : () => _startPlayback(clip),
              icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
            ),
            Text(
              'Duration: ${(clip.totalDuration.inMilliseconds / 1000).toStringAsFixed(2)}s',
            ),
          ],
        ),
      ],
    );
  }

  void _startPlayback(ReplayClip clip) {
    _timer?.cancel();
    setState(() {
      _isPlaying = true;
    });

    _timer = Timer.periodic(clip.frameInterval, (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _index += 1;
        if (_index >= clip.framePaths.length) {
          _index = 0;
        }
      });
    });
  }

  void _stopPlayback() {
    _timer?.cancel();
    setState(() {
      _isPlaying = false;
    });
  }
}

class _MarkerChip extends StatelessWidget {
  const _MarkerChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}

class _ReplayFullscreenScreen extends StatefulWidget {
  const _ReplayFullscreenScreen({
    required this.clip,
    required this.initialIndex,
  });

  final ReplayClip clip;
  final int initialIndex;

  @override
  State<_ReplayFullscreenScreen> createState() =>
      _ReplayFullscreenScreenState();
}

class _ReplayFullscreenScreenState extends State<_ReplayFullscreenScreen> {
  Timer? _timer;
  late int _index;
  bool _isPlaying = true;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _startPlayback();
  }

  @override
  void dispose() {
    _timer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const []);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clip = widget.clip;
    final safeIndex = _index.clamp(0, clip.framePaths.length - 1);
    final framePath = clip.framePaths[safeIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Replay ${safeIndex + 1}/${clip.framePaths.length}'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Image.file(
                    File(framePath),
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Slider(
                value: safeIndex.toDouble(),
                min: 0,
                max: (clip.framePaths.length - 1).toDouble(),
                divisions: clip.framePaths.length - 1,
                onChanged: (value) {
                  setState(() {
                    _index = value.round();
                  });
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: _isPlaying ? _pausePlayback : _startPlayback,
                    icon: Icon(
                      _isPlaying ? Icons.pause_circle : Icons.play_circle,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Rotate device for portrait/landscape',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _startPlayback() {
    _timer?.cancel();
    setState(() {
      _isPlaying = true;
    });

    _timer = Timer.periodic(widget.clip.frameInterval, (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _index += 1;
        if (_index >= widget.clip.framePaths.length) {
          _index = 0;
        }
      });
    });
  }

  void _pausePlayback() {
    _timer?.cancel();
    setState(() {
      _isPlaying = false;
    });
  }
}
