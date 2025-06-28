# SessionMUSE - Flutter Application

🎵 Your AI Music Partner - AIと一緒に音楽を作るFlutterアプリケーション

## 📱 アプリ概要

SessionMUSEは、ユーザーの鼻歌や楽器演奏を録音・解析し、AIが伴奏を生成してくれる革新的な音楽アプリです。

### 主な機能
- 🎤 **音声録音・解析**: 鼻歌や楽器演奏をリアルタイム録音
- 🤖 **AI音楽解析**: キー、BPM、コード進行、ジャンルを自動検出
- 🎵 **伴奏自動生成**: 解析結果に基づいてAIが伴奏トラックを生成
- 💬 **AIチャット**: 音楽についてAIと相談・アドバイス取得

## 🚀 開発環境セットアップ

### 必要な環境
- Flutter SDK (最新安定版)
- Android Studio / VS Code
- Android SDK (API level 21以上)
- 接続されたAndroid デバイスまたはエミュレータ

### インストール手順
```bash
# 依存関係のインストール
flutter pub get

# アプリのビルド
flutter build apk

# デバッグ実行
flutter run
```

## 🧪 テスト・動作確認

⚠️ **重要**: アプリの動作確認やテストを行う際は、必ず **[TESTING_GUIDE.md](./TESTING_GUIDE.md)** を参照してください。

### 基本的なテスト手順
```bash
# 1. テスト環境の準備
chmod +x debug_android.sh
./debug_android.sh auto-detect-device

# 2. アプリの起動とスクリーンショット撮影
./debug_android.sh launch

# 3. 録音機能のテスト
./debug_android.sh test-recording

# 4. チャット機能のテスト
./debug_android.sh tap-chat
```

詳細な手順、デバッグ方法、トラブルシューティングについては **[TESTING_GUIDE.md](./TESTING_GUIDE.md)** をご確認ください。

## 🏗️ プロジェクト構成

```
lib/
├── main.dart                    # メインアプリケーション
├── file_operations_io.dart      # ファイル操作（モバイル）
├── file_operations_web.dart     # ファイル操作（Web）
├── web_audio_recorder.dart      # Web音声録音
├── web_audio_recorder_web.dart  # Web録音実装
└── web_audio_recorder_stub.dart # Web録音スタブ

debug_android.sh                 # テスト自動化スクリプト
device_profiles.json            # デバイス設定ファイル
TESTING_GUIDE.md               # テスト実行ガイド（必読）
```

## 🎨 UI構成とアーキテクチャ

### メインクラス構成
- **`MyApp`**: アプリケーションルート - MaterialAppでアプリ全体のテーマとタイトルを設定
- **`MyHomePage`**: メイン画面 - 録音、解析、チャット機能を統合したStatefulWidget

### 主要UI機能
- **🎙️ 録音UI**: プラットフォーム対応（Web/モバイル）音声録音インターフェース
  - リアルタイム波形表示（`audio_waveforms`パッケージ使用）
  - 録音状態表示（待機/録音中/アップロード中）
  - プログレスアニメーション
- **📊 解析結果表示**: AI解析結果の可視化
  - キー、BPM、コード進行、ジャンル表示
  - バッキングトラック再生コントロール
- **💬 AIチャット**: スライドアップチャットインターフェース
  - Markdown対応メッセージ表示
  - リアルタイムローディングアニメーション
  - 音楽に関するAI相談機能

### データモデル
- **`AudioAnalysisResult`**: API解析結果格納
- **`ChatMessageModel`**: チャットメッセージ管理
- **`RecordingState`**: 録音状態管理（enum）

### プラットフォーム対応
- **Web環境**: WebAudioRecorder、ブラウザベース録音
- **モバイル環境**: RecorderController、ネイティブ録音
- **クロスプラットフォーム**: `kIsWeb`フラグによる動的分岐

