import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/connection_screen.dart';
import 'screens/live_results_screen.dart';
import 'screens/session_screen.dart';
import 'services/session_manager.dart';
import 'services/websocket_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => SessionManager(WebSocketService()),
      child: const CoachApp(),
    ),
  );
}

class CoachApp extends StatelessWidget {
  const CoachApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Coach App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
        useMaterial3: true,
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  static const _screens = <Widget>[
    ConnectionScreen(),
    LiveResultsScreen(),
    SessionScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final status = context.watch<SessionManager>().connectionStatus;
    final (label, color) = switch (status) {
      SocketConnectionStatus.connected => ('Connected', Colors.green),
      SocketConnectionStatus.connecting => ('Connecting', Colors.orange),
      SocketConnectionStatus.reconnecting => ('Reconnecting', Colors.orange),
      SocketConnectionStatus.error => ('Disconnected', Colors.red),
      SocketConnectionStatus.disconnected => ('Disconnected', Colors.grey),
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('BMX Coach App'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: color.withValues(alpha: 0.16),
                  border: Border.all(color: color),
                ),
                child: Text(label),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.wifi),
            label: 'Connection',
          ),
          NavigationDestination(
            icon: Icon(Icons.bolt),
            label: 'Live',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_alt),
            label: 'Session',
          ),
        ],
      ),
    );
  }
}
