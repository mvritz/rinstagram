"""
Unit tests for the ML model inference code.

Tests are designed to run without pre-trained weights — models are built and
exercised with minimal forward passes to verify shapes and types.
"""

import math
import sys
import os
from pathlib import Path

import numpy as np
import pytest
import torch

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from services.ml.app.models.engagement  import EngagementMLP, _extract_features as eng_features
from services.ml.app.models.bot_detector import BotMLP, _extract_features as bot_features
from services.ml.app.models.forecaster  import LSTMForecaster, _preprocess_history
from services.ml.app.schemas import (
    ProfileFeatures, GrowthRequest, HistoryPoint, NicheProfile
)
from services.ml.training.generate_synthetic_data import (
    generate_engagement_data,
    generate_bot_data,
    generate_growth_data,
    generate_niche_data,
)


# ── Synthetic data generators ────────────────────────────────────────────────

class TestSyntheticData:
    def test_engagement_data_shapes(self):
        X, y = generate_engagement_data(n=100)
        assert X.shape == (100, 5)
        assert y.shape == (100,)
        assert np.all(y >= 0) and np.all(y <= 1)

    def test_bot_data_shapes(self):
        X, y = generate_bot_data(n=200)
        assert X.shape == (200, 6)
        assert set(y.astype(int)).issubset({0, 1})

    def test_bot_data_has_both_classes(self):
        _, y = generate_bot_data(n=500)
        assert 0 in y and 1 in y

    def test_growth_data_shapes(self):
        X, y = generate_growth_data(n=50, seq_len=30, horizon=90)
        assert X.shape == (50, 30)
        assert y.shape == (50, 90)

    def test_niche_data_returns_all_classes(self):
        texts, labels = generate_niche_data(n_per_class=10)
        assert len(texts) == len(labels) == 90
        assert set(labels) == set(range(9))


# ── Engagement MLP ────────────────────────────────────────────────────────────

class TestEngagementMLP:
    def test_forward_shape(self):
        model = EngagementMLP()
        x     = torch.randn(4, 5)
        out   = model(x)
        assert out.shape == (4,)

    def test_output_in_range(self):
        model = EngagementMLP().eval()
        x     = torch.randn(20, 5)
        with torch.no_grad():
            out = model(x)
        assert torch.all(out >= 0) and torch.all(out <= 1)

    def test_feature_extraction(self):
        profiles = [
            ProfileFeatures(username="a", follower_count=10000, following_count=500, posts_count=50, avg_likes=500),
            ProfileFeatures(username="b", follower_count=500,   following_count=300, posts_count=10),
        ]
        features = eng_features(profiles)
        assert features.shape == (2, 5)
        assert not torch.any(torch.isnan(features))


# ── Bot MLP ───────────────────────────────────────────────────────────────────

class TestBotMLP:
    def test_forward_shape(self):
        model = BotMLP()
        x     = torch.randn(8, 6)
        out   = model(x)
        assert out.shape == (8,)

    def test_output_sigmoid_range(self):
        model = BotMLP().eval()
        x     = torch.randn(16, 6)
        with torch.no_grad():
            out = model(x)
        assert torch.all(out >= 0) and torch.all(out <= 1)

    def test_feature_extraction(self):
        profiles = [
            ProfileFeatures(username="bot",    follower_count=1_000_000, following_count=500,   posts_count=2,  avg_likes=5),
            ProfileFeatures(username="normal", follower_count=50_000,    following_count=1_000,  posts_count=100, avg_likes=2500),
        ]
        X = bot_features(profiles)
        assert X.shape == (2, 6)
        assert not np.any(np.isnan(X))


# ── LSTM Forecaster ───────────────────────────────────────────────────────────

