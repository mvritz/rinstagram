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

from services.ml.app.encryption import encrypt_instagram_password
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


# ── Encryption ───────────────────────────────────────────────────────────────

class TestEncryption:
    def _keypair(self):
        from nacl.public import PrivateKey
        priv = PrivateKey.generate()
        return priv, priv.public_key.encode().hex()

    def test_returns_base64_string(self):
        import base64
        _, pub_hex = self._keypair()
        result = encrypt_instagram_password("1", pub_hex, "password")
        assert isinstance(result, str)
        assert len(base64.b64decode(result)) > 0

    def test_unique_per_call(self):
        _, pub_hex = self._keypair()
        r1 = encrypt_instagram_password("1", pub_hex, "pw")
        r2 = encrypt_instagram_password("1", pub_hex, "pw")
        assert r1 != r2, "Each call must use a fresh AES key"

    def test_version_byte(self):
        import base64
        _, pub_hex = self._keypair()
        raw = base64.b64decode(encrypt_instagram_password("1", pub_hex, "test"))
        assert raw[0] == 1

    def test_key_id_byte(self):
        import base64
        _, pub_hex = self._keypair()
        raw = base64.b64decode(encrypt_instagram_password("55", pub_hex, "test"))
        assert raw[1] == 55

    def test_invalid_pub_key_raises(self):
        with pytest.raises(Exception):
            encrypt_instagram_password("1", "not_hex", "pw")


# ── FastAPI endpoints ─────────────────────────────────────────────────────────
#
# All endpoint tests receive the `mock_app_client` fixture defined in conftest.py.
# That fixture patches the four model loader functions so the FastAPI lifespan
# startup uses MagicMock objects — no PyTorch training or HuggingFace downloads
# happen during these tests.

def test_health(mock_app_client):
    resp = mock_app_client.get("/health")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"
    assert resp.json()["service"] == "rinstagram"


def test_index(mock_app_client):
    resp = mock_app_client.get("/")
    assert resp.status_code == 200
    assert "rinstagram" in resp.json()["project"]


def test_encrypt_endpoint(mock_app_client):
    from nacl.public import PrivateKey
    pub_hex = PrivateKey.generate().public_key.encode().hex()
    resp = mock_app_client.post("/encrypt", json={"key_id": "1", "pub_key": pub_hex, "password": "secret"})
    assert resp.status_code == 200
    assert "encrypted" in resp.json()
    assert len(resp.json()["encrypted"]) > 10


def test_encrypt_empty_password_rejected(mock_app_client):
    from nacl.public import PrivateKey
    pub_hex = PrivateKey.generate().public_key.encode().hex()
    resp = mock_app_client.post("/encrypt", json={"key_id": "1", "pub_key": pub_hex, "password": ""})
    assert resp.status_code == 422


def test_predict_engagement(mock_app_client):
    payload = {"profiles": [
        {"username": "a", "follower_count": 10000, "following_count": 500, "posts_count": 50},
        {"username": "b", "follower_count": 500,   "following_count": 300, "posts_count": 10},
    ]}
    resp = mock_app_client.post("/predict/engagement", json=payload)
    assert resp.status_code == 200
    assert len(resp.json()["predictions"]) == 2


def test_predict_bot(mock_app_client):
    payload = {"profiles": [
        {"username": "a", "follower_count": 10000,   "following_count": 500, "posts_count": 50},
        {"username": "b", "follower_count": 1000000, "following_count": 500, "posts_count": 2},
    ]}
    resp = mock_app_client.post("/predict/bot", json=payload)
    assert resp.status_code == 200
    data = resp.json()
    assert len(data["bot_probabilities"]) == 2
    assert all(r in {"low", "medium", "high"} for r in data["risk_labels"])


def test_predict_growth(mock_app_client):
    history = [{"date": f"2024-01-{i+1:02d}", "follower_count": 1000 + i * 50} for i in range(10)]
    payload = {"username": "testuser", "horizon": 30, "history": history}
    resp = mock_app_client.post("/predict/growth", json=payload)
    assert resp.status_code == 200
    data = resp.json()
    assert len(data["dates"])       == 2
    assert len(data["predicted"])   == 2
    assert len(data["lower_bound"]) == 2


def test_predict_growth_too_short(mock_app_client):
    history = [{"date": "2024-01-01", "follower_count": 1000}]
    resp = mock_app_client.post("/predict/growth", json={"username": "x", "horizon": 30, "history": history})
    assert resp.status_code == 422


def test_predict_niche(mock_app_client):
    payload = {"profiles": [
        {"username": "fitguy", "bio": "workout gym", "captions": "leg day"},
        {"username": "foodie", "bio": "chef recipe", "captions": "delicious meal"},
    ]}
    resp = mock_app_client.post("/predict/niche", json=payload)
    assert resp.status_code == 200
    data = resp.json()
    assert len(data["niches"])      == 2
    assert len(data["confidences"]) == 2
