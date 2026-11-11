import 'package:flutter/foundation.dart';

/// Client-side projection of the server's match state.
///
/// The client is a **renderer, not a referee**: it never decides whether an answer was
/// right, never starts a timer the server did not start, and never extrapolates the
/// score. Every field here arrives in a `round.*` / `shoot.*` / `match.*` event.
/// That is what makes a modified client harmless and a reconnect exact.
@immutable
class AnswerOption {
  const AnswerOption({required this.id, required this.text});
  final String id;
  final String text;
}

@immutable
class MatchUiState {
  const MatchUiState({
    this.phase = 'idle',
    this.half = 1,
    this.remainingSeconds = 45,
    this.yourGoals = 0,
    this.opponentGoals = 0,
    this.yourZone = 0,
    this.opponentZone = 0,
    this.youHaveBall = true,
    this.roundNo = 0,
    this.prompt = '',
    this.format = 'mc',
    this.formatData = const <String, dynamic>{},
    this.media = const <Map<String, String>>[],
    this.options = const <AnswerOption>[],
    this.selectedOptionId,
    this.correctOptionId,
    this.correctOptionText = '',
    this.explainer = '',
    this.outcome,
    this.opponentAnswered = false,
    this.youAreShooting,
    this.goalFlash = false,
    this.opponentConnected = true,
    this.accuracy,
    this.decidedBy,
    this.finalOutcome,
  });

  final String phase; // intro | open | answered | reveal | shoot | half_time | ended
  final int half;
  final int remainingSeconds;

  final int yourGoals;
  final int opponentGoals;
  final int yourZone;
  final int opponentZone;
  final bool youHaveBall;

  final int roundNo;
  final String prompt;
  final String format;
  final Map<String, dynamic> formatData;
  final List<Map<String, String>> media;
  final List<AnswerOption> options;

  final String? selectedOptionId;
  final String? correctOptionId;
  final String correctOptionText;
  final String explainer;

  final String? outcome; // correct | wrong | no_answer
  final bool opponentAnswered;
  final bool? youAreShooting;
  final bool goalFlash;
  final bool opponentConnected;
  final double? accuracy;
  final String? decidedBy;
  final String? finalOutcome;

  /// The shooter must be able to answer a Shooting Chance; the defender must not.
  bool get answersEnabled =>
      (phase == 'open' || (phase == 'shoot' && youAreShooting == true)) &&
      selectedOptionId == null;

  MatchUiState copyWith({
    String? phase,
    int? half,
    int? remainingSeconds,
    int? yourGoals,
    int? opponentGoals,
    int? yourZone,
    int? opponentZone,
    bool? youHaveBall,
    int? roundNo,
    String? prompt,
    String? format,
    Map<String, dynamic>? formatData,
    List<Map<String, String>>? media,
    List<AnswerOption>? options,
    String? selectedOptionId,
    String? correctOptionId,
    String? correctOptionText,
    String? explainer,
    String? outcome,
    bool? opponentAnswered,
    bool? youAreShooting,
    bool? goalFlash,
    bool? opponentConnected,
    double? accuracy,
    String? decidedBy,
    String? finalOutcome,
  }) {
    return MatchUiState(
      phase: phase ?? this.phase,
      half: half ?? this.half,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      yourGoals: yourGoals ?? this.yourGoals,
      opponentGoals: opponentGoals ?? this.opponentGoals,
      yourZone: yourZone ?? this.yourZone,
      opponentZone: opponentZone ?? this.opponentZone,
      youHaveBall: youHaveBall ?? this.youHaveBall,
      roundNo: roundNo ?? this.roundNo,
      prompt: prompt ?? this.prompt,
      format: format ?? this.format,
      formatData: formatData ?? this.formatData,
      media: media ?? this.media,
      options: options ?? this.options,
      selectedOptionId: selectedOptionId ?? this.selectedOptionId,
      correctOptionId: correctOptionId ?? this.correctOptionId,
      correctOptionText: correctOptionText ?? this.correctOptionText,
      explainer: explainer ?? this.explainer,
      outcome: outcome ?? this.outcome,
      opponentAnswered: opponentAnswered ?? this.opponentAnswered,
      youAreShooting: youAreShooting ?? this.youAreShooting,
      goalFlash: goalFlash ?? this.goalFlash,
      opponentConnected: opponentConnected ?? this.opponentConnected,
      accuracy: accuracy ?? this.accuracy,
      decidedBy: decidedBy ?? this.decidedBy,
      finalOutcome: finalOutcome ?? this.finalOutcome,
    );
  }

  /// Clears per-round fields so the previous round cannot bleed into the next one.
  MatchUiState nextRound() => MatchUiState(
        phase: 'intro',
        half: half,
        remainingSeconds: remainingSeconds,
        yourGoals: yourGoals,
        opponentGoals: opponentGoals,
        yourZone: yourZone,
        opponentZone: opponentZone,
        youHaveBall: youHaveBall,
        roundNo: roundNo,
        formatData: const <String, dynamic>{},
        media: const <Map<String, String>>[],
      );
}

