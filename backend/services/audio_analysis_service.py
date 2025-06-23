import asyncio
import logging
import re
import time
import uuid
import os # os.path.splitext を使用するために追加
from typing import TypedDict, List, Dict, Any, Optional, Union

from langgraph.graph import StateGraph, END
from langchain_core.messages import SystemMessage, HumanMessage, AIMessage, BaseMessageChunk # BaseMessageChunk はストリーミングで利用
from langchain_core.exceptions import OutputParserException # 構造化出力のエラー処理に利用
from langchain_google_vertexai import ChatVertexAI, HarmCategory, HarmBlockThreshold

# models から AnalysisResult と ErrorCode をインポート (ChordProgressionOutput などは削除)
from models import AnalysisResult, ErrorCode
from exceptions import AnalysisFailedException, GenerationFailedException, VertexAIAPIErrorException
from config import settings
from services import prompts

logger = logging.getLogger(__name__)

# AudioAnalysisWorkflowState を新しい仕様に合わせて変更
class AudioAnalysisWorkflowState(TypedDict):
    gcs_file_path: str # 入力音声ファイルのGCSパス
    workflow_run_id: Optional[str] # ワークフロー実行の一意なID
    humming_analysis_theme: Optional[str] # 口ずさみ解析で得られた「トラックの雰囲気/テーマ」
    humming_analysis_error: Optional[str] # 口ずさみ解析ステップでのエラーメッセージ
    generated_musicxml_data: Optional[str] # 生成されたMusicXMLデータ
    musicxml_generation_error: Optional[str] # MusicXML生成ステップでのエラーメッセージ
    # final_analysis_result はチャット連携用に「トラックの雰囲気/テーマ」を保持する AnalysisResult オブジェクト
    final_analysis_result: Optional[AnalysisResult]
    analysis_handled: Optional[bool] # 解析エラーが処理されたかどうかのフラグ
    generation_handled: Optional[bool] # 生成エラーが処理されたかどうかのフラグ
    entry_point_completed: Optional[bool] # エントリーポイントが完了したかどうかのフラグ

