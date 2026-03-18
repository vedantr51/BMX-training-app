import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

enum SocketConnectionStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

class ConnectionStateUpdate {
  const ConnectionStateUpdate({required this.status, this.errorMessage});

  final SocketConnectionStatus status;
  final String? errorMessage;
}

class WebSocketService {
  static const Duration _heartbeatTimeout = Duration(seconds: 10);
  static const Duration _heartbeatCheckInterval = Duration(seconds: 2);

  final StreamController<String> _messageController =
      StreamController<String>.broadcast();
  final StreamController<ConnectionStateUpdate> _statusController =
      StreamController<ConnectionStateUpdate>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _socketSubscription;
  Timer? _reconnectTimer;
  Timer? _heartbeatWatchdog;

  bool _shouldReconnect = false;
  String? _activeUrl;
  int _reconnectAttempt = 0;
  DateTime? _lastPingAt;

  Stream<String> get messages => _messageController.stream;
  Stream<ConnectionStateUpdate> get statusUpdates => _statusController.stream;

  Future<void> connect(String url) async {
    _shouldReconnect = true;
    _activeUrl = url;
    _reconnectAttempt = 0;

    await _openConnection(isReconnect: false);
  }

  Future<void> disconnect() async {
    _shouldReconnect = false;
    _activeUrl = null;
    _reconnectAttempt = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatWatchdog?.cancel();
    _heartbeatWatchdog = null;
    _lastPingAt = null;

    await _socketSubscription?.cancel();
    _socketSubscription = null;

    await _channel?.sink.close();
    _channel = null;

    _emitStatus(SocketConnectionStatus.disconnected);
  }

  Future<void> _openConnection({required bool isReconnect}) async {
    final url = _activeUrl;
    if (url == null) {
      return;
    }

    _emitStatus(
      isReconnect
          ? SocketConnectionStatus.reconnecting
          : SocketConnectionStatus.connecting,
    );

    try {
      await _socketSubscription?.cancel();
      await _channel?.sink.close();

      _channel = WebSocketChannel.connect(Uri.parse(url));
      _socketSubscription = _channel!.stream.listen(
        _onSocketMessage,
        onError: _onSocketError,
        onDone: _onSocketDone,
        cancelOnError: true,
      );

      _lastPingAt = DateTime.now();
      _startHeartbeatWatchdog();
      _emitStatus(SocketConnectionStatus.connected);
    } catch (error) {
      _emitStatus(SocketConnectionStatus.error, error.toString());
      _scheduleReconnect();
    }
  }

  void _onSocketMessage(dynamic data) {
    final messageString = data is String ? data : jsonEncode(data);
    final decoded = _tryDecode(messageString);
    if (decoded != null) {
      final event = (decoded['event'] ?? decoded['type'])?.toString();
      if (event == 'ping') {
        _lastPingAt = DateTime.now();
        _sendControlEvent('pong');
        return;
      }

      _messageController.add(jsonEncode(decoded));
      return;
    }

    _messageController.add(messageString);
  }

  void _onSocketError(dynamic error) {
    _emitStatus(SocketConnectionStatus.error, error.toString());
    _heartbeatWatchdog?.cancel();
    _heartbeatWatchdog = null;
    _scheduleReconnect();
  }

  void _onSocketDone() {
    _heartbeatWatchdog?.cancel();
    _heartbeatWatchdog = null;

    if (_shouldReconnect) {
      _emitStatus(SocketConnectionStatus.disconnected);
      _scheduleReconnect();
      return;
    }

    _emitStatus(SocketConnectionStatus.disconnected);
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect || _activeUrl == null) {
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectAttempt += 1;
    final delaySeconds = _reconnectAttempt <= 5
        ? (1 << _reconnectAttempt)
        : 30;

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      _openConnection(isReconnect: true);
    });
  }

  void _startHeartbeatWatchdog() {
    _heartbeatWatchdog?.cancel();
    _heartbeatWatchdog = Timer.periodic(_heartbeatCheckInterval, (_) {
      if (_connectionState != SocketConnectionStatus.connected) {
        return;
      }

      final lastPingAt = _lastPingAt;
      if (lastPingAt == null) {
        return;
      }

      final elapsed = DateTime.now().difference(lastPingAt);
      if (elapsed <= _heartbeatTimeout) {
        return;
      }

      _emitStatus(
        SocketConnectionStatus.error,
        'Connection lost: heartbeat timeout.',
      );

      _socketSubscription?.cancel();
      _socketSubscription = null;
      _channel?.sink.close();
      _channel = null;
      _scheduleReconnect();
    });
  }

  SocketConnectionStatus _connectionState = SocketConnectionStatus.disconnected;

  void _sendControlEvent(String event) {
    final channel = _channel;
    if (channel == null) {
      return;
    }

    try {
      channel.sink.add(
        jsonEncode(<String, dynamic>{
          'event': event,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        }),
      );
    } catch (_) {
      // Let normal socket error handlers process send failures.
    }
  }

  Map<String, dynamic>? _tryDecode(String raw) {
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map<String, dynamic>) {
        return parsed;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  void _emitStatus(SocketConnectionStatus status, [String? error]) {
    _connectionState = status;
    _statusController.add(
      ConnectionStateUpdate(status: status, errorMessage: error),
    );
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _statusController.close();
  }
}