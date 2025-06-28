# backend/services/vertex_chat_service.py
import logging
import asyncio
from typing import Union, List, AsyncGenerator, Optional

from langchain_core.messages import SystemMessage, HumanMessage, AIMessage, BaseMessageChunk
from langchain_google_vertexai import ChatVertexAI, HarmCategory, HarmBlockThreshold

from models import ChatMessage, ErrorCode
from config import settings
from exceptions import VertexAIAPIErrorException, InternalServerErrorException # Changed
from services import prompts

logger = logging.getLogger(__name__)

class VertexChatService:
    def __init__(self, llm_client: Optional[ChatVertexAI] = None):
        if llm_client:
            self.llm = llm_client
        else:
            try:
                safety_settings_vertex = {
                    HarmCategory.HARM_CATEGORY_HARASSMENT: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
                    HarmCategory.HARM_CATEGORY_HATE_SPEECH: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
                    HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT: HarmBlockThreshold.BLOCK_ONLY_HIGH,
                    HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
                }
                self.llm = ChatVertexAI(
                    location=settings.VERTEX_AI_LOCATION,
                    model_name=settings.CHAT_GEMINI_MODEL_NAME,
                    temperature=0.7,
                    request_timeout=settings.VERTEX_AI_TIMEOUT_SECONDS,
                    safety_settings=safety_settings_vertex,
                )
                logger.info(f"ChatVertexAI initialized for chat service with model '{settings.CHAT_GEMINI_MODEL_NAME}', Location: {settings.VERTEX_AI_LOCATION}).")
            except Exception as e:
                logger.error(f"Failed to initialize ChatVertexAI for chat service: {e}", exc_info=True)
                raise VertexAIAPIErrorException(message="Failed to initialize Vertex AI LLM for chat.", detail=str(e), error_code=ErrorCode.VERTEX_AI_API_ERROR)

    def build_vertex_chat_messages(
        self,
        system_prompt: str,
        humming_theme: Optional[str],
        chat_history: List[ChatMessage],
        musicxml_content: Optional[str] = None
    ) -> List[Union[SystemMessage, HumanMessage, AIMessage]]:
        messages: List[Union[SystemMessage, HumanMessage, AIMessage]] = []
        messages.append(SystemMessage(content=system_prompt))

        # コンテキスト情報を構築
        context_str_parts = []
        if humming_theme:
            context_str_parts.append(f"ユーザーが口ずさんだメロディの雰囲気/テーマ: 「{humming_theme}」")

        if musicxml_content:
            context_str_parts.append(f"このテーマに基づいて生成されたMusicXMLの内容:\n```musicxml\n{musicxml_content}\n```")
        else:
            context_str_parts.append("関連するMusicXMLファイルは提供されていません。")

        if context_str_parts:
            full_context_str = "現在の音楽制作の状況:\n" + "\n".join(context_str_parts)
            messages.append(SystemMessage(content=full_context_str))
            logger.info(f"チャットコンテキスト追加: {full_context_str[:200]}...")

        for msg_data in chat_history:
            if msg_data.role == "user": messages.append(HumanMessage(content=msg_data.content))
            elif msg_data.role == "assistant": messages.append(AIMessage(content=msg_data.content))
        logger.debug(f"Built {len(messages)} Vertex AI chat messages.")
        return messages


    async def stream_vertex_response_as_sse(
        self,
        messages: List[Union[SystemMessage, HumanMessage, AIMessage]]
    ) -> AsyncGenerator[str, None]:
        full_response_content = ""
        try:
            async for chunk in self.llm.astream(messages):
                if not isinstance(chunk, BaseMessageChunk):
                    logger.warning(f"Unexpected chunk type in stream: {type(chunk)}. Skipping.")
                    continue
                content_piece = chunk.content
                if content_piece:
                    sse_chat_message = ChatMessage(role="assistant", content=str(content_piece))
                    yield f"data: {sse_chat_message.model_dump_json()}\n\n"
                    full_response_content += str(content_piece)
            logger.info(f"Finished streaming Vertex AI response. Total length: {len(full_response_content)}")
        except Exception as e:
            error_code_to_use = ErrorCode.VERTEX_AI_API_ERROR
            if "blocked" in str(e).lower() or "safety filter" in str(e).lower():
                logger.warning(f"Vertex AI API chat stream may have been blocked. Reason: {e}")
                error_message_content = f"[Error] Your request may have been blocked by AI safety filters. Detail: {str(e)[:100]}"
            elif isinstance(e, asyncio.TimeoutError):
                logger.error(f"Vertex AI API stream call timed out after {settings.VERTEX_AI_TIMEOUT_SECONDS} seconds.")
                error_message_content = f"[Error] AI chat request timed out after {settings.VERTEX_AI_TIMEOUT_SECONDS} seconds."
            elif isinstance(e, VertexAIAPIErrorException):
                logger.error(f"Vertex AI service error during stream: {e.message}")
                error_message_content = f"[Error] AI service error: {e.message}"
                error_code_to_use = e.error_code # Keep the original error code if it's already VertexAIAPIErrorException
            else:
                logger.error(f"Error during Vertex AI API stream for chat: {e}", exc_info=True)
                error_message_content = "[Error] An unexpected error occurred while communicating with the AI."

            error_message = ChatMessage(role="assistant", content=error_message_content)
            # We don't explicitly set error_code_to_use in ChatMessage, it's for the exception if re-raised
            yield f"data: {error_message.model_dump_json()}\n\n"


    async def generate_chat_response(
        self,
        messages: List[Union[SystemMessage, HumanMessage, AIMessage]]
    ) -> ChatMessage:
        try:
            ai_response: AIMessage = await self.llm.ainvoke(messages)
            if not ai_response.content or not isinstance(ai_response.content, str):
                logger.error(f"Vertex AI API returned empty or invalid content: {ai_response.content}")
                raise VertexAIAPIErrorException(message="AI response was empty or in an unexpected format (Vertex AI).", error_code=ErrorCode.VERTEX_AI_API_ERROR)
            logger.info(f"Received non-streaming AI response: '{str(ai_response.content)[:100]}...'")
            return ChatMessage(role="assistant", content=ai_response.content)
        except Exception as e:
            logger.error(f"Error during Vertex AI API call for chat (non-streaming): {e}", exc_info=True)
            if "blocked" in str(e).lower() or "safety filter" in str(e).lower():
                raise VertexAIAPIErrorException(message="Your request may have been blocked by AI safety filters (Vertex AI).", detail=str(e), error_code=ErrorCode.VERTEX_AI_API_ERROR)
            elif isinstance(e, asyncio.TimeoutError):
                 raise VertexAIAPIErrorException(message=f"AI chat request timed out (Vertex AI).", detail=str(e), error_code=ErrorCode.VERTEX_AI_API_ERROR)
            elif isinstance(e, VertexAIAPIErrorException): # If it's already the correct type, re-raise
                raise
            else: # Wrap other exceptions
                raise VertexAIAPIErrorException(message="An unexpected error occurred while communicating with the AI (Vertex AI).", detail=str(e), error_code=ErrorCode.VERTEX_AI_API_ERROR)

def get_vertex_chat_service() -> VertexChatService:
    return VertexChatService()