class AudioAnalyzer:
    def __init__(self, location: str = settings.VERTEX_AI_LOCATION, model_name: str = settings.ANALYZER_GEMINI_MODEL_NAME, timeout: int = settings.VERTEX_AI_TIMEOUT_SECONDS):
        self.location = location
        # self.model_name はメソッド呼び出し時に指定するため、ここでは初期化不要かもしれないが、互換性のため残す
        self.default_model_name = model_name
        self.timeout = timeout
        self.safety_settings = {
            HarmCategory.HARM_CATEGORY_HARASSMENT: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
            HarmCategory.HARM_CATEGORY_HATE_SPEECH: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
            HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT: HarmBlockThreshold.BLOCK_ONLY_HIGH,
            HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
        }

    # _get_llm メソッドを、モデル名を引数で受け取れるように変更
    def _get_llm(self, task_description: str, model_name: str, for_generation: bool = False) -> ChatVertexAI:
        try:
            temperature = 0.7 if for_generation else 0.3 # 解析と生成で温度を調整
            llm = ChatVertexAI(
                location=self.location,
                model_name=model_name, # 引数で受け取ったモデル名を使用
                temperature=temperature,
                request_timeout=self.timeout,
                safety_settings=self.safety_settings,
            )
            logger.info(f"'{task_description}'用ChatVertexAIをモデル'{model_name}', Location: {self.location})で初期化しました。")
            return llm
        except Exception as e:
            logger.error(f"ChatVertexAIの初期化に失敗しました ('{task_description}', Model: {model_name}): {e}", exc_info=True)
            raise VertexAIAPIErrorException(message=f"Vertex AI LLMの初期化に失敗しました ('{task_description}', Model: {model_name})。", detail=str(e), error_code=ErrorCode.VERTEX_AI_API_ERROR)

    def _get_mime_type_from_gcs_path(self, gcs_file_path: str) -> str:
        """GCSファイルパスからMIMEタイプを推測するヘルパー関数"""
        _, ext = os.path.splitext(gcs_file_path.lower())
        if ext == ".mp3":
            return "audio/mpeg"
        elif ext == ".wav":
            return "audio/wav"
        elif ext == ".m4a":
            return "audio/mp4"
        elif ext == ".aac":
            return "audio/aac"
        else:
            logger.warning(f"不明なファイル拡張子 '{ext}' のため、MIMEタイプを 'application/octet-stream' とします（フォールバック）。GCSパス: {gcs_file_path}")
            return "application/octet-stream" # より汎用的なフォールバックMIMEタイプ

    # _call_vertex_api メソッドの is_structured_output と output_schema は今回不要なので削除またはデフォルトをFalseに
    async def _call_vertex_api(
        self,
        llm: ChatVertexAI,
        messages: List[Union[SystemMessage, HumanMessage, AIMessage]],
        task_description: str,
        request_params: Dict[str, Any], # ログ記録用
        workflow_run_id: Optional[str] = None,
        # is_structured_output: bool = False, # 今回は不要
        # output_schema: Optional[Any] = None # 今回は不要
    ) -> AIMessage: # AIMessage を直接返すように変更 (テキスト応答を期待)
        api_call_start_time = time.time()
        try:
            # target_llm = llm.with_structured_output(output_schema, include_raw=False) if is_structured_output and output_schema else llm
            # 今回は構造化出力は使用しないため、そのまま llm を使用
            response_data = await llm.ainvoke(messages)
            api_call_duration = time.time() - api_call_start_time

            log_extra = {
                "target_service": "VertexAI", "vertex_model": llm.model_name, # llmオブジェクトからモデル名を取得
                "task": task_description, "duration_seconds": api_call_duration,
                "request_params": request_params, "workflow_run_id": workflow_run_id,
            }
            # if is_structured_output and hasattr(response_data, 'model_dump'): # 構造化出力のログは削除
            #     log_extra["parsed_output"] = response_data.model_dump()
            if isinstance(response_data, AIMessage) and response_data.content:
                log_extra["response_content_length"] = len(str(response_data.content))

            logger.info(f"Vertex AI API呼び出し成功 ({task_description})", extra=log_extra)

            if not isinstance(response_data, AIMessage):
                 logger.error(f"Vertex AIからの応答が予期しない型です: {type(response_data)} ({task_description})")
                 raise VertexAIAPIErrorException(message=f"{task_description}: Vertex AIからの応答が予期しない型です。", error_code=ErrorCode.VERTEX_AI_API_ERROR)
            if not response_data.content or not isinstance(response_data.content, str):
                logger.error(f"Vertex AIからの応答内容が空または文字列ではありません: {response_data.content} ({task_description})")
                raise VertexAIAPIErrorException(message=f"{task_description}: Vertex AIからの応答内容が空または不正です。", error_code=ErrorCode.VERTEX_AI_API_ERROR)

            return response_data
        except Exception as e:
            api_call_duration = time.time() - api_call_start_time
            logger.error(
                f"Vertex AI API呼び出し失敗 ({task_description})", exc_info=True,
                extra={
                    "target_service": "VertexAI", "vertex_model": llm.model_name,
                    "task": task_description, "duration_seconds": api_call_duration,
                    "request_params": request_params, "workflow_run_id": workflow_run_id,
                    "error_type": type(e).__name__,
                }
            )
            if "blocked" in str(e).lower() or "safety filter" in str(e).lower():
                raise VertexAIAPIErrorException(message=f"{task_description}リクエストが安全フィルターでブロックされた可能性があります (Vertex AI)。", detail=str(e), error_code=ErrorCode.VERTEX_AI_API_ERROR)
            if isinstance(e, asyncio.TimeoutError):
                raise VertexAIAPIErrorException(message=f"{task_description}がタイムアウトしました (Vertex AI)。", detail=str(e), error_code=ErrorCode.VERTEX_AI_API_ERROR)
            # OutputParserException は構造化出力用なので、ここでは不要
            # if isinstance(e, OutputParserException):
            #      raise AnalysisFailedException(message=f"{task_description}: AIの応答形式が不正でパースできませんでした (Vertex AI)。", detail=getattr(e, 'llm_output', str(e)))
            if isinstance(e, VertexAIAPIErrorException): # 既にカスタム例外ならそのままraise
                raise
            raise VertexAIAPIErrorException(message=f"{task_description}中にエラーが発生しました (Vertex AI)。", detail=str(e), error_code=ErrorCode.VERTEX_AI_API_ERROR)

    async def analyze_humming_audio(self, gcs_file_path: str, workflow_run_id: Optional[str]) -> str:
        """
        口ずさみ音声を解析し、「トラックの雰囲気/テーマ」を取得する。
        """
        task = "Humming Audio Analysis (トラック雰囲気/テーマ取得)"
        llm = self._get_llm(task, model_name=settings.ANALYZER_GEMINI_MODEL_NAME, for_generation=False)
        mime_type = self._get_mime_type_from_gcs_path(gcs_file_path)

        # プロンプトは services.prompts から取得
        messages = [
            HumanMessage(content=[
                prompts.HUMMING_ANALYSIS_SYSTEM_PROMPT, # システムプロンプトとして機能させる
                {
                    "type": "media",
                    "file_uri": gcs_file_path,
                    "mime_type": mime_type,
                }
            ])
        ]
        try:
            response_ai_message: AIMessage = await self._call_vertex_api(
                llm, messages, task, {"gcs_file_path": gcs_file_path, "mime_type": mime_type}, workflow_run_id
            )
            # 応答はテキスト形式を期待
            theme_text = response_ai_message.content.strip()
            if not theme_text:
                logger.warning(f"[{task}] Vertex AI が空の「トラックの雰囲気/テーマ」を返しました。")
                raise AnalysisFailedException(message="AIが「トラックの雰囲気/テーマ」を返しませんでした (Vertex AI)。")
            logger.info(f"口ずさみ音声解析成功。テーマ: {theme_text[:100]}...")
            return theme_text
        except VertexAIAPIErrorException as e: # API呼び出しレベルのエラー
            logger.error(f"[{task}] Vertex AI APIエラー: {e.message}", exc_info=True)
            raise AnalysisFailedException(message=f"口ずさみ音声解析中にAPIエラーが発生しました: {e.message}", detail=e.detail)
        except Exception as e: # その他の予期せぬエラー
            logger.error(f"[{task}] 予期せぬエラー: {e}", exc_info=True)
            raise AnalysisFailedException(message=f"口ずさみ音声解析中に予期せぬエラーが発生しました: {str(e)}")


    async def generate_musicxml_from_theme(self, gcs_file_path: str, humming_analysis_theme: str, workflow_run_id: Optional[str]) -> str:
        """
        口ずさみ音声と「トラックの雰囲気/テーマ」からMusicXMLを生成する。
        """
        task = "MusicXML Generation (バッキングトラック生成)"
        llm = self._get_llm(task, model_name=settings.GENERATOR_GEMINI_MODEL_NAME, for_generation=True)
        mime_type = self._get_mime_type_from_gcs_path(gcs_file_path)

        # プロンプトテンプレートにテーマを埋め込む
        prompt_text = prompts.MUSICXML_GENERATION_PROMPT_TEMPLATE.format(humming_analysis_theme=humming_analysis_theme)
        messages = [
            SystemMessage(content=prompts.MUSICXML_GENERATION_SYSTEM_PROMPT),
            HumanMessage(content=[
                prompt_text, # テキストパート
                { # 音声ファイルパート
                    "type": "media",
                    "file_uri": gcs_file_path,
                    "mime_type": mime_type,
                }
            ])
        ]
        try:
            response_ai_message: AIMessage = await self._call_vertex_api(
                llm, messages, task, {"gcs_file_path": gcs_file_path, "humming_analysis_theme": humming_analysis_theme}, workflow_run_id
            )
            content = response_ai_message.content
            # MusicXMLの抽出ロジック (既存のものを流用・調整)
            match = re.search(r"MUSICXML_START\s*([\s\S]+?)\s*MUSICXML_END", content, re.DOTALL)
            if match:
                musicxml_text = match.group(1).strip()
                if not musicxml_text:
                    logger.error(f"[{task}] 抽出されたMusicXMLデータが空です。")
                    raise GenerationFailedException(message="抽出されたMusicXMLデータが空です (Vertex AI)。", detail="LLM response contained MUSICXML_START/END tags but no content.")
                # 簡単なXML形式のチェック (必須ではないが、より堅牢にするなら)
                if not (musicxml_text.startswith("<?xml") and musicxml_text.endswith("</score-partwise>")):
                    logger.warning(f"[{task}] 生成されたMusicXMLが期待される形式と異なる可能性があります: {musicxml_text[:100]}...{musicxml_text[-100:]}")
                logger.info(f"MusicXML生成成功。データ長: {len(musicxml_text)}")
                return musicxml_text
            if "CANNOT_GENERATE_MUSICXML" in content.upper(): # AIが明示的に生成不可と伝えた場合
                 logger.warning(f"[{task}] Vertex AI がMusicXMLデータを生成できないと報告しました。応答: {content[:200]}")
                 raise GenerationFailedException(message="Vertex AI がMusicXMLデータを生成できないと報告しました。", detail=content)
            logger.warning(f"[{task}] LLM応答のMusicXMLにMUSICXML_START/ENDタグが含まれていませんでした。コンテント: {content[:200]}...")
            raise GenerationFailedException(message="Vertex AI が期待する形式でMusicXMLデータを返しませんでした (タグ欠落)。", detail=f"Response (start): {str(content)[:200]}")
        except VertexAIAPIErrorException as e:
            logger.error(f"[{task}] Vertex AI APIエラー: {e.message}", exc_info=True)
            raise GenerationFailedException(message=f"MusicXML生成中にAPIエラーが発生しました: {e.message}", detail=e.detail)
        except Exception as e:
            logger.error(f"[{task}] 予期せぬエラー: {e}", exc_info=True)
            raise GenerationFailedException(message=f"MusicXML生成中に予期せぬエラーが発生しました: {str(e)}")

