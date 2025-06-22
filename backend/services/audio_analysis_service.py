import asyncio
import logging
import re
import time
import uuid
from typing import TypedDict, List, Dict, Any, Optional, Union

from langgraph.graph import StateGraph, END
from langchain_core.messages import SystemMessage, HumanMessage, AIMessage, BaseMessageChunk
from langchain_core.exceptions import OutputParserException
from langchain_google_vertexai import ChatVertexAI, HarmCategory, HarmBlockThreshold

from ..models import AnalysisResult, ErrorCode, ChordProgressionOutput, KeyOutput, BpmOutput, GenreOutput
from ..exceptions import AnalysisFailedException, GenerationFailedException, VertexAIAPIErrorException # Changed
from ..config import settings
from . import prompts

logger = logging.getLogger(__name__)

class AudioAnalysisWorkflowState(TypedDict):
    gcs_file_path: str
    workflow_run_id: Optional[str]
    estimated_key: Optional[str]
    key_estimation_error: Optional[str]
    estimated_bpm: Optional[int]
    bpm_estimation_error: Optional[str]
    estimated_chords: Optional[List[str]]
    chords_estimation_error: Optional[str]
    estimated_genre: Optional[str]
    genre_estimation_error: Optional[str]
    analysis_error: Optional[str] # Aggregated error from analysis steps
    generated_backing_track_data: Optional[str]
    generation_error: Optional[str]
    final_analysis_result: Optional[AnalysisResult]
    # Flags to indicate if error handlers were executed (optional, for more complex logic)
    analysis_handled: Optional[bool]
    generation_handled: Optional[bool]
    entry_point_completed: Optional[bool]


