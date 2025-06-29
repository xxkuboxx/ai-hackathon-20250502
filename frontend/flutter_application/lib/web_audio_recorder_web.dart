// Web専用の実装
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

class WebAudioRecorderWeb {
  bool _isRecording = false;
  bool _isPlaying = false;
  Timer? _playbackTimer;
  html.AudioElement? _audioElement; // 再生中のAudioElementを保持
  html.MediaRecorder? _mediaRecorder;
  html.MediaStream? _mediaStream;
  final List<html.Blob> _recordedChunks = [];
  final StreamController<List<double>> _audioDataController =
      StreamController<List<double>>.broadcast();
  final StreamController<bool> _playbackStateController =
      StreamController<bool>.broadcast();

  Stream<List<double>> get audioDataStream => _audioDataController.stream;
  Stream<bool> get playbackStateStream => _playbackStateController.stream;
  bool get isRecording => _isRecording;
  bool get isPlaying => _isPlaying;

  Future<bool> checkPermission() async {
    try {
      // 実際のマイク権限をリクエスト
      final stream = await html.window.navigator.mediaDevices?.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
      });

      if (stream != null) {
        // 権限確認後、ストリームを停止
        stream.getTracks().forEach((track) => track.stop());
        if (kDebugMode) {
          print('Microphone permission granted');
        }
        return true;
      } else {
        if (kDebugMode) {
          print('Failed to get media stream');
        }
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Permission check failed: $e');
      }
      return false;
    }
  }

  Future<bool> startRecording() async {
    try {
      if (_isRecording) {
        if (kDebugMode) {
          print('Already recording');
        }
        return false;
      }

      // 既存のリソースをクリーンアップ
      await forceStopRecording();

      // マイクから音声ストリームを取得
      try {
        _mediaStream = await html.window.navigator.mediaDevices?.getUserMedia({
          'audio': {
            'echoCancellation': true,
            'noiseSuppression': true,
            'autoGainControl': true,
            'sampleRate': 44100,
          },
        });
      } catch (e) {
        if (kDebugMode) {
          print('Failed to get user media: $e');
        }

        // より基本的な設定で再試行
        try {
          _mediaStream = await html.window.navigator.mediaDevices?.getUserMedia(
            {'audio': true},
          );
        } catch (e2) {
          if (kDebugMode) {
            print('Failed to get basic audio stream: $e2');
          }
          return false;
        }
      }

      if (_mediaStream == null) {
        if (kDebugMode) {
          print('Failed to get microphone stream');
        }
        return false;
      }

      // MediaRecorderを設定
      _recordedChunks.clear();

      // サポートされているMIMEタイプを確認（WebMを優先）
      String mimeType = 'audio/webm';
      final supportedTypes = [
        'audio/webm;codecs=opus', // WebM with Opus
        'audio/webm',             // WebM形式
        'audio/wav',              // WAV形式
        'audio/mp4',              // MP4/AAC形式
      ];

      for (final type in supportedTypes) {
        if (html.MediaRecorder.isTypeSupported(type)) {
          mimeType = type;
          break;
        }
      }

      try {
        _mediaRecorder = html.MediaRecorder(_mediaStream!, {
          'mimeType': mimeType,
        });
      } catch (e) {
        if (kDebugMode) {
          print('Failed to create MediaRecorder with $mimeType: $e');
        }
        // デフォルト設定で再試行
        try {
          _mediaRecorder = html.MediaRecorder(_mediaStream!);
          mimeType = 'default';
        } catch (e2) {
          if (kDebugMode) {
            print('Failed to create MediaRecorder with default settings: $e2');
          }
          _mediaStream?.getTracks().forEach((track) => track.stop());
          _mediaStream = null;
          return false;
        }
      }

      // データが利用可能になったときのイベント
      _mediaRecorder!.addEventListener('dataavailable', (event) {
        try {
          final blobEvent = event as html.BlobEvent;
          if (blobEvent.data != null && blobEvent.data!.size > 0) {
            _recordedChunks.add(blobEvent.data!);
            if (kDebugMode) {
              print('Recorded chunk: ${blobEvent.data!.size} bytes');
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error handling dataavailable: $e');
          }
        }
      });

      // 録音停止時のイベント
      _mediaRecorder!.addEventListener('stop', (event) {
        if (kDebugMode) {
          print('MediaRecorder stopped, chunks: ${_recordedChunks.length}');
        }
      });

      // エラーハンドリング
      _mediaRecorder!.addEventListener('error', (event) {
        if (kDebugMode) {
          print('MediaRecorder error: $event');
        }
        _isRecording = false;
      });

      // 音声レベル解析の設定
      _setupAudioAnalysis();

      // 録音開始
      try {
        _mediaRecorder!.start(100); // 100msごとにデータを送信
        _isRecording = true;

        if (kDebugMode) {
          print('Real microphone recording started with $mimeType');
        }
        return true;
      } catch (e) {
        if (kDebugMode) {
          print('Failed to start MediaRecorder: $e');
        }
        _mediaStream?.getTracks().forEach((track) => track.stop());
        _mediaStream = null;
        _mediaRecorder = null;
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to start recording: $e');
      }
      _isRecording = false;
      await forceStopRecording();
      return false;
    }
  }

  void _setupAudioAnalysis() {
    try {
      // Web Audio APIによる音声レベル解析は一時的に無効化
      // 代わりにダミーデータを定期的に送信
      Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (!_isRecording) {
          timer.cancel();
          return;
        }

        // ダミーの音声レベルデータを生成
        final audioData = <double>[];
        for (int i = 0; i < 128; i++) {
          audioData.add(math.Random().nextDouble() * 0.5);
        }

        _audioDataController.add(audioData);
      });
    } catch (e) {
      if (kDebugMode) {
        print('Failed to setup audio analysis: $e');
      }
    }
  }

  Future<Uint8List?> stopRecording() async {
    try {
      if (!_isRecording) {
        if (kDebugMode) {
          print('Not currently recording');
        }
        return null;
      }

      _isRecording = false;

      // MediaRecorderを停止
      if (_mediaRecorder != null) {
        _mediaRecorder!.stop();

        // 録音データの完成を待つ
        await Future.delayed(const Duration(milliseconds: 100));

        if (_recordedChunks.isNotEmpty) {
          // 録音されたBlobデータを結合
          final blob = html.Blob(_recordedChunks);
          final bytes = await _blobToUint8List(blob);

          if (kDebugMode) {
            print('Web recording stopped - actual data: ${bytes.length} bytes');
          }

          // メディアストリームを停止
          _mediaStream?.getTracks().forEach((track) => track.stop());
          _mediaStream = null;
          _mediaRecorder = null;

          // 録音データをそのまま返す（形式変換を無効化してノイズを防ぐ）
          if (kDebugMode) {
            print('Returning original recorded audio data');
          }
          return bytes;
        } else {
          if (kDebugMode) {
            print('No recorded chunks available');
          }
        }
      }

      // フォールバック：録音データが取得できない場合はテスト音を生成
      if (kDebugMode) {
        print('Fallback: generating test audio data');
      }
      return _generateTestAudioData();
    } catch (e) {
      if (kDebugMode) {
        print('Failed to stop recording: $e');
      }
      _isRecording = false;

      // メディアストリームを停止
      _mediaStream?.getTracks().forEach((track) => track.stop());
      _mediaStream = null;
      _mediaRecorder = null;

      return null;
    }
  }

  Future<Uint8List> _blobToUint8List(html.Blob blob) async {
    final reader = html.FileReader();
    final completer = Completer<Uint8List>();

    reader.onLoadEnd.listen((event) {
      final result = reader.result as List<int>;
      completer.complete(Uint8List.fromList(result));
    });

    reader.onError.listen((event) {
      completer.completeError('Failed to read blob');
    });

    reader.readAsArrayBuffer(blob);
    return completer.future;
  }

  Uint8List _generateTestAudioData() {
    // 実際に再生可能なWAVファイルを生成（440Hzのトーン、1秒間）
    final sampleRate = 44100;
    final duration = 1; // 1秒
    final numSamples = sampleRate * duration;
    final frequency = 440.0; // ラの音

    // 音声データを生成
    final audioSamples = <int>[];
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final sample = (32767 * 0.3 * math.sin(2 * math.pi * frequency * t))
          .round();
      // 16-bit リトルエンディアン
      audioSamples.add(sample & 0xFF);
      audioSamples.add((sample >> 8) & 0xFF);
    }

    final dataSize = audioSamples.length;
    final fileSize = 44 + dataSize - 8;

    return Uint8List.fromList([
      // WAVファイルヘッダ
      0x52, 0x49, 0x46, 0x46, // "RIFF"
      fileSize & 0xFF,
      (fileSize >> 8) & 0xFF,
      (fileSize >> 16) & 0xFF,
      (fileSize >> 24) & 0xFF,
      0x57, 0x41, 0x56, 0x45, // "WAVE"
      0x66, 0x6D, 0x74, 0x20, // "fmt "
      0x10, 0x00, 0x00, 0x00, // Subchunk1Size (16)
      0x01, 0x00, // AudioFormat (PCM)
      0x01, 0x00, // NumChannels (Mono)
      0x44, 0xAC, 0x00, 0x00, // SampleRate (44100)
      0x88, 0x58, 0x01, 0x00, // ByteRate (44100 * 1 * 16/8)
      0x02, 0x00, // BlockAlign (1 * 16/8)
      0x10, 0x00, // BitsPerSample (16)
      0x64, 0x61, 0x74, 0x61, // "data"
      dataSize & 0xFF,
      (dataSize >> 8) & 0xFF,
      (dataSize >> 16) & 0xFF,
      (dataSize >> 24) & 0xFF,
      // 実際の音声データ
      ...audioSamples,
    ]);
  }

  Future<void> playAudio(Uint8List audioData) async {
    if (_isPlaying) {
      if (kDebugMode) {
        print('Already playing audio');
      }
      return;
    }

    try {
      _isPlaying = true;
      _playbackStateController.add(true);
      if (kDebugMode) {
        print(
          'Web audio playback started - playing recorded data (${audioData.length} bytes)',
        );
      }

      // 録音したオーディオデータを再生
      await _playRecordedAudio(audioData);
    } catch (e) {
      if (kDebugMode) {
        print('Failed to play audio: $e');
      }
      _isPlaying = false;
      _playbackStateController.add(false);
    }
  }

  Future<void> _playRecordedAudio(Uint8List audioData) async {
    try {
      // 適切なMIMEタイプを判定
      String mimeType = 'audio/wav';
      if (audioData.length > 4) {
        // WebM形式の場合
        if (audioData[0] == 0x1A &&
            audioData[1] == 0x45 &&
            audioData[2] == 0xDF &&
            audioData[3] == 0xA3) {
          mimeType = 'audio/webm';
        }
        // MP4形式の場合
        else if (audioData.length > 8 &&
            audioData[4] == 0x66 &&
            audioData[5] == 0x74 &&
            audioData[6] == 0x79 &&
            audioData[7] == 0x70) {
          mimeType = 'audio/mp4';
        }
        // RIFF WAVヘッダーの場合
        else if (audioData[0] == 0x52 &&
            audioData[1] == 0x49 &&
            audioData[2] == 0x46 &&
            audioData[3] == 0x46) {
          mimeType = 'audio/wav';
        }
      }

      // Uint8ListをBlobに変換してオーディオ再生
      final blob = html.Blob([audioData], mimeType);
      final url = html.Url.createObjectUrlFromBlob(blob);

      _audioElement = html.AudioElement(url);
      _audioElement!.volume = 0.7; // 70%の音量

      // 再生完了を監視
      _audioElement!.onEnded.listen((_) {
        if (_audioElement != null) {
          html.Url.revokeObjectUrl(_audioElement!.src); // メモリリークを防ぐ
        }
        _isPlaying = false;
        _playbackStateController.add(false);
        _audioElement = null;
        if (kDebugMode) {
          print('Web audio playback completed (recorded audio)');
        }
      });

      // エラーハンドリング
      _audioElement!.onError.listen((error) {
        if (kDebugMode) {
          print('Audio playback error: $error');
        }
        if (_audioElement != null) {
          html.Url.revokeObjectUrl(_audioElement!.src);
        }
        _isPlaying = false;
        _playbackStateController.add(false);
        _audioElement = null;
        // フォールバック：テストビープ音
        _playTestBeep();
      });

      // 再生開始
      await _audioElement!.play();
      if (kDebugMode) {
        print('Started playing recorded audio data ($mimeType)');
      }

      // フォールバックタイマー（30秒後に強制停止）
      _playbackTimer = Timer(const Duration(seconds: 30), () {
        if (_isPlaying && _audioElement != null) {
          _audioElement!.pause();
          html.Url.revokeObjectUrl(_audioElement!.src);
          _audioElement = null;
          _isPlaying = false;
          _playbackStateController.add(false);
          if (kDebugMode) {
            print('Audio playback timeout (30s)');
          }
        }
      });
    } catch (e) {
      if (kDebugMode) {
        print('Failed to play recorded audio: $e');
      }
      // フォールバック：テストビープ音
      await _playTestBeep();
    }
  }

  Future<void> _playTestBeep() async {
    try {
      // HTMLオーディオ要素を直接使用（より安全）
      await _playWithHtmlAudio();
    } catch (e) {
      if (kDebugMode) {
        print('Failed to play test beep: $e');
      }
      // 最終フォールバック：モック再生
      _playbackTimer = Timer(const Duration(seconds: 1), () {
        _isPlaying = false;
        _playbackStateController.add(false);
        if (kDebugMode) {
          print('Web audio playback completed (fallback)');
        }
      });
    }
  }

  Future<void> _playWithHtmlAudio() async {
    try {
      // 短いビープ音のデータURL（base64エンコードされたWAVファイル）
      const beepDataUrl =
          'data:audio/wav;base64,UklGRnoGAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQoGAACBhYqFbF1fdJivrJBhNjVgodDbq2EcBj+a2/LDciUFLIHO8tiJNwgZaLvt559NEAxQp+PwtmMcBjiR1/LMeSwFJHfH8N2QQAoUXrTp66hVFApGn+DyvmocCDuO2vPNdCMGJnfH8N+OPAsPYrbp6ahVFApEm+TuvmsBBziV0vLKeSYFJn3L8NqPQAoQZLfq6qdVFApFm+PvvmsBBziU0fLLeSYGI3PN9tuLOwsOZLfn7K5aFQtCn+TtvVwBBzhX2vTMfCMGI3vM8NuLPAsQYLP2dA==';

      final audioElement = html.AudioElement(beepDataUrl);
      audioElement.volume = 0.1;

      // 再生完了を監視
      audioElement.onEnded.listen((_) {
        _isPlaying = false;
        _playbackStateController.add(false);
        if (kDebugMode) {
          print('Web audio playback completed (HTML audio)');
        }
      });

      // 再生開始
      await audioElement.play();

      // フォールバックタイマー（3秒後に強制停止）
      _playbackTimer = Timer(const Duration(seconds: 3), () {
        if (_isPlaying) {
          audioElement.pause();
          _isPlaying = false;
          _playbackStateController.add(false);
          if (kDebugMode) {
            print('Web audio playback timeout');
          }
        }
      });
    } catch (e) {
      if (kDebugMode) {
        print('Failed to play with HTML audio: $e');
      }
      // 最終フォールバック：モック再生
      _playbackTimer = Timer(const Duration(seconds: 1), () {
        _isPlaying = false;
        _playbackStateController.add(false);
        if (kDebugMode) {
          print('Web audio playback completed (fallback)');
        }
      });
    }
  }

  Future<void> playAudioFromUrl(String url) async {
    if (_isPlaying) {
      if (kDebugMode) {
        print('Already playing audio');
      }
      return;
    }

    try {
      _isPlaying = true;
      _playbackStateController.add(true);
      if (kDebugMode) {
        print('Web audio playback started - playing from URL: $url');
      }

      // まずダイレクト再生を試行
      await _tryDirectPlayback(url);
    } catch (e) {
      if (kDebugMode) {
        print('Direct playback failed: $e');
        print('Trying fetch + blob approach...');
      }
      
      // ダイレクト再生に失敗した場合、fetch + blob を試行
      try {
        await _tryFetchAndPlay(url);
      } catch (e2) {
        if (kDebugMode) {
          print('Fetch and play also failed: $e2');
          print('Falling back to URL download prompt...');
        }
        
        // 両方失敗した場合は、URLを表示してユーザーに直接アクセスしてもらう
        _isPlaying = false;
        _playbackStateController.add(false);
        _audioElement = null;
        
        // URLをコンソールに表示（開発者向け）
        if (kDebugMode) {
          print('Audio playback failed completely. URL: $url');
        }
        
        // ブラウザで新しいタブでURLを開く（ユーザー操作後）
        _showUrlFallback(url);
      }
    }
  }

  Future<void> _tryDirectPlayback(String url) async {
    _audioElement = html.AudioElement(url);
    _audioElement!.volume = 0.7;
    _audioElement!.preload = 'auto';
    
    // CORS設定を試行
    try {
      _audioElement!.crossOrigin = 'anonymous';
    } catch (e) {
      if (kDebugMode) {
        print('CrossOrigin setting failed, trying without: $e');
      }
    }

    // エラーハンドリング
    final errorCompleter = Completer<void>();
    _audioElement!.onError.listen((error) {
      if (kDebugMode) {
        print('Direct audio playback error: $error');
      }
      if (!errorCompleter.isCompleted) {
        errorCompleter.completeError('Audio load failed');
      }
    });

    // 読み込み完了
    _audioElement!.onCanPlay.listen((_) {
      if (!errorCompleter.isCompleted) {
        errorCompleter.complete();
      }
    });

    // 再生完了を監視
    _audioElement!.onEnded.listen((_) {
      _isPlaying = false;
      _playbackStateController.add(false);
      _audioElement = null;
      if (kDebugMode) {
        print('Web audio playback completed (direct URL)');
      }
    });

    // タイムアウト設定
    final timeoutCompleter = Completer<void>();
    Timer(const Duration(seconds: 10), () {
      if (!timeoutCompleter.isCompleted) {
        timeoutCompleter.completeError('Load timeout');
      }
    });

    // 読み込み待ち（エラーまたは完了まで）
    await Future.any([errorCompleter.future, timeoutCompleter.future]);

    // 再生開始
    await _audioElement!.play();
    if (kDebugMode) {
      print('Started playing from URL (direct): $url');
    }

    // フォールバックタイマー（300秒後に強制停止）
    _playbackTimer = Timer(const Duration(seconds: 300), () {
      if (_isPlaying && _audioElement != null) {
        _audioElement!.pause();
        _audioElement = null;
        _isPlaying = false;
        _playbackStateController.add(false);
        if (kDebugMode) {
          print('Audio playback timeout (300s)');
        }
      }
    });
  }

  Future<void> _tryFetchAndPlay(String url) async {
    // fetchでデータを取得してblobとして再生
    final response = await html.window.fetch(url, {
      'mode': 'cors',
      'credentials': 'omit',
    });

    if (response.status != 200) {
      throw Exception('Fetch failed with status: ${response.status}');
    }

    final blob = await response.blob();
    final blobUrl = html.Url.createObjectUrlFromBlob(blob);

    _audioElement = html.AudioElement(blobUrl);
    _audioElement!.volume = 0.7;

    // 再生完了を監視
    _audioElement!.onEnded.listen((_) {
      html.Url.revokeObjectUrl(blobUrl); // メモリリークを防ぐ
      _isPlaying = false;
      _playbackStateController.add(false);
      _audioElement = null;
      if (kDebugMode) {
        print('Web audio playback completed (fetch + blob)');
      }
    });

    // エラーハンドリング
    _audioElement!.onError.listen((error) {
      if (kDebugMode) {
        print('Blob audio playback error: $error');
      }
      html.Url.revokeObjectUrl(blobUrl);
      _isPlaying = false;
      _playbackStateController.add(false);
      _audioElement = null;
    });

    // 再生開始
    await _audioElement!.play();
    if (kDebugMode) {
      print('Started playing from URL (fetch + blob): $url');
    }

    // フォールバックタイマー（300秒後に強制停止）
    _playbackTimer = Timer(const Duration(seconds: 300), () {
      if (_isPlaying && _audioElement != null) {
        _audioElement!.pause();
        html.Url.revokeObjectUrl(blobUrl);
        _audioElement = null;
        _isPlaying = false;
        _playbackStateController.add(false);
        if (kDebugMode) {
          print('Audio playback timeout (300s)');
        }
      }
    });
  }

  void _showUrlFallback(String url) {
    // ユーザーがクリックで新しいタブでURLを開けるよう、ボタンなどのUIを提供する必要がある
    // ここでは開発者コンソールにURLを表示
    if (kDebugMode) {
      print('=== AUDIO PLAYBACK FALLBACK ===');
      print('Please manually open this URL in a new tab to play the audio:');
      print(url);
      print('===============================');
    }
  }

  Future<void> stopAudio() async {
    if (!_isPlaying) {
      if (kDebugMode) {
        print('No audio currently playing');
      }
      return;
    }

    try {
      _playbackTimer?.cancel();
      _playbackTimer = null;

      if (_audioElement != null) {
        _audioElement!.pause();
        // blob URLの場合のみリボーク
        if (_audioElement!.src.startsWith('blob:')) {
          html.Url.revokeObjectUrl(_audioElement!.src);
        }
        _audioElement = null;
      }

      _isPlaying = false;
      _playbackStateController.add(false);
      if (kDebugMode) {
        print('Web audio playback stopped');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to stop audio: $e');
      }
    }
  }

  Future<void> forceStopRecording() async {
    try {
      _isRecording = false;

      // MediaRecorderを強制停止
      if (_mediaRecorder != null) {
        try {
          _mediaRecorder!.stop();
        } catch (e) {
          if (kDebugMode) {
            print('MediaRecorder stop error (ignoring): $e');
          }
        }
        _mediaRecorder = null;
      }

      // メディアストリームを停止
      if (_mediaStream != null) {
        try {
          _mediaStream!.getTracks().forEach((track) => track.stop());
        } catch (e) {
          if (kDebugMode) {
            print('MediaStream stop error (ignoring): $e');
          }
        }
        _mediaStream = null;
      }

      // 録音チャンクをクリア
      _recordedChunks.clear();

      if (kDebugMode) {
        print('Recording force stopped and cleaned up');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to force stop recording: $e');
      }
    }
  }

  void dispose() {
    // 録音を強制停止
    forceStopRecording();

    // 再生中の音声を停止
    stopAudio();

    // タイマーを停止
    _playbackTimer?.cancel();
    _playbackTimer = null;

    // ストリームコントローラーを閉じる
    if (!_audioDataController.isClosed) {
      _audioDataController.close();
    }
    if (!_playbackStateController.isClosed) {
      _playbackStateController.close();
    }

    if (kDebugMode) {
      print('WebAudioRecorder disposed');
    }
  }
}
