import 'package:flutter/material.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_markdown/flutter_markdown.dart';

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

  static Future<AudioAnalysisResult?> uploadAndProcess(String filePath) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/process'),
      );

      // ファイルを添付
      var file = await http.MultipartFile.fromPath('file', filePath);
      request.files.add(file);

      // リクエスト送信
      var response = await request.send();

      if (response.statusCode == 200) {
        var responseBody = await response.stream.bytesToString();
        var jsonData = json.decode(responseBody);

        return AudioAnalysisResult.fromJson(jsonData);
      } else {
        print('API Error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Upload Error: $e');
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

      final response = await http.post(
        Uri.parse('$baseUrl/api/chat'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestBody),
      );

      if (response.statusCode == 200) {
        var jsonData = json.decode(response.body);
        return jsonData['content'];
      } else {
        print('Chat API Error: ${response.statusCode}');
        print('Response body: ${response.body}');
        return null;
      }
    } catch (e) {
      print('Chat Error: $e');
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

class _MyHomePageState extends State<MyHomePage> {
  String? _audioFilePath;
  final RecorderController _recorderController = RecorderController();
  final PlayerController playerController = PlayerController();
  final TextEditingController _messageController = TextEditingController();
  final List<ChatMessage> _messages = [];
  final List<ChatMessageModel> _chatHistory = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLoadingResponse = false;

  // 状態管理
  bool _isAnalyzed = false;
  bool _isPlaying = false;

  // チャット画面の状態管理
  bool _isChatOpen = false;

  // 録音状態管理
  RecordingState _recordingState = RecordingState.idle;

  // 録音データ管理
  List<double> _recordedWaveformData = [];

  // API分析結果
  AudioAnalysisResult? _analysisResult;

  // プレイヤー状態リスナー管理
  bool _playerListenerAdded = false;

  @override
  void initState() {
    super.initState();
    // 初期メッセージを追加
    _messages.add(
      ChatMessage(
        text: "こんにちは！音楽について何でも聞いてください。音声を録音して解析すると、より詳しいアドバイスができます。",
        isUser: false,
      ),
    );

    // チャット履歴にも初期メッセージを追加
    _chatHistory.add(
      ChatMessageModel(
        role: 'assistant',
        content: "こんにちは！音楽について何でも聞いてください。音声を録音して解析すると、より詳しいアドバイスができます。",
      ),
    );

    // 初期状態で解析結果を表示
    _isAnalyzed = true;

    // アプリ起動時に録音権限を取得
    _recorderController.checkPermission();
  }

  @override
  void dispose() {
    super.dispose();
    _recorderController.dispose();
    playerController.dispose();
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
              text: "申し訳ありません。現在AIサービスに接続できません。しばらく後にもう一度お試しください。",
              isUser: false,
            ),
          );
          _isLoadingResponse = false;
        });
      }
    } catch (e) {
      setState(() {
        _messages.add(
          ChatMessage(text: "エラーが発生しました: ${e.toString()}", isUser: false),
        );
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

  Future<String?> _setupRecording() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final outputPath =
          '${directory.path}/recorded_audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

      print('録音開始: $outputPath');

      // RecorderControllerで録音開始
      await _recorderController.record(
        androidEncoder: AndroidEncoder.aac,
        androidOutputFormat: AndroidOutputFormat.mpeg4,
        path: outputPath,
      );

      print('録音が開始されました');
      return outputPath;
    } catch (e) {
      print('録音設定エラー: $e');
      return null;
    }
  }

  Future<void> _uploadAndAnalyze() async {
    if (_audioFilePath == null) {
      print('音声ファイルが存在しません');
      return;
    }

    print('API upload started: $_audioFilePath');

    try {
      final result = await AudioProcessingService.uploadAndProcess(
        _audioFilePath!,
      );

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
      print('Upload error: $e');
      setState(() {
        _recordingState = RecordingState.idle;
      });

      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('アップロードエラーが発生しました'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _togglePlayback() async {
    if (_audioFilePath == null) {
      print('音声ファイルパスがnullです');
      return;
    }

    print('音声ファイルパス: $_audioFilePath');

    // ファイルの存在確認
    final file = File(_audioFilePath!);
    if (!await file.exists()) {
      print('音声ファイルが存在しません: $_audioFilePath');
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

    final fileSize = await file.length();
    print('ファイルサイズ: $fileSize bytes');

    try {
      if (_isPlaying) {
        // 停止
        print('音声再生を停止します');
        await playerController.stopPlayer();
        setState(() {
          _isPlaying = false;
        });
        print('音声再生が停止されました');
      } else {
        // 再生開始前にPlayerControllerをリセット
        print('音声再生を開始します');

        // 既存の再生を完全に停止してリセット
        try {
          await playerController.stopPlayer();
          print('既存の再生を停止しました');
        } catch (e) {
          print('停止時エラー（無視可能）: $e');
        }

        // プレイヤーを準備
        await playerController.preparePlayer(
          path: _audioFilePath!,
          shouldExtractWaveform: true,
        );
        print('プレイヤーの準備が完了しました');

        // リスナーを一度だけ追加
        if (!_playerListenerAdded) {
          playerController.onPlayerStateChanged.listen((state) {
            print('プレイヤー状態変更: \\${state.toString()}');
            if (state.isPaused || state.isStopped) {
              if (mounted) {
                setState(() {
                  _isPlaying = false;
                });
                print('再生状態をfalseに更新しました');
              }
            }
          });
          _playerListenerAdded = true;
          print('プレイヤーリスナーを追加しました');
        }

        // 再生開始
        await playerController.startPlayer();
        setState(() {
          _isPlaying = true;
        });
        print('音声再生が開始されました');
      }
    } catch (e) {
      print('再生エラー: $e');
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
    print('Build called with _recordingState: $_recordingState');
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
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        _buildRecordingSection(),
                        const SizedBox(height: 16),
                        _buildAnalysisResults(),
                        if (_isAnalyzed) const SizedBox(height: 16),
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
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
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
                      : () async {
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
                            print('録音停止中...');
                            final recordedFilePath = await _recorderController
                                .stop();
                            print('録音停止結果: $recordedFilePath');

                            if (recordedFilePath != null) {
                              setState(() {
                                _audioFilePath = recordedFilePath;
                              });
                              print('録音完了: $recordedFilePath');

                              final file = File(recordedFilePath);
                              if (await file.exists()) {
                                final fileSize = await file.length();
                                print('録音ファイルサイズ: $fileSize bytes');
                              } else {
                                print('録音ファイルが存在しません!');
                              }

                              await _uploadAndAnalyze();
                            } else {
                              print('recordedFilePath is null!');
                              setState(() {
                                _recordingState = RecordingState.idle;
                              });
                            }
                            setState(() {
                              _isAnalyzed = true;
                            });
                          }
                        },
                  style: IconButton.styleFrom(
                    backgroundColor: _recordingState == RecordingState.uploading
                        ? Colors.grey.shade200
                        : (_recordingState == RecordingState.recording
                              ? Colors.red.shade100
                              : Colors.blue.shade100),
                    side: BorderSide(
                      color: _recordingState == RecordingState.uploading
                          ? Colors.grey
                          : (_recordingState == RecordingState.recording
                                ? Colors.red.shade300
                                : Colors.blue.shade300),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _recordingState == RecordingState.recording ? '録音中' : '録音開始',
                style: TextStyle(
                  fontSize: 12,
                  color: _recordingState == RecordingState.recording
                      ? Colors.red
                      : Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 60,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(color: Colors.grey.shade300, width: 1.0),
            ),
            child: _recordingState == RecordingState.recording
                ? AudioWaveforms(
                    recorderController: _recorderController,
                    size: Size(MediaQuery.of(context).size.width - 80, 60),
                    waveStyle: const WaveStyle(
                      waveCap: StrokeCap.round,
                      extendWaveform: true,
                      showMiddleLine: false,
                    ),
                  )
                : _recordingState == RecordingState.uploading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cloud_upload, color: Colors.blue, size: 24),
                        SizedBox(height: 8),
                        Text(
                          '音声解析中...',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  )
                : (_recordingState == RecordingState.idle)
                ? const Center(
                    child: Text(
                      '録音を開始すると波形が表示されます',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  )
                : _recordedWaveformData.isNotEmpty
                ? AudioFileWaveforms(
                    playerController: playerController,
                    size: Size(MediaQuery.of(context).size.width - 80, 60),
                    waveformData: _recordedWaveformData,
                    playerWaveStyle: const PlayerWaveStyle(
                      seekLineColor: Colors.blue,
                      showSeekLine: true,
                      waveCap: StrokeCap.round,
                    ),
                    waveformType: WaveformType.fitWidth,
                  )
                : const Center(
                    child: Text(
                      '録音を開始すると波形が表示されます',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildAnalysisResults() {
    if (!_isAnalyzed) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: Colors.green.shade300, width: 2.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.analytics, color: Colors.green, size: 24),
              const SizedBox(width: 8),
              const Text(
                'AIによる解析結果',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildAnalysisRow('Key', _analysisResult?.key ?? 'C Major'),
          _buildAnalysisRow('BPM', _analysisResult?.bpm.toString() ?? '120'),
          _buildAnalysisRow(
            'Chords',
            _analysisResult?.chords ?? 'C | G | Am | F',
          ),
          _buildAnalysisRow('Genre by AI', _analysisResult?.genre ?? 'Rock'),
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
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8.0),
                  border: Border.all(color: Colors.grey.shade300, width: 1.0),
                ),
                child: _audioFilePath != null
                    ? AudioFileWaveforms(
                        playerController: playerController,
                        size: Size(MediaQuery.of(context).size.width - 80, 60),
                        playerWaveStyle: const PlayerWaveStyle(
                          seekLineColor: Colors.orange,
                          showSeekLine: true,
                          waveCap: StrokeCap.round,
                        ),
                        waveformType: WaveformType.fitWidth,
                      )
                    : const Center(
                        child: Text(
                          '録音完了後に波形が表示されます',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
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
                                    '音声ファイルが保存されました: \\${_audioFilePath!.split('/').last}',
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
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.purple.shade300,
                                  ),
                                ),
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
                                  style: const TextStyle(
                                    color: Colors.white,
                                  ),
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

  Widget _buildAnalysisRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '- $label:',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 4.0,
            ),
            decoration: BoxDecoration(
              color: Colors.green.shade100,
              borderRadius: BorderRadius.circular(16.0),
              border: Border.all(color: Colors.green.shade300, width: 1.0),
            ),
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;

  ChatMessage({required this.text, required this.isUser});
}
