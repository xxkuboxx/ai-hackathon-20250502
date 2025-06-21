# routers/chat_api.py

import logging
import asyncio
import json
from fastapi import APIRouter, HTTPException, Request, Body
from fastapi.responses import JSONResponse, StreamingResponse
from typing import Union, List, Dict, Any, AsyncGenerator, Optional

from langchain_core.messages import SystemMessage, HumanMessage, AIMessage, BaseMessageChunk
from langchain_google_vertexai import ChatVertexAI, HarmCategory, HarmBlockThreshold

from models import ChatRequest, ChatMessage, ErrorResponse, ErrorCode, AnalysisResult
from config import settings
from exceptions import GeminiAPIErrorException, InternalServerErrorException, ExternalServiceErrorException

logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/api",
    tags=["AI Chat"],
)

SESSIONMUSE_CHAT_SYSTEM_PROMPT_TEXT = """
あなたは「SessionMUSE」という名の、親切で創造的なAI音楽パートナーです。
音楽理論に詳しく、抽象的な表現も具体的なアイデアに変換できます。
ユーザーの音楽制作をサポートし、インスピレーションを与えるような、ポジティブで建設的なフィードバックを提供してください。
"""

def get_vertex_llm_for_chat() -> ChatVertexAI:
    """
    チャット用のVertex AI LLMクライアントを取得します。
    """
    if not settings.VERTEX_AI_PROJECT_ID:
        logger.error(f"チャット用VERTEX_AI_PROJECT_IDが設定されていません。")
        raise ExternalServiceErrorException(message="Vertex AI プロジェクトIDが設定されていません。", error_code=ErrorCode.EXTERNAL_SERVICE_ERROR)

    try:
        safety_settings_vertex = {
            HarmCategory.HARM_CATEGORY_HARASSMENT: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
            HarmCategory.HARM_CATEGORY_HATE_SPEECH: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
            HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT: HarmBlockThreshold.BLOCK_ONLY_HIGH,
            HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
        }

        llm = ChatVertexAI(
            project=settings.VERTEX_AI_PROJECT_ID,
            location=settings.VERTEX_AI_LOCATION,
            model_name=settings.GEMINI_MODEL_NAME,
            temperature=0.7,
            request_timeout=settings.VERTEX_AI_TIMEOUT_SECONDS,
            safety_settings=safety_settings_vertex,
        )
        logger.info(f"チャット用ChatVertexAIをモデル'{settings.GEMINI_MODEL_NAME}' (Project: {settings.VERTEX_AI_PROJECT_ID}, Location: {settings.VERTEX_AI_LOCATION})で初期化しました。")
        return llm
    except Exception as e:
        logger.error(f"チャット用ChatVertexAIの初期化に失敗しました: {e}", exc_info=True)
        raise GeminiAPIErrorException(message="チャット用Vertex AI LLMの初期化に失敗しました。", detail=str(e), error_code=ErrorCode.GEMINI_API_ERROR)


def build_vertex_chat_messages(
    system_prompt: str,
    analysis_context: Optional[AnalysisResult],
    chat_history: List[ChatMessage]
) -> List[Union[SystemMessage, HumanMessage, AIMessage]]:
    """
    Vertex AIチャットモデル用のメッセージリストを構築します。
    """
    messages: List[Union[SystemMessage, HumanMessage, AIMessage]] = []
    messages.append(SystemMessage(content=system_prompt))
    if analysis_context:
        context_str_parts = []
        if analysis_context.key and analysis_context.key != "Undetermined": context_str_parts.append(f"Key: {analysis_context.key}")
        if analysis_context.bpm and analysis_context.bpm > 0: context_str_parts.append(f"BPM: {analysis_context.bpm}")
        if analysis_context.chords and analysis_context.chords != ["Undetermined"]: context_str_parts.append(f"Chords: {', '.join(analysis_context.chords)}")
        if analysis_context.genre_by_ai and analysis_context.genre_by_ai != "Undetermined": context_str_parts.append(f"Genre: {analysis_context.genre_by_ai}")
        if context_str_parts:
            full_context_str = "現在の議論のための音楽的コンテキスト: " + ", ".join(context_str_parts) + "."
            messages.append(SystemMessage(content=full_context_str))
    for msg_data in chat_history:
        if msg_data.role == "user": messages.append(HumanMessage(content=msg_data.content))
        elif msg_data.role == "assistant": messages.append(AIMessage(content=msg_data.content))
    logger.debug(f"{len(messages)}件のVertex AIチャットメッセージを構築しました。")
    return messages