audio_analyzer = AudioAnalyzer()

# 既存の estimate_key, estimate_bpm, estimate_chords, estimate_genre は削除

async def node_log_event(state: AudioAnalysisWorkflowState, event_name: str, is_start: bool, data: Optional[Dict] = None) -> None:
    log_level = logging.DEBUG # INFOからDEBUGに変更してログ量を調整
    status = "開始" if is_start else "終了"
    message = f"ワークフローノード {event_name} {status}"
    extra_info = {"workflow_run_id": state.get("workflow_run_id"), "node_name": event_name}
    if data: extra_info.update(data)
    if not is_start and "start_time" in extra_info:
        duration = time.time() - extra_info.pop("start_time")
        extra_info["duration_seconds"] = round(duration, 2)
        message += f". Duration: {extra_info['duration_seconds']:.2f}s"
    logger.log(log_level, message, extra=extra_info)

# execute_analysis_node は汎用性が低くなったため、各ノードで直接呼び出す形式に変更。削除。

# 新しいノード: node_analyze_humming_audio
async def node_analyze_humming_audio(state: AudioAnalysisWorkflowState) -> Dict[str, Any]:
    node_name = "analyze_humming_audio"
    start_time = time.time()
    await node_log_event(state, node_name, is_start=True, data={"start_time": start_time, "gcs_file_path": state["gcs_file_path"]})
    output: Dict[str, Any] = {}
    try:
        theme = await audio_analyzer.analyze_humming_audio(state["gcs_file_path"], state.get("workflow_run_id"))
        output["humming_analysis_theme"] = theme
        # 「トラックの雰囲気/テーマ」を final_analysis_result にも格納 (チャット連携用)
        # ここで AnalysisResult を作成する。humming_theme のみを持つ。
        output["final_analysis_result"] = AnalysisResult(humming_theme=theme)
    except Exception as e:
        error_message = f"{node_name} 失敗: {str(e)}"
        logger.error(error_message, exc_info=True, extra={"workflow_run_id": state.get("workflow_run_id")})
        output["humming_analysis_error"] = error_message
        # エラー発生時も final_analysis_result にエラー情報を含めるか、あるいはNoneのままにするか検討。
        # ここではNoneのままにし、後続の条件分岐でエラーを処理する。
    await node_log_event(state, node_name, is_start=False, data={"start_time": start_time, **output})
    return output

