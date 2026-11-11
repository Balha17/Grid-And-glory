import 'dart:async';

import '../../core/net/ws_client.dart';
import 'match_view_model.dart';

/// The seam between the wire and the reducer.
///
/// The server keys `zones`, `goals` and `possession` by playerId because it does not
/// know which side is "you" — both players are equally first-class to a referee. The
/// client does know, and this class rewrites those keys to `you` / `opponent` exactly
/// once, so `reduce()` stays a pure function of a stable event shape.
///
/// It also holds the round token, which is the only thing that authorises an answer.
class MatchTransport {
  MatchTransport({required GameSocket socket, required String playerId})
      : _socket = socket,
        _playerId = playerId {
    _subscription = socket.frames.listen(_onFrame);
  }

  final GameSocket _socket;
  String _playerId;
  StreamSubscription<Map<String, dynamic>>? _subscription;

  final StreamController<MatchUiState> _states =
      StreamController<MatchUiState>.broadcast();

  MatchUiState _state = const MatchUiState();
  String? _token;
  int _roundNo = 0;

  Stream<MatchUiState> get states => _states.stream;
  MatchUiState get state => _state;

  /// Frames the app cares about, for logging and for the debug overlay.
  final List<Map<String, dynamic>> transcript = <Map<String, dynamic>>[];

  void rebind(String playerId) => _playerId = playerId;

  void _onFrame(Map<String, dynamic> frame) {
    final type = frame['type'] as String? ?? '';
    final adapted = _adapt(frame);

    if (type == 'round.question' || type == 'shoot.question') {
      final payload = adapted['payload'] as Map<String, dynamic>;
      _token = payload['token'] as String?;
      _roundNo = (payload['roundNo'] as int?) ?? _roundNo;
    }

    transcript.add(adapted);
    _state = reduce(_state, adapted);
    if (!_states.isClosed) _states.add(_state);
  }

  /// Submit an answer. The selection locks immediately (neutral styling) but the
  /// *outcome* is only ever coloured by `round.reveal` — the server has not ruled yet.
  void answer(String optionId) {
    final token = _token;
    if (token == null) return;
    _socket.send('round.answer', <String, dynamic>{
      'token': token,
      'optionId': optionId,
      'clientMs': DateTime.now().millisecondsSinceEpoch,
    });
    _emit(_state.copyWith(phase: 'answered', selectedOptionId: optionId));
  }

  void ping() => _socket.send('ping', <String, dynamic>{});

  void _emit(MatchUiState next) {
    _state = next;
    if (!_states.isClosed) _states.add(_state);
  }

  Map<String, dynamic> _adapt(Map<String, dynamic> frame) {
    final payload = Map<String, dynamic>.from(
      (frame['payload'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{},
    );

    final zones = payload['zones'];
    if (zones is Map) payload['zones'] = _pair(zones);

    final goals = payload['goals'];
    if (goals is Map) payload['goals'] = _pair(goals);

    final possession = payload['possession'];
    if (possession is String) {
      payload['possession'] = possession == _playerId ? 'you' : 'opponent';
    }

    return <String, dynamic>{'type': frame['type'], 'payload': payload};
  }

  /// A two-player map keyed by opaque player ids becomes `you` / `opponent`.
  Map<String, int> _pair(Map raw) {
    final map = raw.cast<String, dynamic>();
    final others = map.entries.where((e) => e.key != _playerId);
    return <String, int>{
      'you': (map[_playerId] as num?)?.toInt() ?? 0,
      'opponent': others.isEmpty ? 0 : (others.first.value as num?)?.toInt() ?? 0,
    };
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _states.close();
  }
}
