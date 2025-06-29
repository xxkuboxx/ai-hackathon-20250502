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

## 🚀 クイックスタート

### 🌐 Google Chrome版

以下のURLからすぐにお試しいただけます：
- https://sessionmuse-frontend-469350304561.us-east5.run.app

### 📱 Android APK版

ビルド済みのAndroid APKファイルもすぐにお試しいただけます：

- [**SessionMUSE-release.apk**](build/android/SessionMUSE-release.apk) (23.5MB) - リリース版

### インストール方法
1. 上記リンクからAPKファイルをダウンロード
2. Android設定 > セキュリティで「不明なソース」を有効化
3. ダウンロードしたAPKファイルをタップしてインストール

## 🎥 デモンストレーション
- https://youtu.be/29eVG9dW0fA

## 🏆 ハッカソン成果

### 🥇 技術革新
- **Gemini 2.5 Flash Lite Preview活用**: 鼻歌から直接楽曲制作するAIを実現
- **堅牢なアーキテクチャ**: Cloud RunとLangGraphによるサーバーレス・ワークフロー駆動型設計
- **クロスプラットフォーム**: Flutter による高効率なマルチプラットフォーム対応

## 📄 ライセンス

このプロジェクトはMITライセンスの下で公開されています。