# 既存の node_estimate_... は削除

# node_aggregate_analysis_results は大幅に簡略化されるか不要になる。
# 今回は node_analyze_humming_audio が成功すれば final_analysis_result が作成されるため、集約は不要。削除。

# 新しいノード: node_generate_musicxml (旧 node_generate_backing_track を改修)
async def node_generate_musicxml(state: AudioAnalysisWorkflowState) -> Dict[str, Any]:
    node_name = "generate_musicxml"
    start_time = time.time()
    await node_log_event(state, node_name, is_start=True, data={"start_time": start_time})
    output: Dict[str, Any] = {}

    humming_theme = state.get("humming_analysis_theme")
    gcs_file_path = state.get("gcs_file_path")

    if state.get("humming_analysis_error") or not humming_theme or not gcs_file_path:
        error_msg = "MusicXMLを生成できません: 口ずさみ解析エラーまたは必要な情報（テーマ、ファイルパス）がありません。"
        output["musicxml_generation_error"] = error_msg
        logger.warning(error_msg, extra={"workflow_run_id": state.get("workflow_run_id")})
    else:
        try:
            # humming_theme と gcs_file_path がNoneでないことを保証 (mypyのため)
            if humming_theme and gcs_file_path:
                 output["generated_musicxml_data"] = await audio_analyzer.generate_musicxml_from_theme(
                    gcs_file_path=gcs_file_path,
                    humming_analysis_theme=humming_theme,
                    workflow_run_id=state.get("workflow_run_id")
                )
            else: # このブロックには通常到達しないはず
                output["musicxml_generation_error"] = "予期せぬエラー: MusicXML生成に必要な情報が不足しています。"
                logger.error(output["musicxml_generation_error"], extra={"workflow_run_id": state.get("workflow_run_id")})

        except Exception as e:
            error_message = f"{node_name} 失敗: {str(e)}"
            logger.error(error_message, exc_info=True, extra={"workflow_run_id": state.get("workflow_run_id")})
            output["musicxml_generation_error"] = error_message

    await node_log_event(state, node_name, is_start=False, data={"start_time": start_time, "generation_error_present": bool(output.get("musicxml_generation_error"))})
    return output

