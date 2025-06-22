import os
from typing import Optional, List

from google.cloud import secretmanager # type: ignore
from pydantic import Field, model_validator, AliasChoices
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    """
    アプリケーションの設定を管理するクラス。
    環境変数または .env ファイルから読み込まれる。
    """

    model_config = SettingsConfigDict(
            env_file=".env",
            env_file_encoding='utf-8',
            extra='ignore',
            case_sensitive=False
        )

    # GCS 設定
    GCS_UPLOAD_BUCKET: str = Field(..., description="ユーザーがアップロードした元ファイルを保存するGCSバケット名")
    GCS_TRACK_BUCKET: str = Field(..., description="AIが生成したバッキングトラックを保存するGCSバケット名")
    GCS_LIFECYCLE_DAYS: int = Field(1, description="GCSオブジェクトの自動削除までの日数")

    # Vertex AI / Gemini 設定
    VERTEX_AI_LOCATION: str = Field("us-east5", description="Vertex AIモデルを使用するリージョン。例: us-central1, asia-northeast1")
    GEMINI_MODEL_NAME: str = Field("gemini-2.0-flash", description="使用するGeminiモデル名 (Vertex AI)")
    VERTEX_AI_TIMEOUT_SECONDS: int = Field(120, description="Vertex AI API呼び出しのタイムアウト秒数")

    # アプリケーション設定
    LOG_LEVEL: str = Field("INFO", description="アプリケーションログのレベル (INFO, DEBUGなど)")
    SIGNED_URL_EXPIRATION_SECONDS: int = Field(3600, description="GCS署名付きURLの有効期間（秒数）")
    MAX_FILE_SIZE_MB: int = Field(100, description="アップロードファイルの最大サイズ（MB単位）")
    PORT_LOCAL_DEV: int = Field(8000, description="ローカルUvicorn開発サーバー用ポート")


settings = Settings()
