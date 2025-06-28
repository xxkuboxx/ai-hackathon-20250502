# SessionMUSE インフラストラクチャ詳細設計書 (UltraThink Edition)


## 1. はじめに


本ドキュメントは、「SessionMUSE」アプリケーションの次世代インフラ構成を定義します。Flutter マルチプラットフォームフロントエンドと、LangGraph + Gemini 2.5 による高度なAI音楽処理バックエンドを、Google Cloud Platform (GCP) 上で最適化・統合したアーキテクチャです。

### 1.1. UltraThink アプローチの特徴
- **マルチモーダル AI 処理**: Gemini 2.5 Flash Lite Preview による音声理解とMusicXML生成
- **ワークフロー駆動**: LangGraph による状態管理と非同期AI処理の制御
- **テーマベース音楽理解**: 従来のパラメータ抽出から人間的な音楽テーマ理解への進化
- **フルスタッククロスプラットフォーム**: Flutter による Web/iOS/Android 統一開発


## 2. UltraThink 全体構成図


SessionMUSE の革新的マルチプラットフォーム + AI 統合アーキテクチャ


```mermaid
graph TD
    subgraph "Client Layer"
        Mobile["📱 Mobile Apps\n(Flutter iOS/Android)\nネイティブアプリ配信"]
        Web["🌐 Web App\n(Flutter Web)\nCloud Run 配信"]
        Desktop["💻 Desktop Apps\n(Flutter Desktop)\nローカル実行"]
    end

    subgraph "Google Cloud Platform (GCP)"
        direction TB

        subgraph "Frontend Distribution"
            CR_Web["Cloud Run\nsessionmuse-web\n(Flutter Web Build)\nリージョン：asia-northeast1"]
            CDN["Cloud CDN\n(Flutter Assets)"]
        end

        subgraph "AI Processing Backend"
            CR_Backend["Cloud Run\nsessionmuse-backend\n(FastAPI + LangGraph)\nGemini 2.5 Flash Lite\nリージョン：asia-northeast1"]
            
            subgraph "LangGraph Workflow Engine"
                LG_Analyzer["🎵 Audio Analysis Node\n(Theme Extraction)"]
                LG_Generator["🎼 MusicXML Generator\n(Composition AI)"]
                LG_Synthesizer["🎧 Audio Synthesis\n(MIDI → MP3)"]
            end
        end

        subgraph "AI Services"
            VertexAI["Vertex AI\nGemini 2.5 Flash Lite Preview\nマルチモーダル音声処理"]
            
            subgraph "AI Capabilities"
                Theme["テーマ理解\n(音声 → 雰囲気)"]
                MusicXML["楽譜生成\n(テーマ → MusicXML)"]
                Chat["音楽AI相談\n(MusicXML対応)"]
            end
        end

        subgraph "Storage Layer"
            CS_Uploads["Cloud Storage\nsessionmuse-uploads-{project}\n(音声ファイル + 変換済み)"]
            CS_Generated["Cloud Storage\nsessionmuse-tracks-{project}\n(MusicXML + MP3 + 中間ファイル)"]
        end

        subgraph "Infrastructure Services"
            AR["Artifact Registry\n(コンテナイメージ)"]
            SM["Secret Manager\n(Gemini API Keys)"]
            Terraform["Terraform State\n(Infrastructure as Code)"]
        end
    end

    subgraph "External Services"
        FluidSynth["FluidSynth\n+ GeneralUser GS\nSoundFont\n(MIDI → WAV)"]
        AppStores["📲 App Stores\n(iOS App Store\nGoogle Play Store)"]
    end

    %% Client Connections
    Mobile -.->|"Direct API Calls"| CR_Backend
    Web -->|"Flutter Web Hosting"| CR_Web
    Desktop -.->|"Direct API Calls"| CR_Backend
    
    CR_Web -->|"API Proxy"| CR_Backend

    %% AI Workflow
    CR_Backend --> LG_Analyzer
    LG_Analyzer --> LG_Generator  
    LG_Generator --> LG_Synthesizer
    
    LG_Analyzer <-->|"音声解析"| VertexAI
    LG_Generator <-->|"MusicXML生成"| VertexAI
    CR_Backend <-->|"AI Chat"| VertexAI

    %% Data Flow
    CR_Backend <-->|"ファイル操作"| CS_Uploads
    CR_Backend <-->|"生成物保存"| CS_Generated
    LG_Synthesizer -->|"FluidSynth"| FluidSynth

    %% Infrastructure
    AR -->|"Container Images"| CR_Backend
    AR -->|"Container Images"| CR_Web
    SM -->|"API Keys"| CR_Backend
    
    %% Distribution
    Mobile -.->|"アプリ配信"| AppStores
    
    classDef aiNode fill:#e1f5fe
    classDef clientNode fill:#f3e5f5
    classDef storageNode fill:#e8f5e8
    
    class LG_Analyzer,LG_Generator,LG_Synthesizer,VertexAI,Theme,MusicXML,Chat aiNode
    class Mobile,Web,Desktop clientNode
    class CS_Uploads,CS_Generated storageNode
```


