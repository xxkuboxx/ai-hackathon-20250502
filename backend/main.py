# main.py

import logging
import os # PORT_LOCAL_DEV用
from uuid import uuid4

from fastapi import FastAPI, Request, status
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from asgi_correlation_id import CorrelationIdMiddleware, correlation_id

from config import settings
from logging_config import setup_app_logging
from models import ErrorCode, ErrorDetail, ErrorResponse
from exceptions import AppException
from routers import process_api, chat_api

# --- 1. ロギング初期化 ---
setup_app_logging(settings.LOG_LEVEL)
logger = logging.getLogger(__name__)

# --- 2. FastAPIアプリケーションインスタンス作成 ---
app = FastAPI(
    title="SessionMUSE Backend API",
    description="API for SessionMUSE, providing audio processing and AI chat functionalities.",
    version="0.1.0",
)

# --- 3. ミドルウェア追加 ---
# 3.1. CORS ミドルウェア (Flutter側からのリクエスト許可用)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # 開発用: 本番環境では具体的なドメインを指定
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 3.2. Correlation ID ミドルウェア (リクエスト追跡用)
app.add_middleware(
    CorrelationIdMiddleware,
    header_name='X-Request-ID',
    generator=lambda: uuid4().hex,
)

# 3.3. カスタムロギングミドルウェア (詳細なリクエスト/レスポンスログ用)
@app.middleware("http")
async def log_requests_middleware(request: Request, call_next):
    request_id = correlation_id.get()

    log_payload_request = {
        "client_host": request.client.host if request.client else "unknown",
        "client_port": request.client.port if request.client else "unknown",
        "http_method": request.method,
        "http_path": request.url.path,
        "http_query_params": str(request.query_params),
        "user_agent": request.headers.get("user-agent", "unknown"),
        "gcp_trace_context": request.headers.get("X-Cloud-Trace-Context"),
    }
    logger.info(
        f"Request received: {request.method} {request.url.path}",
        extra=log_payload_request
    )

    response = await call_next(request)

    log_payload_response = {
        "http_status_code": response.status_code,
    }
    full_log_payload = {**log_payload_request, **log_payload_response}
    logger.info(
        f"Request finished: {request.method} {request.url.path} - Status: {response.status_code}",
        extra=full_log_payload
    )

    if request_id:
        response.headers["X-Request-ID"] = request_id

    return response


# --- 4. 例外ハンドラ登録 ---
@app.exception_handler(RequestValidationError)
async def request_validation_exception_handler(request: Request, exc: RequestValidationError):
    error_details_for_log = []
    for error in exc.errors():
        field = " -> ".join(str(loc_item) for loc_item in error["loc"]) if error.get("loc") else "general"
        error_details_for_log.append({"field": field, "message": error["msg"], "type": error["type"]})
    
    logger.warning(
        f"Request Validation Error: {request.method} {request.url.path}",
        extra={
            "validation_errors": error_details_for_log,
            "client_host": request.client.host if request.client else "unknown",
        }
    )
    error_detail_for_client = str(error_details_for_log)
    return JSONResponse(
        status_code=status.HTTP_400_BAD_REQUEST,
        content=jsonable_encoder(ErrorResponse(
            error=ErrorDetail(
                code=ErrorCode.INVALID_REQUEST,
                message="Request validation failed. Please check your input parameters.",
                detail=error_detail_for_client
            )
        ))
    )

@app.exception_handler(AppException)
async def app_exception_handler(request: Request, exc: AppException):
    log_level = logging.WARNING if exc.status_code < 500 else logging.ERROR
    logger.log(
        log_level,
        f"AppException Caught: {exc.error_code.value} - {exc.message} - {request.method} {request.url.path}",
        exc_info=True if exc.status_code >= 500 else False,
        extra={
            "error_code": exc.error_code.value,
            "error_message": exc.message,
            "error_detail": exc.detail,
            "client_host": request.client.host if request.client else "unknown",
        }
    )
    return JSONResponse(
        status_code=exc.status_code,
        content=jsonable_encoder(ErrorResponse(
            error=ErrorDetail(
                code=exc.error_code,
                message=exc.message,
                detail=exc.detail
            )
        ))
    )

@app.exception_handler(Exception)
async def generic_exception_handler(request: Request, exc: Exception):
    logger.error(
        f"Unhandled Exception: {type(exc).__name__} - {str(exc)} - {request.method} {request.url.path}",
        exc_info=True,
        extra={
            "exception_type": type(exc).__name__,
            "exception_message": str(exc),
            "client_host": request.client.host if request.client else "unknown",
        }
    )
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content=jsonable_encoder(ErrorResponse(
            error=ErrorDetail(
                code=ErrorCode.INTERNAL_SERVER_ERROR,
                message="An unexpected internal server error occurred. Please try again later or contact support."
            )
        ))
    )


# --- 5. APIルーター登録 ---
app.include_router(process_api.router)
app.include_router(chat_api.router)
logger.info("API routers registered: process_api, chat_api.")


# --- 基本的なルートとヘルスチェックエンドポイント ---
@app.get("/", include_in_schema=False)
async def root():
    logger.debug("Root path '/' accessed.")
    return {"message": "Welcome to SessionMUSE Backend API", "version": app.version}

@app.get("/health", tags=["Utilities"], summary="Health Check Endpoint")
async def health_check():
    logger.debug("Health check '/health' accessed.")
    return {"status": "healthy", "version": app.version, "log_level": settings.LOG_LEVEL}


# --- 6. ローカル開発用Uvicornランナー ---
if __name__ == "__main__":
    local_dev_port = int(os.environ.get("PORT", getattr(settings, "PORT_LOCAL_DEV", 8000)))
    logger.info(f"Starting Uvicorn server for local development on host 0.0.0.0, port {local_dev_port}...")
    import uvicorn
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=local_dev_port,
        reload=True,
        log_level=settings.LOG_LEVEL.lower()
    )
