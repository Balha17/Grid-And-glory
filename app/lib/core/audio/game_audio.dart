import 'dart:math' as math;
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';

/// Procedurally synthesised, original football sound effects. No downloads required.
class GameAudio {
  GameAudio._();
  static final Map<String, AudioPlayer> _players = <String, AudioPlayer>{};
  static bool enabled = true;
  static Future<void> play(String cue, {double volume = .78}) async {
    if (!enabled) return;
    final player = _players.putIfAbsent(cue, AudioPlayer.new);
    try {
      await player.stop();
      await player.play(BytesSource(_wave(cue), mimeType: 'audio/wav'), volume: volume);
    } catch (_) {}
  }
  static Uint8List _wave(String cue) {
    const rate = 22050;
    final duration = switch (cue) {
      'goal' => 1.35, 'whistle' => .62, 'correct' => .40, 'wrong' => .34,
      'tick' => .075, _ => .22,
    };
    final count = (rate * duration).round();
    final bytes = Uint8List(44 + count * 2);
    final data = ByteData.sublistView(bytes);
    void tag(int offset, String value) {
      for (var i = 0; i < value.length; i++) { bytes[offset + i] = value.codeUnitAt(i); }
    }
    tag(0, 'RIFF'); data.setUint32(4, 36 + count * 2, Endian.little);
    tag(8, 'WAVE'); tag(12, 'fmt '); data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little); data.setUint16(22, 1, Endian.little);
    data.setUint32(24, rate, Endian.little); data.setUint32(28, rate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little); data.setUint16(34, 16, Endian.little);
    tag(36, 'data'); data.setUint32(40, count * 2, Endian.little);
    var seed = 7654321;
    double noise() {
      seed = (seed * 1664525 + 1013904223) & 0x7fffffff;
      return seed / 0x7fffffff * 2 - 1;
    }
    for (var i = 0; i < count; i++) {
      final t = i / rate;
      var sample = 0.0;
      if (cue == 'whistle') {
        final env = math.min(1, t / .03) * math.max(0, math.min(1, (duration - t) / .1));
        sample = (env * (.48 * math.sin(2 * math.pi * 2350 * t) + .25 * math.sin(2 * math.pi * 2940 * t))).toDouble();
        sample *= .88 + .12 * math.sin(2 * math.pi * 8 * t);
      } else if (cue == 'kick') {
        sample = (math.exp(-t * 24) * (.72 * math.sin(2 * math.pi * (72 - 28 * t) * t) + .24 * noise())).toDouble();
      } else if (cue == 'goal') {
        final env = math.max(0, math.min(1, t / .12) * math.min(1, (duration - t) / .25)) *
            (.45 + .55 * math.sin(math.pi * math.min(1, t / duration)));
        sample = (env * (.34 * noise() + .22 * math.sin(2 * math.pi * 95 * t) +
            .12 * math.sin(2 * math.pi * 180 * t) + .1 * math.sin(2 * math.pi * 410 * t))).toDouble();
      } else if (cue == 'correct') {
        final freq = t < .13 ? 660 : t < .26 ? 830 : 1046;
        sample = (.32 * math.sin(2 * math.pi * freq * t) *
            math.min(1, (t % .13) / .015) * math.max(0, math.min(1, (duration - t) / .03))).toDouble();
      } else if (cue == 'wrong') {
        final freq = t < .17 ? 330 : 220;
        sample = (.28 * math.sin(2 * math.pi * freq * t) *
            math.min(1, (t % .17) / .02) * math.max(0, math.min(1, (duration - t) / .04))).toDouble();
      } else if (cue == 'tick') {
        sample = (.25 * math.sin(2 * math.pi * 1250 * t) * math.exp(-t * 65)).toDouble();
      }
      data.setInt16(44 + i * 2, (sample.clamp(-.92, .92) * 32767).round(), Endian.little);
    }
    return bytes;
  }
  static Future<void> dispose() async {
    final players = _players.values.toList(growable: false);
    _players.clear();
    for (final player in players) { await player.dispose(); }
  }
}