import 'package:flutter/material.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http_parser;
import 'dart:convert';
import 'dart:async';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/foundation.dart';
import 'dart:math' as math;
import 'package:google_fonts/google_fonts.dart';
import 'file_operations_io.dart'
    if (dart.library.html) 'file_operations_web.dart';
import 'web_audio_recorder.dart'
    if (dart.library.io) 'web_audio_recorder_stub.dart';

// 録音状態を管理するenum
enum RecordingState {
  idle, // 待機中
  recording, // 録音中
  uploading, // アップロード中
}

// API応答データモデル
class AudioAnalysisResult {
  final String key;
  final int bpm;
  final String chords;
  final String genre;
  final String? backingTrackUrl;

  AudioAnalysisResult({
    required this.key,
    required this.bpm,
    required this.chords,
    required this.genre,
    this.backingTrackUrl,
  });

  factory AudioAnalysisResult.fromJson(Map<String, dynamic> json) {
    return AudioAnalysisResult(
      key: json['key'] ?? 'Unknown',
      bpm: json['bpm'] ?? 120,
      chords: json['chords'] ?? 'Unknown',
      genre: json['genre'] ?? 'Unknown',
      backingTrackUrl: json['generated_mp3_url'],
    );
  }
}

// チャットメッセージモデル
class ChatMessageModel {
  final String role;
  final String content;

  ChatMessageModel({required this.role, required this.content});

  Map<String, dynamic> toJson() {
    return {'role': role, 'content': content};
  }

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    return ChatMessageModel(
      role: json['role'] ?? 'assistant',
      content: json['content'] ?? '',
    );
  }
}

// APIサービスクラス
class AudioProcessingService {
  static const String baseUrl =
      'https://sessionmuse-backend-469350304561.us-east5.run.app';

