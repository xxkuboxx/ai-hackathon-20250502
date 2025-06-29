# AI Hackathon with Google Cloud 受賞作品分析

## 第1回 AI Hackathon with Google Cloud (2024年8月1日〜9月23日)

### 開催概要
- **主催**: Devpost
- **スポンサー**: Google Cloud Japan  
- **応募数**: 400作品以上
- **期間**: 2024年8月1日〜9月23日

### 🥇 優勝作品: Vision Bridge
- **開発者**: 林昱廷 (Lin Yu-Ting)
- **概要**: 詳細情報は限定的だが、革新的なビジョン関連のアプリケーション
- **評価ポイント**: 技術的革新性と実用性

### 🥈 準優勝作品: PersonalityAI as a Service
- **開発者**: 阿部友和 (Abe Tomokazu)
- **概要**: 人間の性格・人格を再現するAIサービス
- **主要機能**:
  - チャット機能
  - 会議シミュレーション
  - 調査研究機能
- **技術スタック**: Google Cloud + Gemini
- **将来計画**: SNS連携、メタバース応用、人間理解の拡張

### 🥉 第3位作品: Mini Chef
- **開発者**: 市原大暉 (Ichihara Daiki)
- **概要**: 子供向けAI料理アプリ「冷蔵庫の中身からレシピ提案」
- **主要機能**:
  - 冷蔵庫の中身に基づくレシピ推薦
  - 子供のスキルレベルに応じたレシピ調整
  - 食品ロス削減
  - 健康的な食事教育
- **コンセプト**: "The AI recipe app making cooking fun for kids!"

### 特別賞
- **Best of Media賞**
- **Best of Retail賞** 
- **Best of SDGs賞**
- **Best of Entertainment賞**
- **Tech Deep Dive賞**
- **Moonshot賞**

## 第1回 AI Agent Hackathon with Google Cloud (2024年12月19日〜2025年2月10日)

### 開催概要
- **主催**: Zenn (Classmethod Inc.)
- **スポンサー**: Google Cloud Japan
- **総賞金**: ¥1,750,000
- **応募数**: 139作品
- **参加者**: 500名以上のエンジニア

### 🥇 最優秀賞: eCoino（イーコイノ）
- **開発チーム**: クニエ（株式会社クニエ）コンサルタント3名
  - 飯田昌司（シニアマネージャー・SCM/S&OP担当）
  - 栗原直樹（マネージャー・流通・小売担当）
  - 池田麟太郎（シニアコンサルタント・SCM/S&OP担当）

#### 作品詳細
- **解決課題**: サプライチェーンにおける「計画と現実のギャップ」の迅速修正
- **具体例**: 「令和の米騒動」のような急な需要変動への対応
- **ユーザー価値**: 
  - 既存ツールにない計画立案機能
  - マスタ情報設定の自動化
  - AIからの能動的な計画提案

#### 技術アーキテクチャ
- **AI基盤**: Vertex AI（Geminiモデル） + LangChain
- **データ管理**: Google Drive → Cloud Functions → dbt → BigQuery
- **UI**: Streamlit（対話型インターフェース）
- **分析エンジン**: DuckDB（ローカルOLAP演算）
- **ファシリテーションAgent**: 複数LLMによる決定論的・非決定論的アルゴリズム切り替え

#### 評価ポイント
- スケーラブルで運用しやすいアーキテクチャ
- 実際のビジネス課題への具体的ソリューション
- 現場のフィードバックに基づく実用性

### 🏆 特別賞受賞作品

#### Tech Deep Dive賞: ココいく
- **開発者**: 株式会社キカガク tetsuro_b氏
- **評価ポイント**: 洗練されたアーキテクチャと独創的アプローチ

#### Moonshot賞受賞作品

**1. CodeBlossom**
- **開発チーム**: 福永圭佑氏、Masataka Nakazawa氏、Riku Yanagawa氏、依田侑也氏
- **概要**: 大量コードデータから仕様書・テストケース生成ツール
- **技術特徴**: Gemini（大規模Token処理）とClaude（高精度）の切り替え機能

**2. Menu Bite**
- **概要**: 飲食店メニュー選択・注文プロセス革新AIエージェント
- **評価ポイント**: 従来概念を覆す大胆な発想

#### Firebase賞: BLOOMS
- **評価ポイント**: Firebaseの効果的活用と優れたユーザー体験
- **技術特徴**: Firebaseの可能性を最大限活用

#### Flutter賞: AI StoryTeller
- **評価ポイント**: 美しいUI/UXと高パフォーマンスの両立
- **技術特徴**: ユーザーフレンドリーで洗練されたデザイン

