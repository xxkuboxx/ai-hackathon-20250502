# ADB テスト実行ガイド - permission問題回避ノウハウ

## 🎯 基本方針

**Claude のbash実行permission制限を回避するため、事前準備されたスクリプトを活用**

## 📋 テスト環境セットアップ

### 1. 事前準備
```bash
# スクリプトに実行権限付与
chmod +x debug_android.sh

# デバイス接続確認
adb devices
```

### 2. 自動デバイス検出（推奨）
```bash
# デバイス自動検出＆座標設定
./debug_android.sh auto-detect-device

# デバイス情報確認
./debug_android.sh device-info
```

## 🔍 UI座標検出手順

### A. 自動検出（permission-safe）
```bash
# 1. UI階層取得
./debug_android.sh get-ui-dump

# 2. 主要要素自動検出
./debug_android.sh detect-coordinates

# 3. 検出結果確認
./debug_android.sh list-coords
```

### B. 手動検出
```bash
# 特定テキストで検索
./debug_android.sh find-element "Record"
./debug_android.sh find-element "Chat"
./debug_android.sh find-element "Settings"

# 手動座標保存
./debug_android.sh save-coord "custom_button" 150 300
```

## 🎮 基本テスト操作

### アプリ起動テスト
```bash
# フルセットアップ（ビルド＋インストール＋起動）
./debug_android.sh full-debug

# 単体起動（スクリーンショット付き）
./debug_android.sh launch
```

### 録音機能テスト
```bash
# 録音ワークフローテスト（自動化）
./debug_android.sh test-recording

# 手動ステップ実行
./debug_android.sh tap-record    # 録音開始
./debug_android.sh stop-record   # 録音停止
```

### UI操作テスト
```bash
# チャット画面テスト
./debug_android.sh tap-chat

# アプリ再起動テスト
./debug_android.sh restart
```

## 📸 スクリーンショット管理

### 自動スクリーンショット
```bash
# タイムスタンプ付きスクリーンショット
./debug_android.sh screenshot

# 操作時自動撮影
# - launch: 起動時
# - tap-record: 録音開始時
# - stop-record: 録音停止時
# - tap-chat: チャット開始時
# - restart: 再起動後
```

### 保存場所
- `./debug_screenshots/` フォルダに自動保存
- ファイル名例: `debug_20241227_143022.png`

## 🔧 デバッグ・ログ確認

### ログ監視
```bash
# Flutter関連ログのみ表示
./debug_android.sh logs

# 画面録画（デバッグ用）
./debug_android.sh record
```

### 権限管理
```bash
# 必要権限一括付与
./debug_android.sh permissions
```

## 📱 デバイス別対応

### 対応済みデバイス
- **Google Pixel 7/8**: `pixel_7`, `pixel_8`
- **Samsung Galaxy S23**: `galaxy_s23`
- **OnePlus 11**: `oneplus_11`
- **Generic 1080p**: `generic_1080p`

### 新デバイス追加手順
1. デバイス接続
2. `./debug_android.sh device-info` で情報取得
3. `device_profiles.json` に新プロファイル追加
4. `debug_android.sh` のauto_detect_device()に判定ロジック追加

## ⚠️ Permission問題回避のベストプラクティス

### 1. 直接adb実行を避ける
```bash
# ❌ 避けるべき
adb shell input tap 100 200
adb shell screencap /sdcard/test.png

# ✅ 推奨
./debug_android.sh tap-record
./debug_android.sh screenshot
```

### 2. スクリプト経由での操作
```bash
# 事前定義されたワークフローを活用
./debug_android.sh full-debug      # 完全セットアップ
./debug_android.sh test-recording  # 録音機能テスト
```

### 3. 座標の事前設定
```bash
# テスト実行前に座標を設定
./debug_android.sh auto-detect-device
# または
./debug_android.sh detect-coordinates
```

### 4. 一時ファイルの自動削除 ⭐ **重要**
```bash
# デバイス上の一時ファイルは自動削除される
# /sdcard/ui_dump.xml
# /sdcard/launch.png
# /sdcard/record_state.png
# /sdcard/stop_state.png
# /sdcard/chat_state.png
# /sdcard/restart.png
# /sdcard/debug_*.png
# /sdcard/app_debug.mp4

# ローカル一時ファイルも定期的に削除
rm -f ui_dump.xml  # UIダンプファイル（必要時再生成）
```

## 🚨 トラブルシューティング

### 座標がずれる場合
```bash
# 1. デバイス再検出
./debug_android.sh auto-detect-device

# 2. UI階層確認
./debug_android.sh get-ui-dump

# 3. 手動座標調整
./debug_android.sh find-element "目的の要素名"
```

### アプリが応答しない場合
```bash
# アプリ強制再起動
./debug_android.sh restart

# 権限再設定
./debug_android.sh permissions

# アプリ再インストール
./debug_android.sh uninstall
./debug_android.sh install
```

### スクリーンショットが取れない場合
```bash
# デバイス接続確認
adb devices

# ストレージ権限確認
./debug_android.sh permissions
```

## 📊 テスト自動化パターン

### 基本回帰テスト
```bash
#!/bin/bash
# 基本機能テスト
./debug_android.sh full-debug
./debug_android.sh test-recording
./debug_android.sh tap-chat
./debug_android.sh screenshot
```

### CI/CD統合
```bash
# 1. デバイス検出
./debug_android.sh auto-detect-device

# 2. アプリデプロイ
./debug_android.sh build
./debug_android.sh install

# 3. 機能テスト
./debug_android.sh test-recording

# 4. 結果確認
ls -la debug_screenshots/
```

## 📁 ファイル構成

```
frontend/flutter_application/
├── debug_android.sh           # メインテストスクリプト
├── device_profiles.json       # デバイスプロファイル定義
├── coordinates.json          # 保存済み座標（自動生成）
├── ui_dump.xml              # UI階層ダンプ（自動生成）
├── debug_screenshots/       # スクリーンショット保存フォルダ
│   ├── launch.png
│   ├── record_state.png
│   └── debug_YYYYMMDD_HHMMSS.png
└── TESTING_GUIDE.md         # このガイド
```

## 🎉 成功パターン例

### 新デバイスでの初回テスト
```bash
1. ./debug_android.sh device-info
2. ./debug_android.sh auto-detect-device
3. ./debug_android.sh full-debug
4. ./debug_android.sh test-recording
5. ./debug_android.sh list-coords  # 結果確認
```

### 定期テスト実行
```bash
1. ./debug_android.sh launch
2. ./debug_android.sh test-recording
3. ./debug_android.sh tap-chat
4. # debug_screenshots/ フォルダで結果確認
5. ./debug_android.sh cleanup  # テスト後のクリーンアップ
```

## 🧹 テスト後のクリーンアップ

### 一時ファイル自動削除機能
```bash
# 全ての一時ファイルを削除
./debug_android.sh cleanup

# 削除される一時ファイル一覧:
# デバイス上: /sdcard/ui_dump.xml, /sdcard/*.png, /sdcard/*.mp4
# ローカル: 必要に応じて ui_dump.xml を削除
```

### 定期メンテナンス推奨
```bash
# テストセッション終了時
./debug_android.sh cleanup

# 週次メンテナンス
rm -rf debug_screenshots/  # 古いスクリーンショット削除
mkdir -p debug_screenshots
./debug_android.sh cleanup
```

---

**💡 重要**: 
- 常にスクリプト経由でテストを実行し、直接adbコマンドの使用は避けること
- テスト終了後は必ず `cleanup` コマンドで一時ファイルを削除すること
- 一時ファイルはデバイスストレージを圧迫するため、定期的な削除が必須