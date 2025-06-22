## Google Cloud Runへのデプロイ

1.  **前提条件**:
    *   Google Cloudプロジェクトがセットアップされていること。
    *   Cloud Run API, Cloud Build API, Artifact Registry API が有効になっていること。
    *   `gcloud` CLIがインストールされ、デプロイに使用するプロジェクトとアカウントで認証済みであること。
    *   Artifact Registry にリポジトリが作成されていること（例: `my-repo`）。

2.  **Dockerfileの準備**:
    *   プロジェクトルートの `Dockerfile` が、アプリケーションのコンテナイメージをビルドするために正しく設定されていることを確認してください。

3.  **Cloud Buildを使用したビルドとデプロイ**:
    *   コマンドラインからCloud Buildを実行する場合、`--substitutions` フラグで変数値を渡します:
        ```bash
        gcloud builds submit --config cloudbuild.yaml . \
          --substitutions=\
        _ARTIFACT_REGISTRY_LOCATION=us-central1,\
        _ARTIFACT_REGISTRY_REPOSITORY=my-repo,\
        _REGION=us-central1,\
        _GCS_UPLOAD_BUCKET=your-gcs-upload-bucket-name,\
        _GCS_TRACK_BUCKET=your-gcs-track-bucket-name,\
        _EXPECTED_AUDIENCE=https://your-cloud-run-service-url.a.run.app
        # ,_SERVICE_ACCOUNT_EMAIL=your-service-account@your-project.iam.gserviceaccount.com # 必要に応じて
        ```
    *   Cloud Buildトリガーを使用する場合は、トリガーの設定画面でこれらの置換変数を定義します。

4.  **サービスアカウントの権限**:
    *   Cloud Runサービスが使用するサービスアカウントには、以下のIAMロールが必要です:
        *   GCSバケットへの読み書きアクセス (`roles/storage.objectAdmin` またはより限定的な `roles/storage.objectCreator` と `roles/storage.objectViewer`)。
        *   Secret Managerのシークレットへのアクセス (`roles/secretmanager.secretAccessor`)。
        *   (もし使用していれば) 他のGoogle Cloudサービスへのアクセス権。
        *   サービス間認証でIDトークンを検証するために、Cloud Runサービス自体は特別な権限は不要ですが、呼び出し元（フロントエンドサービス）がIDトークンを生成できる権限 (`roles/run.invoker` をバックエンドサービスに対して持つなど) が必要です。
