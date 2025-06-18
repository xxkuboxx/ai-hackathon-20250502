from fastapi.testclient import TestClient
from pydantic import BaseModel, Field
from typing import List, Optional
import pytest
from unittest.mock import patch

# Assuming main.py is in backend/app/main.py
# Adjust the import path if your structure is different
from app.main import app

client = TestClient(app)

# Pydantic models based on design document (section 5)
class Analysis(BaseModel):
    key: str
    bpm: float
    chords: List[str]
    genre_by_ai: str

class ProcessResponse(BaseModel):
    analysis: Analysis
    backing_track_url: str

# Test case for POST /api/process (success)
@patch('app.services.process_service.analyze_music_with_gemini') # Mock Gemini call
@patch('app.services.process_service.upload_to_gcs') # Mock GCS call
def test_process_audio_success(mock_upload_to_gcs, mock_analyze_music_with_gemini):
    # Mock return values for external services
    mock_analyze_music_with_gemini.return_value = {
        "key": "C Major",
        "bpm": 120.0,
        "chords": ["C", "G", "Am", "F"],
        "genre_by_ai": "Pop"
    }
    mock_upload_to_gcs.return_value = "http://example.com/backing_track.mp3"

    # Simulate file upload
    # Create a dummy mp3 file for testing
    with open("dummy.mp3", "wb") as f:
        f.write(b"dummy mp3 content")

    with open("dummy.mp3", "rb") as test_file:
        response = client.post(
            "/api/process",
            files={"file": ("test.mp3", test_file, "audio/mpeg")}
        )

    # Assertions
    assert response.status_code == 200

    response_data = response.json()

    # Validate response structure using Pydantic model
    ProcessResponse(**response_data)

    # Specific assertions for analysis content types
    assert isinstance(response_data["analysis"]["key"], str)
    assert isinstance(response_data["analysis"]["bpm"], float)
    assert isinstance(response_data["analysis"]["chords"], list)
    assert all(isinstance(chord, str) for chord in response_data["analysis"]["chords"])
    assert isinstance(response_data["analysis"]["genre_by_ai"], str)
    assert isinstance(response_data["backing_track_url"], str)

    # Verify that mocks were called (optional, but good practice)
    mock_analyze_music_with_gemini.assert_called_once()
    mock_upload_to_gcs.assert_called_once()
