"""
Follower Growth Forecaster — 2-Layer LSTM with MC Dropout (PyTorch)

Architecture:
    Input sequence (normalized daily follower counts)
        → LSTM(hidden=128, layers=2, dropout=0.2)
        → Linear(128 → horizon)

Uncertainty estimation:
    Monte Carlo Dropout: keep dropout active at inference time, run N=50 forward
    passes, compute mean (prediction) and std (uncertainty → confidence interval).

Input:
    Time series of (date, follower_count) tuples from the SQLite snapshots table.
    Internally resampled to daily frequency (forward-filled) and min-max normalised.

Output:
    Per-step predictions + 90 % confidence bounds for the requested horizon.
"""

from __future__ import annotations

import logging
import math
from datetime import date, timedelta
from pathlib import Path
from typing import List, Tuple

import numpy as np
import torch
import torch.nn as nn

logger = logging.getLogger(__name__)

SEQ_LEN    = 30
HIDDEN     = 128
N_LAYERS   = 2
MC_SAMPLES = 50


class LSTMForecaster(nn.Module):
    def __init__(self, hidden: int = HIDDEN, n_layers: int = N_LAYERS, horizon: int = 90) -> None:
        super().__init__()
        self.hidden   = hidden
        self.n_layers = n_layers
        self.horizon  = horizon

        self.lstm   = nn.LSTM(
            input_size  = 1,
            hidden_size = hidden,
            num_layers  = n_layers,
            dropout     = 0.2,
            batch_first = True,
        )
        self.dropout = nn.Dropout(0.2)
        self.head    = nn.Linear(hidden, horizon)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        out, _ = self.lstm(x.unsqueeze(-1))
        last   = self.dropout(out[:, -1, :])
        return self.head(last)


def _preprocess_history(history: list, seq_len: int) -> Tuple[np.ndarray, float, float]:
    """Normalise and prepare input sequence."""
    dates  = [h.date for h in history]
    counts = np.array([h.follower_count for h in history], dtype=np.float64)

    mn, mx = counts.min(), counts.max()
    if mx == mn:
        normalised = np.zeros_like(counts)
    else:
        normalised = (counts - mn) / (mx - mn)

    if len(normalised) >= seq_len:
        seq = normalised[-seq_len:]
    else:
        pad = np.full(seq_len - len(normalised), normalised[0])
        seq = np.concatenate([pad, normalised])

    return seq.astype(np.float32), float(mn), float(mx)


def _generate_future_dates(last_date_str: str, horizon: int) -> List[str]:
    try:
        last = date.fromisoformat(last_date_str)
    except (ValueError, TypeError):
        last = date.today()
    return [(last + timedelta(days=i + 1)).isoformat() for i in range(horizon)]


class GrowthForecaster:
    """MC-Dropout LSTM inference wrapper."""

    def __init__(self, model: LSTMForecaster, device: str = "cpu") -> None:
        self.model  = model.to(device)
        self.device = device

    def predict(self, history: list, horizon: int) -> Tuple[List[str], List[float], List[float], List[float]]:
        seq, mn, mx = _preprocess_history(history, SEQ_LEN)
        x = torch.tensor(seq, dtype=torch.float32).unsqueeze(0).to(self.device)

        self.model.train()
        samples = []
        with torch.no_grad():
            for _ in range(MC_SAMPLES):
                raw = self.model(x).cpu().numpy()[0]
                denorm = raw * (mx - mn) + mn if mx != mn else np.full_like(raw, mn)
                samples.append(denorm[:horizon])

        samples   = np.array(samples)
        predicted = samples.mean(axis=0)
        std       = samples.std(axis=0)

        predicted = np.maximum(predicted, 0)
        lower     = np.maximum(predicted - 1.645 * std, 0)
        upper     = predicted + 1.645 * std

        last_date    = history[-1].date if history else date.today().isoformat()
        future_dates = _generate_future_dates(last_date, horizon)

        self.model.eval()
        return future_dates, predicted.tolist(), lower.tolist(), upper.tolist()


def load_forecaster_model(weights_path: Path, device: str = "cpu") -> GrowthForecaster:
    model = LSTMForecaster(horizon=90)
    if weights_path.exists():
        try:
            model.load_state_dict(torch.load(weights_path, map_location=device, weights_only=True))
            logger.info("Loaded forecaster weights from %s", weights_path)
        except Exception as exc:
            logger.warning("Could not load forecaster weights: %s — training fresh model.", exc)
            model = _train_fresh_model(model, device)
    else:
        logger.info("No forecaster weights found — training with synthetic data.")
        model = _train_fresh_model(model, device)
        torch.save(model.state_dict(), weights_path)

    return GrowthForecaster(model, device)


def _train_fresh_model(model: LSTMForecaster, device: str) -> LSTMForecaster:
    try:
        from ...training.generate_synthetic_data import generate_growth_data  # noqa: PLC0415
    except ImportError:
        from training.generate_synthetic_data import generate_growth_data  # noqa: PLC0415

    X, y = generate_growth_data(n=3000, seq_len=SEQ_LEN, horizon=90)
    X    = torch.tensor(X, dtype=torch.float32).to(device)
    y    = torch.tensor(y, dtype=torch.float32).to(device)

    model   = model.to(device).train()
    optim   = torch.optim.Adam(model.parameters(), lr=1e-3)
    loss_fn = nn.MSELoss()
    ds      = torch.utils.data.TensorDataset(X, y)
    loader  = torch.utils.data.DataLoader(ds, batch_size=64, shuffle=True)

    for epoch in range(50):
        for xb, yb in loader:
            optim.zero_grad()
            loss_fn(model(xb), yb).backward()
            nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            optim.step()
        if (epoch + 1) % 10 == 0:
            logger.info("Forecaster epoch %d/50", epoch + 1)

    return model.eval()