/// A pure reducer: `(state, event) -> state`. No side effects, no clocks, no network.
/// Trivially unit-testable, which is how the UI is tested without a device.
///
/// NOTE: the server keys `zones`, `goals` and `possession` by playerId. The transport
/// adapter rewrites those keys to `you` / `opponent` before calling this function, so the
/// reducer never has to know either player's id. Keeping that mapping in one place is what
/// lets this file stay a pure function of the event shape.
MatchUiState reduce(MatchUiState state, Map<String, dynamic> event) {
  final type = event['type'] as String? ?? '';
  final payload = (event['payload'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
  final zones = (payload['zones'] as Map?)?.cast<String, dynamic>();
  final goals = (payload['goals'] as Map?)?.cast<String, dynamic>();
  final view = (payload['view'] as Map?)?.cast<String, dynamic>();

  switch (type) {
    case 'match.start':
    case 'match.second_half':
      return state.copyWith(
        phase: 'intro',
        half: (payload['half'] as int?) ?? state.half,
        yourGoals: 0,
        opponentGoals: 0,
        yourZone: 0,
        opponentZone: 0,
        remainingSeconds: 45,
        opponentConnected: true,
        finalOutcome: '',
      );

    case 'round.intro':
      final introView = (payload['view'] as Map?)?.cast<String, dynamic>();
      final introOptions = ((introView?['options'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map((o) => AnswerOption(id: o['id'] as String, text: o['text'] as String))
          .toList(growable: false);
      return state.nextRound().copyWith(
        phase: 'intro',
        roundNo: (payload['roundNo'] as int?) ?? state.roundNo,
        remainingSeconds: 1,
        prompt: (introView?['prompt'] as String?) ?? '',
        format: (introView?['format'] as String?) ?? 'mc',
        formatData: (introView?['formatData'] as Map?)?.cast<String, dynamic>() ?? const {},
        media: ((introView?['media'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => m.cast<String, String>())
            .toList(growable: false),
        options: introOptions,
      );

    case 'round.question':
      final options = ((view?['options'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map((o) => AnswerOption(id: o['id'] as String, text: o['text'] as String))
          .toList(growable: false);
      return state.copyWith(
        phase: 'open',
        roundNo: (payload['roundNo'] as int?) ?? state.roundNo,
        prompt: (view?['prompt'] as String?) ?? '',
        format: (view?['format'] as String?) ?? 'mc',
        formatData: (view?['formatData'] as Map?)?.cast<String, dynamic>() ?? const {},
        media: ((view?['media'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => m.cast<String, String>())
            .toList(growable: false),
        remainingSeconds: (((payload['windowEndsAt'] as int?) ?? 0) - ((payload['serverNow'] as int?) ?? 0)).clamp(0, 9000) ~/ 1000,
        options: options,
        selectedOptionId: '',
        correctOptionId: '',
        correctOptionText: '',
        explainer: '',
        outcome: '',
        opponentAnswered: false,
        youAreShooting: null,
      );

    case 'round.answer_ack':
      return state.copyWith(phase: 'answered');

    case 'round.opponent_answered':
      return state.copyWith(opponentAnswered: true);

    case 'round.reveal':
      return state.copyWith(
        phase: 'reveal',
        yourZone: (zones?['you'] as int?) ?? state.yourZone,
        opponentZone: (zones?['opponent'] as int?) ?? state.opponentZone,
        outcome: (payload['outcome'] as String?) ?? '',
        correctOptionId: (payload['correctOptionId'] as String?) ?? '',
        correctOptionText: (payload['correctOptionText'] as String?) ?? '',
        explainer: (payload['explainer'] as String?) ?? '',
        youHaveBall: (payload['possession'] as String?) == 'you',
      );

    case 'shoot.question':
      return state.copyWith(
        phase: 'shoot',
        prompt: (view?['prompt'] as String?) ?? '',
        format: (view?['format'] as String?) ?? 'mc',
        formatData: (view?['formatData'] as Map?)?.cast<String, dynamic>() ?? const {},
        media: ((view?['media'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => m.cast<String, String>())
            .toList(growable: false),
        remainingSeconds: (((payload['windowEndsAt'] as int?) ?? 0) - ((payload['serverNow'] as int?) ?? 0)).clamp(0, 5000) ~/ 1000,
        options: ((view?['options'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map((o) => AnswerOption(id: o['id'] as String, text: o['text'] as String))
            .toList(growable: false),
        selectedOptionId: '',
        youAreShooting: payload['youAreShooting'] as bool?,
        remainingSeconds: 5,
      );

    case 'shoot.reveal':
      return state.copyWith(
        phase: 'reveal',
        goalFlash: payload['scored'] == true,
        yourGoals: (goals?['you'] as int?) ?? state.yourGoals,
        opponentGoals: (goals?['opponent'] as int?) ?? state.opponentGoals,
        yourZone: (zones?['you'] as int?) ?? state.yourZone,
        opponentZone: (zones?['opponent'] as int?) ?? state.opponentZone,
        correctOptionId: (payload['correctOptionId'] as String?) ?? '',
        correctOptionText: (payload['correctOptionText'] as String?) ?? '',
        explainer: (payload['explainer'] as String?) ?? '',
      );

    case 'opponent.connection':
      return state.copyWith(opponentConnected: payload['connected'] == true);

    case 'match.half':
      return state.copyWith(phase: 'half_time');

    case 'match.end':
      final stats = (payload['stats'] as Map?)?.cast<String, dynamic>();
      return state.copyWith(
        phase: 'ended',
        finalOutcome: (payload['outcome'] as String?) ?? 'draw',
        decidedBy: (payload['decidedBy'] as String?) ?? '',
        accuracy: (stats?['accuracy'] as num?)?.toDouble(),
        yourGoals: (goals?['you'] as int?) ?? state.yourGoals,
        opponentGoals: (goals?['opponent'] as int?) ?? state.opponentGoals,
      );

    default:
      return state;
  }
}
