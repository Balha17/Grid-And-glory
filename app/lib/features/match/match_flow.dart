import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/l10n/bidi.dart';
import '../../core/locale/locale_controller.dart';
import '../../core/net/ws_client.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import 'match_screen.dart';
import 'match_transport.dart';
import 'match_view_model.dart';

/// Owns the socket for one visit to the arena, and renders the three states that share
/// that socket: searching → playing → finished.
///
/// One widget on purpose. Pushing a new route per phase is how you end up with a match
/// screen that reconnects itself or a socket that outlives the screen that owns it.
class MatchFlowScreen extends ConsumerStatefulWidget {
  const MatchFlowScreen({super.key});

  @override
  ConsumerState<MatchFlowScreen> createState() => _MatchFlowScreenState();
}

enum _Stage { connecting, searching, found, playing, finished, failed }

class _MatchFlowScreenState extends ConsumerState<MatchFlowScreen> {
  static const String _url = String.fromEnvironment(
    'WS_URL',
    // 10.0.2.2 is the host loopback as seen from an Android emulator.
    defaultValue: 'ws://10.0.2.2:8080/ws',
  );

  late final GameSocket _socket;
  MatchTransport? _transport;
  StreamSubscription<MatchUiState>? _stateSub;

  _Stage _stage = _Stage.connecting;
  MatchUiState _state = const MatchUiState();
  String? _playerId;
  String? _opponentName;
  String? _opponentLocale;
  String _failure = '';

  @override
  void initState() {
    super.initState();
    _socket = GameSocket(_url);
    _socket.frames.listen(_onFrame);
    _start();
  }

  Future<void> _start() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final locale = ref.read(localeControllerProvider);
    try {
      await _socket.connect(
        deviceId: _deviceId(prefs),
        locale: locale.languageCode,
        region: _regionFor(locale.languageCode),
      );
    } catch (_) {
      if (mounted) setState(() => _stage = _Stage.failed);
    }
  }

  String _deviceId(SharedPreferences prefs) {
    final existing = prefs.getString('device_id');
    if (existing != null) return existing;
    final random = math.Random.secure();
    final generated = List<String>.generate(
      16,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    prefs.setString('device_id', generated);
    return generated;
  }

  /// Region is a *latency* hint only. It is never used to pick an opponent's language.
  String _regionFor(String languageCode) => languageCode == 'ar' ? 'MENA' : 'EU';

  void _onFrame(Map<String, dynamic> frame) {
    final type = frame['type'] as String?;
    final payload = (frame['payload'] as Map?)?.cast<String, dynamic>() ?? const {};

    switch (type) {
      case 'hello.ack':
        final playerId = payload['playerId'] as String?;
        if (playerId == null) return;
        _playerId = playerId;
        final transport = MatchTransport(socket: _socket, playerId: playerId);
        _transport = transport;
        _stateSub = transport.states.listen((next) {
          if (!mounted) return;
          setState(() {
            _state = next;
            if (next.phase == 'ended') _stage = _Stage.finished;
          });
        });
        _socket.send('queue.join', const {});
        if (mounted) setState(() => _stage = _Stage.searching);

      case 'match.found':
        final opponent = (payload['opponent'] as Map?)?.cast<String, dynamic>();
        setState(() {
          _opponentName = opponent?['displayName'] as String?;
          _opponentLocale = opponent?['locale'] as String?;
          _stage = _Stage.found;
        });
        // Let the player read who they are facing; it is the only social beat in the game.
        Timer(const Duration(milliseconds: 1400), () {
          if (mounted) setState(() => _stage = _Stage.playing);
        });

      case 'error':
        if (mounted) setState(() => _failure = String(payload['code']));
    }
  }

  Future<void> _rematch() async {
    await _stateSub?.cancel();
    await _transport?.dispose();
    _transport = null;
    _state = const MatchUiState();
    _socket.send('queue.join', const {});
    setState(() => _stage = _Stage.searching);
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _transport?.dispose();
    _socket.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeControllerProvider);
    final l10n = AppLocalizations.of(context)!;

    switch (_stage) {
      case _Stage.playing:
        return MatchScreen(
          state: _state,
          locale: locale,
          onAnswer: (optionId) => _transport?.answer(optionId),
        );
      case _Stage.finished:
        return _ResultView(
          state: _state,
          locale: locale,
          l10n: l10n,
          onRematch: _rematch,
          onHome: () => Navigator.of(context).pop(),
        );
      case _Stage.connecting:
      case _Stage.searching:
      case _Stage.found:
        return _LobbyView(
          locale: locale,
          l10n: l10n,
          searching: _stage != _Stage.found,
          opponentName: _opponentName,
          opponentLocale: _opponentLocale,
          onCancel: () => Navigator.of(context).pop(),
        );
      case _Stage.failed:
        return _FailedView(locale: locale, l10n: l10n, detail: _failure);
    }
  }
}

