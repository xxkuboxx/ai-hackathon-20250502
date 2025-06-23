// プラットフォーム非依存のインターフェース
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'web_audio_recorder_web.dart'
    if (dart.library.io) 'web_audio_recorder_stub.dart';

class WebAudioRecorder {
  late final WebAudioRecorderWeb _impl;
  
  WebAudioRecorder() {
    _impl = WebAudioRecorderWeb();
  }
  
  Stream<List<double>> get audioDataStream => _impl.audioDataStream;
  Stream<bool> get playbackStateStream => _impl.playbackStateStream;
  bool get isRecording => _impl.isRecording;
  bool get isPlaying => _impl.isPlaying;

  Future<bool> checkPermission() => _impl.checkPermission();
  Future<bool> startRecording() => _impl.startRecording();
  Future<Uint8List?> stopRecording() => _impl.stopRecording();
  Future<void> playAudio(Uint8List audioData) => _impl.playAudio(audioData);
  Future<void> stopAudio() => _impl.stopAudio();
  void dispose() => _impl.dispose();
}