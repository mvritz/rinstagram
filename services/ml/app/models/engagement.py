"""
Engagement Rate Predictor — Feed-Forward Neural Network (PyTorch)

Architecture:
    Input (5) → Linear(256) → BatchNorm → ReLU → Dropout(0.3)
              → Linear(128) → BatchNorm → ReLU → Dropout(0.3)
              → Linear(64)  → BatchNorm → ReLU
              → Linear(1)   → Sigmoid

Features (5):
    log1p(follower_count), log1p(following_count), log1p(posts_count),
    follower_following_ratio (clipped), log1p(avg_likes) if available else 0
"""

from __future__ import annotations

import logging
import math
from pathlib import Path
from typing import List

import torch
import torch.nn as nn

logger = logging.getLogger(__name__)

INPUT_DIM = 5


class EngagementMLP(nn.Module):
    def __init__(self, input_dim: int = INPUT_DIM) -> None:
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(input_dim, 256),
            nn.BatchNorm1d(256),
            nn.ReLU(),
            nn.Dropout(0.3),
            nn.Linear(256, 128),
            nn.BatchNorm1d(128),
            nn.ReLU(),
            nn.Dropout(0.3),
            nn.Linear(128, 64),
            nn.BatchNorm1d(64),
            nn.ReLU(),
            nn.Linear(64, 1),
            nn.Sigmoid(),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.net(x).squeeze(-1)


def _extract_features(profiles: list) -> torch.Tensor:
    rows = []
    for p in profiles:
        fc  = max(float(p.follower_count),  1)
        fwc = max(float(p.following_count), 1)
        pc  = max(float(p.posts_count),     1)
        al  = float(p.avg_likes) if p.avg_likes is not None else 0.0

        rows.append([
            math.log1p(fc),
            math.log1p(fwc),
            math.log1p(pc),
            min(fc / fwc, 1000.0) / 1000.0,
            math.log1p(al),
        ])
    return torch.tensor(rows, dtype=torch.float32)


class EngagementPredictor:
    """Inference wrapper around the trained MLP."""

    def __init__(self, model: EngagementMLP, device: str = "cpu") -> None:
        self.model  = model.to(device).eval()
        self.device = device

    def predict(self, profiles: list) -> List[float]:
        x = _extract_features(profiles).to(self.device)
        with torch.no_grad():
            preds = self.model(x)
        return preds.cpu().tolist()


def load_engagement_model(weights_path: Path, device: str = "cpu") -> EngagementPredictor:
    model = EngagementMLP()
    if weights_path.exists():
        try:
            model.load_state_dict(torch.load(weights_path, map_location=device, weights_only=True))
            logger.info("Loaded engagement model weights from %s", weights_path)
        except Exception as exc:
            logger.warning("Could not load engagement weights: %s — training fresh model.", exc)
            model = _train_fresh_model(model, device)
    else:
        logger.info("No engagement weights found — training with synthetic data.")
        model = _train_fresh_model(model, device)
        torch.save(model.state_dict(), weights_path)

    return EngagementPredictor(model, device)


def _train_fresh_model(model: EngagementMLP, device: str) -> EngagementMLP:
    """Quick synthetic training so the service starts without pre-trained weights."""
    try:
        from ...training.generate_synthetic_data import generate_engagement_data  # noqa: PLC0415
    except ImportError:
        from training.generate_synthetic_data import generate_engagement_data  # noqa: PLC0415

    X, y = generate_engagement_data(n=8000)
    X    = torch.tensor(X, dtype=torch.float32).to(device)
    y    = torch.tensor(y, dtype=torch.float32).to(device)

    model   = model.to(device).train()
    optim   = torch.optim.Adam(model.parameters(), lr=1e-3, weight_decay=1e-4)
    loss_fn = nn.MSELoss()

    dataset  = torch.utils.data.TensorDataset(X, y)
    loader   = torch.utils.data.DataLoader(dataset, batch_size=256, shuffle=True)

    for epoch in range(40):
        for xb, yb in loader:
            optim.zero_grad()
            loss = loss_fn(model(xb), yb)
            loss.backward()
            optim.step()

        if (epoch + 1) % 10 == 0:
            logger.info("Engagement training epoch %d/40", epoch + 1)

    return model.eval()