class _LobbyView extends StatelessWidget {
  const _LobbyView({
    required this.locale,
    required this.l10n,
    required this.searching,
    required this.opponentName,
    required this.opponentLocale,
    required this.onCancel,
  });

  final Locale locale;
  final AppLocalizations l10n;
  final bool searching;
  final String? opponentName;
  final String? opponentLocale;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsetsDirectional.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              SizedBox(
                width: 120,
                height: 120,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: searching ? AppColors.accent : AppColors.correct,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                searching ? l10n.searching : l10n.opponentFound,
                style: AppType.title(locale),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                searching ? l10n.searchingWide : '',
                style: AppType.label(locale),
                textAlign: TextAlign.center,
              ),
              if (opponentName != null) ...[
                const SizedBox(height: AppSpacing.xl),
                Container(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.bgRaised,
                    borderRadius: const BorderRadius.all(AppRadii.md),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(opponentName!, style: AppType.body(locale)),
                      const SizedBox(width: AppSpacing.sm),
                      // Showing the opponent's language is the product promise made visible.
                      Container(
                        padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.you.withValues(alpha: 0.15),
                          borderRadius: const BorderRadius.all(AppRadii.pill),
                        ),
                        child: Text(
                          opponentLocale == 'ar' ? 'ع' : 'EN',
                          style: AppType.label(locale).copyWith(color: AppColors.you),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const Spacer(),
              TextButton(
                onPressed: onCancel,
                child: Text(l10n.cancel, style: AppType.body(locale)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({
    required this.state,
    required this.locale,
    required this.l10n,
    required this.onRematch,
    required this.onHome,
  });

  final MatchUiState state;
  final Locale locale;
  final AppLocalizations l10n;
  final VoidCallback onRematch;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final title = switch (state.finalOutcome) {
      'win' => l10n.youWin,
      'loss' => l10n.youLose,
      _ => l10n.draw,
    };
    final accent = switch (state.finalOutcome) {
      'win' => AppColors.correct,
      'loss' => AppColors.wrong,
      _ => AppColors.textSecondary,
    };

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsetsDirectional.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(title, style: AppType.display(locale).copyWith(color: accent)),
              if (state.decidedBy == 'void') ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  l10n.matchVoided,
                  style: AppType.body(locale),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('${state.yourGoals}',
                      style: AppType.numeric(locale, size: 56)),
                  Padding(
                    padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: AppSpacing.lg),
                    child: Text('–', style: AppType.numeric(locale, size: 40)),
                  ),
                  Text('${state.opponentGoals}',
                      style: AppType.numeric(locale, size: 56)),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(l10n.fullTime, style: AppType.label(locale)),
              if (_decidedLabel(state.decidedBy, l10n) case final String decided) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(decided, style: AppType.label(locale)),
              ],
              if (state.accuracy case final double accuracy) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  // The number is isolated so it cannot reorder inside an Arabic line.
                  '${l10n.accuracy}: ${isoNum('${(accuracy * 100).round()}%')}',
                  style: AppType.label(locale),
                ),
              ],
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 60,
                child: FilledButton(
                  onPressed: onRematch,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.bgBase,
                  ),
                  child: Text(l10n.rematch, style: AppType.title(locale)),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextButton(
                onPressed: onHome,
                child: Text(l10n.homeAction, style: AppType.body(locale)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Why the match was decided, when the answer is one of the two cases worth naming.
String? _decidedLabel(String? decidedBy, AppLocalizations l10n) => switch (decidedBy) {
      'goals' => l10n.decidedByGoals,
      'zone' => l10n.decidedByZone,
      _ => null,
    };

class _FailedView extends StatelessWidget {
  const _FailedView({required this.locale, required this.l10n, required this.detail});

  final Locale locale;
  final AppLocalizations l10n;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Center(
        child: Padding(
          padding: const EdgeInsetsDirectional.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(l10n.offline, style: AppType.title(locale), textAlign: TextAlign.center),
              if (detail.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(detail, style: AppType.label(locale)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
