import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/sensitivity.dart';
import '../services/profile_service.dart';
import '../services/websocket_server_service.dart';
import 'calibration_screen.dart';
import 'gate_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _showAddRiderDialog(BuildContext context) async {
    _nameController.text = '';

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Rider'),
          content: TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Rider name'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final name = _nameController.text.trim();
                if (name.isEmpty) return;
                Provider.of<ProfileService>(context, listen: false).addRider(name);
                Navigator.of(context).pop();
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<ProfileService, WebSocketServerService>(
      builder: (context, profiles, socketServer, child) {
        final selected = profiles.selectedRider;
        final wsAddress = socketServer.wsAddress;
        final connectionLabel = socketServer.hasCoachConnection
            ? 'Coach connected'
            : 'Waiting for connection';
        final connectionColor = socketServer.hasCoachConnection
            ? Colors.green
            : Colors.orange;

        return Scaffold(
          appBar: AppBar(
            title: const Text('BMX Gate Reaction Trainer'),
          ),
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Select your rider profile',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: profiles.riders.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final rider = profiles.riders[index];
                      final selectedFlag = selected?.id == rider.id;
                      return ListTile(
                        title: Text(rider.name),
                        subtitle: Text(
                            'Best: ${rider.personalBestReactionTime.isFinite ? (rider.personalBestReactionTime * 1000).toStringAsFixed(0) : "--"}ms • Score: ${rider.bestScore}'),
                        trailing: selectedFlag ? const Icon(Icons.check_circle) : null,
                        onTap: () => profiles.selectRider(rider),
                        onLongPress: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) {
                              return AlertDialog(
                                title: const Text('Delete rider?'),
                                content: Text('Remove ${rider.name} from profiles?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              );
                            },
                          );
                          if (confirmed == true) {
                            await profiles.deleteRider(rider.id);
                          }
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Motion sensitivity',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                DropdownButton<MotionSensitivity>(
                  value: profiles.sensitivity,
                  isExpanded: true,
                  items: MotionSensitivity.values
                      .map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text(s.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      profiles.setSensitivity(value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Calibration',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          profiles.hasCalibration
                              ? 'Status: calibrated'
                              : 'Status: not calibrated',
                        ),
                        if (profiles.hasCalibration &&
                            profiles.calibratedThreshold != null) ...[
                          Text(
                            'Noise: ${profiles.calibrationNoiseLevel.toStringAsFixed(2)}',
                          ),
                          Text(
                            'Threshold: ${profiles.calibratedThreshold!.toStringAsFixed(2)}',
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const CalibrationScreen(),
                                    ),
                                  );
                                },
                                child: const Text('Start Calibration'),
                              ),
                            ),
                            if (profiles.hasCalibration) ...[
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed: () {
                                  profiles.clearCalibration();
                                },
                                child: const Text('Clear'),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Device Ready',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          wsAddress == null
                              ? 'IP Address: unavailable'
                              : 'IP Address: ${socketServer.localIp}:${WebSocketServerService.port}',
                        ),
                        if (socketServer.lastError != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            socketServer.lastError!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.circle, size: 12, color: connectionColor),
                            const SizedBox(width: 8),
                            Text(connectionLabel),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: wsAddress == null
                                  ? null
                                  : () async {
                                      await Clipboard.setData(
                                        ClipboardData(text: wsAddress),
                                      );
                                      if (!context.mounted) {
                                        return;
                                      }
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Address copied'),
                                        ),
                                      );
                                    },
                              icon: const Icon(Icons.copy),
                              label: const Text('Copy'),
                            ),
                          ],
                        ),
                        if (wsAddress != null) ...[
                          const SizedBox(height: 8),
                          Center(
                            child: QrImageView(
                              data: wsAddress,
                              size: 160,
                              backgroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: selected == null
                      ? null
                      : () {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => GateScreen(rider: selected),
                          ));
                        },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14.0),
                    child: Text('Start Session'),
                  ),
                ),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _showAddRiderDialog(context),
            tooltip: 'Add rider',
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }
}
