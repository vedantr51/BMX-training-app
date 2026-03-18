import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'models/rider.dart';
import 'models/session_record.dart';
import 'models/start_type_adapter.dart';
import 'screens/home_screen.dart';
import 'services/profile_service.dart';
import 'services/websocket_server_service.dart';
import 'storage/rider_storage.dart';
import 'storage/settings_storage.dart';
import 'storage/session_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  Hive.registerAdapter(RiderAdapter());
  Hive.registerAdapter(StartTypeAdapter());
  Hive.registerAdapter(SessionRecordAdapter());

  await RiderStorage.init();
  await SettingsStorage.init();
  await SessionStorage.init();

  final websocketServerService = WebSocketServerService();
  await websocketServerService.initialize();

  runApp(MyApp(websocketServerService: websocketServerService));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.websocketServerService});

  final WebSocketServerService websocketServerService;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ProfileService()),
        ChangeNotifierProvider.value(value: websocketServerService),
      ],
      child: MaterialApp(
        title: 'BMX Gate Reaction Trainer',
        theme: ThemeData.from(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