class AudioAnalyzer:
    def __init__(self, location: str = settings.VERTEX_AI_LOCATION, model_name: str = settings.GEMINI_MODEL_NAME, timeout: int = settings.VERTEX_AI_TIMEOUT_SECONDS):
        self.location = location
        self.model_name = model_name # Note: settings.GEMINI_MODEL_NAME is used here. Consider renaming if it's purely Vertex.
        self.timeout = timeout
        self.safety_settings = {
            HarmCategory.HARM_CATEGORY_HARASSMENT: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
            HarmCategory.HARM_CATEGORY_HATE_SPEECH: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
            HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT: HarmBlockThreshold.BLOCK_ONLY_HIGH,
            HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
        }

    def _get_llm(self, task_description: str, for_generation: bool = False) -> ChatVertexAI:
        try:
            temperature = 0.7 if for_generation else 0.3
            llm = ChatVertexAI(
                location=self.location,
                model_name=self.model_name,
                temperature=temperature,
                request_timeout=self.timeout,
                safety_settings=self.safety_settings,
            )
            logger.info(f"'{task_description}'用ChatVertexAIをモデル'{self.model_name}', Location: {self.location})で初期化しました。")
            return llm
        except Exception as e:
            logger.error(f"ChatVertexAIの初期化に失敗しました ('{task_description}'): {e}", exc_info=True)
            raise VertexAIAPIErrorException(message=f"Vertex AI LLMの初期化に失敗しました ('{task_description}')。", detail=str(e), error_code=ErrorCode.VERTEX_AI_API_ERROR)

    async def _call_vertex_api(
        self,
        llm: ChatVertexAI,
        messages: List[Union[SystemMessage, HumanMessage, AIMessage]],
        task_description: str,
        request_params: Dict[str, Any],
        workflow_run_id: Optional[str] = None,
        is_structured_output: bool = False,
        output_schema: Optional[Any] = None
    ) -> Union[AIMessage, Any]:
        api_call_start_time = time.time()
        try:
            target_llm = llm.with_structured_output(output_schema, include_raw=False) if is_structured_output and output_schema else llm
            response_data = await target_llm.ainvoke(messages)
            api_call_duration = time.time() - api_call_start_time

            log_extra = {
                "target_service": "VertexAI", "vertex_model": self.model_name,
                "task": task_description, "duration_seconds": api_call_duration,
                "request_params": request_params, "workflow_run_id": workflow_run_id,
            }
            if is_structured_output and hasattr(response_data, 'model_dump'):
                log_extra["parsed_output"] = response_data.model_dump()
            elif isinstance(response_data, AIMessage) and response_data.content:
                log_extra["response_content_length"] = len(str(response_data.content))

            logger.info(f"Vertex AI API呼び出し成功 ({task_description})", extra=log_extra)
            return response_data
        except Exception as e:
            api_call_duration = time.time() - api_call_start_time
            logger.error(
                f"Vertex AI API呼び出し失敗 ({task_description})", exc_info=True,
                extra={
                    "target_service": "VertexAI", "vertex_model": self.model_name,
                    "task": task_description, "duration_seconds": api_call_duration,
                    "request_params": request_params, "workflow_run_id": workflow_run_id,
                    "error_type": type(e).__name__,
                }
            )
            if "blocked" in str(e).lower() or "safety filter" in str(e).lower():
                raise VertexAIAPIErrorException(message=f"{task_description}リクエストが安全フィルターでブロックされた可能性があります (Vertex AI)。", detail=str(e), error_code=ErrorCode.VERTEX_AI_API_ERROR)
            if isinstance(e, asyncio.TimeoutError):
                raise VertexAIAPIErrorException(message=f"{task_description}がタイムアウトしました (Vertex AI)。", detail=str(e), error_code=ErrorCode.VERTEX_AI_API_ERROR)
            if isinstance(e, OutputParserException):
                 raise AnalysisFailedException(message=f"{task_description}: AIの応答形式が不正でパースできませんでした (Vertex AI)。", detail=getattr(e, 'llm_output', str(e)))
            raise VertexAIAPIErrorException(message=f"{task_description}中にエラーが発生しました (Vertex AI)。", detail=str(e), error_code=ErrorCode.VERTEX_AI_API_ERROR)

    async def estimate_key(self, gcs_file_path: str, workflow_run_id: Optional[str]) -> str:
        task = "Key Estimation (Structured)"
        llm = self._get_llm(task)
        prompt_text = prompts.KEY_ESTIMATION_PROMPT_STRUCTURED.format(gcs_file_path=gcs_file_path)
        messages = [SystemMessage(content=prompts.AUDIO_ANALYSIS_SYSTEM_PROMPT_STRUCTURED), HumanMessage(content=prompt_text)]
        parsed_output: KeyOutput = await self._call_vertex_api(
            llm, messages, task, {"gcs_file_path": gcs_file_path}, workflow_run_id, True, KeyOutput
        )
        if not parsed_output.primary_key or parsed_output.primary_key == "Undetermined":
            logger.warning(f"[{task}] Vertex AI が未確定の主キーを返しました。")
            return "Undetermined"
        return parsed_output.primary_key

    async def estimate_bpm(self, gcs_file_path: str, workflow_run_id: Optional[str]) -> int:
        task = "BPM Estimation (Structured)"
        llm = self._get_llm(task)
        prompt_text = prompts.BPM_ESTIMATION_PROMPT_STRUCTURED.format(gcs_file_path=gcs_file_path)
        messages = [SystemMessage(content=prompts.AUDIO_ANALYSIS_SYSTEM_PROMPT_STRUCTURED), HumanMessage(content=prompt_text)]
        parsed_output: BpmOutput = await self._call_vertex_api(
            llm, messages, task, {"gcs_file_path": gcs_file_path}, workflow_run_id, True, BpmOutput
        )
        if parsed_output.bpm <= 0:
            logger.warning(f"[{task}] Vertex AI が無効なBPMを返しました: {parsed_output.bpm}")
            raise AnalysisFailedException(message="AIが有効なBPMを返しませんでした (Vertex AI)。")
        return parsed_output.bpm

    async def estimate_chords(self, gcs_file_path: str, workflow_run_id: Optional[str]) -> List[str]:
        task = "Chord Progression Estimation (Structured)"
        llm = self._get_llm(task)
        prompt_text = prompts.CHORD_PROGRESSION_PROMPT_STRUCTURED.format(gcs_file_path=gcs_file_path)
        messages = [SystemMessage(content=prompts.AUDIO_ANALYSIS_SYSTEM_PROMPT_STRUCTURED), HumanMessage(content=prompt_text)]
        parsed_output: ChordProgressionOutput = await self._call_vertex_api(
            llm, messages, task, {"gcs_file_path": gcs_file_path}, workflow_run_id, True, ChordProgressionOutput
        )
        if not parsed_output.chords:
            logger.warning(f"[{task}] Vertex AI がコード進行の空リストを返しました。Undeterminedとして扱います。")
            return ["Undetermined"]
        return parsed_output.chords

    async def estimate_genre(self, gcs_file_path: str, workflow_run_id: Optional[str]) -> str:
        task = "Genre Estimation (Structured)"
        llm = self._get_llm(task)
        prompt_text = prompts.GENRE_ESTIMATION_PROMPT_STRUCTURED.format(gcs_file_path=gcs_file_path)
        messages = [SystemMessage(content=prompts.AUDIO_ANALYSIS_SYSTEM_PROMPT_STRUCTURED), HumanMessage(content=prompt_text)]
        parsed_output: GenreOutput = await self._call_vertex_api(
            llm, messages, task, {"gcs_file_path": gcs_file_path}, workflow_run_id, True, GenreOutput
        )
        if not parsed_output.primary_genre or parsed_output.primary_genre == "Undetermined":
            logger.warning(f"[{task}] Vertex AI が未確定の主要ジャンルを返しました。")
            return "Undetermined"
        return parsed_output.primary_genre

    async def generate_backing_track(self, key: str, bpm: int, chords: List[str], genre: str, workflow_run_id: Optional[str]) -> str:
        task = "Backing Track Generation (MusicXML)"
        llm = self._get_llm(task, for_generation=True)
        chords_str = ", ".join(chords)
        prompt_text = prompts.BACKING_TRACK_GENERATION_PROMPT_TEMPLATE.format(key=key, bpm=bpm, chords_str=chords_str, genre=genre)
        messages = [SystemMessage(content=prompts.MUSIC_GENERATION_SYSTEM_PROMPT), HumanMessage(content=prompt_text)]
        request_params = {"key": key, "bpm": bpm, "chords": chords_str, "genre": genre}
        response: AIMessage = await self._call_vertex_api(llm, messages, task, request_params, workflow_run_id) # type: ignore
        content = response.content

        logger.debug(f'LLM (Vertex AI) からのMusicXML用Rawコンテント: {str(content)[:500]}')
        if isinstance(content, str):
            match = re.search(r"MUSICXML_START\s*([\s\S]+?)\s*MUSICXML_END", content, re.DOTALL)
            if match:
                musicxml_text = match.group(1).strip()
                if not musicxml_text:
                    raise GenerationFailedException(message="抽出されたMusicXMLデータが空です (Vertex AI)。", detail="LLM response contained MUSICXML_START/END tags but no content.")
                if not (musicxml_text.startswith("<?xml") or musicxml_text.startswith("<score-partwise")):
                    logger.warning(f"生成されたMusicXML (Vertex AI) は整形されていない可能性があります: {musicxml_text[:100]}")
                return musicxml_text
            if "CANNOT_GENERATE_MUSICXML" in content.upper():
                 raise GenerationFailedException(message="Vertex AI がMusicXMLデータを生成できないと報告しました。", detail=content)
            logger.warning(f"LLM応答 (Vertex AI) のMusicXMLにMUSICXML_START/ENDタグが含まれていませんでした。コンテント: {content[:200]}")
            raise GenerationFailedException(message="Vertex AI が期待する形式でMusicXMLデータを返しませんでした (タグ欠落)。", detail=f"Response (start): {str(content)[:200]}")
        raise GenerationFailedException(message=f"バッキングトラック生成で予期せぬ応答タイプ。期待:str, 受信:{type(content)}。", detail=f"Content: {str(content)[:200]}")