### アニメーション・UX
- TickerProviderMixin使用の複数アニメーションコントローラー
- ローディング状態の視覚的フィードバック
- スムーズな画面遷移とスクロール制御

## 📋 UI構成要素とカード詳細

### 🎨 メインUIカード構成

#### 1. **説明セクションカード** (`_buildExplanationSection()`)
- **目的**: アプリの価値提案とオンボーディング
- **デザイン**: パープル→ブルーグラデーション、角丸16px
- **コンテンツ**: 
  - キャッチコピー「🎵 もう、曲作りで孤独じゃない」
  - 課題解決フロー（アイデア → 行き詰まり → 解決）の視覚化
  - 3ステップソリューション（録音 → AI解析 → 一緒に演奏）
- **機能**: 静的な情報表示、ユーザーのアプリ理解促進

#### 2. **録音セクションカード** (`_buildRecordingSection()`)
- **目的**: メイン録音インターフェース
- **デザイン**: シアン→ブルー→インディゴグラデーション、Material影
- **コンテンツ**:
  - ヘッダー「🎙️ 鼻歌を録音」
  - 録音ボタン（状態により色変化：シアン→赤）
  - 再生ボタン（緑：利用可能、オレンジ：再生中、グレー：無効）
- **機能**: 音声録音、再生、状態管理によるビジュアルフィードバック

#### 3. **解析結果カード** (`_buildAnalysisResults()`)
- **目的**: AI音楽解析データの表示
- **デザイン**: ディープパープル→インディゴ→ブルーグラデーション
- **コンテンツ**:
  - ヘッダー「🎵 AI解析結果」
  - 2×2グリッドレイアウト:
    - **キー**: 音楽的調性（例：C Major）
    - **BPM**: テンポ（例：120）
    - **コード**: コード進行（例：C-G-Am）
    - **ジャンル**: 音楽スタイル（例：Rock）
- **機能**: 読み取り専用データ表示、ローディング状態対応

#### 4. **解析チップ** (`_buildAnalysisChip()` / `_buildLoadingChip()`)
- **目的**: 個別音楽データコンテナ
- **デザイン**: 白→グレーグラデーション、微細な影とボーダー
- **コンテンツ**: ラベル、値、対応する音楽アイコン
- **状態**: ローディング（グレー）、データ表示（カラー）

#### 5. **バッキングトラックプレイヤー** (`_buildBackingTrackPlayer()`)
- **目的**: AI生成伴奏再生インターフェース
- **デザイン**: 
  - アクティブ時：オレンジ→アンバー→イエローグラデーション
  - 非アクティブ時：グレーグラデーション
- **コンテンツ**:
  - ヘッダー「🎧 一緒に演奏」
  - 波形ビジュアライザー（モバイルのみ）
  - 再生コントロール
- **機能**: バッキングトラック再生・停止、波形表示

#### 6. **チャットオーバーレイ** (`_buildChatOverlay()`)
- **目的**: AI音楽相談インターフェース
- **デザイン**: フルスクリーンオーバーレイ、パープルテーマ
- **コンテンツ**:
  - タイトル「🎵 セッション相談室」
  - チャットバブルデザイン（ユーザー/AI区別）
  - Markdownサポート
  - ローディングアニメーション
- **機能**: メッセージ送受信、会話履歴スクロール、オーバーレイ開閉

#### 7. **フローティングアクションボタン** (チャット切り替え)
- **目的**: AIチャット機能への主要エントリーポイント
- **デザイン**: 
  - 複合グラデーション（白→パープル→白）
  - 多層影システム
  - 音楽要素を含むアニメーションアイコン
- **コンテンツ**: ハート、音符、星のグラデーションアイコン
- **機能**: チャットオーバーレイの表示切り替え

### 🔧 ヘルパーウィジェット
- **フローステップ** (`_buildFlowStep()`): プロセス視覚化用円形アイコン
- **問題ステップ** (`_buildProblemStep()`): 課題特定用デザイン要素
- **矢印** (`_buildArrow()`): ステップ間の接続要素
- **ローディングアニメーション**: 各種カスタムローディング状態

