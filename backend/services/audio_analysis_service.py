import asyncio
import logging
import re
import json
import time
import uuid
from typing import TypedDict, List, Dict, Any, Optional, AsyncGenerator, Union

from langgraph.graph import StateGraph, END, START
from langchain_core.messages import SystemMessage, HumanMessage, AIMessage, BaseMessageChunk
from langchain_core.exceptions import OutputParserException

from langchain_google_vertexai import ChatVertexAI, HarmCategory, HarmBlockThreshold

from models import AnalysisResult, ErrorCode, ChordProgressionOutput, KeyOutput, BpmOutput, GenreOutput
from exceptions import AnalysisFailedException, GenerationFailedException, GeminiAPIErrorException, ExternalServiceErrorException
from config import settings

logger = logging.getLogger(__name__)

def get_vertex_llm(task_description: str, for_generation: bool = False) -> ChatVertexAI:
    """
    指定されたタスクのためのVertex AI LLMクライアントを取得します。
    Vertex AIではAPIキーは通常ADC (Application Default Credentials) によって処理されます。
    """
    if not settings.VERTEX_AI_PROJECT_ID:
        logger.error(f"{task_description}: VERTEX_AI_PROJECT_IDが設定されていません。")
        raise ExternalServiceErrorException(message="Vertex AI プロジェクトIDが設定されていません。", error_code=ErrorCode.EXTERNAL_SERVICE_ERROR)

    try:
        temperature = 0.7 if for_generation else 0.3

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
            temperature=temperature,
            request_timeout=settings.VERTEX_AI_TIMEOUT_SECONDS,
            safety_settings=safety_settings_vertex,
        )
        logger.info(f"'{task_description}'用ChatVertexAIをモデル'{settings.GEMINI_MODEL_NAME}' (Project: {settings.VERTEX_AI_PROJECT_ID}, Location: {settings.VERTEX_AI_LOCATION})で初期化しました。")
        return llm
    except Exception as e:
        logger.error(f"ChatVertexAIの初期化に失敗しました ('{task_description}'): {e}", exc_info=True)
        # GeminiAPIErrorExceptionを流用するが、エラーメッセージはVertex AIに合わせる
        raise GeminiAPIErrorException(message=f"Vertex AI LLMの初期化に失敗しました ('{task_description}')。", detail=str(e), error_code=ErrorCode.GEMINI_API_ERROR)


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
    analysis_error: Optional[str]
    generated_backing_track_data: Optional[str]
    generation_error: Optional[str]
    final_analysis_result: Optional[AnalysisResult]
    analysis_handled: Optional[bool]
    generation_handled: Optional[bool]
    entry_point_completed: Optional[bool]