audio_analyzer = AudioAnalyzer()

async def node_log_event(state: AudioAnalysisWorkflowState, event_name: str, is_start: bool, data: Optional[Dict] = None) -> None:
    log_level = logging.DEBUG
    status = "開始" if is_start else "終了"
    message = f"ワークフローノード {event_name} {status}"
    extra_info = {"workflow_run_id": state.get("workflow_run_id"), "node_name": event_name}
    if data: extra_info.update(data)
    if not is_start and "start_time" in extra_info:
        duration = time.time() - extra_info.pop("start_time")
        extra_info["duration_seconds"] = round(duration, 2)
        message += f". Duration: {extra_info['duration_seconds']:.2f}s"
    logger.log(log_level, message, extra=extra_info)

async def execute_analysis_node(state: AudioAnalysisWorkflowState, analysis_func_name: str, output_key: str, error_key: str) -> Dict[str, Any]:
    node_name = analysis_func_name
    start_time = time.time()
    await node_log_event(state, node_name, is_start=True, data={"start_time": start_time})
    output: Dict[str, Any] = {}
    try:
        analysis_method = getattr(audio_analyzer, analysis_func_name)
        result = await analysis_method(state["gcs_file_path"], state.get("workflow_run_id"))
        output[output_key] = result
    except Exception as e:
        logger.error(f"Node {node_name} failed: {e}", exc_info=True, extra={"workflow_run_id": state.get("workflow_run_id")})
        output[error_key] = f"{node_name} failed: {str(e)}"
    await node_log_event(state, node_name, is_start=False, data={"start_time": start_time, **output})
    return output

async def node_estimate_key(state: AudioAnalysisWorkflowState) -> Dict[str, Any]:
    return await execute_analysis_node(state, "estimate_key", "estimated_key", "key_estimation_error")