## 3. 主要コンポーネント設計


### 3.1. フロントエンド配信戦略 (Flutter マルチプラットフォーム)

#### 3.1.1. Web アプリケーション (Cloud Run)

*   **サービス名**: `sessionmuse-web`
*   **リージョン**: `asia-northeast1` (東京)
*   **テクノロジー**: Flutter Web ビルド + Nginxリバースプロキシ
*   **コンテナイメージ**: Flutter Web ビルド成果物を nginx で配信する軽量コンテナ
*   **サービスアカウント**: `sa-web@<project-id>.iam.gserviceaccount.com`
    *   バックエンドAPI呼び出しのための `roles/run.invoker` 権限
*   **インスタンス設定**:
    *   **最小インスタンス数**: 0 (コスト最適化)
    *   **最大インスタンス数**: 5 (Web トラフィック対応)
    *   **CPU**: 1 vCPU
    *   **メモリ**: 512MiB (静的配信なので軽量)
    *   **リクエストタイムアウト**: 30秒
*   **環境変数**:
    *   `BACKEND_API_ENDPOINT`: `https://sessionmuse-backend-xxxx-an.a.run.app`
    *   `FLUTTER_WEB_BUILD_MODE`: `release`
*   **Dockerfile (Flutter Web最適化)**:
    ```dockerfile
    # 1. Flutter Web ビルドステージ
    FROM cirrusci/flutter:stable AS flutter-builder
    WORKDIR /app
    COPY frontend/flutter_application/ .
    RUN flutter config --enable-web
    RUN flutter pub get
    RUN flutter build web --release --web-renderer canvaskit

    # 2. Nginx 配信ステージ  
    FROM nginx:alpine AS runner
    RUN rm -rf /usr/share/nginx/html/*
    COPY --from=flutter-builder /app/build/web/ /usr/share/nginx/html/
    COPY frontend/nginx.conf.template /etc/nginx/conf.d/default.conf
    EXPOSE 80
    CMD ["nginx", "-g", "daemon off;"]
    ```

#### 3.1.2. モバイルアプリ配信

*   **iOS**: App Store Connect 経由でのエンタープライズ配信
    *   **ビルド環境**: GitHub Actions + Xcode Cloud 統合
    *   **署名**: Apple Developer Enterprise Account
    *   **配信方式**: TestFlight → App Store
*   **Android**: Google Play Console 経由での配信
    *   **ビルド環境**: GitHub Actions + Android Gradle Plugin
    *   **署名**: Google Play App Signing
    *   **配信方式**: Internal Testing → Production

#### 3.1.3. デスクトップアプリ配信

*   **Windows**: Microsoft Store / 直接配布
*   **macOS**: Mac App Store / 直接配布  
*   **Linux**: Snap Store / AppImage 配布


### 3.2. 次世代AIバックエンド (Cloud Run + LangGraph)

*   **サービス名**: `sessionmuse-backend`
*   **リージョン**: `asia-northeast1` (東京)
*   **アーキテクチャ**: FastAPI + LangGraph ワークフロー + Gemini 2.5 Flash Lite Preview
*   **コンテナイメージ**: Python 3.11 + 音楽処理ライブラリ統合イメージ
*   **サービスアカウント**: `sa-backend@<project-id>.iam.gserviceaccount.com`
    *   **IAM ロール**:
        *   `roles/storage.objectAdmin`: マルチバケット GCS 操作
        *   `roles/aiplatform.user`: Vertex AI (Gemini 2.5) フルアクセス
        *   `roles/secretmanager.secretAccessor`: API キー管理
        *   `roles/cloudsql.client`: 将来的な永続化対応

