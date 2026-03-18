import 'package:flutter_tts/flutter_tts.dart';

/// Simple service that plays gate audio cues using TTS.
///
/// This is used to speak "Riders Ready", "Watch the Gate" and other cues.
class AudioService {
  final FlutterTts _tts = FlutterTts();

  AudioService() {
    _tts.setStartHandler(() {});
    _tts.setCompletionHandler(() {});
    _tts.setErrorHandler((msg) {});
  }

  /// Speak a short cue phrase.
  Future<void> speak(String message) async {
    await _tts.setSpeechRate(0.55);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    await _tts.speak(message);
  }

  Future<void> stop() async {
    await _tts.stop();
  }
}
