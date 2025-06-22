# models.py

from enum import Enum
from typing import List, Literal, Optional

from pydantic import BaseModel, Field, HttpUrl


class ErrorCode(str, Enum):
    INVALID_REQUEST = "INVALID_REQUEST"
    INVALID_FILE_TYPE = "INVALID_FILE_TYPE"
    FILE_TOO_LARGE = "FILE_TOO_LARGE"
    UNSUPPORTED_MEDIA_TYPE = "UNSUPPORTED_MEDIA_TYPE"
    GCS_UPLOAD_ERROR = "GCS_UPLOAD_ERROR"
    ANALYSIS_FAILED = "ANALYSIS_FAILED"
    GENERATION_FAILED = "GENERATION_FAILED"
    VERTEX_AI_API_ERROR = "VERTEX_AI_API_ERROR" # Renamed from GEMINI_API_ERROR
    EXTERNAL_SERVICE_ERROR = "EXTERNAL_SERVICE_ERROR"
    INTERNAL_SERVER_ERROR = "INTERNAL_SERVER_ERROR"
    AUTHENTICATION_REQUIRED = "AUTHENTICATION_REQUIRED"
    FORBIDDEN_ACCESS = "FORBIDDEN_ACCESS"
    RATE_LIMIT_EXCEEDED = "RATE_LIMIT_EXCEEDED"


class ErrorDetail(BaseModel):
    code: ErrorCode
    message: str
    detail: Optional[str] = None


class ErrorResponse(BaseModel):
    error: ErrorDetail


class AnalysisResult(BaseModel):
    key: str = Field(..., description="解析されたキー", example="C Major")
    bpm: int = Field(..., description="解析されたBPM", example=120, gt=0)
    chords: List[str] = Field(
        ..., description="解析されたコード進行", example=["C", "G", "Am", "F"]
    )
    genre_by_ai: str = Field(
        ..., description="AIによって推定されたジャンル", example="Pop Ballad"
    )


class ProcessResponse(BaseModel):
    analysis: AnalysisResult
    backing_track_url: HttpUrl = Field(..., description="生成されたバッキングトラックの公開URL") # Changed from "署名付きURL"
    original_file_url: Optional[HttpUrl] = Field(
        None, description="アップロードされたオリジナルファイルの公開URL (確認用など)" # Changed from "署名付きURL"
    )


class ChatMessage(BaseModel):
    role: Literal["user", "assistant"]
    content: str


class ChatRequest(BaseModel):
    messages: List[ChatMessage] = Field(..., min_length=1, description="対話履歴。最低1件のメッセージが必要。")
    analysis_context: Optional[AnalysisResult] = Field(
        None, description="現在の楽曲の解析情報（AI推定ジャンル含む）"
    )


class ChordProgressionOutput(BaseModel):
    """AIが推定したコード進行を格納するモデル。"""
    chords: List[str] = Field(description="推定されたコード進行のリスト。例: ['Am', 'G', 'C', 'F']")
    # confidence: Optional[float] = Field(None, description="推定の信頼度 (0.0-1.0)", ge=0.0, le=1.0) # 必要なら追加
    # reasoning: Optional[str] = Field(None, description="推定の根拠やAIの思考プロセス") # 必要なら追加

class KeyOutput(BaseModel):
    primary_key: str = Field(description="最も可能性の高い主要なキー")
    other_plausible_keys: Optional[List[str]] = Field(None, description="他に考えられるキーのリスト")

class BpmOutput(BaseModel):
    bpm: int = Field(description="推定されたBPM (整数値)", gt=0)

class GenreOutput(BaseModel):
    primary_genre: str = Field(description="最も可能性の高い主要なジャンル")
    secondary_genres: Optional[List[str]] = Field(None, description="他に考えられる副次的なジャンル")
