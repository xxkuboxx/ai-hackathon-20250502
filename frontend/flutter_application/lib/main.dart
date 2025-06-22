import 'package:flutter/material.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'dart:math';

// 録音状態を管理するenum
enum RecordingState {
  idle,      // 待機中
  recording, // 録音中
  uploading, // アップロード中
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
  String? _recordedFilePath;
  final RecorderController _recorderController = RecorderController();
  final PlayerController playerController = PlayerController();
  final TextEditingController _messageController = TextEditingController();
  final List<ChatMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();
  
  // 状態管理
  bool _isAnalyzed = false;
  bool _isPlaying = false;
  double _volume = 0.5;
  
  // チャット画面の状態管理
  bool _isChatOpen = false;
  
  // 録音状態管理
  RecordingState _recordingState = RecordingState.idle;
  
  // 録音データ管理
  List<double> _recordedWaveformData = [];

  @override
  void initState() {
    super.initState();
    // 初期メッセージを追加
    _messages.add(ChatMessage(text: "こんにちは！音楽について何でも聞いてください。", isUser: false));

    // 初期状態で解析結果を表示
    _isAnalyzed = true;

    // アプリ起動時に録音権限を取得
    _recorderController.checkPermission();
  }

  @override
  void dispose() {
    super.dispose();
    _recorderController.dispose();
  }

