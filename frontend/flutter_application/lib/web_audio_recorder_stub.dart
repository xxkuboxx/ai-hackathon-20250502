import 'dart:typed_data';
import 'dart:async';

class WebAudioRecorder {
  Stream<List<double>> get audioDataStream => const Stream.empty();
  bool get isRecording => false;

  Future<bool> checkPermission() async {
    return false;
  }

  Future<bool> startRecording() async {
    return false;
  }

  Future<Uint8List?> stopRecording() async {
    return null;
  }

  void dispose() {
  }
}