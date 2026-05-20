"""Pydantic schemas for all ML service endpoints."""

from __future__ import annotations

from typing import List, Optional
from pydantic import BaseModel, Field


# ── Shared ─────────────────────────────────────────────────────────────────

class ProfileFeatures(BaseModel):
    username:        str
    follower_count:  float
    following_count: float
    posts_count:     float
    avg_likes:       Optional[float] = None
    avg_comments:    Optional[float] = None
    engagement_rate: Optional[float] = None


# ── Engagement Prediction ───────────────────────────────────────────────────

class EngagementRequest(BaseModel):
    profiles: List[ProfileFeatures]


class EngagementResponse(BaseModel):
    predictions: List[float] = Field(..., description="Predicted engagement rate (0–1) per profile")


# ── Bot Detection ───────────────────────────────────────────────────────────

class BotRequest(BaseModel):
    profiles: List[ProfileFeatures]


class BotResponse(BaseModel):
    bot_probabilities: List[float] = Field(..., description="Bot probability (0–1) per profile")
    risk_labels:       List[str]   = Field(..., description="'low', 'medium', or 'high'")


# ── Growth Forecasting ──────────────────────────────────────────────────────

class HistoryPoint(BaseModel):
    date:           str
    follower_count: int


class GrowthRequest(BaseModel):
    username: str
    horizon:  int = Field(30, ge=1, le=365)
    history:  List[HistoryPoint]


class GrowthResponse(BaseModel):
    username:    str
    dates:       List[str]
    predicted:   List[float]
    lower_bound: List[float]
    upper_bound: List[float]


# ── Niche Classification ────────────────────────────────────────────────────

class NicheProfile(BaseModel):
    username: str
    bio:      str = ""
    captions: str = ""


class NicheRequest(BaseModel):
    profiles: List[NicheProfile]


class NicheResponse(BaseModel):
    niches:      List[str]   = Field(..., description="Predicted niche label per profile")
    confidences: List[float] = Field(..., description="Softmax confidence per profile")


# ── Health ──────────────────────────────────────────────────────────────────

class HealthResponse(BaseModel):
    status:  str = "ok"
    service: str = "rinstagram-ml"
    version: str = "2.0.0"
    models:  dict = {}
