from pydantic import BaseModel, Field


class EncryptRequest(BaseModel):
    key_id:   str = Field(..., description="Instagram encryption key ID (decimal string)")
    pub_key:  str = Field(..., description="Instagram RSA public key (hex-encoded)")
    password: str = Field(..., min_length=1, description="Plaintext Instagram password")

    model_config = {"json_schema_extra": {"examples": [{"key_id": "247", "pub_key": "0a1b2c...", "password": "mypassword"}]}}


class EncryptResponse(BaseModel):
    encrypted: str = Field(..., description="Base64-encoded encrypted password payload")


class HealthResponse(BaseModel):
    status:  str = "ok"
    service: str = "rinstagram-crypto"
    version: str = "2.0.0"
