# middleware/auth_middleware.py

import logging
from typing import Optional, List

from fastapi import Request, HTTPException, status
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.responses import Response

from google.oauth2 import id_token
from google.auth.transport import requests as google_auth_requests

from config import settings
from models import ErrorCode, ErrorDetail, ErrorResponse

logger = logging.getLogger(__name__)
_CERT_REQUEST = google_auth_requests.Request()

class IDTokenAuthMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        if request.method == "OPTIONS":
            return await call_next(request)
            
        public_paths = ["/health", "/docs", "/openapi.json", "/redoc"]
        if request.url.path in public_paths or request.url.path == "/":
             return await call_next(request)

        if not settings.ENABLE_AUTH_MIDDLEWARE:
            logger.debug("IDトークン認証は無効です。トークン検証をスキップします。")
            return await call_next(request)

        authorization_header = request.headers.get("Authorization")
        if not authorization_header:
            logger.warning("リクエストにAuthorizationヘッダーがありません。")
            return self._build_auth_error_response(
                ErrorCode.AUTHENTICATION_REQUIRED,
                "Authorizationヘッダーがありません。",
                status.HTTP_401_UNAUTHORIZED
            )

        parts = authorization_header.split()
        if len(parts) != 2 or parts[0].lower() != "bearer":
            logger.warning(f"無効なAuthorizationヘッダー形式です: {authorization_header}")
            return self._build_auth_error_response(
                ErrorCode.AUTHENTICATION_REQUIRED,
                "無効なAuthorizationヘッダー形式です。'Bearer <ID_TOKEN>'を期待します。",
                status.HTTP_401_UNAUTHORIZED
            )

        token = parts[1]
        
        try:
            if not settings.EXPECTED_AUDIENCE:
                logger.error("EXPECTED_AUDIENCEが設定されていません。IDトークンを安全に検証できません。")
                return self._build_auth_error_response(
                    ErrorCode.INTERNAL_SERVER_ERROR,
                    "認証システムが正しく設定されていません（オーディエンスがありません）。",
                    status.HTTP_500_INTERNAL_SERVER_ERROR
                )

            id_info = id_token.verify_oauth2_token(
                token,
                _CERT_REQUEST,
                audience=settings.EXPECTED_AUDIENCE
            )
            
            if id_info['iss'] not in ['accounts.google.com', 'https://accounts.google.com']:
                logger.warning(f"トークンの発行者が無効です: {id_info['iss']}")
                raise ValueError('不正な発行者です。')

            # if settings.ALLOWED_INVOKER_SERVICE_ACCOUNTS:
            #     if id_info.get('email') not in settings.ALLOWED_INVOKER_SERVICE_ACCOUNTS:
            #         logger.warning(f"トークンのメールアドレス '{id_info.get('email')}' は許可された呼び出し元に含まれていません。")
            #         return self._build_auth_error_response(
            #             ErrorCode.FORBIDDEN_ACCESS,
            #             "呼び出し元サービスアカウントは認可されていません。",
            #             status.HTTP_403_FORBIDDEN
            #         )
            
            logger.info(f"IDトークンは正常に検証されました。オーディエンス: {settings.EXPECTED_AUDIENCE}。ユーザーメール: {id_info.get('email', 'N/A')}")

        except ValueError as e:
            logger.warning(f"IDトークンの検証に失敗しました: {e}", exc_info=True)
            return self._build_auth_error_response(
                ErrorCode.AUTHENTICATION_REQUIRED,
                f"無効なIDトークンです: {str(e)}",
                status.HTTP_401_UNAUTHORIZED
            )
        except Exception as e:
            logger.error(f"IDトークン認証中に予期せぬエラーが発生しました: {e}", exc_info=True)
            return self._build_auth_error_response(
                ErrorCode.INTERNAL_SERVER_ERROR,
                "認証中に内部エラーが発生しました。",
                status.HTTP_500_INTERNAL_SERVER_ERROR
            )
        
        return await call_next(request)

    def _build_auth_error_response(self, code: ErrorCode, message: str, status_code: int) -> JSONResponse:
        from fastapi.encoders import jsonable_encoder
        error_detail = ErrorDetail(code=code, message=message)
        return JSONResponse(
            status_code=status_code,
            content=jsonable_encoder(ErrorResponse(error=error_detail))
        )
