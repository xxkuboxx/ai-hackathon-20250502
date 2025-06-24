
# SessionMUSE フロントエンド詳細設計書


## 1. はじめに
SessionMUSE フロントエンドアプリケーションの詳細な設計を定義するものです。実際のFlutterアプリケーションの実装に合わせて更新しています。


## 2. 設計方針
 * フレームワーク: Flutter を採用。iOS、Android、Webの全プラットフォームで単一コードベースによる開発を実現します。
 * UI構成: 全ての機能を単一ページに統合したシングルページアプリケーション構成。音声録音・解析、結果表示、AIチャット機能をメイン画面に配置し、ユーザーの直感的な操作を可能にします。
 * 状態管理: Flutterの `StatefulWidget` による局所状態管理を基本とし、ウィジェット間の状態共有は `setState` を使用した親子間でのプロパティ受け渡しで管理します。
 * スタイリング: Material Design を基調とし、カスタムテーマカラー（indigo系）を適用。コンポーネント単位でのスタイリングとデザインシステムの一貫性を確保します。
 * クロスプラットフォーム対応: Web/モバイル環境の差異を `dart:io`、`dart:html` の条件付きインポートで解決し、プラットフォーム固有の機能（録音・再生）を適切に分離します。


## 3. ディレクトリ構成
Flutter プロジェクトの標準的な構成に準拠し、責務に応じて以下のディレクトリ構成とします。
```text
/flutter_application
├── lib/
│   ├── main.dart                      # メインアプリケーション・UIコンポーネント
│   ├── web_audio_recorder.dart        # 音声録音インターフェース
│   ├── web_audio_recorder_web.dart    # Web環境用音声録音実装
│   ├── web_audio_recorder_stub.dart   # モバイル環境用スタブ
│   ├── file_operations_io.dart        # モバイル環境用ファイル操作
│   └── file_operations_web.dart       # Web環境用ファイル操作
├── pubspec.yaml                       # 依存関係定義
├── android/                           # Android固有設定
├── ios/                               # iOS固有設定
├── web/                               # Web固有設定・アセット
└── test/                              # テストファイル
    └── widget_test.dart
```


## 4. 画面・コンポーネント設計
### 4.1. 画面レイアウト（ワイヤーフレーム）
画面はメイン部分と、オーバーレイ式のチャットエリアで構成されます。
```
+------------------------------------------------------+
| SessionMUSE - Your AI Music Partner                  |  (AppBar)
+------------------------------------------------------+
|                                                      |
| [Main Content Area]                                  |
| +--------------------------------------------------+ |
| | 🎵 録音                                          | |
| | [ 🎙️ ] 録音開始/停止                           | |  <RecordingSection>
| | [~~~~~~~~ 波形表示エリア ~~~~~~~~]              | |
| +--------------------------------------------------+ |
| |                                                  | |
| | 📊 AIによる解析結果                             | |
| |   - Key:  [ C Major ]                            | |  <AnalysisResults>
| |   - BPM:  [ 120 ]                                | |
| |   - Chords: [ C | G | Am | F ]                    | |
| |   - Genre by AI: [ Rock ]                        | |
| +--------------------------------------------------+ |
| |                                                  | |
| | 🎧 AIにより自動で生成された伴奏                  | |
| | [~~~~~~~~ 波形表示エリア ~~~~~~~~]              | |  <BackingTrackPlayer>
| | [ ▶ Play ] [ ■ Stop ] [↓ Download]               | |
| +--------------------------------------------------+ |
|                                          [AIと相談]   |  FloatingActionButton
+------------------------------------------------------+

[Chat Overlay - 全画面オーバーレイ]
+------------------------------------------------------+
| [✕] 🤖 AI チャット                                 |
+------------------------------------------------------+
| AI: こんにちは！音楽について何でも聞いてください。   |
| User: この曲に合う歌詞のテーマを考えて...            |  <ChatWindow>
| AI: ...                                              |
+------------------------------------------------------+
| [ メッセージを入力...                    ] [送信]    |
+------------------------------------------------------+
```


### 4.2. コンポーネント詳細
実装では単一の `MyHomePage` StatefulWidget 内に全機能を統合しています。

| ウィジェット/機能 | 内部状態 | 責務 |
|---|---|---|
| `_buildRecordingSection()` | `_recordingState: RecordingState`<br>`_audioFilePath: String?` | 音声録音・停止処理、録音状態表示、波形ウィジェット表示 |
| `_buildAnalysisResults()` | `_analysisResult: AudioAnalysisResult?`<br>`_isAnalyzed: bool` | 音声解析結果（Key/BPM/Chords/Genre）の表示 |
| `_buildBackingTrackPlayer()` | `_isPlaying: bool`<br>`_audioFilePath: String?` | 録音された音声の再生・停止、ダウンロード機能 |
| `_buildChatOverlay()` | `_messages: List<ChatMessage>`<br>`_chatHistory: List<ChatMessageModel>`<br>`_isLoadingResponse: bool`<br>`_isChatOpen: bool` | AIとの対話インターフェース、メッセージ送受信、履歴表示、Markdownレンダリング |


## 5. 状態管理設計 (_MyHomePageState)
アプリケーション全体の状態は `MyHomePage` の `StatefulWidget` 内で一元管理します。


