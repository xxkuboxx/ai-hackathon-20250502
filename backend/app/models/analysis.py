from pydantic import BaseModel, Field
from typing import List

class AnalysisResult(BaseModel):
    key: str = Field(..., example="C Major")
    bpm: float = Field(..., example=120.5)
    chords: List[str] = Field(..., example=["Am", "G", "C"])
    genre_by_ai: str = Field(..., example="Pop")
