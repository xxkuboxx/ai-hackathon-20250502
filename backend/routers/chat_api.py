# routers/chat_api.py

import logging
import asyncio
import json
from fastapi import APIRouter, HTTPException, Request, Body
from fastapi.responses import JSONResponse, StreamingResponse
from typing import Union, List, Dict, Any, AsyncGenerator, Optional

from langchain_core.messages import SystemMessage, HumanMessage, AIMessage, BaseMessageChunk
from langchain_google_genai import ChatGoogleGenerativeAI, HarmBlockThreshold, HarmCategory
import google.generativeai as genai

from models import ChatRequest, ChatMessage, ErrorResponse, ErrorCode, AnalysisResult
from config import settings
from exceptions import GeminiAPIErrorException, InternalServerErrorException

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

def get_gemini_llm_for_chat() -> ChatGoogleGenerativeAI:
    if not settings.GEMINI_API_KEY_FINAL:
        logger.error("チャット用GEMINI_API_KEY_FINALが設定されていません。")
        raise GeminiAPIErrorException(message="Gemini APIキーが設定されていません。", error_code=ErrorCode.GEMINI_API_ERROR)
    try:
        llm = ChatGoogleGenerativeAI(
            model=settings.GEMINI_MODEL_NAME,
            google_api_key=settings.GEMINI_API_KEY_FINAL,
            temperature=0.7,
            request_timeout=settings.GEMINI_API_TIMEOUT_SECONDS,
            safety_settings={
                HarmCategory.HARM_CATEGORY_HARASSMENT: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
                HarmCategory.HARM_CATEGORY_HATE_SPEECH: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
                HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT: HarmBlockThreshold.BLOCK_ONLY_HIGH,
                HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
            },
            convert_system_message_to_human=True
        )
        return llm
    except Exception as e:
        logger.error(f"チャット用ChatGoogleGenerativeAIの初期化に失敗しました: {e}", exc_info=True)
        raise GeminiAPIErrorException(message="チャット用Gemini LLMの初期化に失敗しました。", detail=str(e))

def build_gemini_chat_messages(
    system_prompt: str,
    analysis_context: Optional[AnalysisResult],
    chat_history: List[ChatMessage]
) -> List[Union[SystemMessage, HumanMessage, AIMessage]]:
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
    logger.debug(f"{len(messages)}件のGeminiメッセージを構築しました。")
    return messages

async def stream_gemini_response_as_sse(
    llm: ChatGoogleGenerativeAI,
    messages: List[Union[SystemMessage, HumanMessage, AIMessage]]
) -> AsyncGenerator[str, None]:
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
        logger.info(f"Geminiレスポンスのストリーミングを終了しました。総長: {len(full_response_content)}")
    except genai.types.generation_types.BlockedPromptException as bpe: # type: ignore
        logger.warning(f"Gemini APIチャットストリームがブロックされました。理由: {bpe}")
        error_message = ChatMessage(role="assistant", content=f"[エラー] あなたのリクエストはAIの安全フィルターによってブロックされました。詳細: {str(bpe)[:100]}")
        yield f"data: {error_message.model_dump_json()}\n\n"
    except asyncio.TimeoutError:
        logger.error(f"Gemini APIストリーム呼び出しが {settings.GEMINI_API_TIMEOUT_SECONDS}秒後にタイムアウトしました。")
        error_message = ChatMessage(role="assistant", content=f"[エラー] AIチャットリクエストが {settings.GEMINI_API_TIMEOUT_SECONDS}秒後にタイムアウトしました。")
        yield f"data: {error_message.model_dump_json()}\n\n"
    except GeminiAPIErrorException as e:
        logger.error(f"ストリーム中のGeminiAPIErrorException: {e.message}")
        error_message = ChatMessage(role="assistant", content=f"[エラー] AIサービスエラー: {e.message}")
        yield f"data: {error_message.model_dump_json()}\n\n"
    except Exception as e:
        logger.error(f"チャット用Gemini APIストリーム中のエラー: {e}", exc_info=True)
        error_message = ChatMessage(role="assistant", content="[エラー] AIとの通信中に予期せぬエラーが発生しました。")
        yield f"data: {error_message.model_dump_json()}\n\n"

@router.post("/chat", response_model=ChatMessage)
async def handle_chat_request(
    request: Request,
    chat_request: ChatRequest = Body(...)
):
    logger.info(f"チャットリクエスト受信。メッセージ数: {len(chat_request.messages)}")
    try:
        gemini_messages = build_gemini_chat_messages(
            system_prompt=SESSIONMUSE_CHAT_SYSTEM_PROMPT_TEXT,
            analysis_context=chat_request.analysis_context,
            chat_history=chat_request.messages
        )
    except Exception as e:
        logger.error(f"Geminiチャットメッセージの構築エラー: {e}", exc_info=True)
        raise InternalServerErrorException(message="AIプロンプトの構築に失敗しました。",detail=str(e))

    accept_header = request.headers.get("accept", "").lower()
    is_streaming_requested = "text/event-stream" in accept_header

    try:
        llm = get_gemini_llm_for_chat()
        if is_streaming_requested:
            logger.info("ストリーミングレスポンスが要求されました。Geminiストリームを開始します。")
            return StreamingResponse(
                stream_gemini_response_as_sse(llm, gemini_messages),
                media_type="text/event-stream"
            )
        else:
            logger.info("通常のJSONレスポンスが要求されました。Geminiを呼び出します。")
            ai_response: AIMessage = await llm.ainvoke(gemini_messages)
            if not ai_response.content or not isinstance(ai_response.content, str):
                logger.error(f"Gemini APIが空または無効なコンテンツを返しました: {ai_response.content}")
                raise GeminiAPIErrorException(message="AIの応答が空か予期せぬ形式でした。")
            logger.info(f"AIからの非ストリーミング応答を受信: '{str(ai_response.content)[:100]}...'")
            return ChatMessage(role="assistant", content=ai_response.content)
    except genai.types.generation_types.BlockedPromptException as bpe: # type: ignore
        logger.warning(f"Gemini APIチャットリクエストがブロックされました (メインハンドラ)。理由: {bpe}", exc_info=True)
        raise GeminiAPIErrorException(message="あなたのリクエストはAIの安全フィルターによってブロックされました。", detail=str(bpe), error_code=ErrorCode.GEMINI_API_ERROR)
    except asyncio.TimeoutError:
        logger.error(f"Gemini API呼び出しがタイムアウトしました (メインハンドラ)。", exc_info=True)
        raise GeminiAPIErrorException(message=f"AIチャットリクエストがタイムアウトしました。", error_code=ErrorCode.GEMINI_API_ERROR)
    except GeminiAPIErrorException:
        raise
    except Exception as e:
        logger.error(f"チャット用Gemini API呼び出し中のエラー (メインハンドラ): {e}", exc_info=True)
        if "API key not valid" in str(e) or "PERMISSION_DENIED" in str(e):
             raise GeminiAPIErrorException(message="Gemini APIキーが無効か、権限がありません。", detail=str(e), error_code=ErrorCode.GEMINI_API_ERROR)
        raise GeminiAPIErrorException(message="AIとの通信中に予期せぬエラーが発生しました。", detail=str(e), error_code=ErrorCode.GEMINI_API_ERROR)
