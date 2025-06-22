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


    # 認証設定
    ENABLE_AUTH_MIDDLEWARE: bool = Field(True, description="IDトークン認証ミドルウェアを有効にするか。ローカル開発ではFalseに設定。")
    EXPECTED_AUDIENCE: Optional[str] = Field(
        default=None,
        description="IDトークンの期待されるオーディエンス (このバックエンドCloud RunサービスのURL)"
    )

    @model_validator(mode='after')
    def _resolve_settings(self) -> 'Settings':
        # EXPECTED_AUDIENCEの解決 (Cloud Run環境で設定されていない場合)
        if not self.EXPECTED_AUDIENCE and os.environ.get("SERVICE_URL"):
            self.EXPECTED_AUDIENCE = os.environ.get("SERVICE_URL")
        elif not self.EXPECTED_AUDIENCE and os.environ.get("K_SERVICE") and self.ENABLE_AUTH_MIDDLEWARE:
             print(f"警告: EXPECTED_AUDIENCEが設定されていません。K_SERVICEは '{os.environ.get('K_SERVICE')}' ですが、完全なURLが推奨されます。認証が失敗する可能性があります。")
        return self

settings = Settings()
