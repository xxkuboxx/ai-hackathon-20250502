# routers/process_api.py

import uuid
import logging
import os
from io import BytesIO
# import datetime # _generate_gcs_signed_url を削除するため不要になる可能性
from fastapi import APIRouter, UploadFile, File, HTTPException
from fastapi.responses import JSONResponse
from fastapi.concurrency import run_in_threadpool
from typing import Annotated, Optional, Dict, Any

from google.cloud import storage
from google.auth.exceptions import DefaultCredentialsError

from models import ProcessResponse, ErrorCode, ErrorResponse, AnalysisResult
from config import settings
from exceptions import (
    UnsupportedMediaTypeException,
    FileTooLargeException,
    GCSUploadErrorException,
    InternalServerErrorException,
    AnalysisFailedException,
    GenerationFailedException
)
from services.audio_analysis_service import run_audio_analysis_workflow, AudioAnalysisWorkflowState

logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/api",
    tags=["Audio Processing"],
)

SUPPORTED_AUDIO_MIME_TYPES = ["audio/mpeg", "audio/wav", "audio/x-wav"]

async def _upload_file_obj_to_gcs(
    file_obj: UploadFile, bucket_name: str, destination_blob_name: str, content_type: Optional[str] = None
) -> str:
    try:
        client = storage.Client()
        bucket = client.bucket(bucket_name)
        blob = bucket.blob(destination_blob_name)
        await file_obj.seek(0)
        await run_in_threadpool(
            blob.upload_from_file,
            file_obj.file,
            content_type=content_type or file_obj.content_type
            # オブジェクトをデフォルトで公開にする場合、ここで設定することも検討できますが、
            # バケットポリシーで制御する方が一般的です。
            # 例: blob.upload_from_file(..., predefined_acl='publicRead')
            # ただし、バケットが均一なアクセス制御モードの場合、predefined_acl は無視されます。
        )
        gcs_uri = f"gs://{bucket_name}/{destination_blob_name}"
        logger.info(f"GCSへのファイルオブジェクト '{file_obj.filename}' のアップロードに成功しました: {gcs_uri}")
        return gcs_uri
    except DefaultCredentialsError as e:
        logger.error(f"GCS認証エラー ('{destination_blob_name}'): {e}", exc_info=True)
        raise GCSUploadErrorException(message="GCS認証/設定エラー。")
    except Exception as e:
        logger.error(f"GCSアップロードエラー ('{destination_blob_name}'): {e}", exc_info=True)
        raise GCSUploadErrorException(message="ファイルオブジェクトのGCSへのアップロードに失敗しました。")

async def _upload_data_to_gcs(
    data: bytes|str, bucket_name: str, destination_blob_name: str, content_type: str
) -> str:
    if not data:
        raise ValueError("空のデータをGCSにアップロードできません。")
    
    data_bytes: bytes
    if isinstance(data, str):
        data_bytes = data.encode('utf-8')
    elif isinstance(data, bytes):
        data_bytes = data
    else:
        raise TypeError("サポートされていないデータ型です。bytesまたはstrを指定してください。")

    try:
        client = storage.Client()
        bucket = client.bucket(bucket_name)
        blob = bucket.blob(destination_blob_name)
        file_like_object = BytesIO(data_bytes)
        await run_in_threadpool(
            blob.upload_from_file,
            file_like_object,
            content_type=content_type
            # 同様に、ここで公開ACLを設定することも検討可能
            # predefined_acl='publicRead'
        )
        gcs_uri = f"gs://{bucket_name}/{destination_blob_name}"
        logger.info(f"GCSへのデータのアップロードに成功しました: {gcs_uri} (Content-Type: {content_type})")
        return gcs_uri
    except DefaultCredentialsError as e:
        logger.error(f"GCS認証エラー (データ to '{destination_blob_name}'): {e}", exc_info=True)
        raise GCSUploadErrorException(message="データアップロード時のGCS認証/設定エラー。")
    except Exception as e:
        logger.error(f"GCSアップロードエラー (データ to '{destination_blob_name}'): {e}", exc_info=True)
        raise GCSUploadErrorException(message="データのGCSへのアップロードに失敗しました。")

# _generate_gcs_signed_url 関数は不要になるため削除またはコメントアウト
# async def _generate_gcs_signed_url(
# bucket_name: str, blob_name: str, expiration_seconds: int = settings.SIGNED_URL_EXPIRATION_SECONDS, method: str = "GET"
# ) -> str:
# ... (元のコード)

def get_gcs_public_url(bucket_name: str, blob_name: str) -> str:
    """GCSオブジェクトの公開URLを生成します。"""
    return f"https://storage.googleapis.com/{bucket_name}/{blob_name}"

