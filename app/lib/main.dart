import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/locale/locale_controller.dart';

/// Preferences are loaded *before* the first frame. An async first build would show one
/// frame in the device language and then snap to the saved one — exactly the flash that
/// "instant language toggle" is promising not to have.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const GridAndGloryApp(),
    ),
  );
}
