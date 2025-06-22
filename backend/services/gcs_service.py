# backend/services/gcs_service.py
import logging
from io import BytesIO
from typing import Optional

from fastapi import UploadFile
from fastapi.concurrency import run_in_threadpool
from google.cloud import storage
from google.auth.exceptions import DefaultCredentialsError

from exceptions import GCSUploadErrorException

logger = logging.getLogger(__name__)

class GCSService:
    def __init__(self, storage_client: Optional[storage.Client] = None):
        self.client = storage_client if storage_client else storage.Client()

    async def upload_file_obj_to_gcs(
        self, file_obj: UploadFile, bucket_name: str, destination_blob_name: str, content_type: Optional[str] = None
    ) -> str:
        """
        Uploads a FastAPI UploadFile object to Google Cloud Storage.
        Returns the GCS URI of the uploaded file.
        """
        try:
            bucket = self.client.bucket(bucket_name)
            blob = bucket.blob(destination_blob_name)
            await file_obj.seek(0)
            await run_in_threadpool(
                blob.upload_from_file,
                file_obj.file,
                content_type=content_type or file_obj.content_type
            )
            gcs_uri = f"gs://{bucket_name}/{destination_blob_name}"
            logger.info(f"Successfully uploaded file object '{file_obj.filename}' to GCS: {gcs_uri}")
            return gcs_uri
        except DefaultCredentialsError as e:
            logger.error(f"GCS authentication error while uploading '{destination_blob_name}': {e}", exc_info=True)
            raise GCSUploadErrorException(message="GCS authentication/configuration error.")
        except Exception as e:
            logger.error(f"GCS upload error for file object '{destination_blob_name}': {e}", exc_info=True)
            raise GCSUploadErrorException(message="Failed to upload file object to GCS.")

    async def upload_data_to_gcs(
        self, data: bytes | str, bucket_name: str, destination_blob_name: str, content_type: str
    ) -> str:
        """
        Uploads byte or string data to Google Cloud Storage.
        Returns the GCS URI of the uploaded data.
        """
        if not data:
            raise ValueError("Cannot upload empty data to GCS.")

        data_bytes: bytes
        if isinstance(data, str):
            data_bytes = data.encode('utf-8')
        elif isinstance(data, bytes):
            data_bytes = data
        else:
            raise TypeError("Unsupported data type. Please provide bytes or str.")

        try:
            bucket = self.client.bucket(bucket_name)
            blob = bucket.blob(destination_blob_name)
            file_like_object = BytesIO(data_bytes)
            await run_in_threadpool(
                blob.upload_from_file,
                file_like_object,
                content_type=content_type
            )
            gcs_uri = f"gs://{bucket_name}/{destination_blob_name}"
            logger.info(f"Successfully uploaded data to GCS: {gcs_uri} (Content-Type: {content_type})")
            return gcs_uri
        except DefaultCredentialsError as e:
            logger.error(f"GCS authentication error while uploading data to '{destination_blob_name}': {e}", exc_info=True)
            raise GCSUploadErrorException(message="GCS authentication/configuration error during data upload.")
        except Exception as e:
            logger.error(f"GCS upload error for data to '{destination_blob_name}': {e}", exc_info=True)
            raise GCSUploadErrorException(message="Failed to upload data to GCS.")

    def get_gcs_public_url(self, bucket_name: str, blob_name: str) -> str:
        """
        Generates the public URL for a GCS object.
        Assumes the object and bucket are configured for public access.
        """
        return f"https://storage.googleapis.com/{bucket_name}/{blob_name}"

# Helper function to get an instance of the service, potentially with dependency injection in mind for FastAPI
def get_gcs_service() -> GCSService:
    # In a FastAPI context, you might initialize this with settings or manage its lifecycle.
    # For now, a simple instantiation.
    return GCSService()