@router.post("/process", response_model=ProcessResponse)
async def process_audio_file(
    file: Annotated[UploadFile, File(description="処理する音声ファイル (MP3またはWAV)。")]
):
    local_temp_file_path: Optional[str] = None
    try:
        logger.info(f"ファイルアップロードリクエスト受信: {file.filename}")
        if file.content_type not in SUPPORTED_AUDIO_MIME_TYPES:
            raise UnsupportedMediaTypeException(f"サポートされていないファイルタイプです: {file.content_type}。")
        max_size_bytes = settings.MAX_FILE_SIZE_MB * 1024 * 1024
        actual_file_size = file.size
        if actual_file_size is None:
            raise InternalServerErrorException(message="ファイルサイズを決定できませんでした。")
        if actual_file_size > max_size_bytes:
            raise FileTooLargeException(f"ファイルサイズが{settings.MAX_FILE_SIZE_MB}MBを超えています。")
        logger.info(f"ファイル '{file.filename}' は初期検証を通過しました。")

        file_id = str(uuid.uuid4())
        logger.info(f"処理用の一意なIDを生成しました: {file_id}")

        original_file_extension = ".mp3" if file.content_type == "audio/mpeg" else \
                                  ".wav" if file.content_type in ["audio/wav", "audio/x-wav"] else ".dat"
        gcs_blob_name_original = f"original/{file_id}{original_file_extension}"
        gcs_original_file_uri: Optional[str] = None

        gcs_original_file_uri = await _upload_file_obj_to_gcs(
            file_obj=file, bucket_name=settings.GCS_UPLOAD_BUCKET,
            destination_blob_name=gcs_blob_name_original, content_type=file.content_type
        )
        if not gcs_original_file_uri:
            raise InternalServerErrorException(detail="オリジナルファイルのGCS URIが取得できませんでした。")

        analysis_result_obj: Optional[AnalysisResult] = None
        backing_track_musicxml_data: Optional[str] = None
        workflow_final_state: AudioAnalysisWorkflowState = await run_audio_analysis_workflow(
            gcs_file_path=gcs_original_file_uri
        )
        if workflow_final_state.get("final_analysis_result"):
            analysis_result_obj = workflow_final_state["final_analysis_result"]
        else: raise AnalysisFailedException(detail="AIワークフローは解析結果なしで終了しました。")
        
        if workflow_final_state.get("generated_backing_track_data"):
            generated_data = workflow_final_state["generated_backing_track_data"]
            if isinstance(generated_data, str):
                backing_track_musicxml_data = generated_data
            else:
                logger.error(f"AIワークフローから予期しないデータ型が返されました: {type(generated_data)}。MusicXML(str)を期待していました。")
                raise GenerationFailedException(detail="AIワークフローはバッキングトラックデータ（MusicXML）を期待される型で返しませんでした。")
        else: 
            raise GenerationFailedException(detail="AIワークフローはバッキングトラックデータ（MusicXML）なしで終了しました。")
        
        if not analysis_result_obj or not backing_track_musicxml_data:
             raise InternalServerErrorException(detail="AIワークフロー完了後、重要なデータ（解析結果またはMusicXML）が欠落しています。")

        gcs_blob_name_track = f"generated/{file_id}.musicxml"
        gcs_backing_track_uri: Optional[str] = None
        gcs_backing_track_uri = await _upload_data_to_gcs(
            data=backing_track_musicxml_data,
            bucket_name=settings.GCS_TRACK_BUCKET,
            destination_blob_name=gcs_blob_name_track,
            content_type="application/vnd.recordare.musicxml+xml"
        )
        if not gcs_backing_track_uri:
            raise InternalServerErrorException(detail="MusicXMLバッキングトラックのGCS URIがアップロード後に取得できませんでした。")

        # 署名付きURLの代わりに公開URLを使用
        public_original_url = get_gcs_public_url(settings.GCS_UPLOAD_BUCKET, gcs_blob_name_original)
        public_backing_track_url = get_gcs_public_url(settings.GCS_TRACK_BUCKET, gcs_blob_name_track)
        
        logger.info(f"ファイル {file_id} の処理に成功しました。レスポンスを返します。")
        return ProcessResponse(
            analysis=analysis_result_obj,
            backing_track_url=public_backing_track_url, # 公開MusicXMLファイルのURL
            original_file_url=public_original_url     # 公開オリジナルファイルのURL
        )
    finally:
        if local_temp_file_path and os.path.exists(local_temp_file_path):
            try:
                os.remove(local_temp_file_path)
                logger.info(f"仮のローカル一時ファイルを正常に削除しました: {local_temp_file_path}")
            except Exception as e_cleanup:
                logger.error(f"仮のローカル一時ファイル {local_temp_file_path} のクリーンアップ中にエラー: {e_cleanup}", exc_info=True)
        
        logger.info(f"ファイルのリクエスト処理を終了: {file.filename if file else 'N/A'}")
        if file and hasattr(file, 'close') and callable(file.close):
             try:
                 await file.close()
                 logger.debug(f"UploadFileをクローズしました: {file.filename}")
             except Exception as e_close:
                 logger.warning(f"UploadFile {file.filename} のクローズ中にエラー: {e_close}", exc_info=True)
