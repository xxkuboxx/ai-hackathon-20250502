# Session MUSE - AI Music Partner

🎵 Your AI Music Partner - AIと一緒に音楽を作るプラットフォーム

![SessionMUSE Demo](https://raw.githubusercontent.com/xxkuboxx/ai-hackathon-20250502/main/screenshot/iOS/screenshot1-part.PNG)

## 🎯 概要

Session MUSEは、鼻歌や楽器演奏をAIが解析し、リアルタイムでバッキングトラックを生成するAI音楽パートナーです。第2回 AI Agent Hackathon with Google Cloudで開発されました。

### 主な機能
- 🎤 **音声録音・解析**: 鼻歌や楽器演奏をリアルタイム録音
- 🤖 **AI音楽解析**: キー、BPM、コード進行、ジャンルを自動検出
- 🎵 **伴奏自動生成**: 解析結果に基づいてAIが伴奏トラックを生成
- 💬 **AIチャット**: 音楽についてAIと相談・アドバイス取得

## 🏗️ アーキテクチャ

```
📱 Flutter App (Frontend)
    ↓ 音声アップロード
☁️  Cloud Run (Backend - FastAPI)
    ↓ AI処理
🧠 Vertex AI (Gemini 2.5 Flash Lite Preview)
    ↓ 楽曲生成
🎵 MusicXML → MIDI → MP3
```

### 技術スタック
- **Frontend**: Flutter (クロスプラットフォーム対応)
- **Backend**: FastAPI + LangGraph (Cloud Run)
- **AI**: Gemini 2.5 Flash Lite Preview (Vertex AI)
- **Infrastructure**: Google Cloud Platform + Terraform

## 📱 Android APK

ビルド済みのAndroid APKファイルをすぐにお試しいただけます：

- [**SessionMUSE-release.apk**](build/android/SessionMUSE-release.apk) (23.5MB) - リリース版

### インストール方法
1. 上記リンクからAPKファイルをダウンロード
2. Android設定 > セキュリティで「不明なソース」を有効化
3. ダウンロードしたAPKファイルをタップしてインストール

## 🚀 クイックスタート

### Frontend (Flutter App)
```bash
cd frontend/flutter_application
flutter pub get
flutter run
```

### Backend (FastAPI)
```bash
cd backend
pip install -r requirements.txt
uvicorn main:app --reload
```

詳細なセットアップ手順は各ディレクトリのREADMEを参照してください。

## 📁 プロジェクト構成

```
├── frontend/flutter_application/  # Flutterアプリ
├── backend/                      # FastAPIバックエンド
├── infrastructure/               # Terraformインフラ設定
├── story.md                     # 開発ストーリー
└── SECURITY.md                  # セキュリティガイドライン
```

## 🏆 ハッカソン成果

- **Gemini 2.5 Flash Lite Preview活用**: 鼻歌から直接楽曲制作するAIを実現
- **堅牢なアーキテクチャ**: Cloud RunとLangGraphによるサーバーレス・ワークフロー駆動型設計
- **クロスプラットフォーム**: Flutter による高効率なマルチプラットフォーム対応

## 📖 詳細ドキュメント

- [📱 Flutter App Documentation](frontend/flutter_application/README.md)
- [🔧 Backend API Documentation](backend/README.md)
- [📚 Development Story](story.md)
- [🔒 Security Guidelines](SECURITY.md)


## 📄 ライセンス

このプロジェクトはMITライセンスの下で公開されています。

---

**もう、曲作りで孤独じゃない。**