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
      backingTrackUrl: json['backing_track_url'],
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

  // レスポンシブデザインヘルパー
  bool get _isSmallScreen => MediaQuery.of(context).size.height < 600;
  double get _responsiveSpacing => _isSmallScreen ? 8.0 : 16.0;

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

    // プラットフォームに応じた初期化
    if (isWeb) {
      // Web環境
      _recorderController = null;
      playerController = null;
      _webAudioRecorder = WebAudioRecorder();
      // Web録音権限を取得
      _webAudioRecorder!.checkPermission();
    } else {
      // モバイル環境
      _recorderController = RecorderController();
      playerController = PlayerController();
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
    _recorderController?.dispose();
    playerController?.dispose();
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

          await _uploadAndAnalyze();
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

      if (result != null) {
        setState(() {
          _analysisResult = result;
          _recordingState = RecordingState.idle;
          _isAnalyzed = true;
        });

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
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                flex: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.grey.shade300,
                        width: 2.0,
                      ),
                    ),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        _buildRecordingSection(),
                        if (_recordingState == RecordingState.uploading)
                          _buildUploadingIndicator(),
                        SizedBox(height: _responsiveSpacing),
                        _buildAnalysisResults(),
                        if (_isAnalyzed) SizedBox(height: _responsiveSpacing),
                        _buildBackingTrackPlayer(),
                      ],
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
          : FloatingActionButton.extended(
              onPressed: _toggleChat,
              backgroundColor: Colors.purple,
              icon: const Icon(Icons.chat_bubble, color: Colors.white),
              label: const Text(
                'AIと相談',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildRecordingSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: Colors.blue.shade300, width: 1.0),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.music_note, color: Colors.blue, size: 18),
              const SizedBox(width: 8),
              const Text(
                '録音',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
          SizedBox(height: _responsiveSpacing),
          Row(
            children: [
              Container(
                width: math.min(50, MediaQuery.of(context).size.width * 0.12),
                height: math.min(50, MediaQuery.of(context).size.width * 0.12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _recordingState == RecordingState.recording
                      ? Colors.red.shade100
                      : Colors.blue.shade100,
                  border: Border.all(
                    color: _recordingState == RecordingState.recording
                        ? Colors.red.shade300
                        : Colors.blue.shade300,
                    width: 1.5,
                  ),
                ),
                child: IconButton(
                  icon: Icon(
                    _recordingState == RecordingState.recording
                        ? Icons.stop
                        : Icons.mic,
                    size: 20,
                    color: _recordingState == RecordingState.uploading
                        ? Colors.grey
                        : (_recordingState == RecordingState.recording
                              ? Colors.red
                              : Colors.blue),
                  ),
                  onPressed: _recordingState == RecordingState.uploading
                      ? null
                      : _handleRecordingButtonPress,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _recordingState == RecordingState.recording ? '録音中' : '録音開始',
                  style: TextStyle(
                    fontSize: 12,
                    color: _recordingState == RecordingState.recording
                        ? Colors.red
                        : Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              // 録音データ再生ボタン
              Container(
                width: math.min(50, MediaQuery.of(context).size.width * 0.12),
                height: math.min(50, MediaQuery.of(context).size.width * 0.12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isPlaying
                      ? Colors.orange.shade100
                      : Colors.green.shade100,
                  border: Border.all(
                    color: _isPlaying
                        ? Colors.orange.shade300
                        : Colors.green.shade300,
                    width: 1.5,
                  ),
                ),
                child: IconButton(
                  icon: Icon(
                    _isPlaying ? Icons.stop : Icons.play_arrow,
                    size: 20,
                    color: _isPlaying ? Colors.orange : Colors.green,
                  ),
                  onPressed: _audioFilePath == null
                      ? null
                      : _togglePlayback,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _isPlaying ? '再生中' : '再生',
                style: TextStyle(
                  fontSize: 12,
                  color: _isPlaying ? Colors.orange : Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          SizedBox(height: _responsiveSpacing),
          Container(
            height: math.min(60, MediaQuery.of(context).size.height * 0.08),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(color: Colors.grey.shade300, width: 1.0),
            ),
            child: _buildWaveformWidget(),
          ),
          SizedBox(height: _responsiveSpacing),
        ],
      ),
    );
  }

  Widget _buildAnalysisResults() {
    if (!_isAnalyzed) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: Colors.green.shade300, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.analytics, color: Colors.green, size: 20),
              const SizedBox(width: 8),
              const Text(
                'AIによる解析結果',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8.0,
            runSpacing: 4.0,
            children: [
              _buildAnalysisChip('Key', _analysisResult?.key ?? 'C Major'),
              _buildAnalysisChip('BPM', _analysisResult?.bpm.toString() ?? '120'),
              _buildAnalysisChip(
                  'Chords', _analysisResult?.chords ?? 'C | G | Am | F'),
              _buildAnalysisChip('Genre', _analysisResult?.genre ?? 'Rock'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBackingTrackPlayer() {
    if (!_isAnalyzed) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: Colors.orange.shade300, width: 2.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.headphones, color: Colors.orange, size: 24),
              const SizedBox(width: 8),
              const Text(
                'AIにより自動で生成された伴奏',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Column(
            children: [
              Container(
                height: math.min(60, MediaQuery.of(context).size.height * 0.08),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8.0),
                  border: Border.all(color: Colors.grey.shade300, width: 1.0),
                ),
                child:
                    _audioFilePath != null && !isWeb && playerController != null
                        ? AudioFileWaveforms(
                            playerController: playerController!,
                            size: Size(MediaQuery.of(context).size.width - 80, 60),
                            playerWaveStyle: const PlayerWaveStyle(
                              seekLineColor: Colors.orange,
                              showSeekLine: true,
                              waveCap: StrokeCap.round,
                            ),
                            waveformType: WaveformType.fitWidth,
                          )
                        : Center(
                            child: Text(
                              _audioFilePath != null
                                  ? (isWeb
                                      ? '録音データ: ${_audioFilePath!.split('/').last}'
                                      : '録音完了後に波形が表示されます')
                                  : '録音完了後に波形が表示されます',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: _audioFilePath != null ? _togglePlayback : null,
                    icon: Icon(
                      _isPlaying ? Icons.stop : Icons.play_arrow,
                      color: Colors.white,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: _audioFilePath != null
                          ? (_isPlaying ? Colors.red : Colors.green)
                          : Colors.grey,
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    onPressed: _audioFilePath != null
                        ? () {
                            if (mounted && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '音声ファイルが保存されました: ${_audioFilePath!.split('/').last}',
                                  ),
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            }
                          }
                        : null,
                    icon: const Icon(Icons.download, color: Colors.blue),
                    style: IconButton.styleFrom(
                      backgroundColor: _audioFilePath != null
                          ? Colors.blue.shade50
                          : Colors.grey.shade200,
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChatOverlay() {
    if (!_isChatOpen) return const SizedBox.shrink();

    return Container(
      color: Colors.purple.shade50,
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
                  'AI チャット',
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
    );
  }

  Widget _buildAnalysisChip(String label, String value) {
    return Chip(
      avatar: CircleAvatar(
        backgroundColor: Colors.green.shade100,
        child: Text(
          label.substring(0, 1),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.green,
            fontSize: 12,
          ),
        ),
      ),
      label: Text(
        '$label: $value',
        style: const TextStyle(
          color: Colors.black87,
          fontWeight: FontWeight.w500,
        ),
      ),
      backgroundColor: Colors.green.shade50,
      shape: StadiumBorder(
        side: BorderSide(color: Colors.green.shade200, width: 1.0),
      ),
    );
  }

  Widget _buildUploadingIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: math.min(80, MediaQuery.of(context).size.width * 0.2),
            height: math.min(80, MediaQuery.of(context).size.width * 0.2),
            child: _buildCustomLoadingAnimation(),
          ),
          const SizedBox(height: 8),
          const Text(
            'AIが解析中です...',
            style: TextStyle(
              color: Colors.blue,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
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
