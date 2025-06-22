# routers/process_api.py

import uuid
import logging
import os
from fastapi import APIRouter, UploadFile, File, Depends
from typing import Annotated, Optional

from ..models import ProcessResponse, AnalysisResult
from ..config import settings
from ..exceptions import (
    UnsupportedMediaTypeException,
    FileTooLargeException,
    InternalServerErrorException,
    AnalysisFailedException, # Keep for direct raise if workflow contract violated
    GenerationFailedException # Keep for direct raise if workflow contract violated
)
from ..services.audio_analysis_service import run_audio_analysis_workflow, AudioAnalysisWorkflowState
from ..services.gcs_service import GCSService, get_gcs_service

logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/api",
    tags=["Audio Processing"],
)

SUPPORTED_AUDIO_MIME_TYPES = ["audio/mpeg", "audio/wav", "audio/x-wav"]

@router.post("/process", response_model=ProcessResponse)
async def process_audio_file(
    file: Annotated[UploadFile, File(description="処理する音声ファイル (MP3またはWAV)。")],
    gcs_service: GCSService = Depends(get_gcs_service)
):
    # local_temp_file_path was unused and has been removed.
    try:
        logger.info(f"ファイルアップロードリクエスト受信: {file.filename}")
        if file.content_type not in SUPPORTED_AUDIO_MIME_TYPES:
            raise UnsupportedMediaTypeException(f"サポートされていないファイルタイプです: {file.content_type}。")

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

        original_file_extension = ".mp3" if file.content_type == "audio/mpeg" else \
                                  ".wav" if file.content_type in ["audio/wav", "audio/x-wav"] else ".dat"
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
        # AnalysisFailedException or GenerationFailedException on failure.
        workflow_final_state: AudioAnalysisWorkflowState = await run_audio_analysis_workflow(
            gcs_file_path=gcs_original_file_uri
        )

        analysis_result_obj = workflow_final_state.get("final_analysis_result")
        backing_track_musicxml_data = workflow_final_state.get("generated_backing_track_data")

        # Final safeguard: ensure both essential pieces of data are present.
        # The workflow itself should raise specific exceptions if these are missing due to internal errors.
        if not analysis_result_obj:
            logger.error("AIワークフローから最終解析結果が欠落しています（例外も発生せず）。これは予期せぬ状態です。")
            raise AnalysisFailedException(detail="AIワークフローから最終解析結果が欠落しています。")

        if not backing_track_musicxml_data:
            logger.error("AIワークフローから生成されたバッキングトラックデータが欠落しています（例外も発生せず）。これは予期せぬ状態です。")
            raise GenerationFailedException(detail="AIワークフローから生成されたバッキングトラックデータが欠落しています。")

        if not isinstance(backing_track_musicxml_data, str):
            logger.error(f"AIワークフローから予期しないデータ型が返されました: {type(backing_track_musicxml_data)}。MusicXML(str)を期待していました。")
            raise GenerationFailedException(detail="AIワークフローはバッキングトラックデータ（MusicXML）を期待される型で返しませんでした。")


        gcs_blob_name_track = f"generated/{file_id}.musicxml"

        # GCSService is expected to raise GCSUploadErrorException on failure.
        await gcs_service.upload_data_to_gcs(
            data=backing_track_musicxml_data,
            bucket_name=settings.GCS_TRACK_BUCKET,
            destination_blob_name=gcs_blob_name_track,
            content_type="application/vnd.recordare.musicxml+xml"
        )

        public_original_url = gcs_service.get_gcs_public_url(settings.GCS_UPLOAD_BUCKET, gcs_blob_name_original)
        public_backing_track_url = gcs_service.get_gcs_public_url(settings.GCS_TRACK_BUCKET, gcs_blob_name_track)

        logger.info(f"ファイル {file_id} の処理に成功しました。レスポンスを返します。")
        return ProcessResponse(
            analysis=analysis_result_obj, # analysis_result_obj is confirmed to be not None above
            backing_track_url=public_backing_track_url,
            original_file_url=public_original_url
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
