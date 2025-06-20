# SessionMUSE バックエンド API

SessionMUSE バックエンドAPIは、ユーザーがアップロードした音声ファイルを解析し、AIによるバッキングトラック生成や音楽に関するチャット機能を提供するAPIです。

## 技術スタック

*   **フレームワーク**: FastAPI
*   **言語**: Python 3.11+
*   **AI連携**: LangChain, LangGraph, Google Gemini 1.5 Pro
*   **データ永続化**: Google Cloud Storage (GCS) - 一時オブジェクトとして
*   **実行環境**: Google Cloud Run (コンテナ化)
*   **認証 (サービス間)**: Google IDトークン
*   **主なPythonライブラリ**:
    *   `uvicorn`: ASGIサーバー
    *   `pydantic`: データバリデーションと設定管理
    *   `google-cloud-storage`, `google-cloud-secret-manager`, `google-cloud-logging`: Google Cloud連携
    *   `python-multipart`: ファイルアップロード処理
    *   `asgi-correlation-id`: リクエストIDによるログ追跡

## プロジェクト構造

```
sessionmuse_backend/
├── .env                  # ローカル開発用の環境変数ファイル (サンプル: .env.example)
├── Dockerfile            # Cloud Runデプロイ用のDockerfile
├── requirements.txt      # Python依存ライブラリリスト
├── main.py               # FastAPIアプリケーションのエントリーポイント
├── config.py             # 設定管理
├── models.py             # Pydanticデータモデル
├── exceptions.py         # カスタム例外クラス
├── logging_config.py     # ロギング設定
├── middleware/
│   └── auth_middleware.py # 認証ミドルウェア
├── routers/
│   ├── __init__.py
│   ├── process_api.py     # 音声処理API
│   └── chat_api.py        # AIチャットAPI
└── services/
    ├── __init__.py
    └── audio_analysis_service.py # 音声解析・生成サービス (LangGraph)
```

## 初期セットアップ

1.  **リポジトリのクローン**:
    ```bash
    git clone <リポジトリのURL>
    cd sessionmuse_backend
    ```

2.  **Python仮想環境の作成と有効化**:
    ```bash
    python3 -m venv venv
    source venv/bin/activate  # Linux/macOS
    # venv\Scripts\activate    # Windows
    ```

3.  **依存関係のインストール**:
    ```bash
    pip install -r requirements.txt
    ```

