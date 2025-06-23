# routers/process_api.py

import uuid
import logging
import os
from fastapi import APIRouter, UploadFile, File, Depends
from typing import Annotated, Optional

from models import ProcessResponse, AnalysisResult
from config import settings
from exceptions import (
    UnsupportedMediaTypeException,
    FileTooLargeException,
    InternalServerErrorException,
    AnalysisFailedException, # Keep for direct raise if workflow contract violated
    GenerationFailedException # Keep for direct raise if workflow contract violated
)
from services.audio_analysis_service import run_audio_analysis_workflow, AudioAnalysisWorkflowState
from services.gcs_service import GCSService, get_gcs_service

logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/api",
    tags=["Audio Processing"],
)

SUPPORTED_AUDIO_MIME_TYPES = [
    "audio/mpeg",  # MP3
    "audio/wav",   # WAV
    "audio/x-wav", # WAV
    "audio/mp4",   # M4A (MPEG-4 Audio)
    "audio/x-m4a",   # M4A
    "audio/aac",   # AAC
]

@router.post("/process", response_model=ProcessResponse)
async def process_audio_file(
    file: Annotated[UploadFile, File(description="処理する音声ファイル (MP3, WAV, M4A, AAC)。")],
    gcs_service: GCSService = Depends(get_gcs_service)
):
    # local_temp_file_path was unused and has been removed.
    try:
        logger.info(f"ファイルアップロードリクエスト受信: {file.filename}, Content-Type: {file.content_type}")
        if file.content_type not in SUPPORTED_AUDIO_MIME_TYPES:
            raise UnsupportedMediaTypeException(f"サポートされていないファイルタイプです: {file.content_type}。サポートされているタイプ: {', '.join(SUPPORTED_AUDIO_MIME_TYPES)}")

        actual_file_size = file.size
        if actual_file_size is None: # Should ideally not happen with UploadFile
            logger.warning("UploadFile.size is None, which is unexpected.")
            raise InternalServerErrorException(message="ファイルサイズを決定できませんでした。")

        max_size_bytes = settings.MAX_FILE_SIZE_MB * 1024 * 1024
        if actual_file_size > max_size_bytes:
            raise FileTooLargeException(f"ファイルサイズが{settings.MAX_FILE_SIZE_MB}MBを超えています。")

        logger.info(f"ファイル '{file.filename}' は初期検証を通過しました。")

        file_id = str(uuid.uuid4())
        logger.info(f"処理用の一意なIDを生成しました: {file_id}")

        # Determine file extension based on MIME type
        content_type = file.content_type
        if content_type == "audio/mpeg":
            original_file_extension = ".mp3"
        elif content_type in ["audio/wav", "audio/x-wav"]:
            original_file_extension = ".wav"
        elif content_type in ["audio/wav", "audio/x-m4a"]:
            original_file_extension = ".m4a"
        elif content_type == "audio/aac":
            original_file_extension = ".aac"
        else:
            # This case should ideally be caught by the SUPPORTED_AUDIO_MIME_TYPES check,
            # but as a fallback, use a generic extension.
            logger.warning(f"予期しないコンテントタイプ '{content_type}' のための拡張子を決定できません。'.dat' を使用します。")
            original_file_extension = ".dat"

        gcs_blob_name_original = f"original/{file_id}{original_file_extension}"

        # GCSService is expected to raise GCSUploadErrorException on failure.
        gcs_original_file_uri = await gcs_service.upload_file_obj_to_gcs(
            file_obj=file, bucket_name=settings.GCS_UPLOAD_BUCKET,
            destination_blob_name=gcs_blob_name_original, content_type=file.content_type
        )
        # If gcs_original_file_uri is None here, it means upload_file_obj_to_gcs contract is violated (should return str or raise)
        # This should not happen if the service is implemented correctly.
        # For robustness, a check can be added, but it implies a bug in the service.

        # audio_analysis_service.run_audio_analysis_workflow is expected to raise
        # audio_analysis_service.run_audio_analysis_workflow は AnalysisFailedException または
        # GenerationFailedException を失敗時に送出することが期待されます。
        workflow_final_state: AudioAnalysisWorkflowState = await run_audio_analysis_workflow(
            gcs_file_path=gcs_original_file_uri
        )

        # ワークフローから「トラックの雰囲気/テーマ」を含む解析結果とMusicXMLデータを取得します。
        # final_analysis_result には humming_theme が格納されている想定です。
        analysis_result_obj = workflow_final_state.get("final_analysis_result")
        # generated_musicxml_data に MusicXML 文字列が格納されている想定です。
        generated_musicxml_data = workflow_final_state.get("generated_musicxml_data")

        # 必須データの存在確認 (ワークフロー内で例外が発生しなかった場合の最終防衛線)
        if not analysis_result_obj:
            logger.error("AIワークフローから最終解析結果（トラック雰囲気/テーマ）が欠落しています。これは予期せぬ状態です。")
            raise AnalysisFailedException(detail="AIワークフローから最終解析結果（トラック雰囲気/テーマ）が欠落しています。")

        if not generated_musicxml_data:
            logger.error("AIワークフローから生成されたMusicXMLデータが欠落しています。これは予期せぬ状態です。")
            raise GenerationFailedException(detail="AIワークフローから生成されたMusicXMLデータが欠落しています。")

        if not isinstance(generated_musicxml_data, str):
            logger.error(f"AIワークフローからMusicXMLデータとして予期しないデータ型が返されました: {type(generated_musicxml_data)}。文字列を期待していました。")
            raise GenerationFailedException(detail="AIワークフローはMusicXMLデータを期待される型で返しませんでした。")

        # MusicXMLデータをGCSにアップロード
        gcs_blob_name_musicxml = f"generated_musicxml/{file_id}.musicxml"
        await gcs_service.upload_data_to_gcs(
            data=generated_musicxml_data,
            bucket_name=settings.GCS_TRACK_BUCKET, # MusicXML用のバケット (既存のものを流用または新規)
            destination_blob_name=gcs_blob_name_musicxml,
            content_type="application/vnd.recordare.musicxml+xml" # MusicXMLのMIMEタイプ
        )

        # 各ファイルの公開URLを取得
        public_original_audio_url = gcs_service.get_gcs_public_url(settings.GCS_UPLOAD_BUCKET, gcs_blob_name_original)
        public_musicxml_url = gcs_service.get_gcs_public_url(settings.GCS_TRACK_BUCKET, gcs_blob_name_musicxml)

        logger.info(f"ファイル {file_id} の処理に成功しました。レスポンスを返します。")
        # ProcessResponse モデルの analysis フィールドは、humming_theme を持つ新しい AnalysisResult を期待します。
        # backing_track_url にはMusicXMLの公開URLを設定します。
        return ProcessResponse(
            analysis=analysis_result_obj,
            backing_track_url=public_musicxml_url,
            original_file_url=public_original_audio_url
        )
    finally:
        # Ensure file is closed, even if an error occurs
        logger.info(f"ファイルのリクエスト処理を終了: {file.filename if file else 'N/A'}")
        if file and hasattr(file, 'close') and callable(file.close):
             try:
                 await file.close() # Important for UploadFile
                 logger.debug(f"UploadFileをクローズしました: {file.filename}")
             except Exception as e_close:
                 logger.warning(f"UploadFile {file.filename} のクローズ中にエラー: {e_close}", exc_info=True)
