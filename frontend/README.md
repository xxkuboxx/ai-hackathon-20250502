# Flutter Web on Cloud Run - デプロイガイド

## 概要

この文書は、Flutterで構築されたWebアプリケーションを、Nginxウェブサーバーでホスティングし、Google Cloud Buildを通じてCloud Runへ自動でデプロイするガイドです。

## ディレクトリ構成

```
├── flutter_application/      <-- Flutterのソースコード
├── cloudbuild.yml           <-- Cloud Buildの設定ファイル
├── Dockerfile                <-- Dockerイメージの設計図
└── nginx.conf.template       <-- Nginxの設定ファイルテンプレート
```

## 必要なもの（前提条件）

デプロイを実行する前に、以下の準備が必要です。

1.  **Google Cloud Project**: 課金が有効になっているGCPプロジェクト。
2.  **Google Cloud SDK**: `gcloud` コマンドラインツールがインストールされ、認証が完了していること。
    *   インストール: `https://cloud.google.com/sdk/docs/install`
    *   認証: `gcloud auth login`
    *   プロジェクト設定: `gcloud config set project YOUR_PROJECT_ID`

## デプロイ手順

デプロイは、このディレクトリで以下のコマンドを実行するだけです。

```bash
# 現在のディレクトリのソースコードをCloud Buildに送信し、
# cloudbuild.ymlの設定に従ってビルドとデプロイを実行する
gcloud builds submit --config cloudbuild.yml .
```

Cloud Buildが起動し、`cloudbuild.yml`に定義されたステップ（Dockerイメージのビルド、Artifact Registryへのプッシュ、Cloud Runへのデプロイ）が順次実行されます。完了すると、Cloud RunサービスのURLに新しいバージョンが反映されます。

---

## 各ファイルの詳細解説

### `Dockerfile`

このファイルは、アプリケーションをコンテナ化するための設計図です。多段ビルド（multi-stage build）を採用し、最終的なイメージサイズを最適化しています。

#### Stage 1: `builder`

*   **目的**: Flutterのソースコードを静的なウェブファイルにコンパイル（ビルド）します。
*   `FROM dart:stable as builder`: 信頼できる公式Dartイメージをベースにします。
*   `RUN apt-get ... && git clone ...`: Flutter SDKを特定のバージョンでインストールします。これにより、誰がいつビルドしても同じ環境が保証されます。
*   `RUN flutter build web`: Flutterアプリケーションをウェブ用にビルドし、`./build/web` ディレクトリに静的ファイルを生成します。

#### Stage 2: `server`

*   **目的**: Stage 1でビルドされた静的ファイルを、Nginxウェブサーバーで配信します。
*   `FROM nginx:alpine`: 軽量なNginxイメージをベースにします。
*   `RUN apk add --no-cache gettext`: `envsubst` コマンドをインストールします。これはNginxの設定ファイルに環境変数（`PORT`）を埋め込むために使用します。
*   `COPY --from=builder ...`: **Stage 1からビルド済みのファイルだけをコピーします。** これにより、Flutter SDKなどのビルド時のみ必要だったツールが含まれない、軽量な最終イメージが作成されます。
*   `RUN chown ...`: コピーしたファイルと設定ファイルの所有権をNginxの実行ユーザーに渡し、パーミッションエラーを防ぎます。
*   `CMD [...]`: コンテナ起動時に実行されるコマンドです。`envsubst`で設定ファイルを作成し、`nginx -g 'daemon off;'`でNginxをフォアグラウンドで起動します（コンテナアプリケーションの作法）。

### `nginx.conf.template`

Nginxがどのようにリクエストを処理するかを定義する設定ファイルです。

*   `listen ${PORT};`: Cloud Runが提供する`PORT`環境変数をリッスンするよう指示します。`envsubst`コマンドによって、この`${PORT}`部分が実際のポート番号（例：8080）に置き換えられます。
*   `try_files $uri $uri/ /index.html;`: Flutterのようなシングルページアプリケーション（SPA）に不可欠な設定です。存在しないURLへのリクエスト（例：`/users/123`）が来た場合に、URLを書き換えるのではなく、ルートの`index.html`を返すようにします。これにより、Flutterのクライアントサイドのルーティングが正しく機能します。
*   `access_log /dev/stdout;` & `error_log /dev/stderr;`: Nginxのログをファイルではなく標準出力/エラー出力に送ります。これにより、Cloud Runのログ機能で全てのログを閲覧できます。

### `cloudbuild.yml`

Cloud Buildが実行するステップを定義します。

1.  **Build Docker image**: `Dockerfile` を使ってDockerイメージをビルドします。`env: ['DOCKER_BUILDKIT=1']` を設定することで、ヒアドキュメントなどの新しいDockerfile機能を有効にしています。
2.  **Push image to Artifact Registry**: ビルドしたイメージを、安全なプライベートリポジトリであるArtifact Registryに保存します。
3.  **Deploy to Cloud Run**: 保存したイメージを使ってCloud Runサービスを更新します。リージョン、メモリ、CPUなどの設定もここで行います。

## トラブルシューティング

デプロイで問題が発生した場合、まず確認すべきはログです。

*   **Cloud Buildのログ**: ビルドやプッシュの段階で失敗した場合、Google Cloud Consoleの「Cloud Build」->「履歴」から、失敗したビルドの詳細とログを確認できます。
*   **Cloud Runのログ**: デプロイは成功したように見えても、コンテナが起動に失敗することがあります。その場合は、
    1.  Google Cloud Consoleの「Cloud Run」に移動します。
    2.  対象のサービスをクリックします。
    3.  「**ログ**」タブを選択します。
    4.  フィルタを調整して、失敗したリビジョン（例：`sessionmuse-frontend-0000X-xxx`）のログを表示します。
    5.  ここにコンテナが起動できなかった具体的な理由（コマンドが見つからない、設定ファイルのエラー、パーミッションエラーなど）が出力されます。
