# rinstagram Crypto Service

Standalone FastAPI microservice handling Instagram v10 password encryption.
Separated from the R package so it can be independently versioned, tested, and deployed.

## Encryption Scheme

1. A random 256-bit AES-GCM key is generated per request.
2. The current UNIX timestamp is used as AAD (additional authenticated data).
3. The password is encrypted with AES-GCM.
4. The AES key is encrypted with Instagram's public key via NaCl `SealedBox`.
5. All components are concatenated into a binary frame and base64-encoded.
6. The R package prepends `#PWD_INSTAGRAM_BROWSER:10:<timestamp>:` before sending to Instagram.

## Running locally

```bash
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

API docs: http://localhost:8000/docs

## Running with Docker

```bash
docker build -t rinstagram-crypto .
docker run -p 8000:8000 rinstagram-crypto
```

## Running tests

```bash
pytest tests/ -v
```

## Endpoints

| Method | Path       | Description                    |
|--------|------------|--------------------------------|
| GET    | `/`        | Service info                   |
| GET    | `/health`  | Health check                   |
| POST   | `/encrypt` | Encrypt an Instagram password  |

## Environment variables

Set `RINSTAGRAM_CRYPTO_URL` in the R environment (`.Renviron`) to point the
R package at a custom deployment:

```
RINSTAGRAM_CRYPTO_URL=https://your-deployment.railway.app/encrypt
```
