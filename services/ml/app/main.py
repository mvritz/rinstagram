"""
rinstagram Service

Unified FastAPI service providing Instagram password encryption and all
machine-learning inference endpoints:

  POST /encrypt               — Instagram v10 AES-GCM + NaCl password encryption
  POST /predict/engagement    — MLP engagement rate predictor
  POST /predict/bot           — LightGBM + MLP ensemble bot detector
  POST /predict/growth        — LSTM follower growth forecaster
  POST /predict/niche         — DistilBERT content niche classifier
"""

import logging
from contextlib import asynccontextmanager
from typing import Dict

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from .config import (
    DEVICE, ENGAGEMENT_WEIGHTS, BOT_MLP_WEIGHTS, BOT_GBM_WEIGHTS,
    FORECASTER_WEIGHTS, CLASSIFIER_WEIGHTS,
)
from .encryption import encrypt_instagram_password
from .models import (
    load_engagement_model,
    load_bot_model,
    load_forecaster_model,
    load_classifier_model,
    EngagementPredictor,
    BotDetector,
    GrowthForecaster,
    NicheClassifier,
)
from .schemas import (
    EncryptRequest,    EncryptResponse,
    EngagementRequest, EngagementResponse,
    BotRequest,        BotResponse,
    GrowthRequest,     GrowthResponse,
    NicheRequest,      NicheResponse,
    HealthResponse,
)

logging.basicConfig(
    level  = logging.INFO,
    format = "%(asctime)s %(levelname)-8s %(name)s %(message)s",
)
logger = logging.getLogger(__name__)

_models: Dict[str, object] = {}


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Loading ML models (device=%s) ...", DEVICE)

    logger.info("  → Engagement predictor (MLP)")
    _models["engagement"] = load_engagement_model(ENGAGEMENT_WEIGHTS, DEVICE)

    logger.info("  → Bot detector (LightGBM + MLP ensemble)")
    _models["bot"] = load_bot_model(BOT_MLP_WEIGHTS, BOT_GBM_WEIGHTS, DEVICE)

    logger.info("  → Growth forecaster (LSTM)")
    _models["forecaster"] = load_forecaster_model(FORECASTER_WEIGHTS, DEVICE)

    logger.info("  → Niche classifier (DistilBERT)")
    _models["classifier"] = load_classifier_model(CLASSIFIER_WEIGHTS, DEVICE)

    logger.info("All models ready. Encryption endpoint active.")
    yield
    _models.clear()


app = FastAPI(
    title       = "rinstagram Service",
    description = "Unified Instagram analytics service — encryption + ML inference",
    version     = "2.0.0",
    docs_url    = "/docs",
    redoc_url   = "/redoc",
    lifespan    = lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins  = ["*"],
    allow_methods  = ["GET", "POST"],
    allow_headers  = ["*"],
)


# ── Meta ────────────────────────────────────────────────────────────────────

@app.get("/health", response_model=HealthResponse, tags=["meta"])
def health() -> HealthResponse:
    return HealthResponse(
        service = "rinstagram",
        models  = {
            "engagement":  "engagement" in _models,
            "bot":         "bot"        in _models,
            "forecaster":  "forecaster" in _models,
            "classifier":  "classifier" in _models,
        }
    )


@app.get("/", tags=["meta"])
def index() -> dict:
    return {"project": "rinstagram", "author": "github.com/mvritz"}


# ── Encryption ───────────────────────────────────────────────────────────────

@app.post("/encrypt", response_model=EncryptResponse, tags=["encryption"])
def encrypt(body: EncryptRequest) -> EncryptResponse:
    """
    Encrypt a plaintext Instagram password using the v10 AES-GCM + NaCl
    envelope scheme required by the Instagram login API.

    Called automatically by the R package's `lscrape()` login flow.
    """
    try:
        encrypted = encrypt_instagram_password(body.key_id, body.pub_key, body.password)
    except Exception as exc:
        raise HTTPException(status_code=422, detail=f"Encryption failed: {exc}") from exc
    return EncryptResponse(encrypted=encrypted)


# ── ML Inference ─────────────────────────────────────────────────────────────

@app.post("/predict/engagement", response_model=EngagementResponse, tags=["inference"])
def predict_engagement(body: EngagementRequest) -> EngagementResponse:
    """
    Predict the engagement rate for a list of Instagram profiles using a
    3-layer feed-forward neural network with BatchNorm and Dropout.
    """
    if not body.profiles:
        raise HTTPException(status_code=422, detail="Profiles list must not be empty.")

    predictor: EngagementPredictor = _models["engagement"]
    try:
        preds = predictor.predict(body.profiles)
    except Exception as exc:
        logger.exception("Engagement prediction failed.")
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    return EngagementResponse(predictions=preds)


@app.post("/predict/bot", response_model=BotResponse, tags=["inference"])
def predict_bot(body: BotRequest) -> BotResponse:
    """
    Estimate the bot/fake-account probability for each profile using a
    soft-vote ensemble of LightGBM and a two-layer MLP.
    """
    if not body.profiles:
        raise HTTPException(status_code=422, detail="Profiles list must not be empty.")

    detector: BotDetector = _models["bot"]
    try:
        probs, labels = detector.predict(body.profiles)
    except Exception as exc:
        logger.exception("Bot detection failed.")
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    return BotResponse(bot_probabilities=probs, risk_labels=labels)


@app.post("/predict/growth", response_model=GrowthResponse, tags=["inference"])
def predict_growth(body: GrowthRequest) -> GrowthResponse:
    """
    Forecast follower growth using a 2-layer LSTM with Monte Carlo Dropout
    uncertainty estimation. Requires at least 5 historical data points.
    """
    if len(body.history) < 5:
        raise HTTPException(status_code=422, detail="Need at least 5 historical data points.")

    forecaster: GrowthForecaster = _models["forecaster"]
    try:
        dates, predicted, lower, upper = forecaster.predict(body.history, body.horizon)
    except Exception as exc:
        logger.exception("Growth forecasting failed.")
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    return GrowthResponse(
        username    = body.username,
        dates       = dates,
        predicted   = predicted,
        lower_bound = lower,
        upper_bound = upper,
    )


@app.post("/predict/niche", response_model=NicheResponse, tags=["inference"])
def predict_niche(body: NicheRequest) -> NicheResponse:
    """
    Classify each profile into one of nine content niches using a fine-tuned
    DistilBERT model applied to biography text and post captions.
    """
    if not body.profiles:
        raise HTTPException(status_code=422, detail="Profiles list must not be empty.")

    classifier: NicheClassifier = _models["classifier"]
    try:
        niches, confidences = classifier.predict(body.profiles)
    except Exception as exc:
        logger.exception("Niche classification failed.")
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    return NicheResponse(niches=niches, confidences=confidences)