AUDIO_ANALYSIS_SYSTEM_PROMPT_STRUCTURED = """
あなたは音楽理論と楽曲構造を専門とする熟練の音声アナリストです。
あなたのタスクは、提供された音声ファイルを分析し、特定の音楽情報を抽出することです。
応答は、私が提供する構造化フォーマット（JSONスキーマ）で提供してください。
音声ファイルは、ユーザーが提供したGCS URIにあります。
"""
KEY_ESTIMATION_PROMPT_STRUCTURED = """
GCS URI: "{gcs_file_path}" にある音声ファイルに基づいて、楽曲のキーを推定してください。
主要なキーと、その他考えられるキーを提示してください。
"""
BPM_ESTIMATION_PROMPT_STRUCTURED = """
GCS URI: "{gcs_file_path}" にある音声ファイルに基づいて、BPM（Beats Per Minute）を推定してください。
整数値で提供してください。
"""
CHORD_PROGRESSION_PROMPT_STRUCTURED = """
GCS URI: "{gcs_file_path}" にある音声ファイルに基づいて、主要なコード進行を推定してください。
コード文字列のリストで提供してください。
"""
GENRE_ESTimation_PROMPT_STRUCTURED = """
GCS URI: "{gcs_file_path}" にある音声ファイルに基づいて、音楽ジャンルを推定してください。
主要なジャンルと、その他考えられる副次的なジャンルを提示してください。
"""
MUSIC_GENERATION_SYSTEM_PROMPT = """
あなたは創造的なAI作曲家です。あなたのタスクは、提供された音楽パラメータに基づいて短いバッキングトラックを生成することです。
出力は直接使用可能な音楽データであるべきで、理想的にはMP3形式で、rawバイトまたはbase64エンコードされた文字列として提供できる場合です。
raw MP3データを生成できない場合は、その旨を明確に述べ、可能であれば代替の表現を提案してください。
この演習では、MP3データを期待しています。
"""
BACKING_TRACK_GENERATION_PROMPT_TEMPLATE = """
以下の特性を持つバッキングトラックのMusicXML構造を記述してください。
- キー: {key}
- BPM (Beats Per Minute): {bpm}
- コード進行: {chords_str} (これは進行の繰り返しループです)
- ジャンル: {genre}
- おおよその長さ: 10秒
- 希望フォーマット: MusicXMLテキストデータ。
MusicXMLのテキストデータは以下のようにフォーマットしてください:
MUSICXML_START
[ここにMusicXMLテキストデータを記述]
MUSICXML_END
MusicXML構造のみ出力してください。
```xml や ``` のようなマークダウンの囲みなどいかなるマークダウンフォーマットも使用しないせず、
コード部分のみをプレーンテキストで出力してください。
"""

