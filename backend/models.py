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
    VERTEX_AI_API_ERROR = "VERTEX_AI_API_ERROR"
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


class MusicAnalysisFeatures(BaseModel):
    """
    AIによってMusicXMLから解析された音楽的特徴。
    structured_outputとして利用される。
    """
    key: str = Field(..., description="楽曲のキー (調)。例: 'C Major', 'A minor'")
    bpm: int = Field(..., description="楽曲のテンポ (Beats Per Minute)。例: 120")
    chords: List[str] = Field(..., description="楽曲の主要なコード進行。例: ['C', 'G', 'Am', 'F']")
    genre: str = Field(..., description="楽曲のジャンル。例: 'J-POP', 'Rock'")


class ProcessResponse(BaseModel):
    humming_theme: str = Field(..., description="口ずさみ音声から解析されたトラックの雰囲気/テーマ", example="明るくエネルギッシュなJ-POP")
    analysis: Optional[MusicAnalysisFeatures] = Field(None, description="MusicXMLから解析された音楽的特徴")
    backing_track_url: HttpUrl = Field(..., description="生成されたバッキングトラックMusicXMLの公開URL")
    original_file_url: Optional[HttpUrl] = Field(
        None, description="アップロードされたオリジナル音声ファイルの公開URL"
    )
    generated_mp3_url: Optional[HttpUrl] = Field(
        None, description="生成されたMP3ファイルの公開URL"
    )


class ChatMessage(BaseModel):
    role: Literal["user", "assistant"]
    content: str


class ChatRequest(BaseModel):
    messages: List[ChatMessage] = Field(..., min_length=1, description="対話履歴。最低1件のメッセージが必要。")
    humming_theme: Optional[str] = Field(
        None, description="現在の楽曲の解析情報（トラックの雰囲気/テーマ）"
    )
    musicxml_gcs_url: Optional[HttpUrl] = Field(
        None, description="MusicXMLファイルが格納されているGoogle Cloud StorageのURL。指定された場合、ここからMusicXMLを取得します。"
    )


# 以下の構造化出力モデルは新しいフローでは使用されないため削除
# class ChordProgressionOutput(BaseModel):
#     """AIが推定したコード進行を格納するモデル。"""
#     chords: List[str] = Field(description="推定されたコード進行のリスト。")
#
#
# class KeyOutput(BaseModel):
#     primary_key: str = Field(description="最も可能性の高い主要なキー")
#     other_plausible_keys: Optional[List[str]] = Field(None, description="他に考えられるキーのリスト")
#
# class BpmOutput(BaseModel):
#     bpm: int = Field(description="推定されたBPM (整数値)", gt=0)
#
# class GenreOutput(BaseModel):
#     primary_genre: str = Field(description="最も可能性の高い主要なジャンル")
#     secondary_genres: Optional[List[str]] = Field(None, description="他に考えられる副次的なジャンル")