### 🎯 デザインシステム特徴
- **カラーパレット**: パープル/インディゴ/ブルー/シアン主体、オレンジ/アンバーアクセント
- **デザイン言語**: モダンMaterial Design + グラスモーフィズム要素
- **グラデーション**: 視覚的深度を演出する多色グラデーション
- **影システム**: カード立体感のための多層影
- **タイポグラフィ**: 一貫したフォントウェイトと階層
- **レスポンシブ**: Web/モバイル自動検出と適応機能
- **状態管理**: 全インタラクティブ状態の視覚的フィードバック

## 🛠️ 開発・デバッグ

### UI変更の動作確認 ⭐ **検証済み手順**
UI変更を行った際は以下の手順で必ず動作確認を行ってください：

#### 🔍 **基本チェック**
```bash
# 1. 構文チェック
flutter analyze

# 2. ビルドテスト  
flutter build apk
```

#### 📱 **実機での動作確認（重要：正しい順序で実行）**
```bash
# 3. デバイス検出
./debug_android.sh auto-detect-device

# 4. ビルド → インストール → 起動（この順序が重要！）
./debug_android.sh build     # APKビルド
./debug_android.sh install   # デバイスにインストール ⚠️ 必須
./debug_android.sh launch    # アプリ起動

# 5. 権限付与（初回のみ）
./debug_android.sh permissions

# 6. 動作確認
./debug_android.sh screenshot

# 7. クリーンアップ
./debug_android.sh cleanup
```

#### ⚡ **一括実行（推奨）**
```bash
# デバイス検出
./debug_android.sh auto-detect-device

# ビルド+インストール+起動を一括実行
./debug_android.sh full-debug

# スクリーンショット撮影
./debug_android.sh screenshot

# クリーンアップ
./debug_android.sh cleanup
```

#### ❌ **使用しない方法（Androidターゲット時）**
```bash
# ❌ これらは使わない
flutter run -d android
flutter run -d [DEVICE_ID]
```

⚠️ **重要**: Androidターゲット時は `flutter run` コマンドを使わず、必ず上記の手順に従ってください。
ビルド後のインストールが漏れると、古いバージョンが実行されて変更が反映されません。

詳細は **[TESTING_GUIDE.md](./TESTING_GUIDE.md)** を参照してください。

### デバッグ用ファイル
- `debug_screenshots/`: スクリーンショット保存フォルダ
- `coordinates.json`: UI要素座標（自動生成）
- `ui_dump.xml`: UI階層ダンプ（自動生成）

## 🔧 トラブルシューティング

### よくある問題
1. **録音機能が動作しない**: 権限設定を確認
   ```bash
   ./debug_android.sh permissions
   ```

2. **座標がずれる**: デバイス再検出を実行
   ```bash
   ./debug_android.sh auto-detect-device
   ```

3. **アプリが応答しない**: 強制再起動
   ```bash
   ./debug_android.sh restart
   ```

詳細なトラブルシューティングは **[TESTING_GUIDE.md](./TESTING_GUIDE.md)** をご覧ください。

## 📖 参考資料

- [Flutter公式ドキュメント](https://docs.flutter.dev/)
- [TESTING_GUIDE.md](./TESTING_GUIDE.md) - **動作確認・テスト手順（必読）**
- [ADB_DEBUG_COMMANDS.md](./ADB_DEBUG_COMMANDS.md) - ADBコマンド参考

## 📝 注意事項

- **テスト実行時**: 必ず `TESTING_GUIDE.md` の手順に従ってください
- **Permission問題**: 直接adbコマンドを使わず、`debug_android.sh` スクリプトを使用してください
- **一時ファイル**: テスト後は `./debug_android.sh cleanup` でクリーンアップしてください