async def _call_vertex_api_with_logging(
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
        if is_structured_output and output_schema:
            structured_llm = llm.with_structured_output(output_schema, include_raw=False)
            response_data = await structured_llm.ainvoke(messages)
        else:
            response_data = await llm.ainvoke(messages)

        api_call_duration = time.time() - api_call_start_time
        log_extra_response_data = {}
        if is_structured_output and hasattr(response_data, 'model_dump'):
            log_extra_response_data["parsed_output"] = response_data.model_dump()
        elif isinstance(response_data, AIMessage) and response_data.content:
            log_extra_response_data["response_content_length"] = len(str(response_data.content))

        logger.info(
            f"Vertex AI API呼び出し成功 ({task_description})",
            extra={
                "target_service": "VertexAI", "vertex_model": settings.GEMINI_MODEL_NAME,
                "task": task_description, "duration_seconds": api_call_duration,
                "request_params": request_params, "workflow_run_id": workflow_run_id,
                **log_extra_response_data
            }
        )
        return response_data
    except Exception as e:
        api_call_duration = time.time() - api_call_start_time
        logger.error(
            f"Vertex AI API呼び出し失敗 ({task_description})", exc_info=True,
            extra={
                "target_service": "VertexAI", "vertex_model": settings.GEMINI_MODEL_NAME,
                "task": task_description, "duration_seconds": api_call_duration,
                "request_params": request_params, "workflow_run_id": workflow_run_id,
                "error_type": type(e).__name__,
            }
        )
        # Vertex AI (LangChain経由) でのコンテンツブロックは、より一般的な例外でラップされる可能性がある
        if "blocked" in str(e).lower() or "safety filter" in str(e).lower():
            raise GeminiAPIErrorException(message=f"{task_description}リクエストが安全フィルターでブロックされた可能性があります (Vertex AI)。", detail=str(e), error_code=ErrorCode.GEMINI_API_ERROR)
        if isinstance(e, asyncio.TimeoutError):
            raise GeminiAPIErrorException(message=f"{task_description}がタイムアウトしました (Vertex AI)。", detail=str(e), error_code=ErrorCode.GEMINI_API_ERROR)
        if isinstance(e, OutputParserException): # OutputParsingException から OutputParserException に修正済み
             raise AnalysisFailedException(message=f"{task_description}: AIの応答形式が不正でパースできませんでした (Vertex AI)。", detail=getattr(e, 'llm_output', str(e)))

        raise GeminiAPIErrorException(message=f"{task_description}中にエラーが発生しました (Vertex AI)。", detail=str(e), error_code=ErrorCode.GEMINI_API_ERROR)


async def _estimate_key_gemini(gcs_file_path: str, workflow_run_id: Optional[str]) -> str:
    task = "Key Estimation (Structured)"
    llm = get_vertex_llm(task)
    prompt_text = KEY_ESTIMATION_PROMPT_STRUCTURED.format(gcs_file_path=gcs_file_path)
    messages = [SystemMessage(content=AUDIO_ANALYSIS_SYSTEM_PROMPT_STRUCTURED), HumanMessage(content=prompt_text)]
    parsed_output: KeyOutput = await _call_vertex_api_with_logging( # type: ignore
        llm, messages, task, {"gcs_file_path": gcs_file_path}, workflow_run_id,
        is_structured_output=True, output_schema=KeyOutput
    )
    if not parsed_output.primary_key or parsed_output.primary_key == "Undetermined":
        logger.warning(f"[{task}] Vertex AI が未確定の主キーを返しました。")
        return "Undetermined"
    return parsed_output.primary_key

async def _estimate_bpm_gemini(gcs_file_path: str, workflow_run_id: Optional[str]) -> int:
    task = "BPM Estimation (Structured)"
    llm = get_vertex_llm(task)
    prompt_text = BPM_ESTIMATION_PROMPT_STRUCTURED.format(gcs_file_path=gcs_file_path)
    messages = [SystemMessage(content=AUDIO_ANALYSIS_SYSTEM_PROMPT_STRUCTURED), HumanMessage(content=prompt_text)]
    parsed_output: BpmOutput = await _call_vertex_api_with_logging( # type: ignore
        llm, messages, task, {"gcs_file_path": gcs_file_path}, workflow_run_id,
        is_structured_output=True, output_schema=BpmOutput
    )
    if parsed_output.bpm <= 0:
        logger.warning(f"[{task}] Vertex AI が無効なBPMを返しました: {parsed_output.bpm}")
        raise AnalysisFailedException(message="AIが有効なBPMを返しませんでした (Vertex AI)。")
    return parsed_output.bpm

async def _estimate_chords_gemini(gcs_file_path: str, workflow_run_id: Optional[str]) -> List[str]:
    task = "Chord Progression Estimation (Structured)"
    llm = get_vertex_llm(task)
    prompt_text = CHORD_PROGRESSION_PROMPT_STRUCTURED.format(gcs_file_path=gcs_file_path)
    messages = [SystemMessage(content=AUDIO_ANALYSIS_SYSTEM_PROMPT_STRUCTURED), HumanMessage(content=prompt_text)]
    parsed_output: ChordProgressionOutput = await _call_vertex_api_with_logging( # type: ignore
        llm, messages, task, {"gcs_file_path": gcs_file_path}, workflow_run_id,
        is_structured_output=True, output_schema=ChordProgressionOutput
    )
    if not parsed_output.chords:
        logger.warning(f"[{task}] Vertex AI がコード進行の空リストを返しました。")
        return ["Undetermined"]
    return parsed_output.chords

async def _estimate_genre_gemini(gcs_file_path: str, workflow_run_id: Optional[str]) -> str:
    task = "Genre Estimation (Structured)"
    llm = get_vertex_llm(task)
    prompt_text = GENRE_ESTimation_PROMPT_STRUCTURED.format(gcs_file_path=gcs_file_path)
    messages = [SystemMessage(content=AUDIO_ANALYSIS_SYSTEM_PROMPT_STRUCTURED), HumanMessage(content=prompt_text)]
    parsed_output: GenreOutput = await _call_vertex_api_with_logging( # type: ignore
        llm, messages, task, {"gcs_file_path": gcs_file_path}, workflow_run_id,
        is_structured_output=True, output_schema=GenreOutput
    )
    if not parsed_output.primary_genre or parsed_output.primary_genre == "Undetermined":
        logger.warning(f"[{task}] Vertex AI が未確定の主要ジャンルを返しました。")
        return "Undetermined"
    return parsed_output.primary_genre

async def _generate_backing_track_gemini(key: str, bpm: int, chords: List[str], genre: str, workflow_run_id: Optional[str]) -> str:
    task = "Backing Track Generation (MusicXML)"
    llm = get_vertex_llm(task, for_generation=True)
    chords_str = ", ".join(chords)
    prompt_text = BACKING_TRACK_GENERATION_PROMPT_TEMPLATE.format(key=key, bpm=bpm, chords_str=chords_str, genre=genre)
    messages = [SystemMessage(content=MUSIC_GENERATION_SYSTEM_PROMPT), HumanMessage(content=prompt_text)]
    request_params = {"key": key, "bpm": bpm, "chords": chords_str, "genre": genre}
    response: AIMessage = await _call_vertex_api_with_logging(llm, messages, task, request_params, workflow_run_id) # type: ignore
    content = response.content

    logger.debug(f'LLM (Vertex AI) からのMusicXML用Rawコンテント: {str(content)[:500]}')

    if isinstance(content, str):
        musicxml_match = re.search(r"MUSICXML_START\s*([\s\S]+?)\s*MUSICXML_END", content, re.DOTALL)
        if musicxml_match:
            musicxml_text = musicxml_match.group(1).strip()
            if not musicxml_text:
                raise GenerationFailedException(message="抽出されたMusicXMLデータが空です (Vertex AI)。", detail="LLM response contained MUSICXML_START and MUSICXML_END tags but no content between them.")
            if not (musicxml_text.startswith("<?xml") or musicxml_text.startswith("<score-partwise")):
                 logger.warning(f"生成されたMusicXML (Vertex AI) は整形されていない可能性があります: {musicxml_text[:100]}")
            return musicxml_text

        if "CANNOT_GENERATE_MUSICXML" in content.upper():
            raise GenerationFailedException(message="Vertex AI がMusicXMLデータを生成できないと報告しました。", detail=content)

        logger.warning(f"LLM応答 (Vertex AI) のMusicXMLにMUSICXML_START/ENDタグが含まれていませんでした。コンテント: {content[:200]}")
        raise GenerationFailedException(
            message="Vertex AI が期待する形式でMusicXMLデータを返しませんでした (MUSICXML_START/END タグが見つかりません)。",
            detail=f"Response (start): {str(content)[:200]}"
        )

    raise GenerationFailedException(
        message=f"バッキングトラック生成でVertex AIから予期せぬ応答タイプ。期待したのはstrですが、得られたのは {type(content)} です。",
        detail=f"Response content (type: {type(content)}): {str(content)[:200]}"
    )


async def node_log_start(state: AudioAnalysisWorkflowState, node_name: str) -> None:
    logger.debug(f"ワークフローノード開始: {node_name}", extra={"workflow_run_id": state.get("workflow_run_id"), "node_name": node_name})

async def node_log_end(state: AudioAnalysisWorkflowState, node_name: str, start_time: float, output: Optional[Dict] = None) -> None:
    duration = time.time() - start_time
    logger.debug(f"ワークフローノード終了: {node_name}. Duration: {duration:.2f}s", extra={"workflow_run_id": state.get("workflow_run_id"), "node_name": node_name, "duration_seconds": duration})

async def node_estimate_key(state: AudioAnalysisWorkflowState) -> Dict[str, Any]:
    node_name = "estimate_key"
    await node_log_start(state, node_name)
    start_time = time.time()
    output: Dict[str, Any] = {}
    try:
        output["estimated_key"] = await _estimate_key_gemini(state["gcs_file_path"], state.get("workflow_run_id"))
    except Exception as e: output["key_estimation_error"] = f"{node_name} failed: {str(e)}"
    await node_log_end(state, node_name, start_time, output)
    return output

async def node_estimate_bpm(state: AudioAnalysisWorkflowState) -> Dict[str, Any]:
    node_name = "estimate_bpm"
    await node_log_start(state, node_name)
    start_time = time.time()
    output: Dict[str, Any] = {}
    try:
        output["estimated_bpm"] = await _estimate_bpm_gemini(state["gcs_file_path"], state.get("workflow_run_id"))
    except Exception as e: output["bpm_estimation_error"] = f"{node_name} failed: {str(e)}"
    await node_log_end(state, node_name, start_time, output)
    return output

async def node_estimate_chords(state: AudioAnalysisWorkflowState) -> Dict[str, Any]:
    node_name = "estimate_chords"
    await node_log_start(state, node_name)
    start_time = time.time()
    output: Dict[str, Any] = {}
    try:
        output["estimated_chords"] = await _estimate_chords_gemini(state["gcs_file_path"], state.get("workflow_run_id"))
    except Exception as e: output["chords_estimation_error"] = f"{node_name} failed: {str(e)}"
    await node_log_end(state, node_name, start_time, output)
    return output

async def node_estimate_genre(state: AudioAnalysisWorkflowState) -> Dict[str, Any]:
    node_name = "estimate_genre"
    await node_log_start(state, node_name)
    start_time = time.time()
    output: Dict[str, Any] = {}
    try:
        output["estimated_genre"] = await _estimate_genre_gemini(state["gcs_file_path"], state.get("workflow_run_id"))
    except Exception as e: output["genre_estimation_error"] = f"{node_name} failed: {str(e)}"
    await node_log_end(state, node_name, start_time, output)
    return output

async def node_aggregate_analysis_results(state: AudioAnalysisWorkflowState) -> Dict[str, Any]:
    node_name = "aggregate_analysis_results"
    await node_log_start(state, node_name)
    start_time = time.time()
    output: Dict[str, Any] = {}

    collected_errors = []
    if state.get("key_estimation_error"): collected_errors.append(state["key_estimation_error"]) # type: ignore
    if state.get("bpm_estimation_error"): collected_errors.append(state["bpm_estimation_error"]) # type: ignore
    if state.get("chords_estimation_error"): collected_errors.append(state["chords_estimation_error"]) # type: ignore
    if state.get("genre_estimation_error"): collected_errors.append(state["genre_estimation_error"]) # type: ignore

    if collected_errors:
        aggregated_error_message = "Analysis failed in one or more tasks: " + "; ".join(collected_errors)
        logger.error(aggregated_error_message, extra={"workflow_run_id": state.get("workflow_run_id"), "individual_errors": collected_errors})
        output["analysis_error"] = aggregated_error_message
        await node_log_end(state, node_name, start_time, output)
        return output

    missing_details = []
    if state.get("estimated_key") == "Undetermined": missing_details.append("key")
    if state.get("estimated_bpm") is None or state.get("estimated_bpm", 0) <= 0 : missing_details.append("BPM")
    if not state.get("estimated_chords") or state.get("estimated_chords") == ["Undetermined"]: missing_details.append("chords")
    if state.get("estimated_genre") == "Undetermined": missing_details.append("genre")

    if missing_details:
        err_msg = f"必須の解析結果のいくつかが 'Undetermined' または無効です: {', '.join(missing_details)}。"
        logger.error(err_msg, extra={"workflow_run_id": state.get("workflow_run_id")})
        output["analysis_error"] = err_msg
        await node_log_end(state, node_name, start_time, output)
        return output

    try:
        analysis_result = AnalysisResult(
            key=state.get("estimated_key", "Undetermined"),
            bpm=state.get("estimated_bpm", 0),
            chords=state.get("estimated_chords", []),
            genre_by_ai=state.get("estimated_genre", "Undetermined")
        )
        output["final_analysis_result"] = analysis_result
    except Exception as e:
        logger.error(f"AnalysisResult Pydanticモデルの作成エラー: {e}", exc_info=True, extra={"workflow_run_id": state.get("workflow_run_id")})
        output["analysis_error"] = f"解析結果の最終処理に失敗しました: {str(e)}"

    await node_log_end(state, node_name, start_time, output)
    return output

async def node_generate_backing_track(state: AudioAnalysisWorkflowState) -> Dict[str, Any]:
    node_name = "generate_backing_track"
    await node_log_start(state, node_name)
    start_time = time.time()
    output: Dict[str, Any] = {}
    if state.get("analysis_error") or state.get("generation_error"):
        await node_log_end(state, node_name, start_time)
        return output
    analysis_result = state.get("final_analysis_result")
    if not analysis_result:
        output["generation_error"] = "バッキングトラックを生成できません: 解析結果がないか無効です。"
        await node_log_end(state, node_name, start_time, output)
        return output
    try:
        track_data_str = await _generate_backing_track_gemini(
            key=analysis_result.key, bpm=analysis_result.bpm,
            chords=analysis_result.chords, genre=analysis_result.genre_by_ai,
            workflow_run_id=state.get("workflow_run_id")
        )
        output["generated_backing_track_data"] = track_data_str
    except Exception as e: output["generation_error"] = f"{node_name} failed: {str(e)}"
    await node_log_end(state, node_name, start_time, output)
    return output

def should_proceed_to_generation(state: AudioAnalysisWorkflowState) -> str:
    if state.get("analysis_error"): return "handle_analysis_error"
    if not state.get("final_analysis_result"): return "handle_analysis_error"
    return "generate_backing_track_node"

def check_generation_outcome(state: AudioAnalysisWorkflowState) -> str:
    if state.get("generation_error"): return "handle_generation_error"
    if not state.get("generated_backing_track_data"): return "handle_generation_error"
    return END

async def handle_analysis_error_node(state: AudioAnalysisWorkflowState) -> Dict[str, Any]:
    logger.error(f"解析エラー発生: {state.get('analysis_error')}", extra={"workflow_run_id": state.get("workflow_run_id")})
    return {"analysis_handled": True}

async def handle_generation_error_node(state: AudioAnalysisWorkflowState) -> Dict[str, Any]:
    logger.error(f"生成エラー発生: {state.get('generation_error')}", extra={"workflow_run_id": state.get("workflow_run_id")})
    return {"generation_handled": True}

async def entry_point_node(state: AudioAnalysisWorkflowState) -> Dict[str, Any]:
    logger.info("Workflow entry point node executing.", extra={"workflow_run_id": state.get("workflow_run_id")})
    return {"entry_point_completed": True}

workflow_v2 = StateGraph(AudioAnalysisWorkflowState)

workflow_v2.add_node("entry_point", entry_point_node)
workflow_v2.add_node("estimate_key_node", node_estimate_key)
workflow_v2.add_node("estimate_bpm_node", node_estimate_bpm)
workflow_v2.add_node("estimate_chords_node", node_estimate_chords)
workflow_v2.add_node("estimate_genre_node", node_estimate_genre)
workflow_v2.add_node("aggregate_analysis_node", node_aggregate_analysis_results)
workflow_v2.add_node("generate_backing_track_node", node_generate_backing_track)
workflow_v2.add_node("handle_analysis_error_node", handle_analysis_error_node)
workflow_v2.add_node("handle_generation_error_node", handle_generation_error_node)

workflow_v2.set_entry_point("entry_point")

def select_analysis_branches_for_fan_out(state: AudioAnalysisWorkflowState) -> List[str]:
    branches = ["estimate_key_node", "estimate_bpm_node", "estimate_chords_node", "estimate_genre_node"]
    logger.info(f"条件付きルーター: 並列解析のためのブランチを選択: {branches}", extra={"workflow_run_id": state.get("workflow_run_id")})
    return branches

workflow_v2.add_conditional_edges(
    "entry_point",
    select_analysis_branches_for_fan_out
)

workflow_v2.add_edge("estimate_key_node", "aggregate_analysis_node")
workflow_v2.add_edge("estimate_bpm_node", "aggregate_analysis_node")
workflow_v2.add_edge("estimate_chords_node", "aggregate_analysis_node")
workflow_v2.add_edge("estimate_genre_node", "aggregate_analysis_node")

workflow_v2.add_conditional_edges(
    "aggregate_analysis_node",
    should_proceed_to_generation,
    {
        "generate_backing_track_node": "generate_backing_track_node",
        "handle_analysis_error": "handle_analysis_error_node"
    }
)
workflow_v2.add_edge("handle_analysis_error_node", END)

workflow_v2.add_conditional_edges(
    "generate_backing_track_node",
    check_generation_outcome,
    {
        END: END,
        "handle_generation_error": "handle_generation_error_node"
    }
)
workflow_v2.add_edge("handle_generation_error_node", END)

app_graph = workflow_v2.compile()

async def run_audio_analysis_workflow(gcs_file_path: str) -> AudioAnalysisWorkflowState:
    workflow_run_id = uuid.uuid4().hex
    logger.info(
        f"音声解析ワークフロー開始 ({gcs_file_path})",
        extra={"workflow_run_id": workflow_run_id, "gcs_file_path": gcs_file_path}
    )
    start_time_overall = time.time()
    initial_state: AudioAnalysisWorkflowState = {
        "gcs_file_path": gcs_file_path,
        "workflow_run_id": workflow_run_id,
        "estimated_key": None,
        "key_estimation_error": None,
        "estimated_bpm": None,
        "bpm_estimation_error": None,
        "estimated_chords": None,
        "chords_estimation_error": None,
        "estimated_genre": None,
        "genre_estimation_error": None,
        "analysis_error": None,
        "generated_backing_track_data": None,
        "generation_error": None,
        "final_analysis_result": None,
        "analysis_handled": None,
        "generation_handled": None,
        "entry_point_completed": None
    }
    final_state = initial_state.copy()

    try:
        config = {"recursion_limit": 10, "configurable": {"workflow_run_id": workflow_run_id}}
        invoked_state = await app_graph.ainvoke(initial_state, config=config)
        if invoked_state is not None: final_state = invoked_state # type: ignore
        else: logger.warning("app_graph.ainvokeがNoneを返しました。")
    except Exception as e:
        logger.error(f"LangGraphワークフロー実行中の致命的エラー ({gcs_file_path}): {e}", exc_info=True, extra={"workflow_run_id": workflow_run_id})
        error_addon = f" | Workflow execution framework error: {e}"
        current_analysis_error = final_state.get("analysis_error", "") or ""
        final_state["analysis_error"] = current_analysis_error + error_addon
        current_generation_error = final_state.get("generation_error", "") or ""
        final_state["generation_error"] = current_generation_error + error_addon

    duration = time.time() - start_time_overall
    log_extra = {
        "workflow_run_id": workflow_run_id, "gcs_file_path": gcs_file_path, "duration_seconds": duration,
        "analysis_result_present": bool(final_state.get("final_analysis_result")),
        "generation_data_present": bool(final_state.get("generated_backing_track_data")),
        "analysis_error": final_state.get("analysis_error"), "generation_error": final_state.get("generation_error"),
    }

    if final_state.get("analysis_error") and not final_state.get("final_analysis_result"):
        raise AnalysisFailedException(message="音声解析に失敗しました。", detail=str(final_state.get("analysis_error")))
    if final_state.get("generation_error") and not final_state.get("generated_backing_track_data"):
        raise GenerationFailedException(message="バッキングトラック生成に失敗しました。", detail=str(final_state.get("generation_error")))
    if not final_state.get("final_analysis_result"):
        detail = str(final_state.get('analysis_error')) if final_state.get('analysis_error') else "ワークフローは解析結果を生成せずに終了しました。"
        raise AnalysisFailedException(message="音声解析が正常に完了しませんでした（結果欠落）。", detail=detail)
    if not final_state.get("generated_backing_track_data"):
        detail = str(final_state.get('generation_error')) if final_state.get('generation_error') else "ワークフローはバッキングトラックデータを生成せずに終了しました。"
        raise GenerationFailedException(message="バッキングトラック生成が正常に完了しませんでした（データ欠落）。", detail=detail)

    logger.info(f"ワークフロー ({gcs_file_path}) 正常終了。", extra=log_extra)
    return final_state
