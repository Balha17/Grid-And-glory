/// Bidi helpers.
///
/// Every place the app inserts a dynamic value into a translated sentence is a place
/// where text can silently reorder. In Arabic, "2 – 1" can render as "1 – 2" and a
/// percentage can lose its side. The fix is the Unicode isolate pair LRI (U+2066) …
/// PDI (U+2069), which walls off the embedded run from the surrounding paragraph.
///
/// These are three characters that prevent a whole class of bug reports like
/// "the score shows the wrong player first".
library;

const String kLri = '\u2066'; // LEFT-TO-RIGHT ISOLATE
const String kRli = '\u2067'; // RIGHT-TO-LEFT ISOLATE
const String kPdi = '\u2069'; // POP DIRECTIONAL ISOLATE
const String kLrm = '\u200E'; // LEFT-TO-RIGHT MARK (zero width)

/// Wraps a value in an LTR isolate so it cannot reorder inside Arabic text.
///
/// ```dart
/// Text('${l10n.finalScore}: ${isolate('$you – $opponent')}')
/// ```
String isolate(Object? value) => '$kLri${value ?? ''}$kPdi';

/// Isolates a number run. Use for scores, percentages, minutes and ratings.
String isoNum(Object? value) => '$kLri${value ?? ''}$kPdi';

/// Arabic-Indic digits, for the optional numeral style setting.
///
/// Deliberately NOT applied to the match clock or scoreline — see docs/04-ui-ux-spec.md §5.4.
/// Two numeral systems on one screen is worse than either one alone.
const List<String> _arabicIndic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];

String toArabicIndic(String western) {
  final buffer = StringBuffer();
  for (final rune in western.runes) {
    final char = String.fromCharCode(rune);
    final digit = int.tryParse(char);
    buffer.write(digit == null ? char : _arabicIndic[digit]);
  }
  return buffer.toString();
}

/// True when the string needs an isolate before being dropped into a translated
/// sentence: mixed scripts, leading digits, or anything with a dash/range in it.
bool needsIsolation(String value) =>
    RegExp(r'[0-9]').hasMatch(value) || RegExp(r'[\u0600-\u06FF]').hasMatch(value);
