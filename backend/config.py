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

    # GCS 設定
    GCS_UPLOAD_BUCKET: str = Field(..., description="ユーザーがアップロードした元ファイルを保存するGCSバケット名")
    GCS_TRACK_BUCKET: str = Field(..., description="AIが生成したバッキングトラックを保存するGCSバケット名")
    GCS_LIFECYCLE_DAYS: int = Field(1, description="GCSオブジェクトの自動削除までの日数")

    # Gemini API 設定
    GEMINI_MODEL_NAME: str = Field("gemini-1.5-pro-latest", description="使用するGeminiモデル名")
    GEMINI_API_KEY_SECRET_NAME: Optional[str] = Field(
        None,
        description="Gemini APIキーが格納されているSecret Managerのシークレット名"
    )
    # Pydantic v2では先頭アンダースコアのフィールド名はプライベート属性と見なされるため変更
    gemini_api_key_env_var: Optional[str] = Field(  # <--- フィールド名変更
        default=None,
        alias="GEMINI_API_KEY", # 環境変数名と合わせる
        validation_alias=AliasChoices("GEMINI_API_KEY"), # 環境変数名と合わせる
        description="ローカル開発用のGemini APIキー (環境変数 GEMINI_API_KEY から直接読み込む)",
        exclude=True # 最終的な settings オブジェクトには含めない (GEMINI_API_KEY_FINAL を使う)
    )
    GEMINI_API_KEY_FINAL: Optional[str] = None # 実際に使用するAPIキー
    GEMINI_API_TIMEOUT_SECONDS: int = Field(120, description="Gemini API呼び出しのタイムアウト秒数")

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

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding='utf-8',
        extra='ignore',
        case_sensitive=False
    )

    def _fetch_secret_from_gcp(self, secret_full_name: str) -> Optional[str]:
        if not secret_full_name or \
           "YOUR_PROJECT_ID" in secret_full_name or \
           "DUMMY_SECRET" in secret_full_name:
            return None
        try:
            client = secretmanager.SecretManagerServiceClient()
            response = client.access_secret_version(name=secret_full_name)
            return response.payload.data.decode("UTF-8")
        except Exception as e:
            print(f"警告: Secret Managerからのシークレット '{secret_full_name}' の取得に失敗しました。エラー: {e}")
            return None

    @model_validator(mode='after')
    def _resolve_settings(self) -> 'Settings':
        # Gemini APIキーの解決
        if self.gemini_api_key_env_var: # <--- 参照するフィールド名を変更
            self.GEMINI_API_KEY_FINAL = self.gemini_api_key_env_var
        elif self.GEMINI_API_KEY_SECRET_NAME:
            api_key_from_sm = self._fetch_secret_from_gcp(self.GEMINI_API_KEY_SECRET_NAME)
            if api_key_from_sm:
                self.GEMINI_API_KEY_FINAL = api_key_from_sm
        
        if not self.GEMINI_API_KEY_FINAL:
             print("警告: GEMINI_API_KEYが決定できませんでした。AI関連機能が動作しない可能性があります。")

        # EXPECTED_AUDIENCEの解決 (Cloud Run環境で設定されていない場合)
        if not self.EXPECTED_AUDIENCE and os.environ.get("SERVICE_URL"):
            self.EXPECTED_AUDIENCE = os.environ.get("SERVICE_URL")
        elif not self.EXPECTED_AUDIENCE and os.environ.get("K_SERVICE") and self.ENABLE_AUTH_MIDDLEWARE:
             print(f"警告: EXPECTED_AUDIENCEが設定されていません。K_SERVICEは '{os.environ.get('K_SERVICE')}' ですが、完全なURLが推奨されます。認証が失敗する可能性があります。")
        return self

settings = Settings()
