
# SessionMUSE フロントエンド詳細設計書


## 1. はじめに
フロントエンドアプリケーションの詳細な設計を定義するものです。


## 2. 設計方針
 * フレームワーク: Next.js (App Router) を採用します。サーバーコンポーネントとクライアントコンポーネントを適切に使い分けることで、初期表示速度の最適化とインタラクティブ性の高いUIを両立させます。
 * UI構成: 要件にある全ての機能を単一ページに集約したシングルページアプリケーション (SPA) として構築します。これにより、ユーザーは画面遷移なく直感的に操作できます。
 * 状態管理: コンポーネントの局所的な状態はReactの `useState` フックで管理します。複数のコンポーネント間で共有する必要のある状態（例: 音声解析結果、AIとの対話履歴など）については、React Context API と `useReducer` を組み合わせて管理し、シンプルで見通しの良い状態管理を目指します。
 * スタイリング: Tailwind CSSを利用し、コンポーネント単位でのスタイリングとグローバルなデザインシステムの一貫性を確保します。
 * 型定義: TypeScript を全面的に採用し、型安全性を高め、開発効率とメンテナンス性を向上させます。


## 3. ディレクトリ構成
Next.js (App Router) の標準的な構成に準拠し、責務に応じて以下のディレクトリ構成とします。
```text
/src
├── app/
│   ├── page.tsx               # メインページのUIコンポーネント
│   ├── layout.tsx             # ルートレイアウト
│   └── globals.css            # グローバルCSS
├── components/                # 再利用可能なUIコンポーネント
│   ├── AudioUploader.tsx      # 音声ファイルアップロード機能
│   ├── AnalysisResult.tsx     # 音声解析結果表示
│   ├── PlaybackControl.tsx    # バッキングトラック再生・ダウンロード
│   └── ChatWindow.tsx         # AIとのチャットUI
├── contexts/                  # 状態管理用のContext
│   └── AppContext.tsx         # アプリケーション全体の状態を管理
├── lib/
│   └── api.ts                 # バックエンドAPIとの通信処理
└── types/
    └── index.ts               # アプリケーション全体で使用する型定義
```


## 4. 画面・コンポーネント設計
### 4.1. 画面レイアウト（ワイヤーフレーム）
画面は大きく3つのエリアに分割します。
```
+------------------------------------------------------+
| SessionMUSE - Your AI Music Partner                  |  (Header)
+------------------------------------------------------+
|                                                      |
| [Left Pane]                                          |  (Main Content)
| +--------------------------------------------------+ |
| | 🎵 音声ファイルをアップロード                    | |
| | [ ドラッグ＆ドロップ or ファイルを選択 ]           | |  <AudioUploader />
| | <ProgressBar />                                  | |
| +--------------------------------------------------+ |
| |                                                  | |
| | 📊 解析結果                                      | |
| |   - Key:  [ C Major ]                            | |  <AnalysisResult />
| |   - BPM:  [ 120 ]                                | |
| |   - Chords: [ C | G | Am | F ]                    | |
| |   - Genre by AI: [ Rock ]                        | |
| +--------------------------------------------------+ |
| |                                                  | |
| | 🎧 バッキングトラック                            | |
| |  [ ▶ Play ] [ ■ Stop ] [ 🔊 Volume ] [↓ Download] | |  <PlaybackControl />
| +--------------------------------------------------+ |
|                                                      |
+------------------------------------------------------+
|                                                      |
| [Right Pane]                                         |  (Chat Area)
| | 🤖 AI とのチャット                               | |
| | +----------------------------------------------+ | |
| | | AI: こんにちは！どんな曲にしましょうか？     | | |
| | | User: この曲に合う歌詞のテーマを考えて...    | | |  <ChatWindow />
| | | AI: ...                                      | | |
| | +----------------------------------------------+ | |
| | | [ メッセージを入力...                  ] [送信] | |
| +--------------------------------------------------+ |
|                                                      |
+------------------------------------------------------+
```


### 4.2. コンポーネント詳細
| コンポーネント名 | Props (入力) | State (内部状態) | 責務 |
|---|---|---|---|
| AudioUploader.tsx | onUploadSuccess: (fileId: string) => void<br>onUploadError: (error: Error) => void | isUploading: boolean<br>uploadProgress: number<br>errorMessage: string \| null | 音声ファイルのアップロード処理、進捗表示、エラーハンドリング |
| AnalysisResult.tsx | analysis: { key: string, bpm: number, chords: string[], genre_by_ai: string } \| null<br>isLoading: boolean | - | 音声解析結果の表示 |
| PlaybackControl.tsx | trackUrl: string \| null<br>isLoading: boolean | isPlaying: boolean | バッキングトラックの再生、停止、音量調整、ダウンロード機能 |
| ChatWindow.tsx | analysisContext: { key: string, bpm: number, chords: string[], genre_by_ai: string } \| null | messages: Array<{ role: 'user' \| 'assistant', content: string }><br>isLoading: boolean<br>userInput: string | AIとの対話インターフェース、メッセージ送受信、履歴表示 |


## 5. 状態管理設計 (AppContext.tsx)
アプリケーション全体で共有する状態は `AppContext` で一元管理します。