### 5.1. 管理する状態 (State)
```dart
class _MyHomePageState extends State<MyHomePage> {
  // UI制御
  RecordingState _recordingState = RecordingState.idle;  // 録音状態（idle/recording/uploading）
  bool _isAnalyzed = false;                              // 解析完了フラグ
  bool _isPlaying = false;                               // 音声再生状態
  bool _isChatOpen = false;                              // チャット画面表示フラグ
  bool _isLoadingResponse = false;                       // AIチャット応答待ちフラグ

  // データ
  String? _audioFilePath;                                // 録音ファイルパス
  AudioAnalysisResult? _analysisResult;                  // 音声解析結果
  final List<ChatMessage> _messages = [];                // チャット表示用メッセージ
  final List<ChatMessageModel> _chatHistory = [];        // APIチャット履歴

  // 音声処理用コントローラー
  RecorderController? _recorderController;               // モバイル用録音
  PlayerController? playerController;                    // モバイル用再生
  WebAudioRecorder? _webAudioRecorder;                  // Web用録音・再生
}
```


### 5.2. 更新処理
`setState()` メソッドで状態を更新します。主要な状態更新タイミング：
 * `_handleRecordingButtonPress()`: 録音開始・停止時の状態更新
 * `_uploadAndAnalyze()`: 音声解析完了時の結果設定
 * `_sendMessage()`: チャットメッセージ送信・受信時の状態更新
 * `_togglePlayback()`: 音声再生・停止時の状態更新
 * `_toggleChat()`: チャット画面表示・非表示の切り替え


## 6. API連携設計 (AudioProcessingService)
フロントエンドは以下のAPIエンドポイントと通信します。非同期処理には Dart の `http` パッケージを使用します。

### 6.0. 基本設定
```dart
class AudioProcessingService {
  static const String baseUrl = 'https://sessionmuse-backend-469350304561.us-east5.run.app';
  // ...
}
```


### 6.1. 音声処理API
 * エンドポイント: `POST /api/process`
 * 説明: 音声ファイルのアップロード、解析を一つのエンドポイントで処理します。
 * 実装: `uploadAndProcess()` メソッド
 * リクエスト:
   * Content-Type: `multipart/form-data`
   * Body:
     * `file`: 音声ファイルデータ（モバイル：ファイルパス、Web：Uint8Listデータ）
 * レスポンス (成功時 200 OK):
   ```json
   {
     "key": "C Major",
     "bpm": 120,
     "chords": "C | G | Am | F",
     "genre": "Rock",
     "backing_track_url": "https://storage.googleapis.com/..." // オプション
   }
   ```
 * データモデル:
   ```dart
   class AudioAnalysisResult {
     final String key;
     final int bpm;
     final String chords;
     final String genre;
     final String? backingTrackUrl;
   }
   ```


### 6.2. AIチャットAPI
 * エンドポイント: `POST /api/chat`
 * 説明: 現在のチャット履歴と音楽的文脈を送信し、AIからの応答を取得します。
 * 実装: `sendChatMessage()` メソッド
 * リクエスト:
   * Content-Type: `application/json`
   * Body:
     ```json
     {
       "messages": [
         { "role": "user", "content": "この曲に合う歌詞のテーマを考えて" }
         // ...過去の対話履歴
       ],
       "analysis_context": { // AIが音楽的文脈を理解するために付与（オプション）
         "key": "C Major",
         "bpm": 120,
         "chords": "C | G | Am | F",
         "genre": "Rock"
       }
     }
     ```
 * レスポンス (成功時 200 OK):
     ```json
     {
       "content": "切ない別れのシーンや、新しい旅立ちの希望をテーマにするのはいかがでしょうか？"
     }
     ```
 * データモデル:
   ```dart
   class ChatMessageModel {
     final String role;  // 'user' | 'assistant'
     final String content;
   }
   ```


## 7. エラーハンドリング
 * API通信エラー: `http` パッケージの例外処理で通信エラーを捕捉します。APIが返すエラーステータスコード（4xx, 5xx）もハンドリングし、エラー種別に応じて適切なメッセージを表示します。
 * UIでの表示: エラーが発生した場合、`ScaffoldMessenger.of(context).showSnackBar()` を使用してSnackBarでユーザーに通知します。
 * 特殊エラーハンドリング:
   * CORS/ネットワークエラー: Web環境でのブラウザセキュリティ制限
   * SocketException/TimeoutException: ネットワーク接続問題
   * 音声ファイル関連: ファイル存在確認、サイズチェック、権限問題
 * ログ出力: デバッグモード（`kDebugMode`）でのみ詳細ログを出力

## 8. プラットフォーム固有実装
### 8.1. 音声録音・再生
 * **モバイル環境**: `audio_waveforms` パッケージの `RecorderController` / `PlayerController` を使用
 * **Web環境**: 独自実装の `WebAudioRecorder` クラスでブラウザのMedia Recorder APIを使用
 * **条件付きインポート**: `dart.library.html` / `dart.library.io` での環境判定

### 8.2. ファイル操作
 * **モバイル環境**: `dart:io` の `File` クラスで実ファイル操作
 * **Web環境**: メモリ上の `Map<String, Uint8List>` でファイルデータ管理
 * **HTTP アップロード**: 両環境で `http.MultipartFile` を使用、データ供給方法を分岐

## 9. 依存関係 (pubspec.yaml)
```yaml
dependencies:
  flutter: sdk: flutter
  cupertino_icons: ^1.0.8
  audio_waveforms: ^1.3.0      # 音声録音・再生・波形表示
  path_provider: ^2.1.2        # ファイルパス取得
  http: ^1.1.0                 # HTTP通信
  flutter_markdown: ^0.6.22    # Markdownレンダリング
```
