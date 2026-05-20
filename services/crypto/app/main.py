"""
rinstagram Crypto Service

Standalone FastAPI microservice that handles Instagram v10 password encryption.
Separated from the R package so it can be independently deployed, versioned, and tested.
"""

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from .encryption import encrypt_instagram_password
from .schemas import EncryptRequest, EncryptResponse, HealthResponse

app = FastAPI(
    title       = "rinstagram Crypto Service",
    description = "Instagram v10 password encryption microservice",
    version     = "2.0.0",
    docs_url    = "/docs",
    redoc_url   = "/redoc",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins  = ["*"],
    allow_methods  = ["GET", "POST"],
    allow_headers  = ["*"],
)


@app.get("/health", response_model=HealthResponse, tags=["meta"])
def health() -> HealthResponse:
    return HealthResponse()


@app.get("/", tags=["meta"])
def index() -> dict:
    return {"project": "rinstagram", "author": "github.com/mvritz", "service": "crypto"}


@app.post("/encrypt", response_model=EncryptResponse, tags=["crypto"])
def encrypt(body: EncryptRequest) -> EncryptResponse:
    """
    Encrypt a plaintext Instagram password using the v10 AES-GCM + NaCl envelope scheme.

    The R package calls this endpoint during the `lscrape()` login flow.
    """
    try:
        encrypted = encrypt_instagram_password(body.key_id, body.pub_key, body.password)
    except Exception as exc:
        raise HTTPException(status_code=422, detail=f"Encryption failed: {exc}") from exc

    return EncryptResponse(encrypted=encrypted)
