import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Injected at app start so [LocaleController.build] can read synchronously.
/// An async first frame would mean a visible flash of the wrong language — the exact
/// thing "instant language toggle" is promising not to do.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('override with the preloaded instance'),
);

final localeControllerProvider = NotifierProvider<LocaleController, Locale>(LocaleController.new);

class LocaleController extends Notifier<Locale> {
  static const String storageKey = 'app_locale';

  static const List<Locale> supported = [Locale('en'), Locale('ar')];

  @override
  Locale build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final stored = prefs.getString(storageKey);
    if (stored != null && supported.any((l) => l.languageCode == stored)) {
      return Locale(stored);
    }
    // First launch: follow the device, but only if we actually speak it.
    final device = WidgetsBinding.instance.platformDispatcher.locale;
    return device.languageCode == 'ar' ? const Locale('ar') : const Locale('en');
  }

  /// Persists locally and pushes to `player_settings` (fire-and-forget: the UI must not
  /// wait on the network to change language).
  void set(Locale locale) {
    if (state == locale) return;
    state = locale;
    ref.read(sharedPreferencesProvider).setString(storageKey, locale.languageCode);
  }

  void toggle() => set(state.languageCode == 'ar' ? const Locale('en') : const Locale('ar'));
}

/// Direction is derived, never stored. Storing it is how a screen ends up in the wrong
/// direction after a locale change.
TextDirection directionOf(Locale locale) =>
    locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr;

// NOTE: there is deliberately no `Directionality` wrapper here.
// `MaterialApp.locale` makes `WidgetsApp` derive `Directionality` from the resolved
// locale, and every directional widget below it flips automatically. Wrapping the tree
// in a second `Directionality` would give the app two sources of truth for direction —
// which is precisely how a screen ends up RTL after the user switches back to English.