async def node_estimate_bpm(state: AudioAnalysisWorkflowState) -> Dict[str, Any]:
    return await execute_analysis_node(state, "estimate_bpm", "estimated_bpm", "bpm_estimation_error")

async def node_estimate_chords(state: AudioAnalysisWorkflowState) -> Dict[str, Any]:
    return await execute_analysis_node(state, "estimate_chords", "estimated_chords", "chords_estimation_error")

async def node_estimate_genre(state: AudioAnalysisWorkflowState) -> Dict[str, Any]:
    return await execute_analysis_node(state, "estimate_genre", "estimated_genre", "genre_estimation_error")

async def node_aggregate_analysis_results(state: AudioAnalysisWorkflowState) -> Dict[str, Any]:
    node_name = "aggregate_analysis_results"
    start_time = time.time()
    await node_log_event(state, node_name, is_start=True, data={"start_time": start_time})
    output: Dict[str, Any] = {}
    errors = [err for key, err in state.items() if "error" in key and err and key not in ["analysis_error", "generation_error"]]

    if errors:
        output["analysis_error"] = "Analysis failed in one or more tasks: " + "; ".join(str(e) for e in errors)
        logger.error(output["analysis_error"], extra={"workflow_run_id": state.get("workflow_run_id"), "individual_errors": errors})
    else:
        missing = []
        if state.get("estimated_key") == "Undetermined": missing.append("key")
        if state.get("estimated_bpm", 0) <= 0: missing.append("BPM")
        if not state.get("estimated_chords") or state.get("estimated_chords") == ["Undetermined"]: missing.append("chords")
        if state.get("estimated_genre") == "Undetermined": missing.append("genre")

        if missing:
            output["analysis_error"] = f"必須の解析結果のいくつかが 'Undetermined' または無効です: {', '.join(missing)}。"
            logger.error(output["analysis_error"], extra={"workflow_run_id": state.get("workflow_run_id")})
        else:
            try:
                output["final_analysis_result"] = AnalysisResult(
                    key=state.get("estimated_key", "Undetermined"),
                    bpm=state.get("estimated_bpm", 0),
                    chords=state.get("estimated_chords", []),
                    genre_by_ai=state.get("estimated_genre", "Undetermined")
                )
            except Exception as e:
                logger.error(f"AnalysisResult Pydanticモデルの作成エラー: {e}", exc_info=True, extra={"workflow_run_id": state.get("workflow_run_id")})
                output["analysis_error"] = f"解析結果の最終処理に失敗しました: {str(e)}"

    await node_log_event(state, node_name, is_start=False, data={"start_time": start_time, **output})
    return output

async def node_generate_backing_track(state: AudioAnalysisWorkflowState) -> Dict[str, Any]:
    node_name = "generate_backing_track"
    start_time = time.time()
    await node_log_event(state, node_name, is_start=True, data={"start_time": start_time})
    output: Dict[str, Any] = {}
    analysis_result = state.get("final_analysis_result")

    if state.get("analysis_error") or not analysis_result:
        output["generation_error"] = "バッキングトラックを生成できません: 解析エラーまたは解析結果がありません。"
        logger.warning(output["generation_error"], extra={"workflow_run_id": state.get("workflow_run_id")})
    else:
        try:
            output["generated_backing_track_data"] = await audio_analyzer.generate_backing_track(
                key=analysis_result.key, bpm=analysis_result.bpm, chords=analysis_result.chords,
                genre=analysis_result.genre_by_ai, workflow_run_id=state.get("workflow_run_id")
            )
        except Exception as e:
            logger.error(f"Node {node_name} failed: {e}", exc_info=True, extra={"workflow_run_id": state.get("workflow_run_id")})
            output["generation_error"] = f"{node_name} failed: {str(e)}"

    await node_log_event(state, node_name, is_start=False, data={"start_time": start_time, "generation_error_present": bool(output.get("generation_error"))})
    return output

