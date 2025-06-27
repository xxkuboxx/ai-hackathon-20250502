import 'dart:async';
import 'package:flutter/foundation.dart';

class WebAudioRecorderWeb {
  Stream<List<double>> get audioDataStream => const Stream.empty();
  Stream<bool> get playbackStateStream => const Stream.empty();
  bool get isRecording => false;
  bool get isPlaying => false;

  Future<bool> checkPermission() async {
    return false;
  }

  Future<bool> startRecording() async {
    return false;
  }

  Future<Uint8List?> stopRecording() async {
    return null;
  }

  Future<void> playAudio(Uint8List audioData) async {
    // スタブ実装
  }

  Future<void> playAudioFromUrl(String url) async {
    // スタブ実装
  }

  Future<void> stopAudio() async {
    // スタブ実装
  }

  void dispose() {}
}

// モバイル環境用のスタブクラス
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
  Future<void> playAudioFromUrl(String url) => _impl.playAudioFromUrl(url);
  Future<void> stopAudio() => _impl.stopAudio();
  void dispose() => _impl.dispose();
}
