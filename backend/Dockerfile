# ベースイメージとして公式Pythonランタイムを使用
# 依存関係と互換性のあるバージョンを選択 (例: Python 3.11)
FROM python:3.11-slim

# 環境変数を設定
# Pythonがpycファイルをディスクに書き込むのを防ぐ (パフォーマンス向上に寄与するケースあり)
ENV PYTHONDONTWRITEBYTECODE 1
# Pythonの出力をバッファリングせず直接ターミナルに送る (Dockerログ用)
ENV PYTHONUNBUFFERED 1

# コンテナ内の作業ディレクトリを設定
WORKDIR /app

# アプリケーション実行用の非特権ユーザーを作成
# root以外で実行するのはセキュリティのベストプラクティス
ARG UID=10001
RUN useradd -m -u ${UID} --no-log-init appuser

# システム依存関係をインストール
# FFmpegを追加
RUN apt-get update && \
    apt-get install -y --no-install-recommends fluidsynth ffmpeg && \
    rm -rf /var/lib/apt/lists/*
# もしgccやbuild-essentialも必要であれば、以下のように記述します
# RUN apt-get update && \
#     apt-get install -y --no-install-recommends gcc build-essential ffmpeg && \
#     rm -rf /var/lib/apt/lists/*

# requirementsファイルをコンテナの/appにコピー
COPY requirements.txt .

# Python依存関係をインストール
# --no-cache-dirでイメージサイズを削減
# pipを最新版にアップグレード
RUN pip install --upgrade pip
RUN pip install --no-cache-dir -r requirements.txt

# 残りのアプリケーションコードをコンテナの/appにコピー
# 依存関係インストール後に行うことでDockerのレイヤーキャッシュを活用
COPY . .

# /appディレクトリの所有権を非特権ユーザーに変更
RUN chown -R appuser:appuser /app

# 非特権ユーザーに切り替え
USER appuser

# アプリケーションが実行されるポートを公開
# Cloud RunはPORT環境変数を自動的に使用
# このEXPOSE命令はドキュメント化やローカルDocker実行用
EXPOSE 8080

# Uvicornを使用してアプリケーションを起動するコマンドを定義
# Cloud RunはPORT環境変数を設定するので、Uvicornはそのポートでリッスンする必要がある
# コンテナ外部からアクセスできるように0.0.0.0でリッスン
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