4.  **Google Cloud SDKのセットアップ (ローカル開発時)**:
    *   まだインストールしていない場合は、[Google Cloud SDK](https://cloud.google.com/sdk/docs/install) をインストールします。
    *   SDKを初期化し、認証を行います:
        ```bash
        gcloud init
        gcloud auth application-default login
        ```
    *   これにより、ローカル環境からGCSやSecret ManagerなどのGCPサービスにアクセスできるようになります。

5.  **環境変数ファイル `.env` の作成**:
    *   プロジェクトルートに `.env` ファイルを作成します。`.env.example` (もしあれば) をコピーして編集するか、以下のテンプレートを参考にしてください。
    *   **必須項目**:
        *   `GCS_UPLOAD_BUCKET`: 元ファイルをアップロードするGCSバケット名。
        *   `GCS_TRACK_BUCKET`: 生成されたトラックを保存するGCSバケット名。
        *   `GEMINI_API_KEY`: ローカル開発時に使用するGemini APIキー (Secret Managerを使用しない場合)。
    *   **推奨項目 (Secret Managerを使用する場合)**:
        *   `GEMINI_API_KEY_SECRET_NAME`: Gemini APIキーが格納されているSecret Managerのシークレットのフルリソース名 (例: `projects/YOUR_PROJECT_ID/secrets/YOUR_GEMINI_KEY_NAME/versions/latest`)。
    *   その他の設定値 (ログレベル、タイムアウトなど) は `config.py` にデフォルト値がありますが、必要に応じて `.env` で上書きできます。
    *   ローカル開発でIDトークン認証を無効にするには、以下を設定します:
        *   `ENABLE_AUTH_MIDDLEWARE=False`

    **`.env` ファイルの例**:
    ```env
    # GCS設定
    GCS_UPLOAD_BUCKET="your-dev-gcs-upload-bucket-name"
    GCS_TRACK_BUCKET="your-dev-gcs-track-bucket-name"

    # Gemini APIキー (直接指定またはSecret Manager経由)
    GEMINI_API_KEY="AIzaSyXXXXXXXXXXXXXXXXXXXXXXXXXXX"
    # または
    # GEMINI_API_KEY_SECRET_NAME="projects/my-gcp-project/secrets/gemini-api-key/versions/latest"

    # ログレベル (DEBUG, INFO, WARNING, ERROR)
    LOG_LEVEL="DEBUG"

    # 認証ミドルウェア (ローカル開発では無効化を推奨)
    ENABLE_AUTH_MIDDLEWARE=False

    # ローカル開発用ポート
    PORT_LOCAL_DEV=8000
    ```

6.  **Google Cloud Storageバケットの作成**:
    *   `.env` ファイルで指定したGCSバケット (`GCS_UPLOAD_BUCKET`, `GCS_TRACK_BUCKET`) をGoogle Cloud Consoleまたは `gsutil` コマンドで作成してください。
    *   例: `gsutil mb gs://your-dev-gcs-upload-bucket-name`
    *   設計書に基づき、これらのバケットにはライフサイクルポリシーを設定して、ファイルが一定期間後に自動削除されるようにすることを推奨します。

7.  **Google Cloud Secret Managerの設定 (オプション)**:
    *   Gemini APIキーなどの機密情報をSecret Managerで管理する場合、対応するシークレットを作成し、`.env` ファイルの `GEMINI_API_KEY_SECRET_NAME` にそのリソース名を設定してください。
    *   ローカルで実行するサービスアカウントまたはユーザーアカウントに、これらのシークレットへのアクセス権 (`roles/secretmanager.secretAccessor`) を付与してください。

## ローカルでの実行方法

1.  上記「初期セットアップ」が完了していることを確認してください。
2.  仮想環境が有効化されていることを確認してください。
3.  `main.py` を直接実行してUvicorn開発サーバーを起動します:
    ```bash
    python main.py
    ```
    または、Uvicornコマンドを直接使用することもできます:
    ```bash
    uvicorn main:app --reload --host 0.0.0.0 --port <PORT_LOCAL_DEVで指定したポート、デフォルト8000>
    ```
4.  APIは `http://localhost:<ポート番号>` (例: `http://localhost:8000`) で利用可能になります。
5.  APIドキュメント (Swagger UI) は `http://localhost:<ポート番号>/docs` でアクセスできます。
6.  ReDocドキュメントは `http://localhost:<ポート番号>/redoc` でアクセスできます。

## Google Cloud Runへのデプロイ

1.  **前提条件**:
    *   Google Cloudプロジェクトがセットアップされていること。
    *   Cloud Run API, Cloud Build API, Artifact Registry API (またはContainer Registry API) が有効になっていること。
    *   `gcloud` CLIがインストールされ、デプロイに使用するプロジェクトとアカウントで認証済みであること。

2.  **Dockerfileの準備**:
    *   プロジェクトルートの `Dockerfile` が、アプリケーションのコンテナイメージをビルドするために正しく設定されていることを確認してください。

3.  **Cloud Buildを使用したビルドとデプロイ (推奨)**:
    *   Cloud Build を使用すると、ソースコードからコンテナイメージをビルドし、Artifact Registry (またはContainer Registry) にプッシュし、Cloud Runにデプロイする一連のプロセスを自動化できます。
    *   プロジェクトルートに `cloudbuild.yaml` ファイルを作成します。

    **`cloudbuild.yaml` の例**:
    ```yaml
    steps:
    # Dockerイメージをビルド
    - name: 'gcr.io/cloud-builders/docker'
      args: ['build', '-t', 'gcr.io/$PROJECT_ID/sessionmuse-backend:$COMMIT_SHA', '.']
      id: 'Build Docker image'

    # イメージをGoogle Container Registry (GCR) にプッシュ
    # Artifact Registry を使用する場合は、イメージ名を適宜変更 (例: us-central1-docker.pkg.dev/$PROJECT_ID/my-repo/sessionmuse-backend:$COMMIT_SHA)
    - name: 'gcr.io/cloud-builders/docker'
      args: ['push', 'gcr.io/$PROJECT_ID/sessionmuse-backend:$COMMIT_SHA']
      id: 'Push image to GCR'

    # Cloud Runにデプロイ
    - name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
      entrypoint: gcloud
      args:
        - 'run'
        - 'deploy'
        - 'sessionmuse-backend' # Cloud Runサービス名
        - '--image=gcr.io/$PROJECT_ID/sessionmuse-backend:$COMMIT_SHA'
        - '--platform=managed'
        - '--region=YOUR_REGION' # 例: us-central1, asia-northeast1
        - '--allow-unauthenticated' # フロントエンドからの呼び出しを許可 (IDトークン認証はアプリ内で実施)
        # サービスアカウントを指定する場合 (GCSやSecret Managerアクセス用)
        # - '--service-account=YOUR_SERVICE_ACCOUNT_EMAIL'
        # 環境変数を設定 (GCSバケット名、Secret Managerのシークレット名など)
        - '--update-env-vars=^##^GCS_UPLOAD_BUCKET=YOUR_GCS_UPLOAD_BUCKET##GCS_TRACK_BUCKET=YOUR_GCS_TRACK_BUCKET##GEMINI_API_KEY_SECRET_NAME=projects/$PROJECT_ID/secrets/YOUR_GEMINI_KEY_NAME/versions/latest##LOG_LEVEL=INFO##ENABLE_AUTH_MIDDLEWARE=True##EXPECTED_AUDIENCE=YOUR_BACKEND_SERVICE_URL_PLACEHOLDER'
        # EXPECTED_AUDIENCEはデプロイ後に取得できるサービスのURLに置き換えるか、
        # Cloud Runが自動的に設定するSERVICE_URL環境変数をconfig.pyで利用する
        # `##` はCloud Buildでカンマ区切り環境変数を扱うための区切り文字
      id: 'Deploy to Cloud Run'

    images:
    - 'gcr.io/$PROJECT_ID/sessionmuse-backend:$COMMIT_SHA'
    ```
    *   上記の `YOUR_REGION`, `YOUR_SERVICE_ACCOUNT_EMAIL`, 各環境変数のプレースホルダーを実際の値に置き換えてください。
    *   `EXPECTED_AUDIENCE` は、最初のデプロイ後にCloud RunサービスのURLが確定してから設定するか、`config.py` 内で `SERVICE_URL` 環境変数 (Cloud Runが設定) を利用するようにします。
    *   コマンドラインからCloud Buildを実行:
        ```bash
        gcloud builds submit --config cloudbuild.yaml .
        ```

4.  **`gcloud` CLI を使用した手動デプロイ (ビルド済みのイメージがある場合)**:
    *   まずイメージをビルドしてレジストリにプッシュします:
        ```bash
        docker build -t gcr.io/YOUR_PROJECT_ID/sessionmuse-backend:latest .
        docker push gcr.io/YOUR_PROJECT_ID/sessionmuse-backend:latest
        ```
    *   Cloud Runにデプロイ:
        ```bash
        gcloud run deploy sessionmuse-backend \
          --image gcr.io/YOUR_PROJECT_ID/sessionmuse-backend:latest \
          --platform managed \
          --region YOUR_REGION \
          --allow-unauthenticated \
          --set-env-vars="GCS_UPLOAD_BUCKET=YOUR_GCS_UPLOAD_BUCKET,GCS_TRACK_BUCKET=YOUR_GCS_TRACK_BUCKET,GEMINI_API_KEY_SECRET_NAME=projects/YOUR_PROJECT_ID/secrets/YOUR_GEMINI_KEY_NAME/versions/latest,LOG_LEVEL=INFO,ENABLE_AUTH_MIDDLEWARE=True,EXPECTED_AUDIENCE=YOUR_BACKEND_SERVICE_URL"
          # 必要に応じて他の環境変数を追加
        ```

5.  **サービスアカウントの権限**:
    *   Cloud Runサービスが使用するサービスアカウントには、以下のIAMロールが必要です:
        *   GCSバケットへの読み書きアクセス (`roles/storage.objectAdmin` またはより限定的な `roles/storage.objectCreator` と `roles/storage.objectViewer`)。
        *   Secret Managerのシークレットへのアクセス (`roles/secretmanager.secretAccessor`)。
        *   (もし使用していれば) 他のGoogle Cloudサービスへのアクセス権。
        *   サービス間認証でIDトークンを検証するために、Cloud Runサービス自体は特別な権限は不要ですが、呼び出し元（フロントエンドサービス）がIDトークンを生成できる権限 (`roles/run.invoker` をバックエンドサービスに対して持つなど) が必要です。

## APIエンドポイント

*   `POST /api/process`: 音声ファイルをアップロードし、解析結果とバッキングトラックURLを取得します。
    *   リクエスト: `multipart/form-data` (キー `file` に音声ファイル)
    *   レスポンス: `ProcessResponse` JSON
*   `POST /api/chat`: AIと音楽に関するチャットを行います。
    *   リクエスト: `ChatRequest` JSON
    *   レスポンス: `ChatMessage` JSON (非ストリーミング時) または SSEストリーム (`text/event-stream`)

詳細はAPIドキュメント (`/docs` または `/redoc`) を参照してください。

## トラブルシューティング

*   **ローカル実行時のエラー**:
    *   Pythonのバージョン、依存関係が正しくインストールされているか確認してください。
    *   `.env` ファイルが正しく設定され、必要な環境変数が読み込まれているか確認してください。
    *   `gcloud auth application-default login` が実行されているか確認してください。
*   **Cloud Runデプロイ時のエラー**:
    *   Cloud Buildのログ、Cloud Runのログ（Logging）を確認してください。
    *   Dockerfileが正しくイメージをビルドできているか確認してください。
    *   サービスアカウントの権限が適切に設定されているか確認してください。
    *   環境変数が正しくCloud Runサービスに渡されているか確認してください。
    *   `EXPECTED_AUDIENCE` がバックエンドサービスの正しいURLに設定されているか確認してください。
*   **APIエラー**:
    *   APIからのエラーレスポンス (JSON形式) の `error.code` と `error.message`、`error.detail` を確認してください。
    *   サーバーログ (Cloud Logging) で詳細なエラー情報やスタックトレースを確認してください。リクエストID (`X-Request-ID`) を使うとログの追跡が容易です。
