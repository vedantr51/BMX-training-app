import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'qr_scanner_screen.dart';
import '../services/session_manager.dart';
import '../services/websocket_service.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final TextEditingController _ipController =
      TextEditingController(text: '192.168.1.2:8080');

  Future<void> _scanQrAndConnect(SessionManager manager) async {
    await manager.prepareForQrScanner();

    if (!mounted) {
      return;
    }

    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );

    await manager.restoreCameraAfterQrScanner();

    if (!mounted || scanned == null || scanned.isEmpty) {
      return;
    }

    final endpoint = scanned.trim();
    final isWsUrl = endpoint.startsWith('ws://') ||
        endpoint.startsWith('wss://') ||
        endpoint.startsWith('http://') ||
        endpoint.startsWith('https://') ||
        endpoint.contains('.');

    if (!isWsUrl) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid QR code. Expected ws://<ip>:8080'),
        ),
      );
      return;
    }

    _ipController.text = endpoint;
    await manager.connectToHost(endpoint);
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SessionManager>(
      builder: (context, manager, child) {
        final status = manager.connectionStatus;
        final isBusy = status == SocketConnectionStatus.connecting ||
            status == SocketConnectionStatus.reconnecting;
        final isConnected = status == SocketConnectionStatus.connected;

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _ipController,
                decoration: const InputDecoration(
                  labelText: 'Rider app IP or endpoint',
                  hintText: '192.168.1.10:8080',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: isBusy
                    ? null
                    : () {
                        manager.connectToHost(_ipController.text);
                      },
                icon: const Icon(Icons.link),
                label: Text(isBusy ? 'Connecting...' : 'Connect'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: isBusy
                    ? null
                    : () {
                        _scanQrAndConnect(manager);
                      },
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan QR to Connect'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: isConnected
                    ? () {
                        manager.disconnect();
                      }
                    : null,
                icon: const Icon(Icons.link_off),
                label: const Text('Disconnect'),
              ),
              const SizedBox(height: 16),
              _ConnectionStatusCard(status: status),
              const SizedBox(height: 10),
              if (manager.currentEndpoint != null)
                Text('Endpoint: ${manager.currentEndpoint}'),
              if (manager.lastError != null) ...[
                const SizedBox(height: 8),
                Text(
                  manager.lastError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ConnectionStatusCard extends StatelessWidget {
  const _ConnectionStatusCard({required this.status});

  final SocketConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (label, color) = switch (status) {
      SocketConnectionStatus.connected => ('Connected', Colors.green),
      SocketConnectionStatus.connecting => ('Connecting', Colors.orange),
      SocketConnectionStatus.reconnecting => ('Reconnecting', Colors.orange),
      SocketConnectionStatus.error => ('Error', colorScheme.error),
      _ => ('Disconnected', colorScheme.outline),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, size: 12, color: color),
          const SizedBox(width: 8),
          Text('Connection status: $label'),
        ],
      ),
    );
  }
}