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


# AnalysisResult モデルを新しい仕様に合わせて変更
class AnalysisResult(BaseModel):
    humming_theme: str = Field(..., description="口ずさみ音声から解析されたトラックの雰囲気/テーマ", example="明るくエネルギッシュなJ-POP")
    # key, bpm, chords, genre_by_ai は削除。

class ProcessResponse(BaseModel):
    analysis: AnalysisResult # 更新された AnalysisResult を使用
    backing_track_url: HttpUrl = Field(..., description="生成されたバッキングトラックMusicXMLの公開URL")
    original_file_url: Optional[HttpUrl] = Field(
        None, description="アップロードされたオリジナル音声ファイルの公開URL"
    )


class ChatMessage(BaseModel):
    role: Literal["user", "assistant"]
    content: str


class ChatRequest(BaseModel):
    messages: List[ChatMessage] = Field(..., min_length=1, description="対話履歴。最低1件のメッセージが必要。")
    analysis_context: Optional[AnalysisResult] = Field(
        None, description="現在の楽曲の解析情報（トラックの雰囲気/テーマ）"
    )
    # MusicXMLのGCS URLの代わりに、MusicXMLの内容自体を格納するフィールドに変更
    musicxml_content: Optional[str] = Field(None, description="生成されたMusicXMLファイルの内容（文字列）")


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