def build_workflow() -> StateGraph:
    workflow = StateGraph(AudioAnalysisWorkflowState)

    # ノードの定義
    workflow.add_node("entry_point", lambda state: {"entry_point_completed": True})
    workflow.add_node("analyze_humming_node", node_analyze_humming_audio) # 新しい解析ノード
    workflow.add_node("generate_musicxml_node", node_generate_musicxml)   # 新しい生成ノード
    # エラーハンドリングノード (名前をより具体的に)
    workflow.add_node("handle_humming_analysis_error_node", lambda state: {"analysis_handled": True, "humming_analysis_error": state.get("humming_analysis_error") or "口ずさみ解析中に不明なエラーが発生しました。"})
    workflow.add_node("handle_musicxml_generation_error_node", lambda state: {"generation_handled": True, "musicxml_generation_error": state.get("musicxml_generation_error") or "MusicXML生成中に不明なエラーが発生しました。"})

    workflow.set_entry_point("entry_point")

    # エッジの接続
    workflow.add_edge("entry_point", "analyze_humming_node")

    # 口ずさみ解析ノードからの条件分岐
    workflow.add_conditional_edges(
        "analyze_humming_node",
        lambda state: "handle_humming_analysis_error_node" if state.get("humming_analysis_error") else "generate_musicxml_node",
        {
            "generate_musicxml_node": "generate_musicxml_node",
            "handle_humming_analysis_error_node": "handle_humming_analysis_error_node"
        }
    )
    workflow.add_edge("handle_humming_analysis_error_node", END) # 解析エラー時は終了

    # MusicXML生成ノードからの条件分岐
    workflow.add_conditional_edges(
        "generate_musicxml_node",
        lambda state: "handle_musicxml_generation_error_node" if state.get("musicxml_generation_error") or not state.get("generated_musicxml_data") else END,
        {
            END: END, # 成功時は終了
            "handle_musicxml_generation_error_node": "handle_musicxml_generation_error_node"
        }
    )
    workflow.add_edge("handle_musicxml_generation_error_node", END) # 生成エラー時は終了

    return workflow.compile()

app_graph = build_workflow()

