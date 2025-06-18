from pydantic import BaseModel, Field
from typing import Optional

class ErrorResponse(BaseModel):
    error_code: str = Field(..., example="UNEXPECTED_ERROR")
    message: str = Field(..., example="An unexpected error occurred.")
    details: Optional[str] = Field(None, example="Optional detailed error information.")
