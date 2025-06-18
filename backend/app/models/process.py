from pydantic import BaseModel, Field
from typing import Optional
from .analysis import AnalysisResult # Corrected import path

class ProcessRequestArgs(BaseModel):
    # Currently no specific arguments, but can be extended
    pass

class ProcessResponse(BaseModel):
    analysis: AnalysisResult
    backing_track_url: str = Field(..., example="https://storage.googleapis.com/your-bucket/backing_track.mp3")