  void _sendMessage() {
    if (_messageController.text.trim().isNotEmpty) {
      setState(() {
        _messages.add(ChatMessage(text: _messageController.text, isUser: true));
        // AIの応答をシミュレート
        _messages.add(
          ChatMessage(text: "ありがとうございます。音楽について詳しく教えてください。", isUser: false),
        );
      });
      _messageController.clear();
      // スクロールを最下部に移動
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
  }

  void _simulateUpload() {
    print('_simulateUpload called: _recordingState = uploading');
    setState(() {
      _recordingState = RecordingState.uploading;
      print('State changed to: uploading');
    });

    // アップロードのシミュレーション（3秒で完了）
    Future.delayed(const Duration(seconds: 3), () {
      setState(() {
        _recordingState = RecordingState.idle;
        print('Upload completed: _recordingState = idle');
      });
      // Toast（SnackBar）表示
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('録音データの送信が完了しました'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    });
  }

  void _togglePlayback() {
    setState(() {
      _isPlaying = !_isPlaying;
    });
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
                        // 録音/停止セクション
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20.0),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8.0),
                            border: Border.all(
                              color: Colors.blue.shade300,
                              width: 1.0,
                            ),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.music_note,
                                    color: Colors.blue,
                                    size: 18,
                                  ),
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
                                            ? Colors.grey // 送信中はグレー
                                            : (_recordingState == RecordingState.recording ? Colors.red : Colors.blue),
                                      ),
                                      onPressed: _recordingState == RecordingState.uploading
                                          ? null
                                          : () async {
                                              if (_recordingState == RecordingState.idle) {
                                                // 録音開始
                                                setState(() {
                                                  _recordingState = RecordingState.recording;
                                                  _isAnalyzed = true;
                                                });
                                                _recorderController.record();
                                              } else {
                                                // 録音停止
                                                setState(() {
                                                  _recordingState = RecordingState.uploading;
                                                });
                                                final recordedFilePath = await _recorderController.stop();
                                                if (recordedFilePath != null) {
                                                  _simulateUpload();
                                                } else {
                                                  print('recordedFilePath is null!');
                                                  _simulateUpload();
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
                                    _recordingState == RecordingState.recording 
                                        ? '録音中' 
                                        : '録音開始',
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
                              // 録音波形表示
                              Container(
                                height: 60,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8.0),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                    width: 1.0,
                                  ),
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
                                                Icon(
                                                  Icons.cloud_upload,
                                                  color: Colors.blue,
                                                  size: 24,
                                                ),
                                                SizedBox(height: 8),
                                                Text(
                                                  '録音データを送信中...',
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
                                                  style: TextStyle(
                                                    color: Colors.grey,
                                                    fontSize: 12,
                                                  ),
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
                                                      style: TextStyle(
                                                        color: Colors.grey,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ),
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // 解析結果
                        if (_isAnalyzed)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20.0),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12.0),
                              border: Border.all(
                                color: Colors.green.shade300,
                                width: 2.0,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.analytics,
                                      color: Colors.green,
                                      size: 24,
                                    ),
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
                                _buildAnalysisRow('Key', 'C Major'),
                                _buildAnalysisRow('BPM', '120'),
                                _buildAnalysisRow('Chords', 'C | G | Am | F'),
                                _buildAnalysisRow('Genre by AI', 'Rock'),
                              ],
                            ),
                          ),

                        if (_isAnalyzed) const SizedBox(height: 16),

                        // バッキングトラック
                        if (_isAnalyzed)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20.0),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12.0),
                              border: Border.all(
                                color: Colors.orange.shade300,
                                width: 2.0,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.headphones,
                                      color: Colors.orange,
                                      size: 24,
                                    ),
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
                                    // 波形表示
                                    Container(
                                      height: 60,
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(8.0),
                                        border: Border.all(
                                          color: Colors.grey.shade300,
                                          width: 1.0,
                                        ),
                                      ),
                                      child: AudioFileWaveforms(
                                        playerController: playerController,
                                        size: Size(MediaQuery.of(context).size.width - 80, 60),
                                        waveformData: _recordedWaveformData,
                                        playerWaveStyle: const PlayerWaveStyle(
                                          seekLineColor: Colors.orange,
                                          showSeekLine: true,
                                          waveCap: StrokeCap.round,
                                        ),
                                        waveformType: WaveformType.fitWidth,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        // Play/Stop ボタン
                                        IconButton(
                                          onPressed: _togglePlayback,
                                          icon: Icon(
                                            _isPlaying
                                                ? Icons.stop
                                                : Icons.play_arrow,
                                            color: Colors.white,
                                          ),
                                          style: IconButton.styleFrom(
                                            backgroundColor: _isPlaying
                                                ? Colors.red
                                                : Colors.green,
                                            padding: const EdgeInsets.all(12),
                                          ),
                                        ),
                                        const SizedBox(width: 16),

                                        // Download ボタン
                                        IconButton(
                                          onPressed: () {
                                            // ダウンロード機能
                                          },
                                          icon: const Icon(
                                            Icons.download,
                                            color: Colors.blue,
                                          ),
                                          style: IconButton.styleFrom(
                                            backgroundColor: Colors.blue.shade50,
                                            padding: const EdgeInsets.all(12),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          // 全画面チャット画面
          if (_isChatOpen)
            Container(
              color: Colors.purple.shade50,
              child: Column(
                children: [
                  // チャットヘッダー
                  Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade100,
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.grey.shade300,
                          width: 1.0,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: _toggleChat,
                          icon: const Icon(Icons.close, color: Colors.purple),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.chat_bubble,
                          color: Colors.purple,
                          size: 24,
                        ),
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

                  // メッセージリスト
                  Expanded(
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16.0),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
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
                                  child: Text(
                                    message.text,
                                    style: TextStyle(
                                      color: message.isUser
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                ),
                              ),
                              if (message.isUser) ...[
                                const SizedBox(width: 8),
                                CircleAvatar(
                                  backgroundColor: Colors.purple.shade400,
                                  child: const Icon(
                                    Icons.person,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  // メッセージ入力エリア
                  Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        top: BorderSide(
                          color: Colors.grey.shade300,
                          width: 1.0,
                        ),
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
                                borderRadius: BorderRadius.all(
                                  Radius.circular(24.0),
                                ),
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
                          onPressed: _sendMessage,
                          icon: const Icon(Icons.send),
                          color: Colors.purple,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.purple.shade100,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _toggleChat,
        backgroundColor: Colors.purple,
        icon: const Icon(Icons.chat_bubble, color: Colors.white),
        label: const Text(
          'AIと相談',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
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
