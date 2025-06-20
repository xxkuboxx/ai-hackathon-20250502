import asyncio
import logging
import re
import json
import time
import uuid
from typing import TypedDict, List, Dict, Any, Optional, AsyncGenerator, Union

from langgraph.graph import StateGraph, END, START # START をインポート
from langchain_core.messages import SystemMessage, HumanMessage, AIMessage, BaseMessageChunk
from langchain_google_genai import ChatGoogleGenerativeAI, HarmBlockThreshold, HarmCategory
import google.generativeai as genai

# 構造化出力用のPydanticモデルをインポートまたは定義
from models import AnalysisResult, ErrorCode, ChordProgressionOutput, KeyOutput, BpmOutput, GenreOutput
from exceptions import AnalysisFailedException, GenerationFailedException, GeminiAPIErrorException
from config import settings

logger = logging.getLogger(__name__)

def get_gemini_llm(task_description: str, for_generation: bool = False) -> ChatGoogleGenerativeAI:
    if not settings.GEMINI_API_KEY_FINAL:
        logger.error(f"{task_description}用GEMINI_API_KEY_FINALが設定されていません。")
        raise GeminiAPIErrorException(message="Gemini APIキーが設定されていません。", error_code=ErrorCode.GEMINI_API_ERROR)
    try:
        temperature = 0.7 if for_generation else 0.3
        llm = ChatGoogleGenerativeAI(
            model=settings.GEMINI_MODEL_NAME, # config.py からモデル名を取得
            google_api_key=settings.GEMINI_API_KEY_FINAL,
            temperature=temperature,
            request_timeout=settings.GEMINI_API_TIMEOUT_SECONDS,
            safety_settings={
                HarmCategory.HARM_CATEGORY_HARASSMENT: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
                HarmCategory.HARM_CATEGORY_HATE_SPEECH: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
                HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
                HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
            },
            convert_system_message_to_human=True
        )
        logger.info(f"'{task_description}'用ChatGoogleGenerativeAIをモデル'{settings.GEMINI_MODEL_NAME}'で初期化しました。")
        return llm
    except Exception as e:
        logger.error(f"ChatGoogleGenerativeAIの初期化に失敗しました ('{task_description}'): {e}", exc_info=True)
        raise GeminiAPIErrorException(message=f"Gemini LLMの初期化に失敗しました ('{task_description}')。", detail=str(e))

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
    analysis_error: Optional[str] # 集約されたエラーメッセージ
    generated_backing_track_data: Optional[str] # MusicXMLテキストを格納するため str に変更
    generation_error: Optional[str]
    final_analysis_result: Optional[AnalysisResult]
    analysis_handled: Optional[bool] # エラー処理ノードが実行されたか
    generation_handled: Optional[bool] # エラー処理ノードが実行されたか
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

async def _call_gemini_api_with_logging(
    llm: ChatGoogleGenerativeAI,
    messages: List[Union[SystemMessage, HumanMessage, AIMessage]],
    task_description: str,
    request_params: Dict[str, Any],
    workflow_run_id: Optional[str] = None,
    is_structured_output: bool = False, # 構造化出力を使用するかどうか
    output_schema: Optional[Any] = None  # 構造化出力のスキーマ (Pydanticモデル)
) -> Union[AIMessage, Any]: # 構造化出力の場合はパースされたオブジェクトを返す
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
            f"Gemini API呼び出し成功 ({task_description})",
            extra={
                "target_service": "GeminiAPI", "gemini_model": settings.GEMINI_MODEL_NAME,
                "task": task_description, "duration_seconds": api_call_duration,
                "request_params": request_params, "workflow_run_id": workflow_run_id,
                **log_extra_response_data
            }
        )
        return response_data
    except Exception as e:
        api_call_duration = time.time() - api_call_start_time
        logger.error(
            f"Gemini API呼び出し失敗 ({task_description})", exc_info=True,
            extra={
                "target_service": "GeminiAPI", "gemini_model": settings.GEMINI_MODEL_NAME,
                "task": task_description, "duration_seconds": api_call_duration,
                "request_params": request_params, "workflow_run_id": workflow_run_id,
                "error_type": type(e).__name__,
            }
        )
        if isinstance(e, genai.types.generation_types.BlockedPromptException): # type: ignore
            raise GeminiAPIErrorException(message=f"{task_description}リクエストが安全フィルターでブロックされました。", detail=str(e))
        if isinstance(e, asyncio.TimeoutError):
            raise GeminiAPIErrorException(message=f"{task_description}がタイムアウトしました。")
        if "API key not valid" in str(e) or "PERMISSION_DENIED" in str(e):
             raise GeminiAPIErrorException(message="Gemini APIキーが無効か、権限がありません。", detail=str(e))
        from langchain_core.exceptions import OutputParsingException
        if isinstance(e, OutputParsingException):
             raise AnalysisFailedException(message=f"{task_description}: AIの応答形式が不正でパースできませんでした。", detail=getattr(e, 'llm_output', str(e)))

        raise GeminiAPIErrorException(message=f"{task_description}中にエラーが発生しました。", detail=str(e))


