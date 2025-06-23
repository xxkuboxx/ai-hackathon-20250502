# routers/chat_api.py

import logging
from fastapi import APIRouter, Request, Body, Depends
from fastapi.responses import StreamingResponse

from models import ChatRequest, ChatMessage, ErrorCode, AnalysisResult
from exceptions import VertexAIAPIErrorException, InternalServerErrorException # Changed
from services.vertex_chat_service import VertexChatService, get_vertex_chat_service
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
    chat_service: VertexChatService = Depends(get_vertex_chat_service)
):
    logger.info(f"チャットリクエスト受信。メッセージ数: {len(chat_request.messages)}")

    try:
        # build_vertex_chat_messages に musicxml_gcs_url も渡すように変更
        # build_vertex_chat_messages に musicxml_content を渡すように変更
        vertex_messages = chat_service.build_vertex_chat_messages(
            system_prompt=prompts.SESSIONMUSE_CHAT_SYSTEM_PROMPT,
            analysis_context=chat_request.analysis_context,
            chat_history=chat_request.messages,
            musicxml_content=chat_request.musicxml_content # musicxml_gcs_url から変更
        )
    except Exception as e:
        logger.error(f"Vertex AIチャットメッセージの構築エラー: {e}", exc_info=True)
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
