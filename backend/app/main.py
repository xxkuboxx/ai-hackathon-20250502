from fastapi import FastAPI
from app.api.endpoints import process_router # Adjusted import

app = FastAPI(
    title="Music Processing API",
    description="API for analyzing music and generating backing tracks.",
    version="0.1.0"
)

# Include the router for the /api prefix
app.include_router(process_router, prefix="/api", tags=["Processing"])

@app.get("/")
async def root():
    return {"message": "Welcome to the Music Processing API!"}

# Health check endpoint (optional but good practice)
@app.get("/health", tags=["Health"])
async def health_check():
    return {"status": "ok"}
