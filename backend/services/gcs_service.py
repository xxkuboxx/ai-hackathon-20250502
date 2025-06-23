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

    def _parse_gcs_url(self, gcs_url: str) -> tuple[str, str]:
        """
        Parses a GCS URL (gs://bucket/object or https://storage.googleapis.com/bucket/object)
        and returns (bucket_name, blob_name).
        Raises ValueError if the URL format is invalid.
        """
        if gcs_url.startswith("gs://"):
            parts = gcs_url[5:].split("/", 1)
            if len(parts) == 2:
                return parts[0], parts[1]
        elif gcs_url.startswith("https://storage.googleapis.com/"):
            parts = gcs_url[len("https://storage.googleapis.com/"):].split("/", 1)
            if len(parts) == 2:
                return parts[0], parts[1]
        raise ValueError(f"Invalid GCS URL format: {gcs_url}")

    async def download_file_as_string_from_gcs(self, gcs_url: str, encoding: str = "utf-8") -> str:
        """
        Downloads a file from GCS given its GCS URL and returns its content as a string.
        """
        try:
            bucket_name, blob_name = self._parse_gcs_url(gcs_url)
            bucket = self.client.bucket(bucket_name)
            blob = bucket.blob(blob_name)

            logger.info(f"Attempting to download GCS object: gs://{bucket_name}/{blob_name}")

            # Use run_in_threadpool for the blocking GCS download call
            file_bytes = await run_in_threadpool(blob.download_as_bytes)

            content = file_bytes.decode(encoding)
            logger.info(f"Successfully downloaded and decoded GCS object: gs://{bucket_name}/{blob_name}")
            return content
        except DefaultCredentialsError as e:
            logger.error(f"GCS authentication error while downloading '{gcs_url}': {e}", exc_info=True)
            # Consider a more specific exception, e.g., GCSDownloadErrorException
            raise GCSUploadErrorException(message=f"GCS authentication/configuration error during download from {gcs_url}.")
        except ValueError as e: # From _parse_gcs_url
            logger.error(f"Invalid GCS URL format for download: {gcs_url} - {e}", exc_info=True)
            raise GCSUploadErrorException(message=f"Invalid GCS URL format: {gcs_url}.") # Or a more specific client error
        except Exception as e:
            # This could include google.cloud.exceptions.NotFound, Forbidden, etc.
            logger.error(f"Failed to download file from GCS '{gcs_url}': {e}", exc_info=True)
            # Consider a more specific exception, e.g., GCSDownloadErrorException
            # Or re-raise specific Google Cloud exceptions if the caller should handle them.
            raise GCSUploadErrorException(message=f"Failed to download file from GCS: {gcs_url}. Error: {type(e).__name__}")


# Helper function to get an instance of the service, potentially with dependency injection in mind for FastAPI
def get_gcs_service() -> GCSService:
    # In a FastAPI context, you might initialize this with settings or manage its lifecycle.
    # For now, a simple instantiation.
    return GCSService()
