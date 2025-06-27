# 🚀 Flutter Android Debug Commands with adb

## 📱 **基本操作**

### アプリ管理
```bash
# APKビルド・インストール
./debug_android.sh build
./debug_android.sh install

# アプリ起動・停止
./debug_android.sh launch
adb shell am force-stop com.example.flutter_application

# アプリ再起動
./debug_android.sh restart

# アプリアンインストール
./debug_android.sh uninstall
```

### 権限管理
```bash
# 必要な権限を一括付与
./debug_android.sh permissions

# 個別権限付与
adb shell pm grant com.example.flutter_application android.permission.RECORD_AUDIO
adb shell pm grant com.example.flutter_application android.permission.CAMERA
adb shell pm grant com.example.flutter_application android.permission.WRITE_EXTERNAL_STORAGE
```

## 🎯 **UI操作・テスト**

### 録音機能テスト
```bash
# 録音ワークフロー自動テスト
./debug_android.sh test-recording

# 手動操作
./debug_android.sh tap-record    # 録音開始
./debug_android.sh stop-record   # 録音停止
```

### チャット機能テスト
```bash
# AIチャット開く
./debug_android.sh tap-chat

# テキスト入力
adb shell input text "こんにちは"

# 送信ボタンタップ (座標は画面に応じて調整)
adb shell input tap 600 1400
```

### 画面操作
```bash
# タップ操作
adb shell input tap X Y

# スワイプ操作
adb shell input swipe X1 Y1 X2 Y2

# テキスト入力
adb shell input text "入力したいテキスト"

# キー入力
adb shell input keyevent KEYCODE_BACK
adb shell input keyevent KEYCODE_HOME
adb shell input keyevent KEYCODE_MENU
```

## 📊 **デバッグ・モニタリング**

### ログ監視
```bash
# Flutterアプリのログのみ表示
./debug_android.sh logs

# 全ログをファイルに保存
adb logcat > debug.log

# 特定のタグでフィルタ
adb logcat -s flutter

# リアルタイムでエラーログを監視
adb logcat | grep -E "(ERROR|FATAL)"
```

### スクリーンショット・録画
```bash
# スクリーンショット
./debug_android.sh screenshot

# 画面録画
./debug_android.sh record

# 特定の時間だけ録画
adb shell screenrecord --time-limit 30 /sdcard/test.mp4
adb pull /sdcard/test.mp4 .
```

### パフォーマンス監視
```bash
# CPU使用率
adb shell top | grep flutter

# メモリ使用量
adb shell dumpsys meminfo com.example.flutter_application

# バッテリー使用状況
adb shell dumpsys batterystats | grep flutter

# ネットワーク使用量
adb shell dumpsys netstats | grep flutter
```

## 🔧 **トラブルシューティング**

### アプリ状態確認
```bash
# アプリが起動中か確認
adb shell ps | grep flutter

# アプリのアクティビティ確認
adb shell dumpsys activity activities | grep flutter

# インストール済みアプリ確認
adb shell pm list packages | grep flutter
```

### デバイス情報
```bash
# 接続済みデバイス一覧
adb devices

# デバイス情報
adb shell getprop ro.product.model
adb shell getprop ro.build.version.release

# 画面解像度
adb shell wm size

# 画面密度
adb shell wm density
```

### キャッシュ・データクリア
```bash
# アプリデータクリア
adb shell pm clear com.example.flutter_application

# キャッシュクリア
adb shell rm -rf /data/data/com.example.flutter_application/cache/*
```

## 🎨 **SessionMUSE特有の操作**

### UI座標 (Pixel 7基準)
```bash
# 録音ボタン
adb shell input tap 106 364

# 再生ボタン
adb shell input tap 544 364

# AIチャットボタン
adb shell input tap 572 1451

# バッキングトラック再生ボタン
adb shell input tap 400 1220
```

### 音楽機能テスト
```bash
# 録音→解析→再生フロー
./debug_android.sh tap-record
sleep 5
./debug_android.sh stop-record
sleep 10  # 解析待機
adb shell input tap 400 1220  # バッキングトラック再生
```

## 🚀 **自動化スクリプト例**

### 完全テストフロー
```bash
#!/bin/bash
echo "🔧 Starting complete test flow..."

./debug_android.sh full-debug
sleep 3

echo "🎵 Testing recording..."
./debug_android.sh test-recording
sleep 10

echo "💬 Testing chat..."
./debug_android.sh tap-chat
sleep 2

echo "📊 Collecting logs..."
./debug_android.sh logs > test_results.log

echo "✅ Test complete!"
```

## 🎯 **正確なUI座標取得とスクリーンショット最適化**

### uiautomatorを使用した正確な座標取得
```bash
# UI階層をダンプ
adb shell uiautomator dump /sdcard/ui_dump.xml && adb pull /sdcard/ui_dump.xml .

# XML内のbounds属性から座標を特定
# 例: bounds="[101,494][223,616]" → 中心座標は (162, 555)
```

### 座標計算方法
```bash
# 左上座標: (x1, y1), 右下座標: (x2, y2)
# 中心座標: ((x1+x2)/2, (y1+y2)/2)
```

### スクリーンショット撮影とJPEG変換（データサイズ削減）
```bash
# 基本的なスクリーンショット撮影
adb shell screencap -p /sdcard/screenshot.png && adb pull /sdcard/screenshot.png .

# JPEG変換（データサイズ削減）
# macOSの場合
sips -s format jpeg -s formatOptions 80 screenshot.png --out screenshot.jpg

# Linuxの場合（ImageMagickが必要）
convert screenshot.png -quality 80 screenshot.jpg
```

### 正確なテスト手順のベストプラクティス
```bash
# 1. 事前状態確認
adb shell screencap -p /sdcard/before.png && adb pull /sdcard/before.png .

# 2. 正確な座標取得
adb shell uiautomator dump /sdcard/ui_dump.xml && adb pull /sdcard/ui_dump.xml .

# 3. 操作実行（例：録音ボタン）
adb shell input tap 162 555

# 4. 結果確認
adb shell screencap -p /sdcard/after.png && adb pull /sdcard/after.png .

# 5. データサイズ最適化
sips -s format jpeg -s formatOptions 80 after.png --out after.jpg
```

## 💡 **Tips**

1. **座標の確認**: `adb shell uiautomator dump` でUI階層から正確な座標を取得
2. **スクリーンショット最適化**: 解析前にJPEGに変換してデータサイズを削減
3. **デバイス固有**: 画面サイズが違う場合はuiautomatorで座標を再取得
4. **権限**: 初回実行時は必ず権限付与を実行
5. **ログ**: 問題発生時は必ずログを確認
6. **連続操作**: 操作間に適切な待機時間を設ける
7. **状態確認**: 操作前後でスクリーンショットを撮影して状態変化を確認