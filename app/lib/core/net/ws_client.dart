import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Thin WebSocket transport: framing, clock estimation, heartbeat.
///
/// It knows nothing about football. Everything it emits is handed to
/// `MatchTransport`, which adapts player ids into `you`/`opponent` and feeds the
/// reducer. Splitting those two means the socket can be faked in a widget test with a
/// plain `StreamController<Map<String, dynamic>>`.
class GameSocket {
  GameSocket(this.url);

  final String url;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _pingTimer;
  final StreamController<Map<String, dynamic>> _frames =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Recent `serverNow - localNow` samples. Median, not mean: one GC pause must not
  /// move the clock (docs/03 §6).
  final List<int> _offsetSamples = <int>[];

  int _seq = 0;
  bool _disposed = false;

  Stream<Map<String, dynamic>> get frames => _frames.stream;

  bool get isOpen => _channel != null && !_disposed;

  Future<void> connect({
    required String deviceId,
    required String locale,
    required String region,
    String? sessionToken,
  }) async {
    _channel = WebSocketChannel.connect(Uri.parse(url));
    await _channel!.ready;

    _subscription = _channel!.stream.listen(
      _onData,
      onDone: _onDone,
      onError: _onError,
      cancelOnError: false,
    );

    send('hello', <String, dynamic>{
      'deviceId': deviceId,
      'locale': locale,
      'region': region,
      if (sessionToken != null) 'sessionToken': sessionToken,
    });

    _pingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      send('ping', <String, dynamic>{'c0': DateTime.now().millisecondsSinceEpoch});
    });
  }

  void send(String type, Map<String, dynamic> payload) {
    if (_disposed) return;
    final socket = _channel;
    if (socket == null) return;
    _seq += 1;
    socket.sink.add(jsonEncode(<String, dynamic>{
      'v': 1,
      'type': type,
      'seq': _seq,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'payload': payload,
    }));
  }

  /// Best estimate of the server clock. Used only to draw a countdown that matches the
  /// verdict; it never influences whether an answer counts.
  int get estimatedServerNowMs {
    final offset = _medianOffset;
    return DateTime.now().millisecondsSinceEpoch + (offset ?? 0);
  }

  /// How long is left in a round, according to the server's deadline.
  Duration remaining(int windowEndsAtMs) {
    final ms = windowEndsAtMs - estimatedServerNowMs;
    return Duration(milliseconds: ms < 0 ? 0 : ms);
  }

  int? get _medianOffset {
    if (_offsetSamples.isEmpty) return null;
    final sorted = <int>[..._offsetSamples]..sort();
    return sorted[sorted.length ~/ 2];
  }

  void _onData(dynamic raw) {
    Map<String, dynamic> frame;
    try {
      frame = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return; // a malformed frame from a modified server is not our problem
    }

    final payload = (frame['payload'] as Map?)?.cast<String, dynamic>();
    final serverNow = payload?['serverNow'];
    if (serverNow is int) _sampleClock(serverNow);

    if (!_frames.isClosed) _frames.add(frame);
  }

  void _sampleClock(int serverNowMs) {
    _offsetSamples.add(serverNowMs - DateTime.now().millisecondsSinceEpoch);
    if (_offsetSamples.length > 5) _offsetSamples.removeAt(0);
  }

  void _onDone() {
    if (!_frames.isClosed) _frames.close();
  }

  void _onError(Object error) {
    if (!_frames.isClosed) _frames.addError(error);
  }

  Future<void> dispose() async {
    _disposed = true;
    _pingTimer?.cancel();
    await _subscription?.cancel();
    await _channel?.sink.close();
    if (!_frames.isClosed) await _frames.close();
  }
}
