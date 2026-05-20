"""
Bot / Fake Account Detector — Soft-Vote Ensemble (LightGBM + MLP)

Features (6):
    log1p(follower_count), log1p(following_count), log1p(posts_count),
    follower_following_ratio (clipped), engagement_deviation, engagement_rate

Architecture:
    - LightGBM binary classifier (gradient-boosted trees)
    - Two-layer MLP (128 → 64 → 1) with Dropout
    - Final prediction = average of both softmax/sigmoid outputs

Training signal:
    Semi-supervised using a synthetic dataset:
    - "Normal" profiles: realistic engagement rates that correlate with follower count
    - "Bot" profiles: anomalously low engagement with high follower counts,
      extreme or random follower/following ratios
"""

from __future__ import annotations

import logging
import math
from pathlib import Path
from typing import List, Tuple

import numpy as np
import torch
import torch.nn as nn

logger = logging.getLogger(__name__)


class BotMLP(nn.Module):
    def __init__(self, input_dim: int = 6) -> None:
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(input_dim, 128),
            nn.ReLU(),
            nn.Dropout(0.3),
            nn.Linear(128, 64),
            nn.ReLU(),
            nn.Dropout(0.2),
            nn.Linear(64, 1),
            nn.Sigmoid(),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.net(x).squeeze(-1)


def _extract_features(profiles: list) -> np.ndarray:
    rows = []
    for p in profiles:
        fc  = max(float(p.follower_count),  1)
        fwc = max(float(p.following_count), 1)
        pc  = max(float(p.posts_count),     1)

        er = float(p.engagement_rate) if p.engagement_rate is not None else (
            (float(p.avg_likes or 0) + float(p.avg_comments or 0)) / fc
        )
        al = float(p.avg_likes) if p.avg_likes is not None else 0.0

        expected_er   = max(0.001, 0.15 * (fc ** -0.3))
        er_deviation  = (expected_er - er) / (expected_er + 1e-9)

        rows.append([
            math.log1p(fc),
            math.log1p(fwc),
            math.log1p(pc),
            min(fc / fwc, 1000.0) / 1000.0,
            float(np.clip(er_deviation, -5, 5)),
            float(np.clip(er, 0, 1)),
        ])
    return np.array(rows, dtype=np.float32)


class BotDetector:
    """Soft-vote ensemble of LightGBM and MLP."""

    def __init__(self, mlp: BotMLP, lgbm_model, device: str = "cpu") -> None:
        self.mlp        = mlp.to(device).eval()
        self.lgbm       = lgbm_model
        self.device     = device

    def predict(self, profiles: list) -> Tuple[List[float], List[str]]:
        X_np = _extract_features(profiles)
        X_t  = torch.tensor(X_np, dtype=torch.float32).to(self.device)

        with torch.no_grad():
            mlp_probs = self.mlp(X_t).cpu().numpy()

        lgbm_probs = self.lgbm.predict(X_np)

        ensemble_probs = (mlp_probs + lgbm_probs) / 2.0

        labels = [
            "high"   if p >= 0.7 else
            "medium" if p >= 0.4 else
            "low"
            for p in ensemble_probs
        ]
        return ensemble_probs.tolist(), labels


def load_bot_model(mlp_path: Path, gbm_path: Path, device: str = "cpu") -> BotDetector:
    import lightgbm as lgb

    mlp   = BotMLP()
    lgbm  = None

    if mlp_path.exists() and gbm_path.exists():
        try:
            mlp.load_state_dict(torch.load(mlp_path, map_location=device, weights_only=True))
            lgbm = lgb.Booster(model_file=str(gbm_path))
            logger.info("Loaded bot detector weights.")
        except Exception as exc:
            logger.warning("Could not load bot weights: %s — training fresh model.", exc)
            mlp, lgbm = _train_fresh_model(device)
    else:
        logger.info("No bot detector weights found — training with synthetic data.")
        mlp, lgbm = _train_fresh_model(device)
        torch.save(mlp.state_dict(), mlp_path)
        lgbm.save_model(str(gbm_path))

    return BotDetector(mlp, lgbm, device)


def _train_fresh_model(device: str):
    import lightgbm as lgb
    try:
        from ...training.generate_synthetic_data import generate_bot_data  # noqa: PLC0415
    except ImportError:
        from training.generate_synthetic_data import generate_bot_data  # noqa: PLC0415

    X, y = generate_bot_data(n=10000)
    X    = X.astype(np.float32)

    split     = int(0.8 * len(X))
    X_train, X_val = X[:split], X[split:]
    y_train, y_val = y[:split], y[split:]

    train_ds = lgb.Dataset(X_train, label=y_train)
    val_ds   = lgb.Dataset(X_val,   label=y_val, reference=train_ds)

    params = {
        "objective":        "binary",
        "metric":           "binary_logloss",
        "num_leaves":       63,
        "learning_rate":    0.05,
        "feature_fraction": 0.8,
        "bagging_fraction": 0.8,
        "bagging_freq":     5,
        "verbose":          -1,
        "n_jobs":           -1,
    }
    lgbm_model = lgb.train(
        params, train_ds, num_boost_round=200,
        valid_sets=[val_ds],
        callbacks=[lgb.early_stopping(20, verbose=False), lgb.log_evaluation(-1)],
    )

    X_t  = torch.tensor(X_train, dtype=torch.float32).to(device)
    y_t  = torch.tensor(y_train, dtype=torch.float32).to(device)
    mlp  = BotMLP().to(device).train()
    opt  = torch.optim.Adam(mlp.parameters(), lr=5e-4, weight_decay=1e-4)
    loss = nn.BCELoss()
    ds   = torch.utils.data.TensorDataset(X_t, y_t)
    ldr  = torch.utils.data.DataLoader(ds, batch_size=256, shuffle=True)

    for epoch in range(30):
        for xb, yb in ldr:
            opt.zero_grad()
            loss(mlp(xb), yb).backward()
            opt.step()
        if (epoch + 1) % 10 == 0:
            logger.info("Bot MLP epoch %d/30", epoch + 1)

    return mlp.eval(), lgbm_model
