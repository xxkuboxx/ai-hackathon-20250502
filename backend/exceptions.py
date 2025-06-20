# exceptions.py

from typing import Optional
from models import ErrorCode

class AppException(Exception):
    status_code: int = 500
    error_code: ErrorCode = ErrorCode.INTERNAL_SERVER_ERROR
    message: str = "予期せぬアプリケーションエラーが発生しました。"
    detail: Optional[str] = None

    def __init__(
        self,
        message: Optional[str] = None,
        detail: Optional[str] = None,
        error_code: Optional[ErrorCode] = None,
        status_code: Optional[int] = None,
    ):
        final_message = message if message is not None else self.__class__.message
        super().__init__(final_message)

        self.message = final_message
        self.detail = detail if detail is not None else self.__class__.detail
        self.error_code = error_code if error_code is not None else self.__class__.error_code
        self.status_code = status_code if status_code is not None else self.__class__.status_code


class InvalidRequestDataException(AppException):
    status_code = 400
    error_code = ErrorCode.INVALID_REQUEST
    message = "無効なリクエストデータが提供されました。"

class UnsupportedMediaTypeException(AppException):
    status_code = 415
    error_code = ErrorCode.UNSUPPORTED_MEDIA_TYPE
    message = "提供されたメディアタイプはサポートされていません。"

class FileTooLargeException(AppException):
    status_code = 413
    error_code = ErrorCode.FILE_TOO_LARGE
    message = "提供されたファイルが大きすぎます。"

class GCSUploadErrorException(AppException):
    status_code = 503
    error_code = ErrorCode.GCS_UPLOAD_ERROR
    message = "Google Cloud Storageへのファイルアップロードに失敗しました。"

class AnalysisFailedException(AppException):
    status_code = 503
    error_code = ErrorCode.ANALYSIS_FAILED
    message = "音声解析プロセスに失敗しました。"

class GenerationFailedException(AppException):
    status_code = 503
    error_code = ErrorCode.GENERATION_FAILED
    message = "バッキングトラック生成プロセスに失敗しました。"

class GeminiAPIErrorException(AppException):
    status_code = 503
    error_code = ErrorCode.GEMINI_API_ERROR
    message = "Gemini APIとの通信中にエラーが発生しました。"

class ExternalServiceErrorException(AppException):
    status_code = 503
    error_code = ErrorCode.EXTERNAL_SERVICE_ERROR
    message = "外部サービスとの連携でエラーが発生しました。"

class AuthenticationRequiredException(AppException):
    status_code = 401
    error_code = ErrorCode.AUTHENTICATION_REQUIRED
    message = "このリソースへのアクセスには認証が必要です。"

class ForbiddenAccessException(AppException):
    status_code = 403
    error_code = ErrorCode.FORBIDDEN_ACCESS
    message = "このリソースへのアクセス権がありません。"

class RateLimitExceededException(AppException):
    status_code = 429
    error_code = ErrorCode.RATE_LIMIT_EXCEEDED
    message = "レート制限を超過しました。後でもう一度お試しください。"

class InternalServerErrorException(AppException):
    status_code = 500
    error_code = ErrorCode.INTERNAL_SERVER_ERROR
    message = "内部サーバーエラーが発生しました。"
