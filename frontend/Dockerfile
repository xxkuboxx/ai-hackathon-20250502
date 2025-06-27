# syntax=docker/dockerfile:1

# Stage 1: Build the Flutter web application
# 信頼できる公式Dartイメージをベースにする
FROM dart:stable as builder

WORKDIR /app

# gitをインストール（dart:stableイメージには含まれていないため）
RUN apt-get update && apt-get install -y --no-install-recommends git && rm -rf /var/lib/apt/lists/*

# Dart 3.8.1を含むFlutter 3.32.2をタグで正確に指定してクローン
# --depth 1 は履歴を全て取得せず、最新のスナップショットのみを取得するため、ダウンロードが高速化されます
RUN git clone https://github.com/flutter/flutter.git --depth 1 --branch 3.32.2 /usr/local/flutter
ENV PATH="/usr/local/flutter/bin:${PATH}"

# Flutterのセットアップとバージョンの確認
RUN flutter doctor
RUN flutter --version

# アプリケーションの依存関係を先にインストールする（推奨）
# これにより、ソースコードの変更時にも依存関係のレイヤーキャッシュが再利用され、ビルドが高速化します
COPY ./flutter_application/pubspec.* ./
RUN flutter pub get

# アプリケーションのソースコードをコピー
COPY ./flutter_application/ ./

# Flutterウェブアプリケーションをビルド
RUN flutter build web

# Stage 2: Serve the Flutter web application with Nginx
FROM nginx:alpine

# gettextパッケージをインストール（envsubstコマンドのため）
RUN apk add --no-cache gettext

# デフォルトのNginx設定を削除
RUN rm /etc/nginx/conf.d/default.conf

# Nginxの設定テンプレートをコンテナにコピー
COPY nginx.conf.template /etc/nginx/conf.d/app.conf.template

# ビルダー（Stage 1）からビルドされたWebファイルをコピー
COPY --from=builder /app/build/web /usr/share/nginx/html

# コピーしたファイルのオーナーをnginxユーザーに変更する
RUN chown -R nginx:nginx /usr/share/nginx/html

# ポートを公開（ドキュメント目的）
EXPOSE 8080

# Nginxを起動し、PORT環境変数を設定ファイルに適用する
CMD ["/bin/sh", "-c", "envsubst '\\$PORT' < /etc/nginx/conf.d/app.conf.template > /etc/nginx/conf.d/default.conf && nginx -g 'daemon off;'"]