#### 3.2.1. インスタンス設定 (UltraThink最適化)

*   **最小インスタンス数**: 1 (LangGraph ワークフロー初期化コスト軽減)
*   **最大インスタンス数**: 20 (並列AI処理対応)
*   **CPU**: 2 vCPU (音声変換 + AI並列処理)
*   **メモリ**: 4GiB (MusicXML生成 + FluidSynth + 複数音声フォーマット対応)
*   **リクエストタイムアウト**: 300秒 (複雑な音楽生成ワークフロー対応)
*   **同時実行数**: 10 (AI処理の品質確保)

#### 3.2.2. 環境変数 (新世代構成)

```bash
# GCS ストレージ管理
GCS_UPLOAD_BUCKET=sessionmuse-uploads-{project-id}
GCS_TRACK_BUCKET=sessionmuse-tracks-{project-id}
GCS_LIFECYCLE_DAYS=1

# Gemini 2.5 Flash Lite Preview
VERTEX_AI_LOCATION=global
ANALYZER_GEMINI_MODEL_NAME=gemini-2.5-flash-lite-preview-06-17
GENERATOR_GEMINI_MODEL_NAME=gemini-2.5-flash-lite-preview-06-17
CHAT_GEMINI_MODEL_NAME=gemini-2.5-flash-lite-preview-06-17
VERTEX_AI_TIMEOUT_SECONDS=120

# アプリケーション設定
LOG_LEVEL=INFO
MAX_FILE_SIZE_MB=100
PORT_LOCAL_DEV=8000

# 音楽処理設定
FLUIDSYNTH_SOUNDFONT_PATH=/app/GeneralUser GS v1.472.sf2
MUSIC_GENERATION_QUALITY=high
AUDIO_SYNTHESIS_FORMAT=mp3
```

#### 3.2.3. Dockerfile (AI音楽処理特化版)

```dockerfile
# 1. Python AI/音楽処理基盤
FROM python:3.11-slim AS base

# システム依存関係 (FluidSynth + 音声処理)
RUN apt-get update && apt-get install -y \
    fluidsynth \
    fluid-soundfont-gm \
    ffmpeg \
    libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

# 2. Python依存関係インストール
WORKDIR /app
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 3. SoundFont配置
COPY backend/GeneralUser\ GS\ v1.472.sf2 ./
COPY backend/ .

# 4. ヘルスチェック + 起動
EXPOSE 8080
ENV PORT=8080
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
```

#### 3.2.4. LangGraph ワークフロー設計

```python
# 音声処理ワークフロー (audio_analysis_service.py)
def create_audio_analysis_workflow():
    workflow = StateGraph(AudioAnalysisWorkflowState)
    
    # ノード定義
    workflow.add_node("analyze_humming", node_analyze_humming_audio)
    workflow.add_node("generate_musicxml", node_generate_musicxml)
    workflow.add_node("handle_analysis_error", node_handle_analysis_error)
    workflow.add_node("handle_generation_error", node_handle_generation_error)
    
    # フロー制御
    workflow.set_entry_point("analyze_humming")
    workflow.add_conditional_edges(
        "analyze_humming",
        should_proceed_to_generation,
        {
            "continue": "generate_musicxml", 
            "error": "handle_analysis_error"
        }
    )
    
    return workflow.compile()
```


### 3.3. ストレージ (Cloud Storage)


*   **バケット**:
    *   `sessionmuse-uploads-your-project-id` (ユーザーのアップロード音声用)
    *   `sessionmuse-tracks-your-project-id` (AIが生成したバッキングトラック用)
*   **ロケーション**: `asia-northeast1` (東京)
*   **ストレージクラス**: Standard (頻繁なアクセスを想定)
*   **アクセス制御 (IAM)**:
    *   バックエンドCloud Runのサービスアカウント (`sa-backend@<project-id>.iam.gserviceaccount.com`) に対して、両バケットの **ストレージオブジェクト管理者** (`roles/storage.objectAdmin`) ロールを付与します。
