## Google Cloud Runへのデプロイ

1.  **前提条件**:
    *   Google Cloudプロジェクトがセットアップされていること。
    *   Cloud Run API, Cloud Build API, Artifact Registry API が有効になっていること。
    *   `gcloud` CLIがインストールされ、デプロイに使用するプロジェクトとアカウントで認証済みであること。
    *   Artifact Registry にリポジトリが作成されていること（例: `my-repo`）。

2.  **Dockerfileの準備**:
    *   プロジェクトルートの `Dockerfile` が、アプリケーションのコンテナイメージをビルドするために正しく設定されていることを確認してください。

3.  **Cloud Buildを使用したビルドとデプロイ**:  
    ```
    gcloud builds submit --config cloudbuild.yml . 
    ```
    Cloud Buildトリガーを使用する場合は、トリガーの設定画面でこれらの置換変数を定義します。

4.  **サービスアカウントの権限**:
    *   Cloud Runサービスが使用するサービスアカウントには、以下のIAMロールが必要です:
        *   GCSバケットへの読み書きアクセス (`roles/storage.objectAdmin` またはより限定的な `roles/storage.objectCreator` と `roles/storage.objectViewer`)。
        *   Secret Managerのシークレットへのアクセス (`roles/secretmanager.secretAccessor`)。
        *   (もし使用していれば) 他のGoogle Cloudサービスへのアクセス権。
        *   サービス間認証でIDトークンを検証するために、Cloud Runサービス自体は特別な権限は不要ですが、呼び出し元（フロントエンドサービス）がIDトークンを生成できる権限 (`roles/run.invoker` をバックエンドサービスに対して持つなど) が必要です。