class TestLSTMForecaster:
    def test_forward_shape(self):
        model = LSTMForecaster(hidden=32, n_layers=1, horizon=30)
        x     = torch.randn(4, 30)
        out   = model(x)
        assert out.shape == (4, 30)

    def test_preprocess_pads_short_history(self):
        history = [
            HistoryPoint(date="2024-01-01", follower_count=1000),
            HistoryPoint(date="2024-01-02", follower_count=1100),
        ]
        seq, mn, mx = _preprocess_history(history, seq_len=30)
        assert len(seq) == 30
        assert mn == 1000
        assert mx == 1100

    def test_preprocess_truncates_long_history(self):
        history = [
            HistoryPoint(date=f"2024-01-{i+1:02d}", follower_count=1000 + i * 10)
            for i in range(50)
        ]
        seq, _, _ = _preprocess_history(history, seq_len=30)
        assert len(seq) == 30


# ── FastAPI endpoints ─────────────────────────────────────────────────────────

class TestFastAPIEndpoints:
    @pytest.fixture(autouse=True)
    def setup(self):
        from fastapi.testclient import TestClient
        from unittest.mock import patch, MagicMock

        dummy_engagement = MagicMock()
        dummy_engagement.predict.return_value = [0.03, 0.08]

        dummy_bot = MagicMock()
        dummy_bot.predict.return_value = ([0.1, 0.85], ["low", "high"])

        dummy_forecaster = MagicMock()
        dummy_forecaster.predict.return_value = (
            ["2024-02-01", "2024-02-02"],
            [10000.0, 10100.0],
            [9800.0,  9900.0],
            [10200.0, 10300.0],
        )

        dummy_classifier = MagicMock()
        dummy_classifier.predict.return_value = (["fitness", "food"], [0.92, 0.88])

        models_patch = {
            "engagement":  dummy_engagement,
            "bot":         dummy_bot,
            "forecaster":  dummy_forecaster,
            "classifier":  dummy_classifier,
        }

        with patch("services.ml.app.main._models", models_patch):
            from services.ml.app.main import app
            self.client = TestClient(app, raise_server_exceptions=True)

    def test_health(self):
        resp = self.client.get("/health")
        assert resp.status_code == 200
        assert resp.json()["status"] == "ok"

    def test_predict_engagement(self):
        payload = {"profiles": [
            {"username": "a", "follower_count": 10000, "following_count": 500, "posts_count": 50},
            {"username": "b", "follower_count": 500,   "following_count": 300, "posts_count": 10},
        ]}
        resp = self.client.post("/predict/engagement", json=payload)
        assert resp.status_code == 200
        assert len(resp.json()["predictions"]) == 2

    def test_predict_bot(self):
        payload = {"profiles": [
            {"username": "a", "follower_count": 10000, "following_count": 500, "posts_count": 50},
            {"username": "b", "follower_count": 1000000, "following_count": 500, "posts_count": 2},
        ]}
        resp = self.client.post("/predict/bot", json=payload)
        assert resp.status_code == 200
        data = resp.json()
        assert len(data["bot_probabilities"]) == 2
        assert all(r in {"low", "medium", "high"} for r in data["risk_labels"])

    def test_predict_growth(self):
        history = [{"date": f"2024-01-{i+1:02d}", "follower_count": 1000 + i * 50} for i in range(10)]
        payload = {"username": "testuser", "horizon": 30, "history": history}
        resp = self.client.post("/predict/growth", json=payload)
        assert resp.status_code == 200
        data = resp.json()
        assert len(data["dates"])       == 2
        assert len(data["predicted"])   == 2
        assert len(data["lower_bound"]) == 2

    def test_predict_growth_too_short(self):
        history = [{"date": "2024-01-01", "follower_count": 1000}]
        resp    = self.client.post("/predict/growth", json={"username": "x", "horizon": 30, "history": history})
        assert resp.status_code == 422

    def test_predict_niche(self):
        payload = {"profiles": [
            {"username": "fitguy", "bio": "workout gym athlete fitness", "captions": "leg day"},
            {"username": "foodie", "bio": "chef cooking recipe", "captions": "delicious meal"},
        ]}
        resp = self.client.post("/predict/niche", json=payload)
        assert resp.status_code == 200
        data = resp.json()
        assert len(data["niches"])      == 2
        assert len(data["confidences"]) == 2