*   **ライフサイクル管理**:
    *   **ルール**: オブジェクト作成から 1日 後にオブジェクトを自動的に削除するルールを両バケットに設定します。これにより、ストレージコストを抑制し、不要なユーザーデータを保持しません。


### 3.4. シークレット管理 (Secret Manager)
*   **目的**: Gemini APIキーなどの機密情報を安全に保管し、バックエンドアプリケーションからセキュアにアクセスします。
*   **アクセス制御 (IAM)**:
    *   バックエンドCloud Runのサービスアカウント (`sa-backend@<project-id>.iam.gserviceaccount.com`) に対して、対象シークレットへの **Secret Manager シークレットアクセサー** (`roles/secretmanager.secretAccessor`) ロールを付与します。


## 4. UltraThink AI処理パイプライン

### 4.1. Gemini 2.5 Flash Lite Preview 統合

*   **マルチモーダル処理**: 音声ファイルを直接Geminiに送信し、テーマとMusicXMLを同時生成
*   **コンテキスト理解**: 口ずさみから「明るくエネルギッシュなJ-POP風」等の人間的表現を抽出
*   **楽譜生成**: テーマベースでMusicXMLを構造化生成、従来のMIDI生成を超越

### 4.2. LangGraph ワークフロー管理

```python
# 状態管理型AI処理
class AudioAnalysisWorkflowState(TypedDict):
    gcs_file_path: str
    workflow_run_id: Optional[str]
    humming_analysis_theme: Optional[str]  # テーマ抽出結果
    generated_musicxml_data: Optional[str]  # MusicXML生成結果
    final_analysis_result: Optional[AnalysisResult]
```

*   **エラーハンドリング**: ノード単位での例外処理と状態復旧
*   **非同期実行**: AI処理の並列化とタイムアウト管理
*   **監視可能性**: ワークフロー実行状況のリアルタイム追跡

### 4.3. 音楽合成パイプライン

```
音声アップロード → WebM/AAC→WAV変換 → Gemini解析 → テーマ抽出
                                                    ↓
MP3配信 ← FluidSynth合成 ← MIDI変換 ← MusicXML生成 ← Gemini生成
```

## 5. モニタリング・オブザーバビリティ

### 5.1. 構造化ログ戦略

*   **相関ID追跡**: X-Request-ID によるリクエスト全体の追跡
*   **ワークフロー監視**: LangGraph ノード実行状況の詳細ログ
*   **AI処理メトリクス**: Gemini API呼び出し時間・成功率・エラー分類

### 5.2. Cloud Monitoring 統合

*   **カスタムメトリクス**:
    *   `sessionmuse/audio_processing_duration`: 音声処理時間
    *   `sessionmuse/musicxml_generation_success_rate`: MusicXML生成成功率
    *   `sessionmuse/gemini_api_latency`: Gemini API応答時間
*   **アラート設定**:
    *   AI処理失敗率 > 5%
    *   平均応答時間 > 30秒
    *   Gemini APIエラー率 > 1%

### 5.3. 分散トレーシング

*   **Cloud Trace**: リクエスト→ワークフロー→AI処理の完全な経路追跡
*   **LangGraph統合**: 各ワークフローノードのスパン生成
*   **外部API追跡**: Vertex AI呼び出しのトレース情報

## 6. コスト最適化 (UltraThink版)

### 6.1. インテリジェントスケーリング

*   **Flutter Web**: 最小インスタンス数 0 (静的配信)
*   **Backend**: 最小インスタンス数 1 (ワームアップコスト削減)
*   **AI処理**: 同時実行数制限でリソース効率化

### 6.2. ストレージライフサイクル

*   **自動削除**: アップロード・生成ファイル1日後削除
*   **バケット分離**: 用途別コスト追跡
*   **圧縮配信**: MusicXML/MP3 gzip圧縮

### 6.3. AI API最適化

*   **モデル選択**: Flash Lite Preview (高速・低コスト)
*   **バッチ処理**: 複数リクエストの統合処理
*   **キャッシュ戦略**: 類似音声の結果再利用
