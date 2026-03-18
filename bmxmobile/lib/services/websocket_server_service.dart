import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';

import '../models/session_result.dart';

class WebSocketServerService extends ChangeNotifier {
  static const int port = 8080;
  static const Duration heartbeatInterval = Duration(seconds: 3);

  final NetworkInfo _networkInfo = NetworkInfo();
  final Set<WebSocket> _clients = <WebSocket>{};

  HttpServer? _server;
  Timer? _heartbeatTimer;
  String? _localIp;
  bool _isReady = false;
  String? _lastError;

  bool get isReady => _isReady;
  bool get hasCoachConnection => _clients.isNotEmpty;
  int get connectedCoachCount => _clients.length;
  String? get localIp => _localIp;
  String? get lastError => _lastError;

  String? get wsAddress {
    final ip = _localIp;
    if (ip == null || ip.isEmpty) {
      return null;
    }
    return 'ws://$ip:$port';
  }

  Future<void> initialize() async {
    await _fetchLocalIp();
    await _startServer();
  }

  Future<void> _fetchLocalIp() async {
    try {
      final ip = await _networkInfo.getWifiIP();
      if (ip != null && ip.isNotEmpty && ip != '127.0.0.1') {
        _localIp = ip;
      } else {
        _localIp = null;
      }
    } catch (error) {
      _lastError = 'Unable to read WiFi IP: $error';
    }
  }

  Future<void> _startServer() async {
    try {
      await _server?.close(force: true);
      _server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        port,
        shared: true,
      );

      _server!.listen(_handleRequest, onError: (Object error) {
        _lastError = 'WebSocket server error: $error';
        notifyListeners();
      });

      _isReady = true;
      _lastError = null;
    } catch (error) {
      _isReady = false;
      _lastError = 'Failed to start server on $port: $error';
    }

    notifyListeners();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('WebSocket upgrade required')
        ..close();
      return;
    }

    try {
      final socket = await WebSocketTransformer.upgrade(request);
      _clients.add(socket);
      _startHeartbeatIfNeeded();
      notifyListeners();

      socket.listen(
        (message) {
          _handleIncomingMessage(message);
        },
        onDone: () {
          _clients.remove(socket);
          if (_clients.isEmpty) {
            _heartbeatTimer?.cancel();
            _heartbeatTimer = null;
          }
          notifyListeners();
        },
        onError: (_) {
          _clients.remove(socket);
          if (_clients.isEmpty) {
            _heartbeatTimer?.cancel();
            _heartbeatTimer = null;
          }
          notifyListeners();
        },
        cancelOnError: true,
      );
    } catch (error) {
      _lastError = 'Failed to accept client: $error';
      notifyListeners();
    }
  }

  Future<void> sendRunResult({
    required String riderName,
    required double reactionTime,
    required int score,
    required StartType startType,
  }) async {
    final payload = <String, dynamic>{
      'rider': riderName,
      'reaction_time': reactionTime,
      'score': score,
      'start_type': _startTypeLabel(startType),
    };

    await broadcastEvent(event: 'run_result', payload: payload);
  }

  Future<void> sendGateStarted() {
    return broadcastEvent(event: 'gate_started');
  }

  Future<void> sendYellowLight() {
    return broadcastEvent(event: 'yellow_light');
  }

  Future<void> sendGreenLight() {
    return broadcastEvent(event: 'green_light');
  }

  Future<void> broadcastEvent({
    required String event,
    Map<String, dynamic> payload = const <String, dynamic>{},
  }) async {
    if (_clients.isEmpty) {
      return;
    }

    final messageMap = <String, dynamic>{
      'event': event,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      ...payload,
    };

    final message = jsonEncode(messageMap);
    final deadSockets = <WebSocket>[];

    for (final socket in _clients) {
      try {
        socket.add(message);
      } catch (_) {
        deadSockets.add(socket);
      }
    }

    if (deadSockets.isNotEmpty) {
      for (final socket in deadSockets) {
        _clients.remove(socket);
      }
      if (_clients.isEmpty) {
        _heartbeatTimer?.cancel();
        _heartbeatTimer = null;
      }
      notifyListeners();
    }
  }

  void _startHeartbeatIfNeeded() {
    if (_heartbeatTimer != null) {
      return;
    }

    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      broadcastEvent(event: 'ping');
    });
  }

  void _handleIncomingMessage(dynamic message) {
    if (message is! String) {
      return;
    }

    try {
      final decoded = jsonDecode(message);
      if (decoded is! Map<String, dynamic>) {
        return;
      }
    } catch (_) {
      // Ignore malformed inbound messages from clients.
    }
  }

  String _startTypeLabel(StartType startType) {
    switch (startType) {
      case StartType.valid:
        return 'valid';
      case StartType.falseStart:
        return 'false_start';
      case StartType.lateStart:
        return 'late_start';
    }
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    unawaited(_server?.close(force: true));
    for (final socket in _clients) {
      socket.close();
    }
    _clients.clear();
    super.dispose();
  }
}