def build_workflow() -> StateGraph:
    workflow = StateGraph(AudioAnalysisWorkflowState)

    workflow.add_node("entry_point", lambda state: {"entry_point_completed": True})
    workflow.add_node("estimate_key_node", node_estimate_key)
    workflow.add_node("estimate_bpm_node", node_estimate_bpm)
    workflow.add_node("estimate_chords_node", node_estimate_chords)
    workflow.add_node("estimate_genre_node", node_estimate_genre)
    workflow.add_node("aggregate_analysis_node", node_aggregate_analysis_results)
    workflow.add_node("generate_backing_track_node", node_generate_backing_track)
    workflow.add_node("handle_analysis_error_node", lambda state: {"analysis_handled": True, "analysis_error": state.get("analysis_error") or "Unknown analysis error"})
    workflow.add_node("handle_generation_error_node", lambda state: {"generation_handled": True, "generation_error": state.get("generation_error") or "Unknown generation error"})

    workflow.set_entry_point("entry_point")
    workflow.add_conditional_edges("entry_point", lambda state: ["estimate_key_node", "estimate_bpm_node", "estimate_chords_node", "estimate_genre_node"])
    for node_name in ["estimate_key_node", "estimate_bpm_node", "estimate_chords_node", "estimate_genre_node"]:
        workflow.add_edge(node_name, "aggregate_analysis_node")
    workflow.add_conditional_edges("aggregate_analysis_node", lambda state: "handle_analysis_error_node" if state.get("analysis_error") else "generate_backing_track_node",
        {"generate_backing_track_node": "generate_backing_track_node", "handle_analysis_error_node": "handle_analysis_error_node"})
    workflow.add_edge("handle_analysis_error_node", END)
    workflow.add_conditional_edges("generate_backing_track_node", lambda state: "handle_generation_error_node" if state.get("generation_error") or not state.get("generated_backing_track_data") else END,
        {END: END, "handle_generation_error_node": "handle_generation_error_node"})
    workflow.add_edge("handle_generation_error_node", END)
    return workflow.compile()

app_graph = build_workflow()

async def run_audio_analysis_workflow(gcs_file_path: str) -> AudioAnalysisWorkflowState:
    workflow_run_id = uuid.uuid4().hex
    logger.info(f"音声解析ワークフロー開始 ({gcs_file_path})", extra={"workflow_run_id": workflow_run_id, "gcs_file_path": gcs_file_path})
    start_time_overall = time.time()
    initial_state = AudioAnalysisWorkflowState(
        gcs_file_path=gcs_file_path, workflow_run_id=workflow_run_id, estimated_key=None, key_estimation_error=None,
        estimated_bpm=None, bpm_estimation_error=None, estimated_chords=None, chords_estimation_error=None,
        estimated_genre=None, genre_estimation_error=None, analysis_error=None, generated_backing_track_data=None,
        generation_error=None, final_analysis_result=None, analysis_handled=None, generation_handled=None,
        entry_point_completed=None
    )
    final_state: AudioAnalysisWorkflowState = initial_state
    try:
        config = {"recursion_limit": 15, "configurable": {"workflow_run_id": workflow_run_id}}
        invoked_state = await app_graph.ainvoke(initial_state, config=config)
        if isinstance(invoked_state, AudioAnalysisWorkflowState):
            final_state = invoked_state
        else:
            logger.warning(f"app_graph.ainvoke returned an unexpected type: {type(invoked_state)}. Using initial state as fallback.")
            final_state["analysis_error"] = (final_state.get("analysis_error") or "") + " | Workflow invocation returned unexpected type."
    except Exception as e:
        logger.error(f"LangGraphワークフロー実行中の致命的エラー ({gcs_file_path}): {e}", exc_info=True, extra={"workflow_run_id": workflow_run_id})
        error_addon = f" | Workflow execution framework error: {type(e).__name__}: {e}"
        final_state["analysis_error"] = (final_state.get("analysis_error") or "") + error_addon
        final_state["generation_error"] = (final_state.get("generation_error") or "") + error_addon

    duration = time.time() - start_time_overall
    log_extra = {
        "workflow_run_id": workflow_run_id, "gcs_file_path": gcs_file_path, "duration_seconds": round(duration, 2),
        "analysis_result_present": bool(final_state.get("final_analysis_result")),
        "generation_data_present": bool(final_state.get("generated_backing_track_data")),
        "analysis_error": final_state.get("analysis_error"), "generation_error": final_state.get("generation_error"),
    }
    if not final_state.get("final_analysis_result"):
        detail = str(final_state.get('analysis_error', "ワークフローは解析結果を生成せずに終了しました。"))
        logger.error(f"音声解析失敗（結果欠落）: {detail}", extra=log_extra)
        raise AnalysisFailedException(message="音声解析が正常に完了しませんでした（結果欠落）。", detail=detail)
    if not final_state.get("generated_backing_track_data"):
        detail = str(final_state.get('generation_error', "ワークフローはバッキングトラックデータを生成せずに終了しました。"))
        logger.error(f"バッキングトラック生成失敗（データ欠落）: {detail}", extra=log_extra)
        raise GenerationFailedException(message="バッキングトラック生成が正常に完了しませんでした（データ欠落）。", detail=detail)
    logger.info(f"ワークフロー ({gcs_file_path}) 正常終了。", extra=log_extra)
    return final_state