async def _estimate_key_gemini(gcs_file_path: str, workflow_run_id: Optional[str]) -> str:
    task = "Key Estimation (Structured)"
    llm = get_gemini_llm(task)
    prompt_text = KEY_ESTIMATION_PROMPT_STRUCTURED.format(gcs_file_path=gcs_file_path)
    messages = [SystemMessage(content=AUDIO_ANALYSIS_SYSTEM_PROMPT_STRUCTURED), HumanMessage(content=prompt_text)]
    parsed_output: KeyOutput = await _call_gemini_api_with_logging( # type: ignore
        llm, messages, task, {"gcs_file_path": gcs_file_path}, workflow_run_id,
        is_structured_output=True, output_schema=KeyOutput
    )
    if not parsed_output.primary_key or parsed_output.primary_key == "Undetermined":
        logger.warning(f"[{task}] Gemini returned an undetermined primary key.")
        return "Undetermined"
    return parsed_output.primary_key

async def _estimate_bpm_gemini(gcs_file_path: str, workflow_run_id: Optional[str]) -> int:
    task = "BPM Estimation (Structured)"
    llm = get_gemini_llm(task)
    prompt_text = BPM_ESTIMATION_PROMPT_STRUCTURED.format(gcs_file_path=gcs_file_path)
    messages = [SystemMessage(content=AUDIO_ANALYSIS_SYSTEM_PROMPT_STRUCTURED), HumanMessage(content=prompt_text)]
    parsed_output: BpmOutput = await _call_gemini_api_with_logging( # type: ignore
        llm, messages, task, {"gcs_file_path": gcs_file_path}, workflow_run_id,
        is_structured_output=True, output_schema=BpmOutput
    )
    if parsed_output.bpm <= 0:
        logger.warning(f"[{task}] Gemini returned invalid BPM: {parsed_output.bpm}")
        raise AnalysisFailedException(message="AIが有効なBPMを返しませんでした。")
    return parsed_output.bpm

async def _estimate_chords_gemini(gcs_file_path: str, workflow_run_id: Optional[str]) -> List[str]:
    task = "Chord Progression Estimation (Structured)"
    llm = get_gemini_llm(task)
    prompt_text = CHORD_PROGRESSION_PROMPT_STRUCTURED.format(gcs_file_path=gcs_file_path)
    messages = [SystemMessage(content=AUDIO_ANALYSIS_SYSTEM_PROMPT_STRUCTURED), HumanMessage(content=prompt_text)]
    parsed_output: ChordProgressionOutput = await _call_gemini_api_with_logging( # type: ignore
        llm, messages, task, {"gcs_file_path": gcs_file_path}, workflow_run_id,
        is_structured_output=True, output_schema=ChordProgressionOutput
    )
    if not parsed_output.chords:
        logger.warning(f"[{task}] Gemini returned an empty list for chords.")
        return ["Undetermined"]
    return parsed_output.chords

async def _estimate_genre_gemini(gcs_file_path: str, workflow_run_id: Optional[str]) -> str:
    task = "Genre Estimation (Structured)"
    llm = get_gemini_llm(task)
    prompt_text = GENRE_ESTimation_PROMPT_STRUCTURED.format(gcs_file_path=gcs_file_path)
    messages = [SystemMessage(content=AUDIO_ANALYSIS_SYSTEM_PROMPT_STRUCTURED), HumanMessage(content=prompt_text)]
    parsed_output: GenreOutput = await _call_gemini_api_with_logging( # type: ignore
        llm, messages, task, {"gcs_file_path": gcs_file_path}, workflow_run_id,
        is_structured_output=True, output_schema=GenreOutput
    )
    if not parsed_output.primary_genre or parsed_output.primary_genre == "Undetermined":
        logger.warning(f"[{task}] Gemini returned an undetermined primary genre.")
        return "Undetermined"
    return parsed_output.primary_genre