async def stream_vertex_response_as_sse(
    llm: ChatVertexAI,
    messages: List[Union[SystemMessage, HumanMessage, AIMessage]]
) -> AsyncGenerator[str, None]:
    """
    Vertex AIからのストリーミングレスポンスをSSE (Server-Sent Events) 形式で非同期に生成します。
    """
    full_response_content = ""
    try:
        async for chunk in llm.astream(messages):
            if not isinstance(chunk, BaseMessageChunk):
                logger.warning(f"ストリームで予期せぬチャンクタイプ: {type(chunk)}。スキップします。")
                continue
            content_piece = chunk.content
            if content_piece:
                sse_chat_message = ChatMessage(role="assistant", content=str(content_piece))
                yield f"data: {sse_chat_message.model_dump_json()}\n\n"
                full_response_content += str(content_piece)
        logger.info(f"Vertex AIレスポンスのストリーミングを終了しました。総長: {len(full_response_content)}")
    except Exception as e:
        if "blocked" in str(e).lower() or "safety filter" in str(e).lower():
            logger.warning(f"Vertex AI APIチャットストリームがブロックされた可能性があります。理由: {e}")
            error_message = ChatMessage(role="assistant", content=f"[エラー] あなたのリクエストはAIの安全フィルターによってブロックされた可能性があります。詳細: {str(e)[:100]}")
            yield f"data: {error_message.model_dump_json()}\n\n"
        elif isinstance(e, asyncio.TimeoutError):
            logger.error(f"Vertex AI APIストリーム呼び出しが {settings.VERTEX_AI_TIMEOUT_SECONDS}秒後にタイムアウトしました。")
            error_message = ChatMessage(role="assistant", content=f"[エラー] AIチャットリクエストが {settings.VERTEX_AI_TIMEOUT_SECONDS}秒後にタイムアウトしました。")
            yield f"data: {error_message.model_dump_json()}\n\n"
        elif isinstance(e, GeminiAPIErrorException):
            logger.error(f"ストリーム中のVertex AIサービスエラー: {e.message}")
            error_message = ChatMessage(role="assistant", content=f"[エラー] AIサービスエラー: {e.message}")
            yield f"data: {error_message.model_dump_json()}\n\n"
        else:
            logger.error(f"チャット用Vertex AI APIストリーム中のエラー: {e}", exc_info=True)
            error_message = ChatMessage(role="assistant", content="[エラー] AIとの通信中に予期せぬエラーが発生しました。")
            yield f"data: {error_message.model_dump_json()}\n\n"

@router.post("/chat", response_model=ChatMessage)
async def handle_chat_request(
    request: Request,
    chat_request: ChatRequest = Body(...)
):
    logger.info(f"チャットリクエスト受信。メッセージ数: {len(chat_request.messages)}")
    try:
        vertex_messages = build_vertex_chat_messages(
            system_prompt=SESSIONMUSE_CHAT_SYSTEM_PROMPT_TEXT,
            analysis_context=chat_request.analysis_context,
            chat_history=chat_request.messages
        )
    except Exception as e:
        logger.error(f"Vertex AIチャットメッセージの構築エラー: {e}", exc_info=True)
        raise InternalServerErrorException(message="AIプロンプトの構築に失敗しました。",detail=str(e))

    accept_header = request.headers.get("accept", "").lower()
    is_streaming_requested = "text/event-stream" in accept_header

    try:
        llm = get_vertex_llm_for_chat()
        if is_streaming_requested:
            logger.info("ストリーミングレスポンスが要求されました。Vertex AIストリームを開始します。")
            return StreamingResponse(
                stream_vertex_response_as_sse(llm, vertex_messages),
                media_type="text/event-stream"
            )
        else:
            logger.info("通常のJSONレスポンスが要求されました。Vertex AIを呼び出します。")
            ai_response: AIMessage = await llm.ainvoke(vertex_messages)
            if not ai_response.content or not isinstance(ai_response.content, str):
                logger.error(f"Vertex AI APIが空または無効なコンテンツを返しました: {ai_response.content}")
                raise GeminiAPIErrorException(message="AIの応答が空か予期せぬ形式でした (Vertex AI)。")
            logger.info(f"AIからの非ストリーミング応答を受信: '{str(ai_response.content)[:100]}...'")
            return ChatMessage(role="assistant", content=ai_response.content)
    except Exception as e:
        if "blocked" in str(e).lower() or "safety filter" in str(e).lower():
            logger.warning(f"Vertex AI APIチャットリクエストがブロックされた可能性があります (メインハンドラ)。理由: {e}", exc_info=True)
            raise GeminiAPIErrorException(message="あなたのリクエストはAIの安全フィルターによってブロックされた可能性があります (Vertex AI)。", detail=str(e), error_code=ErrorCode.GEMINI_API_ERROR)
        elif isinstance(e, asyncio.TimeoutError):
            logger.error(f"Vertex AI API呼び出しがタイムアウトしました (メインハンドラ)。", exc_info=True)
            raise GeminiAPIErrorException(message=f"AIチャットリクエストがタイムアウトしました (Vertex AI)。", error_code=ErrorCode.GEMINI_API_ERROR)
        elif isinstance(e, GeminiAPIErrorException):
            raise
        else:
            logger.error(f"チャット用Vertex AI API呼び出し中のエラー (メインハンドラ): {e}", exc_info=True)
            raise GeminiAPIErrorException(message="AIとの通信中に予期せぬエラーが発生しました (Vertex AI)。", detail=str(e), error_code=ErrorCode.GEMINI_API_ERROR)