  static Future<AudioAnalysisResult?> uploadAndProcess(
    String filePath, {
    Uint8List? webAudioData,
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/process'),
      );
      
      // タイムアウト設定を追加（音声解析処理のため長めに設定）
      request.headers['Connection'] = 'keep-alive';

      // ファイルを添付
      http.MultipartFile file;
      if (webAudioData != null) {
        // Web環境：バイトデータから直接作成
        file = await createMultipartFileFromBytes(
          'file',
          filePath.split('/').last,
          webAudioData,
        );
      } else {
        // モバイル環境：ファイルパスから作成（WAV形式固定）
        file = await http.MultipartFile.fromPath(
          'file',
          filePath,
          contentType: http_parser.MediaType.parse('audio/wav'),
        );
      }
      request.files.add(file);

      // リクエスト送信（タイムアウト設定: 3分）
      var response = await request.send().timeout(
        const Duration(minutes: 3),
        onTimeout: () {
          if (kDebugMode) print('API request timeout after 3 minutes');
          throw TimeoutException('API request timeout', const Duration(minutes: 3));
        },
      );

      if (response.statusCode == 200) {
        var responseBody = await response.stream.bytesToString();
        if (kDebugMode) print('API Response Body: $responseBody');
        var jsonData = json.decode(responseBody);

        return AudioAnalysisResult.fromJson(jsonData);
      } else {
        var responseBody = await response.stream.bytesToString();
        if (kDebugMode) {
          print('API Error: ${response.statusCode}');
          print('Error Response Body: $responseBody');
        }
        return null;
      }
    } catch (e) {
      if (kDebugMode) print('Upload Error: $e');
      return null;
    }
  }

  // AIチャット機能
  static Future<String?> sendChatMessage(
    List<ChatMessageModel> messages,
    AudioAnalysisResult? analysisContext,
  ) async {
    try {
      Map<String, dynamic> requestBody = {
        'messages': messages.map((msg) => msg.toJson()).toList(),
      };

      // 音楽解析結果があれば追加
      if (analysisContext != null) {
        requestBody['analysis_context'] = {
          'key': analysisContext.key,
          'bpm': analysisContext.bpm,
          'chords': analysisContext.chords,
          'genre': analysisContext.genre,
        };
      }

      if (kDebugMode) {
        print('Sending chat request to: $baseUrl/api/chat');
        print('Request body: ${json.encode(requestBody)}');
      }

      final response = await http.post(
        Uri.parse('$baseUrl/api/chat'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode(requestBody),
      ).timeout(
        const Duration(minutes: 2),
        onTimeout: () {
          if (kDebugMode) print('Chat API request timeout after 2 minutes');
          throw TimeoutException('Chat API request timeout', const Duration(minutes: 2));
        },
      );

      if (kDebugMode) {
        print('Response status: ${response.statusCode}');
        print('Response headers: ${response.headers}');
        print('Response body: ${response.body}');
      }

      if (response.statusCode == 200) {
        var jsonData = json.decode(response.body);
        return jsonData['content'];
      } else {
        if (kDebugMode) {
          print('Chat API Error: ${response.statusCode}');
          print('Response body: ${response.body}');
        }
        return null;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Chat Error: $e');
        print('Error type: ${e.runtimeType}');
      }
      return null;
    }
  }
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SessionMUSE - Your AI Music Partner',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        textTheme: GoogleFonts.notoSansJpTextTheme(),
      ),
      home: const MyHomePage(title: 'SessionMUSE - Your AI Music Partner'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with TickerProviderStateMixin {
  String? _audioFilePath;
  late final RecorderController? _recorderController;
  late final PlayerController? playerController;
  late final WebAudioRecorder? _webAudioRecorder;

  // プラットフォーム検出
  bool get isWeb => kIsWeb;
  bool get isRecordingSupported => true; // Web版でも録音機能をサポート
  final TextEditingController _messageController = TextEditingController();
  final List<ChatMessage> _messages = [];
  final List<ChatMessageModel> _chatHistory = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLoadingResponse = false;
  
  // Animation controllers
  late AnimationController _loadingAnimationController;
  late AnimationController _chatLoadingAnimationController;
  late AnimationController _progressAnimationController;


  // 状態管理
  bool _isAnalyzed = false;
  bool _isPlaying = false;

  // チャット画面の状態管理
  bool _isChatOpen = false;

  // 録音状態管理
  RecordingState _recordingState = RecordingState.idle;

  // API分析結果
  AudioAnalysisResult? _analysisResult;

  // プレイヤー状態リスナー管理
  bool _playerListenerAdded = false;

  // 解析キャンセル用
  bool _shouldCancelAnalysis = false;

  // バッキングトラック再生用
  late final PlayerController? backingTrackController;
  bool _isBackingTrackPlaying = false;
  bool _backingTrackListenerAdded = false;

  @override
  void initState() {
    super.initState();

    // Animation controllers initialization
    _loadingAnimationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
    
    _chatLoadingAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _progressAnimationController = AnimationController(
      duration: const Duration(minutes: 1), // 1分で100%に達する
      vsync: this,
    );

    // プラットフォームに応じた初期化
    if (isWeb) {
      // Web環境
      _recorderController = null;
      playerController = null;
      backingTrackController = null;
      _webAudioRecorder = WebAudioRecorder();
      // Web録音権限を取得
      _webAudioRecorder!.checkPermission();
    } else {
      // モバイル環境
      _recorderController = RecorderController();
      playerController = PlayerController();
      backingTrackController = PlayerController();
      _webAudioRecorder = null;
      // アプリ起動時に録音権限を取得
      _recorderController!.checkPermission();
    }

    // 初期メッセージを追加
    final initialMessage =
        "こんにちは！音楽について何でも聞いてください。音声を録音して解析すると、より詳しいアドバイスができます。";

    _messages.add(ChatMessage(text: initialMessage, isUser: false));

    // チャット履歴にも初期メッセージを追加
    _chatHistory.add(
      ChatMessageModel(role: 'assistant', content: initialMessage),
    );

    // 初期状態で解析結果を表示
    _isAnalyzed = true;
  }

  @override
  void dispose() {
    _loadingAnimationController.dispose();
    _chatLoadingAnimationController.dispose();
    _progressAnimationController.dispose();
    _recorderController?.dispose();
    playerController?.dispose();
    backingTrackController?.dispose();
    _webAudioRecorder?.dispose();
    super.dispose();
  }

  void _sendMessage() async {
    if (_messageController.text.trim().isEmpty || _isLoadingResponse) {
      return;
    }

    final userMessage = _messageController.text.trim();
    _messageController.clear();

    setState(() {
      _messages.add(ChatMessage(text: userMessage, isUser: true));
      _isLoadingResponse = true;
    });

    // チャット履歴に追加
    _chatHistory.add(ChatMessageModel(role: 'user', content: userMessage));

    // スクロールを最下部に移動
    _scrollToBottom();

    try {
      // AI APIを呼び出し
      final aiResponse = await AudioProcessingService.sendChatMessage(
        _chatHistory,
        _analysisResult,
      );

      if (aiResponse != null && aiResponse.isNotEmpty) {
        setState(() {
          _messages.add(ChatMessage(text: aiResponse, isUser: false));
          _isLoadingResponse = false;
        });

        // チャット履歴に追加
        _chatHistory.add(
          ChatMessageModel(role: 'assistant', content: aiResponse),
        );
      } else {
        setState(() {
          _messages.add(
            ChatMessage(
              text: "申し訳ありません。AIサービスからの応答が空でした。もう一度お試しください。",
              isUser: false,
            ),
          );
          _isLoadingResponse = false;
        });
      }
    } catch (e) {
      String errorMessage;
      if (e.toString().contains('CORS') ||
          e.toString().contains('XMLHttpRequest')) {
        errorMessage =
            "CORS/ネットワークエラー: ブラウザのセキュリティ制限によりAPIに接続できません。サーバー側でCORS設定が必要です。";
      } else if (e.toString().contains('SocketException')) {
        errorMessage = "ネットワークエラー: APIサーバーに接続できません。インターネット接続を確認してください。";
      } else if (e.toString().contains('TimeoutException')) {
        errorMessage = "処理時間が長くなっています。サーバーで音声解析処理中の可能性があります。しばらくお待ちください。";
      } else {
        errorMessage = "予期しないエラーが発生しました: ${e.toString()}";
      }

      setState(() {
        _messages.add(ChatMessage(text: errorMessage, isUser: false));
        _isLoadingResponse = false;
      });
    }

    // スクロールを最下部に移動
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleRecordingButtonPress() async {
    if (_recordingState == RecordingState.uploading) {
      // 解析中の場合はキャンセルして新しい録音を開始
      setState(() {
        _shouldCancelAnalysis = true;
        _recordingState = RecordingState.recording;
        _isAnalyzed = true;
      });
      if (kDebugMode) print('解析をキャンセルして新しい録音を開始します');
      
      // 新しい録音を開始
      final recordingPath = await _setupRecording();
      if (recordingPath != null) {
        setState(() {
          _audioFilePath = recordingPath;
        });
      } else {
        // 録音開始に失敗した場合は待機状態に戻す
        setState(() {
          _recordingState = RecordingState.idle;
        });
      }
      return;
    }
    
    if (_recordingState == RecordingState.idle) {
      setState(() {
        _recordingState = RecordingState.recording;
        _isAnalyzed = true;
      });
      final recordingPath = await _setupRecording();
      if (recordingPath != null) {
        setState(() {
          _audioFilePath = recordingPath;
        });
      }
    } else {
      setState(() {
        _recordingState = RecordingState.uploading;
      });
      // プログレスアニメーションを開始
      _progressAnimationController.reset();
      _progressAnimationController.forward();
      if (kDebugMode) print('録音停止中...');

      if (isWeb) {
        // Web環境での録音停止
        final recordedData = await _webAudioRecorder!.stopRecording();
        if (recordedData != null && _audioFilePath != null) {
          // Web環境でのデータ保存
          saveWebAudioFile(_audioFilePath!, recordedData);
          if (kDebugMode) {
            print('Web録音完了: $_audioFilePath (${recordedData.length} bytes)');
          }
          await _uploadAndAnalyze();
        } else {
          if (kDebugMode) print('Web録音データが取得できませんでした');
          setState(() {
            _recordingState = RecordingState.idle;
          });
        }
      } else {
        // モバイル環境での録音停止
        final recordedFilePath = await _recorderController!.stop();
        if (kDebugMode) print('録音停止結果: $recordedFilePath');

        if (recordedFilePath != null) {
          setState(() {
            _audioFilePath = recordedFilePath;
          });
          if (kDebugMode) print('録音完了: $recordedFilePath');

          if (await fileExists(recordedFilePath)) {
            final fileSize = await getFileSize(recordedFilePath);
            if (kDebugMode) print('録音ファイルサイズ: $fileSize bytes');
            
          } else {
            if (kDebugMode) print('録音ファイルが存在しません!');
          }

          // PlayerControllerで波形を準備（解析キャンセル時でも波形表示のため）
          if (playerController != null) {
            try {
              await playerController!.preparePlayer(
                path: recordedFilePath,
                shouldExtractWaveform: true,
              );
              if (kDebugMode) print('録音停止後の波形準備完了');
              // 準備完了後にUIを更新
              setState(() {});
            } catch (e) {
              if (kDebugMode) print('録音停止後の波形準備エラー: $e');
              // エラーが発生してもUIを更新（代替表示のため）
              setState(() {});
            }
          }
          
          // 解析がキャンセルされている場合は解析を実行せず、状態のみ更新
          if (_shouldCancelAnalysis) {
            if (kDebugMode) print('解析キャンセル済み - 状態のみ更新');
            setState(() {
              _recordingState = RecordingState.idle;
            });
          } else {
            await _uploadAndAnalyze();
          }
        } else {
          if (kDebugMode) print('recordedFilePath is null!');
          setState(() {
            _recordingState = RecordingState.idle;
          });
        }
      }
      setState(() {
        _isAnalyzed = true;
      });
    }
  }

  Widget _buildWaveformWidget() {
    if (_recordingState == RecordingState.recording) {
      if (!isWeb && _recorderController != null) {
        return AudioWaveforms(
          recorderController: _recorderController,
          size: Size(MediaQuery.of(context).size.width - 80, 60),
          waveStyle: const WaveStyle(
            waveCap: StrokeCap.round,
            extendWaveform: true,
            showMiddleLine: false,
            waveColor: Colors.red,
          ),
        );
      } else {
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.mic, color: Colors.red, size: 24),
              SizedBox(height: 4),
              Text('録音中...', style: TextStyle(color: Colors.red, fontSize: 12)),
            ],
          ),
        );
      }
    } else if (_audioFilePath != null && !isWeb) {
      // 録音完了後はPlayerControllerを使って波形を表示
      if (playerController != null) {
        return AudioFileWaveforms(
          playerController: playerController!,
          size: Size(MediaQuery.of(context).size.width - 80, 60),
          playerWaveStyle: const PlayerWaveStyle(
            seekLineColor: Colors.blue,
            showSeekLine: false,
            waveCap: StrokeCap.round,
            fixedWaveColor: Colors.blue,
            liveWaveColor: Colors.blue,
          ),
          waveformType: WaveformType.fitWidth,
        );
      } else {
        // PlayerControllerが一時的に利用できない場合の代替表示
        return const Center(
          child: Text(
            '録音完了 - 波形準備中...',
            style: TextStyle(color: Colors.blue, fontSize: 12),
          ),
        );
      }
    } else {
      return const Center(
        child: Text(
          '録音を開始すると波形が表示されます',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      );
    }
  }

  Future<String?> _setupRecording() async {
    if (!isRecordingSupported) {
      return null;
    }

    try {
      if (isWeb) {
        // Web環境での録音開始
        final success = await _webAudioRecorder!.startRecording();
        if (success) {
          final outputPath =
              'web_recorded_audio_${DateTime.now().millisecondsSinceEpoch}.wav';
          if (kDebugMode) print('Web録音開始: $outputPath');
          return outputPath;
        } else {
          if (kDebugMode) print('Web録音開始に失敗');
          return null;
        }
      } else {
        // モバイル環境での録音開始（AAC形式）
        final directory = await getApplicationDocumentsDirectory();
        final outputPath =
            '${directory.path}/recorded_audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

        if (kDebugMode) print('録音開始: $outputPath');

        // RecorderControllerで録音開始（AACエンコーダー）
        await _recorderController!.record(
          androidEncoder: AndroidEncoder.aac,
          androidOutputFormat: AndroidOutputFormat.mpeg4,
          path: outputPath,
        );

        if (kDebugMode) print('録音が開始されました');
        return outputPath;
      }
    } catch (e) {
      if (kDebugMode) print('録音設定エラー: $e');
      return null;
    }
  }

  Future<void> _uploadAndAnalyze() async {
    if (_audioFilePath == null) {
      if (kDebugMode) print('音声ファイルが存在しません');
      return;
    }

    // 解析開始前にキャンセルフラグをリセット
    _shouldCancelAnalysis = false;
    
    if (kDebugMode) print('API upload started: $_audioFilePath');

    try {
      AudioAnalysisResult? result;
      if (isWeb) {
        // Web環境：メモリ上のデータを使用
        final webAudioData = getWebAudioFile(_audioFilePath!);
        if (webAudioData != null) {
          result = await AudioProcessingService.uploadAndProcess(
            _audioFilePath!,
            webAudioData: webAudioData,
          );
        } else {
          if (kDebugMode) print('Web音声データが見つかりません');
          return;
        }
      } else {
        // モバイル環境：ファイルパスを使用
        result = await AudioProcessingService.uploadAndProcess(_audioFilePath!);
      }

      // キャンセルされた場合は処理を中断
      if (_shouldCancelAnalysis) {
        if (kDebugMode) print('解析がキャンセルされました');
        return;
      }

      if (result != null) {
        setState(() {
          _analysisResult = result;
          _recordingState = RecordingState.idle;
          _isAnalyzed = true;
        });
        // プログレスアニメーションを停止
        _progressAnimationController.stop();

        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('音楽解析が完了しました'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        setState(() {
          _recordingState = RecordingState.idle;
        });

        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('解析に失敗しました'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) print('Upload error: $e');
      
      // キャンセルされた場合はエラーメッセージを表示しない
      if (_shouldCancelAnalysis) {
        if (kDebugMode) print('解析がキャンセルされました（エラー処理中）');
        return;
      }
      
      setState(() {
        _recordingState = RecordingState.idle;
      });

      if (mounted && context.mounted) {
        String errorMessage = 'アップロードエラーが発生しました';
        if (e.toString().contains('TimeoutException')) {
          errorMessage = '音声解析に時間がかかっています。処理を継続中です...';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _togglePlayback() async {
    if (_audioFilePath == null) {
      return;
    }

    // Web版では独自の再生機能を使用
    if (isWeb) {
      await _toggleWebPlayback();
      return;
    }

    if (playerController == null) {
      return;
    }

    if (kDebugMode) print('音声ファイルパス: $_audioFilePath');

    // ファイルの存在確認
    if (!await fileExists(_audioFilePath!)) {
      if (kDebugMode) print('音声ファイルが存在しません: $_audioFilePath');
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('音声ファイルが見つかりません'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final fileSize = await getFileSize(_audioFilePath!);
    if (kDebugMode) print('ファイルサイズ: $fileSize bytes');

    try {
      if (_isPlaying) {
        // 停止
        if (kDebugMode) print('音声再生を停止します');
        await playerController!.stopPlayer();
        setState(() {
          _isPlaying = false;
        });
        if (kDebugMode) print('音声再生が停止されました');
      } else {
        // 再生開始前にPlayerControllerをリセット
        if (kDebugMode) print('音声再生を開始します');

        // 既存の再生を完全に停止してリセット
        try {
          await playerController!.stopPlayer();
          if (kDebugMode) print('既存の再生を停止しました');
        } catch (e) {
          if (kDebugMode) print('停止時エラー（無視可能）: $e');
        }

        // プレイヤーを準備
        await playerController!.preparePlayer(
          path: _audioFilePath!,
          shouldExtractWaveform: true,
        );
        if (kDebugMode) print('プレイヤーの準備が完了しました');

        // リスナーを一度だけ追加
        if (!_playerListenerAdded) {
          playerController!.onPlayerStateChanged.listen((state) {
            if (kDebugMode) print('プレイヤー状態変更: \\${state.toString()}');
            if (state.isPaused || state.isStopped) {
              if (mounted) {
                setState(() {
                  _isPlaying = false;
                });
                if (kDebugMode) print('再生状態をfalseに更新しました');
              }
            }
          });
          _playerListenerAdded = true;
          if (kDebugMode) print('プレイヤーリスナーを追加しました');
        }

        // 再生開始
        await playerController!.startPlayer();
        setState(() {
          _isPlaying = true;
        });
        if (kDebugMode) print('音声再生が開始されました');
      }
    } catch (e) {
      if (kDebugMode) print('再生エラー: $e');
      setState(() {
        _isPlaying = false;
      });
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('再生エラー: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _toggleWebPlayback() async {
    if (_webAudioRecorder == null) return;

    try {
      if (_isPlaying) {
        // 停止
        if (kDebugMode) print('Web音声再生を停止します');
        await _webAudioRecorder.stopAudio();
        setState(() {
          _isPlaying = false;
        });
      } else {
        // 再生開始
        if (kDebugMode) print('Web音声再生を開始します');
        final audioData = getWebAudioFile(_audioFilePath!);
        if (audioData != null) {
          // ユーザーアクションから直接呼び出すことで、ブラウザの自動再生制限を回避
          setState(() {
            _isPlaying = true;
          });

          // 再生完了を監視
          _webAudioRecorder.playbackStateStream.listen((isPlaying) {
            if (mounted) {
              setState(() {
                _isPlaying = isPlaying;
              });
            }
          });

          await _webAudioRecorder.playAudio(audioData);
        } else {
          if (mounted && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('録音データが見つかりません'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }

      }
    } catch (e) {
      if (kDebugMode) print('Web再生エラー: $e');
      setState(() {
        _isPlaying = false;
      });
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('再生エラー: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _toggleBackingTrackPlayback() async {
    final backingTrackUrl = _analysisResult?.backingTrackUrl;
    if (backingTrackUrl == null || backingTrackUrl.isEmpty) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('バッキングトラックが利用できません'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // Web環境では直接URLを再生
    if (isWeb) {
      await _toggleWebBackingTrackPlayback(backingTrackUrl);
      return;
    }

    // モバイル環境でのバッキングトラック再生
    if (backingTrackController == null) {
      return;
    }

    try {
      if (_isBackingTrackPlaying) {
        // 停止
        if (kDebugMode) print('バッキングトラック再生を停止します');
        await backingTrackController!.stopPlayer();
        setState(() {
          _isBackingTrackPlaying = false;
        });
        if (kDebugMode) print('バッキングトラック再生が停止されました');
      } else {
        // 再生開始
        if (kDebugMode) print('バッキングトラック再生を開始します: $backingTrackUrl');

        // 既存の再生を完全に停止してリセット
        try {
          await backingTrackController!.stopPlayer();
          if (kDebugMode) print('既存のバッキングトラック再生を停止しました');
        } catch (e) {
          if (kDebugMode) print('停止時エラー（無視可能）: $e');
        }

        // リスナーを一度だけ追加
        if (!_backingTrackListenerAdded) {
          backingTrackController!.onPlayerStateChanged.listen((state) {
            if (kDebugMode) print('バッキングトラックプレイヤー状態変更: ${state.toString()}');
            if (state.isPaused || state.isStopped) {
              if (mounted) {
                setState(() {
                  _isBackingTrackPlaying = false;
                });
                if (kDebugMode) print('バッキングトラック再生状態をfalseに更新しました');
              }
            }
          });
          _backingTrackListenerAdded = true;
          if (kDebugMode) print('バッキングトラックプレイヤーリスナーを追加しました');
        }

        // URL から再生開始
        await backingTrackController!.preparePlayer(
          path: backingTrackUrl,
          shouldExtractWaveform: true,
        );
        await backingTrackController!.startPlayer();
        setState(() {
          _isBackingTrackPlaying = true;
        });
        if (kDebugMode) print('バッキングトラック再生が開始されました');
      }
    } catch (e) {
      if (kDebugMode) print('バッキングトラック再生エラー: $e');
      setState(() {
        _isBackingTrackPlaying = false;
      });
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('バッキングトラック再生エラー: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _toggleWebBackingTrackPlayback(String url) async {
    if (_webAudioRecorder == null) return;

    try {
      if (_isBackingTrackPlaying) {
        // 停止
        if (kDebugMode) print('Webバッキングトラック再生を停止します');
        await _webAudioRecorder.stopAudio();
        setState(() {
          _isBackingTrackPlaying = false;
        });
      } else {
        // 再生開始
        if (kDebugMode) print('Webバッキングトラック再生を開始します: $url');
        setState(() {
          _isBackingTrackPlaying = true;
        });

        // 再生完了を監視
        _webAudioRecorder.playbackStateStream.listen((isPlaying) {
          if (mounted) {
            setState(() {
              _isBackingTrackPlaying = isPlaying;
            });
          }
        });

        // URLから音声を再生（実際のWeb実装では fetch + AudioContext を使用）
        await _webAudioRecorder.playAudioFromUrl(url);
      }
    } catch (e) {
      if (kDebugMode) print('Webバッキングトラック再生エラー: $e');
      setState(() {
        _isBackingTrackPlaying = false;
      });
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('バッキングトラック再生エラー: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _toggleChat() {
    setState(() {
      _isChatOpen = !_isChatOpen;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) {
      print('Build called with _recordingState: $_recordingState');
    }
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.deepPurple.shade600,
                Colors.indigo.shade500,
                Colors.blue.shade400,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.deepPurple.withValues(alpha: 0.3),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.music_note,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(
                    colors: [
                      Colors.white,
                      Colors.white.withValues(alpha: 0.8),
                    ],
                  ).createShader(bounds),
                  child: const Text(
                    'SessionMUSE',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                Text(
                  'Your AI Music Partner',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.greenAccent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.greenAccent.withValues(alpha: 0.6),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'LIVE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                flex: 1,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.grey.shade50,
                        Colors.grey.shade100,
                      ],
                    ),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: isWeb ? 800 : double.infinity, // Web版は最大幅800px
                      ),
                      child: SingleChildScrollView(
                        padding: EdgeInsets.only(
                          left: isWeb ? 24.0 : 14.0,
                          right: isWeb ? 24.0 : 14.0,
                          top: 16.0,
                          bottom: 120.0, // フローティングボタンの分の余白を追加
                        ),
                        child: Column(
                          children: [
                            _buildExplanationSection(),
                            const SizedBox(height: 16),
                            _buildRecordingSection(),
                            if (_recordingState == RecordingState.uploading || _recordingState == RecordingState.idle || _recordingState == RecordingState.recording)
                              _buildUploadingIndicator(),
                            const SizedBox(height: 16),
                            _buildAnalysisResults(),
                            if (_isAnalyzed) const SizedBox(height: 16),
                            _buildBackingTrackPlayer(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          _buildChatOverlay(),
        ],
      ),
      floatingActionButton: _isChatOpen
          ? null
          : Container(
              margin: const EdgeInsets.only(bottom: 16, right: 8),
              child: Material(
                elevation: 12,
                borderRadius: BorderRadius.circular(30),
                shadowColor: Colors.purple.withValues(alpha: 0.3),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white,
                        Colors.purple.shade50,
                        Colors.white,
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: Colors.purple.shade200,
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.purple.withValues(alpha: 0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                        spreadRadius: 2,
                      ),
                      BoxShadow(
                        color: Colors.purple.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                  child: InkWell(
                    onTap: _toggleChat,
                    borderRadius: BorderRadius.circular(30),
                    splashColor: Colors.purple.withValues(alpha: 0.2),
                    highlightColor: Colors.purple.withValues(alpha: 0.1),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.orange.shade300,
                                Colors.pink.shade400,
                                Colors.purple.shade500,
                              ],
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.purple.withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // 背景の音符
                              Positioned(
                                top: 6,
                                right: 8,
                                child: Icon(
                                  Icons.music_note,
                                  color: Colors.white.withValues(alpha: 0.4),
                                  size: 12,
                                ),
                              ),
                              // メインアイコン（ハートと音楽の組み合わせ）
                              Icon(
                                Icons.favorite_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                              // 小さな星
                              Positioned(
                                bottom: 4,
                                left: 6,
                                child: Icon(
                                  Icons.auto_awesome,
                                  color: Colors.white.withValues(alpha: 0.8),
                                  size: 8,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '行き詰まったら・気分転換',
                              style: TextStyle(
                                color: Colors.purple.shade700,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'AIバンドメンバーに相談してみよう',
                              style: TextStyle(
                                color: Colors.purple.shade600,
                                fontWeight: FontWeight.w400,
                                fontSize: 11,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildExplanationSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.purple.shade50, Colors.blue.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.purple.shade200, width: 1),
      ),
      child: Column(
        children: [
          // 1. ATTENTION: キャッチコピー
          Text(
            '🎵 もう、曲作りで孤独じゃない',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.purple.shade700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '24時間いつでも付き合ってくれるAIバンドメンバー',
            style: TextStyle(
              fontSize: 14,
              color: Colors.purple.shade600,
            ),
          ),
          const SizedBox(height: 16),
          
          // 2. INTEREST: 問題提起と利用シーン（図解）
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Column(
              children: [
                Text(
                  '💡 こんな課題を解決',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildProblemStep('💭', 'アイデアが\n浮かんだ', Colors.orange),
                    _buildProblemArrow(),
                    _buildProblemStep('😕', '一人だと\n行き詰まり', Colors.red),
                    _buildProblemArrow(),
                    _buildProblemStep('🤔', '客観的意見\nが欲しい', Colors.blue),
                  ],
                ),
                const SizedBox(height: 10),
                // シンプルな要因説明
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200, width: 1),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.red.shade600,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '原因：孤独な作業・客観視できない・新アイデアが浮かばない',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          
          // 3. DESIRE: ソリューション（使い方の流れ）
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.purple.shade100),
            ),
            child: Column(
              children: [
                Text(
                  '✨ 簡単3ステップでAIとセッション',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.purple.shade700,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _buildFlowStep('🎤', '① 鼻歌を\n録音', Colors.blue),
                    _buildArrow(),
                    _buildFlowStep('🤖', '② AI解析\n実行', Colors.green),
                    _buildArrow(),
                    _buildFlowStep('🎵', '③ 一緒に\n演奏', Colors.orange),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.purple.shade200, width: 1),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        color: Colors.purple.shade600,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '💬 + 「もっとドラマチックに」など感性もAIに相談可能',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.purple.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          
          // 5. BENEFIT: 得られる価値
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Column(
              children: [
                Text(
                  '🌟 得られるもの',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.star_outline,
                      color: Colors.green.shade700,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '🎯 鼻歌から、AIと一緒に作り上げる、世界で唯一無二の作品',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlowStep(String icon, String text, Color color) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(icon, style: const TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArrow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Icon(
        Icons.arrow_forward,
        color: Colors.grey.shade400,
        size: 16,
      ),
    );
  }

  Widget _buildProblemStep(String icon, String text, Color color) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 35,
            height: 35,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
            ),
            child: Center(
              child: Text(icon, style: const TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: Colors.amber.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProblemArrow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Icon(
        Icons.arrow_forward,
        color: Colors.amber.shade400,
        size: 14,
      ),
    );
  }

  Widget _buildRecordingSection() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.cyan.shade50,
            Colors.blue.shade50,
            Colors.indigo.shade50,
          ],
        ),
        borderRadius: BorderRadius.circular(24.0),
        boxShadow: [
          BoxShadow(
            color: Colors.cyan.withValues(alpha: 0.15),
            blurRadius: 24,
            offset: const Offset(0, 12),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
            spreadRadius: -2,
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.8),
          width: 1.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24.0),
        child: Container(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.cyan.shade600,
                        Colors.blue.shade600,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.cyan.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.mic_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        '鼻歌を録音',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white,
                      Colors.cyan.shade50,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.cyan.shade200, width: 1),
                ),
                child: Text(
                  '🎶 あなたのアイデアを聞かせてください。一緒に楽曲を作りましょう！',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.cyan.shade700,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          const SizedBox(height: 16),
          Row(
            children: [
              // 録音ボタンカード
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: _recordingState == RecordingState.recording
                          ? [Colors.red.shade100, Colors.red.shade200]
                          : [Colors.white, Colors.cyan.shade50],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _recordingState == RecordingState.recording
                          ? Colors.red.shade300
                          : Colors.cyan.shade200,
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (_recordingState == RecordingState.recording ? Colors.red : Colors.cyan).withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: InkWell(
                    onTap: _handleRecordingButtonPress,
                    borderRadius: BorderRadius.circular(16),
                    child: Column(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: _recordingState == RecordingState.recording
                                  ? [Colors.red.shade500, Colors.red.shade700]
                                  : [Colors.cyan.shade500, Colors.cyan.shade700],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (_recordingState == RecordingState.recording ? Colors.red : Colors.blue).withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(
                            _recordingState == RecordingState.recording
                                ? Icons.stop_rounded
                                : Icons.mic_rounded,
                            size: 24,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _recordingState == RecordingState.recording ? '録音中...' : '🎤 アイデア録音',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: _recordingState == RecordingState.recording
                                ? Colors.red.shade700
                                : Colors.cyan.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // 再生ボタンカード
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: _isPlaying
                          ? [Colors.orange.shade100, Colors.orange.shade200]
                          : _audioFilePath != null
                              ? [Colors.white, Colors.green.shade50]
                              : [Colors.white, Colors.grey.shade100],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _isPlaying
                          ? Colors.orange.shade300
                          : _audioFilePath != null
                              ? Colors.green.shade200
                              : Colors.grey.shade300,
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (_isPlaying ? Colors.orange : _audioFilePath != null ? Colors.green : Colors.grey).withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: InkWell(
                    onTap: _audioFilePath == null ? null : _togglePlayback,
                    borderRadius: BorderRadius.circular(16),
                    child: Column(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: _isPlaying
                                  ? [Colors.orange.shade500, Colors.orange.shade700]
                                  : _audioFilePath != null
                                      ? [Colors.green.shade500, Colors.green.shade700]
                                      : [Colors.grey.shade400, Colors.grey.shade500],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (_isPlaying ? Colors.orange : _audioFilePath != null ? Colors.green : Colors.grey).withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(
                            _isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
                            size: 24,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isPlaying ? '🎵 再生中' : _audioFilePath != null ? '🎧 アイデア再生' : '🎧 録音待ち',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: _isPlaying
                                ? Colors.orange.shade700
                                : _audioFilePath != null
                                    ? Colors.green.shade700
                                    : Colors.grey.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (!isWeb) ...[
            const SizedBox(height: 16),
            Container(
              height: math.min(60, MediaQuery.of(context).size.height * 0.08),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(color: Colors.grey.shade300, width: 1.0),
              ),
              child: _buildWaveformWidget(),
            ),
            const SizedBox(height: 16),
          ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnalysisResults() {
    // 常にカードを表示 - 解析中はローディング状態を表示

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.deepPurple.shade50,
            Colors.indigo.shade50,
            Colors.blue.shade50,
          ],
        ),
        borderRadius: BorderRadius.circular(24.0),
        boxShadow: [
          BoxShadow(
            color: Colors.deepPurple.withValues(alpha: 0.15),
            blurRadius: 24,
            offset: const Offset(0, 12),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
            spreadRadius: -2,
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.8),
          width: 1.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24.0),
        child: Container(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.deepPurple.shade600,
                        Colors.indigo.shade600,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.deepPurple.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.auto_awesome,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'AI解析結果',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _isAnalyzed 
                ? GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: isWeb ? 3.0 : 1.8, // Web版はより横長に（高さはコンテンツに依存）
                      children: [
                        _buildAnalysisChip('Key', _analysisResult?.key ?? 'C Major', Icons.music_note),
                        _buildAnalysisChip('BPM', _analysisResult?.bpm.toString() ?? '120', Icons.speed),
                        _buildAnalysisChip('Chords', _analysisResult?.chords ?? 'C-G-Am', Icons.piano),
                        _buildAnalysisChip('Genre', _analysisResult?.genre ?? 'Rock', Icons.library_music),
                      ],
                    )
                : _buildAnalysisLoadingState(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackingTrackPlayer() {
    // バッキングトラックカードを常に表示
    final hasBackingTrack = _analysisResult?.backingTrackUrl != null && _analysisResult!.backingTrackUrl!.isNotEmpty;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: hasBackingTrack
              ? [
                  Colors.orange.shade50,
                  Colors.amber.shade50,
                  Colors.yellow.shade50,
                ]
              : [
                  Colors.grey.shade50,
                  Colors.blueGrey.shade50,
                  Colors.grey.shade100,
                ],
        ),
        borderRadius: BorderRadius.circular(24.0),
        boxShadow: [
          BoxShadow(
            color: (hasBackingTrack ? Colors.orange : Colors.grey).withValues(alpha: 0.15),
            blurRadius: 24,
            offset: const Offset(0, 12),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
            spreadRadius: -2,
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.8),
          width: 1.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24.0),
        child: Container(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: hasBackingTrack
                          ? [
                              Colors.orange.shade600,
                              Colors.amber.shade600,
                            ]
                          : [
                              Colors.grey.shade500,
                              Colors.blueGrey.shade500,
                            ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: (hasBackingTrack ? Colors.orange : Colors.grey).withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          hasBackingTrack ? Icons.piano : Icons.piano_outlined,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        '一緒に演奏',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: hasBackingTrack
                        ? [
                            Colors.white,
                            Colors.orange.shade50,
                          ]
                        : [
                            Colors.white,
                            Colors.grey.shade50,
                          ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: hasBackingTrack ? Colors.orange.shade200 : Colors.grey.shade200,
                    width: 1,
                  ),
                ),
            child: Column(
              children: [
                Icon(
                  hasBackingTrack ? Icons.music_note : Icons.music_off,
                  color: hasBackingTrack ? Colors.orange.shade600 : Colors.grey.shade400,
                  size: 32,
                ),
                const SizedBox(height: 6),
                Text(
                  hasBackingTrack 
                      ? '🎤 素敵なメロディですね！伴奏を付けました'
                      : '録音・解析後、AIが伴奏を自動生成します',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: hasBackingTrack ? Colors.orange.shade700 : Colors.grey.shade600,
                    fontSize: 15,
                    fontWeight: hasBackingTrack ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          if (!isWeb) ...[
            const SizedBox(height: 16),
            Container(
              height: math.min(60, MediaQuery.of(context).size.height * 0.08),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(color: Colors.grey.shade300, width: 1.0),
              ),
              child: hasBackingTrack && backingTrackController != null
                  ? AudioFileWaveforms(
                      playerController: backingTrackController!,
                      size: Size(MediaQuery.of(context).size.width - 80, 60),
                      playerWaveStyle: const PlayerWaveStyle(
                        seekLineColor: Colors.orange,
                        showSeekLine: true,
                        waveCap: StrokeCap.round,
                        fixedWaveColor: Colors.orange,
                        liveWaveColor: Colors.orange,
                      ),
                      waveformType: WaveformType.fitWidth,
                    )
                  : const Center(
                      child: Text(
                        'バッキングトラックが利用可能になると波形が表示されます',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 16),
          ] else if (isWeb && hasBackingTrack) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(color: Colors.orange.shade200, width: 1.0),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.music_note,
                    color: Colors.orange.shade600,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'バッキングトラック: ${_analysisResult!.backingTrackUrl!.split('/').last}',
                      style: TextStyle(
                        color: Colors.orange.shade700,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: hasBackingTrack
                              ? (_isBackingTrackPlaying 
                                  ? [Colors.red.shade100, Colors.red.shade200]
                                  : [Colors.white, Colors.green.shade50])
                              : [Colors.white, Colors.grey.shade100],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: hasBackingTrack
                              ? (_isBackingTrackPlaying ? Colors.red.shade300 : Colors.green.shade200)
                              : Colors.grey.shade300,
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: hasBackingTrack
                                ? (_isBackingTrackPlaying ? Colors.red : Colors.green).withValues(alpha: 0.2)
                                : Colors.grey.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: InkWell(
                        onTap: hasBackingTrack 
                            ? _toggleBackingTrackPlayback 
                            : () {
                                if (mounted && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('音声を録音・解析するとバッキングトラックが利用できます'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                              },
                        borderRadius: BorderRadius.circular(16),
                        child: Column(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: hasBackingTrack
                                      ? (_isBackingTrackPlaying 
                                          ? [Colors.red.shade500, Colors.red.shade700]
                                          : [Colors.green.shade500, Colors.green.shade700])
                                      : [Colors.grey.shade400, Colors.grey.shade500],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: hasBackingTrack
                                        ? (_isBackingTrackPlaying ? Colors.red : Colors.green).withValues(alpha: 0.3)
                                        : Colors.grey.withValues(alpha: 0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Icon(
                                hasBackingTrack && _isBackingTrackPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
                                size: 24,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              hasBackingTrack && _isBackingTrackPlaying ? '🎵 演奏中' : hasBackingTrack ? '🎧 演奏開始' : '🎧 演奏待ち',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: hasBackingTrack
                                    ? (_isBackingTrackPlaying ? Colors.red.shade700 : Colors.green.shade700)
                                    : Colors.grey.shade600,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: hasBackingTrack
                              ? [Colors.white, Colors.blue.shade50]
                              : [Colors.white, Colors.grey.shade100],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: hasBackingTrack ? Colors.blue.shade200 : Colors.grey.shade300,
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (hasBackingTrack ? Colors.blue : Colors.grey).withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: InkWell(
                        onTap: hasBackingTrack
                            ? () async {
                                final url = _analysisResult!.backingTrackUrl!;
                                if (mounted && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'バッキングトラックURL: $url',
                                      ),
                                      duration: const Duration(seconds: 3),
                                      action: SnackBarAction(
                                        label: 'コピー',
                                        onPressed: () {
                                          // URLをクリップボードにコピーする機能はプラットフォーム依存のため省略
                                        },
                                      ),
                                    ),
                                  );
                                }
                              }
                            : () {
                                if (mounted && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('バッキングトラックが生成されるとダウンロードできます'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                              },
                        borderRadius: BorderRadius.circular(16),
                        child: Column(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: hasBackingTrack
                                      ? [Colors.blue.shade500, Colors.blue.shade700]
                                      : [Colors.grey.shade400, Colors.grey.shade500],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: (hasBackingTrack ? Colors.blue : Colors.grey).withValues(alpha: 0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.download_rounded,
                                size: 24,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              hasBackingTrack ? '💾 ダウンロード' : '💾 生成待ち',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: hasBackingTrack ? Colors.blue.shade700 : Colors.grey.shade600,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatOverlay() {
    if (!_isChatOpen) return const SizedBox.shrink();

    return Container(
      color: Colors.purple.shade50,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isWeb ? 800 : double.infinity, // Web版は最大幅800px
          ),
          child: Column(
            children: [
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.purple.shade100,
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade300, width: 1.0),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: _toggleChat,
                  icon: const Icon(Icons.close, color: Colors.purple),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chat_bubble, color: Colors.purple, size: 24),
                const SizedBox(width: 8),
                const Text(
                  '🎵 セッション相談室',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.purple,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16.0),
              itemCount: _messages.length + (_isLoadingResponse ? 1 : 0),
              itemBuilder: (context, index) {
                // ローディングインジケーターを表示
                if (index == _messages.length && _isLoadingResponse) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.purple.shade200,
                          child: const Icon(
                            Icons.smart_toy,
                            color: Colors.purple,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.all(12.0),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16.0),
                            border: Border.all(
                              color: Colors.grey.shade300,
                              width: 1.0,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 32,
                                height: 32,
                                child: _buildMiniLoadingAnimation(),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                "AI が考えています...",
                                style: TextStyle(
                                  color: Colors.black54,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final message = _messages[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Row(
                    mainAxisAlignment: message.isUser
                        ? MainAxisAlignment.end
                        : MainAxisAlignment.start,
                    children: [
                      if (!message.isUser) ...[
                        CircleAvatar(
                          backgroundColor: Colors.purple.shade200,
                          child: const Icon(
                            Icons.smart_toy,
                            color: Colors.purple,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.all(12.0),
                          decoration: BoxDecoration(
                            color: message.isUser
                                ? Colors.purple.shade200
                                : Colors.white,
                            borderRadius: BorderRadius.circular(16.0),
                            border: Border.all(
                              color: Colors.grey.shade300,
                              width: 1.0,
                            ),
                          ),
                          child: message.isUser
                              ? Text(
                                  message.text,
                                  style: const TextStyle(color: Colors.white),
                                )
                              : MarkdownBody(
                                  data: message.text,
                                  styleSheet: MarkdownStyleSheet(
                                    p: const TextStyle(
                                      color: Colors.black87,
                                      fontSize: 14,
                                    ),
                                    strong: const TextStyle(
                                      color: Colors.black87,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    em: const TextStyle(
                                      color: Colors.black87,
                                      fontSize: 14,
                                      fontStyle: FontStyle.italic,
                                    ),
                                    code: TextStyle(
                                      backgroundColor: Colors.grey.shade200,
                                      color: Colors.purple.shade700,
                                      fontSize: 13,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      if (message.isUser) ...[
                        const SizedBox(width: 8),
                        CircleAvatar(
                          backgroundColor: Colors.purple.shade400,
                          child: const Icon(Icons.person, color: Colors.white),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: Colors.grey.shade300, width: 1.0),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: 'メッセージを入力...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(24.0)),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 12.0,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isLoadingResponse ? null : _sendMessage,
                  icon: _isLoadingResponse
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.purple.shade300,
                            ),
                          ),
                        )
                      : const Icon(Icons.send),
                  color: _isLoadingResponse ? Colors.grey : Colors.purple,
                  style: IconButton.styleFrom(
                    backgroundColor: _isLoadingResponse
                        ? Colors.grey.shade100
                        : Colors.purple.shade100,
                  ),
                ),
              ],
            ),
          ),
        ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnalysisLoadingState() {
    final isUploading = _recordingState == RecordingState.uploading;
    
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // アニメーション付きローディングサークル
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  Colors.deepPurple.shade400,
                  Colors.indigo.shade400,
                  Colors.blue.shade400,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.deepPurple.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                strokeWidth: 3,
              ),
            ),
          ),
          const SizedBox(height: 24),
          // ローディングテキスト
          Text(
            isUploading ? 'AI解析を実行中...' : 'AI解析を待機中',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.deepPurple.shade700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isUploading 
                ? '音楽的特徴を分析しています\n少々お待ちください' 
                : '録音完了後に自動で解析を開始します',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          // ローディング用のプレースホルダーチップ
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.8,
            children: [
              _buildLoadingChip('Key', Icons.music_note),
              _buildLoadingChip('BPM', Icons.speed),
              _buildLoadingChip('Chords', Icons.piano),
              _buildLoadingChip('Genre', Icons.library_music),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.grey.shade100,
            Colors.grey.shade200,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey.shade300,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 14,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(7),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: LinearProgressIndicator(
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.grey.shade400),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysisChip(String label, String value, IconData icon) {
    return Container(
      constraints: isWeb ? const BoxConstraints(maxHeight: 100) : null, // Web版は最大高さ制限
      padding: EdgeInsets.all(isWeb ? 12 : 16), // Web版は少し小さく
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            Colors.grey.shade50,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey.shade200,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.deepPurple.shade400,
                      Colors.indigo.shade400,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: isWeb ? 14 : 16, // Web版は少し小さく
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                    fontSize: isWeb ? 10 : 11, // Web版は少し小さく
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: Colors.grey.shade800,
              fontWeight: FontWeight.bold,
              fontSize: isWeb ? 12 : 14, // Web版は少し小さく
              letterSpacing: 0.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildUploadingIndicator() {
    // 状態に応じたメッセージとアイコンを決定
    String titleText;
    String subtitle;
    List<Color> gradientColors;
    
    switch (_recordingState) {
      case RecordingState.idle:
        titleText = 'AI解析待機中';
        subtitle = 'AIがあなたの鼻歌を解析して自動的に伴奏を生成します';
        gradientColors = [Colors.cyan.shade50, Colors.blue.shade50, Colors.indigo.shade50];
        break;
      case RecordingState.recording:
        titleText = '録音実行中';
        subtitle = '音声を収集しています';
        gradientColors = [Colors.red.shade50, Colors.pink.shade50, Colors.orange.shade50];
        break;
      case RecordingState.uploading:
        titleText = 'AI解析実行中';
        subtitle = '音楽的特徴を分析しています';
        gradientColors = [Colors.deepPurple.shade50, Colors.indigo.shade50, Colors.blue.shade50];
        break;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 16.0),
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        borderRadius: BorderRadius.circular(24.0),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // タイトル部分（他のカードと同じスタイル）
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.deepPurple.shade600,
                    Colors.indigo.shade600,
                    Colors.blue.shade700,
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.smart_toy_outlined,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    titleText,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // コンテンツ部分
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (_recordingState == RecordingState.uploading) ...[
            const SizedBox(height: 20),
            _buildModernProgressBar(),
          ],
        ],
      ),
    );
  }

  Widget _buildModernProgressBar() {
    return AnimatedBuilder(
      animation: _progressAnimationController,
      builder: (context, child) {
        final progress = _progressAnimationController.value;
        final percentage = (progress * 100).toInt();
        
        return Column(
          children: [
            // パーセンテージ表示
            Text(
              '$percentage%',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple.shade700,
              ),
            ),
            const SizedBox(height: 12),
            // プログレスバー
            Container(
              width: double.infinity,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(4),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Color.lerp(
                      Colors.deepPurple.shade400,
                      Colors.indigo.shade500,
                      progress,
                    ) ?? Colors.deepPurple,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 残り時間表示
            Text(
              '残り時間: ${((1 - progress) * 60).toInt()}秒',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCustomLoadingAnimation() {
    return AnimatedBuilder(
      animation: _loadingAnimationController,
      builder: (context, child) {
        final value = _loadingAnimationController.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer pulsing hexagon
            Transform.rotate(
              angle: value * 6.28318,
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF00D4FF).withValues(alpha: 0.6),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00D4FF).withValues(alpha: 0.3),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
            
            // Middle rotating ring with gradient effect
            Transform.rotate(
              angle: -value * 4.71, // 3/4 speed in opposite direction
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF6366F1),
                      const Color(0xFF8B5CF6),
                      const Color(0xFFEC4899),
                      const Color(0xFF06B6D4),
                    ],
                    stops: const [0.0, 0.33, 0.66, 1.0],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    transform: GradientRotation(value * 6.28318),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.4),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Container(
                  margin: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            
            // Inner data particles
            ...List.generate(6, (index) {
              final particleAngle = (index * 1.047) + (value * 8.377); // π/3 spacing, faster rotation
              final radius = 15.0 + (3.0 * math.sin(value * 6.28 + index));
              final particleSize = 3.0 + (1.5 * math.sin(value * 12.56 + index * 2));
              final opacity = 0.7 + (0.3 * math.sin(value * 10 + index));
              
              return Transform.translate(
                offset: Offset(
                  radius * math.cos(particleAngle),
                  radius * math.sin(particleAngle),
                ),
                child: Container(
                  width: particleSize,
                  height: particleSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF00F5FF).withValues(alpha: opacity),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00F5FF).withValues(alpha: 0.6),
                        blurRadius: 3,
                        spreadRadius: 0.5,
                      ),
                    ],
                  ),
                ),
              );
            }),
            
            // Central AI core with matrix effect
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF00F5FF).withValues(alpha: 0.9),
                    const Color(0xFF6366F1).withValues(alpha: 0.7),
                    const Color(0xFF1E293B).withValues(alpha: 0.9),
                  ],
                  stops: const [0.0, 0.6, 1.0],
                ),
                border: Border.all(
                  color: const Color(0xFF00D4FF).withValues(alpha: 0.8),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00F5FF).withValues(alpha: 0.5),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(
                Icons.memory,
                size: 16,
                color: Colors.white.withValues(alpha: 0.9 + 0.1 * math.sin(value * 10)),
              ),
            ),
            
            // Scanning lines effect
            Positioned.fill(
              child: ClipOval(
                child: CustomPaint(
                  painter: ScanLinesPainter(animationValue: value),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMiniLoadingAnimation() {
    return AnimatedBuilder(
      animation: _chatLoadingAnimationController,
      builder: (context, child) {
        final value = _chatLoadingAnimationController.value;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (index) {
            final delay = index * 0.33;
            final adjustedValue = ((value + delay) % 1.0);
            final opacity = 0.3 + 0.7 * math.sin(adjustedValue * math.pi);
            final scale = 0.5 + 0.5 * math.sin(adjustedValue * math.pi);
            final colors = [Colors.purple, Colors.blue, Colors.teal];
            
            return Transform.scale(
              scale: scale,
              child: Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: colors[index].withValues(alpha: opacity),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: colors[index].withValues(alpha: 0.3),
                      blurRadius: 2,
                      spreadRadius: 0.5,
                    ),
                  ],
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class ScanLinesPainter extends CustomPainter {
  final double animationValue;

  ScanLinesPainter({required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00F5FF).withValues(alpha: 0.3)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Draw scanning lines
    for (int i = 0; i < 3; i++) {
      final angle = (animationValue * 6.28318) + (i * 2.094); // 120° apart
      final startAngle = angle - 0.52; // 30° sweep
      final sweepAngle = 1.047; // 60° sweep

      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
    }
  }

  @override
  bool shouldRepaint(ScanLinesPainter oldDelegate) =>
      oldDelegate.animationValue != animationValue;
}

class ChatMessage {
  final String text;
  final bool isUser;

  ChatMessage({required this.text, required this.isUser});
}