async def _generate_backing_track_gemini(key: str, bpm: int, chords: List[str], genre: str, workflow_run_id: Optional[str]) -> str: # 戻り値を str に変更
    task = "Backing Track Generation (MusicXML)"
    llm = get_gemini_llm(task, for_generation=True)
    chords_str = ", ".join(chords)
    prompt_text = BACKING_TRACK_GENERATION_PROMPT_TEMPLATE.format(key=key, bpm=bpm, chords_str=chords_str, genre=genre)
    messages = [SystemMessage(content=MUSIC_GENERATION_SYSTEM_PROMPT), HumanMessage(content=prompt_text)]
    request_params = {"key": key, "bpm": bpm, "chords": chords_str, "genre": genre}
    response: AIMessage = await _call_gemini_api_with_logging(llm, messages, task, request_params, workflow_run_id) # type: ignore
    content = response.content

    logger.debug(f'############################# Raw content from LLM for MusicXML: {str(content)[:500]} ################################') # ログ出力を調整
    
    if isinstance(content, str):
        # MusicXMLデータの抽出用に正規表現を変更
        musicxml_match = re.search(r"MUSICXML_START\s*([\s\S]+?)\s*MUSICXML_END", content, re.DOTALL)
        if musicxml_match:
            musicxml_text = musicxml_match.group(1).strip()
            if not musicxml_text: 
                raise GenerationFailedException(message="抽出されたMusicXMLデータが空です。", detail="LLM response contained MUSICXML_START and MUSICXML_END tags but no content between them.")
            # MusicXMLとして基本的な形式を持っているか簡易チェック（オプション）
            if not (musicxml_text.startswith("<?xml") or musicxml_text.startswith("<score-partwise")):
                 logger.warning(f"Generated MusicXML may not be well-formed (does not start with <?xml or <score-partwise): {musicxml_text[:100]}")
            return musicxml_text # MusicXMLテキストを直接返す
        
        # CANNOT_GENERATE_MUSICXML をチェックするように変更
        if "CANNOT_GENERATE_MUSICXML" in content.upper():
            raise GenerationFailedException(message="GeminiがMusicXMLデータを生成できないと報告しました。", detail=content)
        
        # 上記のマーカーがない場合でも、内容がMusicXMLっぽいか最後の手段としてチェックすることもできるが、
        # プロンプトでフォーマットを指示しているので、それに従わない場合はエラーとするのが妥当。
        logger.warning(f"LLM response for MusicXML did not contain MUSICXML_START/END tags. Content: {content[:200]}")
        raise GenerationFailedException(
            message="Geminiが期待する形式でMusicXMLデータを返しませんでした (MUSICXML_START/END タグが見つかりません)。", 
            detail=f"Response (start): {str(content)[:200]}"
        )

    # MusicXMLはテキストなので、strで返されることを期待する。
    # AIMessage.content が bytes や他の型であるケースは LangChain/Gemini の使い方として通常想定しづらいが、念のため型チェック。
    raise GenerationFailedException(
        message=f"バッキングトラック生成でGeminiから予期せぬ応答タイプ。期待したのはstrですが、得られたのは {type(content)} です。",
        detail=f"Response content (type: {type(content)}): {str(content)[:200]}" # content が bytes の場合も考慮して str() で囲む
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
        # _generate_backing_track_gemini は str (MusicXML テキスト) を返すように変更済み
        track_data_str = await _generate_backing_track_gemini(
            key=analysis_result.key, bpm=analysis_result.bpm,
            chords=analysis_result.chords, genre=analysis_result.genre_by_ai,
            workflow_run_id=state.get("workflow_run_id")
        )
        output["generated_backing_track_data"] = track_data_str # 文字列データを格納
    except Exception as e: output["generation_error"] = f"{node_name} failed: {str(e)}"
    await node_log_end(state, node_name, start_time, output)
    return output

def should_proceed_to_generation(state: AudioAnalysisWorkflowState) -> str:
    if state.get("analysis_error"): return "handle_analysis_error"
    if not state.get("final_analysis_result"): return "handle_analysis_error"
    return "generate_backing_track_node"

def check_generation_outcome(state: AudioAnalysisWorkflowState) -> str:
    if state.get("generation_error"): return "handle_generation_error"
    # generated_backing_track_data が文字列であり、空でないことを確認
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
    logger.info(f"Conditional router: selecting branches for parallel analysis: {branches}", extra={"workflow_run_id": state.get("workflow_run_id")})
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
        "generated_backing_track_data": None, # 初期値は None (str型)
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
        "generation_data_present": bool(final_state.get("generated_backing_track_data")), # 文字列データの存在確認
        "analysis_error": final_state.get("analysis_error"), "generation_error": final_state.get("generation_error"),
    }

    if final_state.get("analysis_error") and not final_state.get("final_analysis_result"):
        raise AnalysisFailedException(message="音声解析に失敗しました。", detail=str(final_state.get("analysis_error")))
    if final_state.get("generation_error") and not final_state.get("generated_backing_track_data"):
        raise GenerationFailedException(message="バッキングトラック生成に失敗しました。", detail=str(final_state.get("generation_error")))
    if not final_state.get("final_analysis_result"):
        detail = str(final_state.get('analysis_error')) if final_state.get('analysis_error') else "ワークフローは解析結果を生成せずに終了しました。"
        raise AnalysisFailedException(message="音声解析が正常に完了しませんでした（結果欠落）。", detail=detail)
    # generated_backing_track_data が文字列であり、空でないことを確認
    if not final_state.get("generated_backing_track_data"):
        detail = str(final_state.get('generation_error')) if final_state.get('generation_error') else "ワークフローはバッキングトラックデータを生成せずに終了しました。"
        raise GenerationFailedException(message="バッキングトラック生成が正常に完了しませんでした（データ欠落）。", detail=detail)

    logger.info(f"ワークフロー ({gcs_file_path}) 正常終了。", extra=log_extra)
    return final_state