async def run_audio_analysis_workflow(gcs_file_path: str) -> AudioAnalysisWorkflowState:
    workflow_run_id = uuid.uuid4().hex
    logger.info(f"新しい音声解析・MusicXML生成ワークフロー開始 ({gcs_file_path})", extra={"workflow_run_id": workflow_run_id, "gcs_file_path": gcs_file_path})
    start_time_overall = time.time()

    # AudioAnalysisWorkflowState の初期化を新しいフィールドに合わせて変更
    initial_state = AudioAnalysisWorkflowState(
        gcs_file_path=gcs_file_path,
        workflow_run_id=workflow_run_id,
        humming_analysis_theme=None,
        humming_analysis_error=None,
        generated_musicxml_data=None,
        musicxml_generation_error=None,
        final_analysis_result=None, # 初期値はNone
        analysis_handled=None,
        generation_handled=None,
        entry_point_completed=None
    )
    final_state: AudioAnalysisWorkflowState = initial_state.copy()

    try:
        config = {"recursion_limit": 10, "configurable": {"workflow_run_id": workflow_run_id}} # 再帰制限は通常これで十分
        invoked_result = await app_graph.ainvoke(initial_state, config=config)

        if isinstance(invoked_result, dict):
            for key, value in invoked_result.items():
                if key in AudioAnalysisWorkflowState.__annotations__:
                    final_state[key] = value # type: ignore
                else:
                    logger.warning(f"ainvokeから予期しないキー '{key}' が返されました。")
        else:
            logger.warning(f"app_graph.ainvokeが予期しない型を返しました: {type(invoked_result)}。初期状態をフォールバックとして使用します。")
            # このケースでは、エラー情報を final_state に追加
            final_state["humming_analysis_error"] = (final_state.get("humming_analysis_error") or "") + " | ワークフロー呼び出しが予期しない型を返しました。"

    except Exception as e:
        logger.error(f"LangGraphワークフロー実行中の致命的エラー ({gcs_file_path}): {e}", exc_info=True, extra={"workflow_run_id": workflow_run_id})
        error_addon = f" | ワークフロー実行フレームワークエラー: {type(e).__name__}: {e}"
        # エラーが発生した場合、関連するエラーステートに情報を追加
        current_humming_error = final_state.get("humming_analysis_error") or ""
        final_state["humming_analysis_error"] = current_humming_error + error_addon # type: ignore
        current_musicxml_error = final_state.get("musicxml_generation_error") or ""
        final_state["musicxml_generation_error"] = current_musicxml_error + error_addon # type: ignore


    duration = time.time() - start_time_overall
    log_extra = {
        "workflow_run_id": workflow_run_id, "gcs_file_path": gcs_file_path, "duration_seconds": round(duration, 2),
        "humming_analysis_theme_present": bool(final_state.get("humming_analysis_theme")),
        "musicxml_data_present": bool(final_state.get("generated_musicxml_data")),
        "humming_analysis_error": final_state.get("humming_analysis_error"),
        "musicxml_generation_error": final_state.get("musicxml_generation_error"),
        "final_analysis_result_present": bool(final_state.get("final_analysis_result"))
    }

    # 最終結果の検証と例外送出
    final_analysis_result_obj = final_state.get("final_analysis_result")
    generated_musicxml_data_val = final_state.get("generated_musicxml_data")

    # final_analysis_result (口ずさみ解析の結果) がない場合は AnalysisFailedException
    if not final_analysis_result_obj:
        detail = str(final_state.get('humming_analysis_error', "ワークフローは口ずさみ解析結果を生成せずに終了しました。"))
        logger.error(f"口ずさみ解析失敗（結果欠落）: {detail}", extra=log_extra)
        raise AnalysisFailedException(message="口ずさみ音声解析が正常に完了しませんでした（結果欠落）。", detail=detail)

    # generated_musicxml_data がない場合は GenerationFailedException
    # musicxml_generation_error がある場合はそれを詳細として使用
    if not generated_musicxml_data_val:
        detail = str(final_state.get('musicxml_generation_error', "ワークフローはMusicXMLデータを生成せずに終了しました。"))
        logger.error(f"MusicXML生成失敗（データ欠落またはエラー）: {detail}", extra=log_extra)
        raise GenerationFailedException(message="MusicXML生成が正常に完了しませんでした。", detail=detail)


    logger.info(f"新しいワークフロー ({gcs_file_path}) 正常終了。", extra=log_extra)
    return final_state