### 5.1. 管理する状態 (State)
```typescript
interface AppState {
  // UI制御
  isProcessing: boolean; // 音声解析・バッキング生成中のフラグ
  isChatting: boolean;   // チャット応答待ちのフラグ
  errorMessage: string | null; // バックエンドからのエラーメッセージを保持

  // データ
  uploadedFileId: string | null;
  analysisResult: {
    key: string;
    bpm: number;
    chords: string[];
    genre_by_ai: string; // AIによって推定されたジャンル
  } | null;
  backingTrackUrl: string | null; // バックエンドから提供される署名付きURL
  chatHistory: Array<{
    role: 'user' | 'assistant';
    content: string;
  }>;
}
```


### 5.2. 更新処理 (Reducer Actions)
`useReducer` を用いて、以下のActionで状態を更新します。
 * `START_PROCESSING`: 音声処理開始
 * `PROCESS_SUCCESS`: 音声処理成功（解析結果とトラックURLをセット）
 * `PROCESS_ERROR`: 音声処理失敗 (エラーメッセージをセット)
 * `SEND_MESSAGE`: チャットメッセージ送信
 * `RECEIVE_CHAT_RESPONSE`: チャット応答受信
 * `CHAT_ERROR`: チャットエラー (エラーメッセージをセット)
 * `CLEAR_ERROR`: エラーメッセージクリア


## 6. API連携設計 (lib/api.ts)
フロントエンドは以下のAPIエンドポイントと通信します。非同期処理には `async/await` と `fetch` API を使用します。


### 6.1. 音声処理API
 * エンドポイント: `POST /api/process`
 * 説明: 音声ファイルのアップロード、解析、バッキングトラック生成を一つのエンドポイントで処理します。
 * リクエスト:
   * Content-Type: `multipart/form-data`
   * Body:
     * `file`: 音声ファイルデータ
 * レスポンス (成功時 200 OK):
   ```json
   {
     "analysis": {
       "key": "C Major",
       "bpm": 120,
       "chords": ["C", "G", "Am", "F"],
       "genre_by_ai": "rock"
     },
     "backing_track_url": "https://storage.googleapis.com/your-bucket/generated_audio/track_id.mp3?Signature=XXX&Expires=YYY",
     "original_file_url": "https://storage.googleapis.com/your-bucket/original_audio/file_id.mp3?Signature=XXX&Expires=YYY" // フロントエンドではこのURLを直接は利用しない
   }
   ```
 * レスポンス (失敗時 4xx/5xx):
   ```json
   {
     "error": {
       "code": "ERROR_CODE_ENUM",
       "message": "人が読んで理解できるエラーメッセージ",
       "detail": "（オプション）エラーに関する追加の詳細情報やデバッグ情報"
     }
   }
   ```


### 6.2. AIチャットAPI
 * エンドポイント: `POST /api/chat`
 * 説明: 現在のチャット履歴と音楽的文脈を送信し、AIからの応答を取得します。
 * リクエスト:
   * Content-Type: `application/json`
   * Body:
     ```json
     {
       "messages": [
         { "role": "user", "content": "この曲に合う歌詞のテーマを考えて" }
         // ...過去の対話履歴
       ],
       "analysis_context": { // AIが音楽的文脈を理解するために付与
         "key": "C Major",
         "bpm": 120,
         "chords": ["C", "G", "Am", "F"],
         "genre_by_ai": "rock"
       }
     }
     ```
 * レスポンス (成功時 200 OK):
   * バックエンドがストリーミングに対応している場合、`text/event-stream` で逐次的にテキストを返却。フロントエンドはこれを受けてタイプライターのように表示します。
   * ストリーミング非対応の場合は、完成したテキストをJSONで返却します。
     ```json
     {
       "role": "assistant",
       "content": "切ない別れのシーンや、新しい旅立ちの希望をテーマにするのはいかがでしょうか？"
     }
     ```
 * レスポンス (失敗時 4xx/5xx):
   ```json
   {
     "error": {
       "code": "ERROR_CODE_ENUM",
       "message": "人が読んで理解できるエラーメッセージ",
       "detail": "（オプション）エラーに関する追加の詳細情報やデバッグ情報"
     }
   }
   ```


## 7. エラーハンドリング
 * API通信エラー: `fetch` の `catch` 節でネットワークエラー等を捕捉します。APIが返すエラーステータスコード（4xx, 5xx）もハンドリングし、バックエンドから返却される構造化されたエラーレスポンス (`ErrorResponse` モデル形式) をパースします。パースしたエラーオブジェクトから `message` プロパティを抽出し、`AppContext` の `errorMessage` に内容をセットします。必要に応じて `code` や `detail` もログ出力などに活用します。
 * UIでの表示: `errorMessage` が存在する場合、画面上部にトーストやアラートコンポーネントを表示し、ユーザーに問題を通知します。一定時間経過後、またはユーザー操作によって非表示にできるようにします。
 * ファイルアップロード制限: ファイルサイズが上限（100MB）を超える場合や、対応していないファイル形式（MP3, WAV以外）が選択された場合は、APIリクエスト前にクライアントサイドでバリデーションを行い、即座にフィードバックします。
