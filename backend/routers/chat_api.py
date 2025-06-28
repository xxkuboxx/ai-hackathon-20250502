# routers/chat_api.py

import logging
from fastapi import APIRouter, Request, Body, Depends
from fastapi.responses import StreamingResponse
from typing import Optional # Optional をインポート

from models import ChatRequest, ChatMessage, ErrorCode
from exceptions import VertexAIAPIErrorException, InternalServerErrorException # Changed
from services.vertex_chat_service import VertexChatService, get_vertex_chat_service
from services.gcs_service import GCSService, get_gcs_service # GCSService をインポート
from services import prompts

logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/api",
    tags=["AI Chat"],
)

@router.post("/chat", response_model=ChatMessage)
async def handle_chat_request(
    request: Request,
    chat_request: ChatRequest = Body(...),
    chat_service: VertexChatService = Depends(get_vertex_chat_service),
    gcs_service: "GCSService" = Depends(get_gcs_service) # GCSServiceをインポートしてDI
):
    logger.info(f"チャットリクエスト受信。メッセージ数: {len(chat_request.messages)}, musicxml_gcs_url: {chat_request.musicxml_gcs_url}")

    musicxml_content_for_vertex: Optional[str] = None # Vertex AIに渡すMusicXMLコンテンツ

    try:
        if chat_request.musicxml_gcs_url:
            logger.info(f"musicxml_gcs_urlが提供されました: {chat_request.musicxml_gcs_url}。GCSからダウンロードします。")
            try:
                # str(chat_request.musicxml_gcs_url) でPydanticのHttpUrlを文字列に変換
                musicxml_content_for_vertex = await gcs_service.download_file_as_string_from_gcs(str(chat_request.musicxml_gcs_url))
                logger.info(f"MusicXMLファイルのダウンロード成功。文字数: {len(musicxml_content_for_vertex)}")
            except Exception as e: # GCSDownloadErrorException やその他 GCS関連の例外を想定
                logger.error(f"GCSからのMusicXMLファイルダウンロードエラー ({chat_request.musicxml_gcs_url}): {e}", exc_info=True)
                # GCSからのダウンロードエラーはシステムエラーとして扱う
                raise InternalServerErrorException(
                    message="MusicXMLファイルの取得に失敗しました。",
                    detail=f"GCSからのダウンロードエラー: {str(e)}"
                )
        else:
            logger.info("musicxml_gcs_urlは提供されませんでした。バッキングトラックなしとして処理します。")
            # musicxml_content_for_vertex は None のまま

        # Vertex AIチャットメッセージの構築
        vertex_messages = chat_service.build_vertex_chat_messages(
            system_prompt=prompts.SESSIONMUSE_CHAT_SYSTEM_PROMPT,
            humming_theme=chat_request.humming_theme, # analysis_contextからhumming_themeに変更
            chat_history=chat_request.messages,
            musicxml_content=musicxml_content_for_vertex # ダウンロードした内容またはNoneを渡す
        )
    except InternalServerErrorException: # 既にInternalServerErrorExceptionならそのままraise
        raise
    except Exception as e:
        logger.error(f"Vertex AIチャットメッセージの構築またはGCS処理中の予期せぬエラー: {e}", exc_info=True)
        raise InternalServerErrorException(message="AIプロンプトの構築に失敗しました。",detail=str(e))

    accept_header = request.headers.get("accept", "").lower()
    is_streaming_requested = "text/event-stream" in accept_header

    try:
        if is_streaming_requested:
            logger.info("ストリーミングレスポンスが要求されました。Vertex AIストリームを開始します。")
            return StreamingResponse(
                chat_service.stream_vertex_response_as_sse(vertex_messages),
                media_type="text/event-stream"
            )
        else:
            logger.info("通常のJSONレスポンスが要求されました。Vertex AIを呼び出します。")
            ai_chat_message = await chat_service.generate_chat_response(vertex_messages)
            return ai_chat_message
    except VertexAIAPIErrorException as e: # Changed
        logger.warning(f"Vertex AI Service Error: {e.message} Code: {e.error_code} Detail: {e.detail}", exc_info=False)
        raise
    except Exception as e:
        logger.error(f"チャット処理中の予期せぬエラー: {e}", exc_info=True)
        # Ensure this fallback also uses the new exception type and error code
        raise VertexAIAPIErrorException(message="AIとの通信中に予期せぬエラーが発生しました。", detail=str(e), error_code=ErrorCode.VERTEX_AI_API_ERROR)
