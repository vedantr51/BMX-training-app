import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/calibration_service.dart';
import '../services/profile_service.dart';

enum _CalibrationStage { idle, baseline, pushes, complete, error }

class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  final CalibrationService _calibrationService = CalibrationService();

  _CalibrationStage _stage = _CalibrationStage.idle;
  bool _busy = false;
  String? _error;

  double? _noiseLevel;
  double? _threshold;
  List<double> _samples = const <double>[];

  @override
  void dispose() {
    _calibrationService.dispose();
    super.dispose();
  }

  Future<void> _startCalibration() async {
    setState(() {
      _busy = true;
      _stage = _CalibrationStage.baseline;
      _error = null;
      _noiseLevel = null;
      _threshold = null;
      _samples = const <double>[];
    });

    try {
      final noise = await _calibrationService.measureBaselineNoise();
      if (!mounted) return;

      setState(() {
        _stage = _CalibrationStage.pushes;
        _noiseLevel = noise;
      });

      final pushes = await _calibrationService.collectForwardPushSamples(
        noiseLevel: noise,
        sampleCount: 3,
      );
      if (!mounted) return;

      final averagePush =
          pushes.fold<double>(0.0, (sum, value) => sum + value) / pushes.length;
        final margin = max(0.20, noise * 0.6);
        final threshold = max(noise + margin, averagePush * 0.50);

      await Provider.of<ProfileService>(
        context,
        listen: false,
      ).saveCalibration(
        threshold: threshold,
        noiseLevel: noise,
        confidenceMin: 1.0,
        forwardRatio: 0.30,
      );

      if (!mounted) return;

      setState(() {
        _busy = false;
        _stage = _CalibrationStage.complete;
        _threshold = threshold;
        _samples = pushes;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _stage = _CalibrationStage.error;
        _error = error.toString();
      });
    }
  }

  String _instructionText() {
    switch (_stage) {
      case _CalibrationStage.baseline:
        return 'Keep device still';
      case _CalibrationStage.pushes:
        return 'Push forward 3 times';
      case _CalibrationStage.complete:
        return 'Calibration complete';
      case _CalibrationStage.error:
        return 'Calibration failed';
      case _CalibrationStage.idle:
        return 'Start calibration';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Calibration')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _instructionText(),
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'Step 1: Keep device still for 1 second.\nStep 2: Push forward 3 times.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (_busy)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(12.0),
                  child: CircularProgressIndicator(),
                ),
              ),
            if (_noiseLevel != null)
              _InfoRow(label: 'Noise level', value: _noiseLevel!.toStringAsFixed(2)),
            if (_threshold != null)
              _InfoRow(label: 'Threshold', value: _threshold!.toStringAsFixed(2)),
            if (_samples.isNotEmpty)
              _InfoRow(
                label: 'Push samples',
                value: _samples.map((e) => e.toStringAsFixed(2)).join(', '),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const Spacer(),
            ElevatedButton(
              onPressed: _busy ? null : _startCalibration,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Start Calibration'),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () {
                      Navigator.of(context).pop();
                    },
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
