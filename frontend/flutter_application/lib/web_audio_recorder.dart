// Web Audio API用の簡易実装（package:webを使用せずにコンパイルエラーを回避）
import 'dart:async';
import 'package:flutter/foundation.dart';

class WebAudioRecorder {
  bool _isRecording = false;
  final StreamController<List<double>> _audioDataController = StreamController<List<double>>.broadcast();
  
  Stream<List<double>> get audioDataStream => _audioDataController.stream;
  bool get isRecording => _isRecording;

  Future<bool> checkPermission() async {
    try {
      // Web環境でのマイク権限チェック（簡易版）
      return true;
    } catch (e) {
      if (kDebugMode) print('Permission check failed: $e');
      return false;
    }
  }

  Future<bool> startRecording() async {
    try {
      if (_isRecording) {
        if (kDebugMode) print('Already recording');
        return false;
      }

      _isRecording = true;
      if (kDebugMode) print('Web recording started (mock implementation)');
      
      // モック用のオーディオデータを定期的に送信
      Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (!_isRecording) {
          timer.cancel();
          return;
        }
        
        // ダミーのオーディオレベルデータ
        List<double> mockAudioData = List.generate(32, (i) => 
          0.1 + (0.3 * (DateTime.now().millisecondsSinceEpoch % 1000) / 1000));
        _audioDataController.add(mockAudioData);
      });
      
      return true;
    } catch (e) {
      if (kDebugMode) print('Failed to start recording: $e');
      return false;
    }
  }

  Future<Uint8List?> stopRecording() async {
    try {
      if (!_isRecording) {
        if (kDebugMode) print('Not currently recording');
        return null;
      }

      _isRecording = false;
      if (kDebugMode) print('Web recording stopped');
      
      // モック用のオーディオファイルデータ（WAVファイル形式のヘッダを模擬）
      final mockAudioData = Uint8List.fromList([
        // WAVファイルヘッダ
        0x52, 0x49, 0x46, 0x46, // "RIFF"
        0x24, 0x00, 0x00, 0x00, // ChunkSize
        0x57, 0x41, 0x56, 0x45, // "WAVE"
        0x66, 0x6D, 0x74, 0x20, // "fmt "
        0x10, 0x00, 0x00, 0x00, // Subchunk1Size
        0x01, 0x00,             // AudioFormat (PCM)
        0x01, 0x00,             // NumChannels (Mono)
        0x44, 0xAC, 0x00, 0x00, // SampleRate (44100)
        0x88, 0x58, 0x01, 0x00, // ByteRate
        0x02, 0x00,             // BlockAlign
        0x10, 0x00,             // BitsPerSample (16)
        0x64, 0x61, 0x74, 0x61, // "data"
        0x00, 0x00, 0x00, 0x00, // Subchunk2Size
        // 短いオーディオデータサンプル
        ...List.generate(1000, (i) => (i % 256)),
      ]);
      
      return mockAudioData;
    } catch (e) {
      if (kDebugMode) print('Failed to stop recording: $e');
      _isRecording = false;
      return null;
    }
  }

  void dispose() {
    _isRecording = false;
    _audioDataController.close();
  }
}