## 受賞作品の共通成功パターン

### 1. 技術アーキテクチャの特徴
- **Google Cloudサービスの複合活用**: Cloud Run + Firebase + BigQuery
- **スケーラブル設計**: サーバーレス・イベント駆動型
- **AI技術の効果的活用**: Gemini + LangChainの組み合わせ
- **明確なアーキテクチャ設計**: 拡張性・保守性を重視

### 2. 問題解決アプローチ
- **明確な課題設定**: 具体的なユーザーペイン
- **実用性重視**: 現場での実証・フィードバック
- **社会的インパクト**: SDGs、業務効率化、教育など
- **革新性**: 従来手法の根本的改善

### 3. 実装・完成度
- **動作するプロトタイプ**: デモ可能な実装
- **ユーザー体験**: 直感的なUI/UX
- **技術的深度**: 高度なAI機能の実装
- **将来性**: 拡張計画・ビジネス展開の明確化

### 4. プレゼンテーション・ストーリー
- **問題の普遍性**: 多くの人が共感できる課題
- **解決策の独創性**: ユニークなアプローチ
- **技術的説明**: アーキテクチャの明確な説明
- **社会的価値**: インパクトの定量化


## 📚 参考資料・情報源

### 公式情報
- [第2回 AI Agent Hackathon with Google Cloud](https://zenn.dev/hackathons/google-cloud-japan-ai-hackathon-vol2)
- [第1回 AI Agent Hackathon with Google Cloud](https://zenn.dev/hackathons/2024-google-cloud-japan-ai-hackathon)
- [AI ハッカソンで生まれた革新的なアプリたち | Google Cloud 公式ブログ](https://cloud.google.com/blog/ja/products/ai-machine-learning/innovative-apps-from-the-ai-hackathon?hl=ja)

### 受賞作品情報
- [eCoino最優秀賞受賞 | クニエ公式発表](https://www.qunie.com/release/20250325/)
- [想定外のズレをすぐに取り戻す！対話型AIシステム eCoino](https://zenn.dev/nayus/articles/45d29a213c4213)
- [AI Agent Hackathon に見る、現場発の AI エージェント開発！| Google Gemini Note](https://note.com/google_gemini/n/n6e700848017c)

### 特別賞・その他受賞作品
- [Zenn AI Agent Hackathon 受賞！AI を活用した３つの受賞戦略を大公開！](https://zenn.dev/kikagaku/articles/d2876e8e2e50a5)
- [第2回 AI Agent Hackathon with Google Cloudに向けて～第1回の振り返りと成功のヒント～](https://zenn.dev/taku_sid/articles/20250403_ai_hackathon_review)

### 2024年ハッカソン（Devpost主催）
- [AI Hackathon with Google Cloud : Google Cloud と AI で、あなたのアイデアをカタチに - Devpost](https://googlecloudjapanaihackathon.devpost.com/project-gallery)

### ハッカソン参加者の体験記
- [AI Hackathon with Google Cloud で入賞した話 ~概要編~](https://belonginc.dev/members/ttyfky/posts/ai-hackathon-with-google-cloud-2024-pt1)
- [Zenn AI Agent Hackathon with Google Cloud ハッカソン参加メモ📝](https://zenn.dev/manase/scraps/eb975ed64ad34b)

### 企業・組織情報
- [ZennでGoogle Cloudのマーケティングを支援。139もの作品を生んだオーダーメイド型ハッカソンを開催｜クラスメソッド](https://classmethod.jp/cases/google-cloud-japan-ai-hackathon/)
- [クニエのコンサルタントが参画したチームがAI Agent Hackathon with Google Cloudで最優秀賞を受賞 | AXIS Business Insight](https://insight.axc.ne.jp/article/consulnews/4303/)

### 審査・評価関連
- [第2回ハッカソン審査基準](https://zenn.dev/hackathons/google-cloud-japan-ai-hackathon-vol2?tab=rule)
- [第2回ハッカソン審査員情報](https://zenn.dev/hackathons/google-cloud-japan-ai-hackathon-vol2?tab=judge)
- [第2回ハッカソン賞金・賞品詳細](https://zenn.dev/hackathons/google-cloud-japan-ai-hackathon-vol2?tab=prize)
- [第2回ハッカソンFAQ](https://zenn.dev/hackathons/google-cloud-japan-ai-hackathon-vol2?tab=faq)

**調査実施日**: 2025年6月28日  
**情報の正確性**: 公式発表および受賞者自身の記事に基づく