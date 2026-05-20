"""
Train the LSTM growth forecaster and save weights.

Usage:
    python -m services.ml.training.train_forecaster [--epochs N] [--n-samples N]
"""

import argparse
import logging
import sys
from pathlib import Path

import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset, random_split

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from services.ml.app.config import FORECASTER_WEIGHTS, DEVICE
from services.ml.app.models.forecaster import LSTMForecaster, SEQ_LEN
from services.ml.training.generate_synthetic_data import generate_growth_data

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

HORIZON = 90


def train(epochs: int = 100, n_samples: int = 10000, device: str = DEVICE) -> None:
    logger.info("Generating %d synthetic growth sequences ...", n_samples)
    X, y = generate_growth_data(n=n_samples, seq_len=SEQ_LEN, horizon=HORIZON)
    X_t  = torch.tensor(X, dtype=torch.float32)
    y_t  = torch.tensor(y, dtype=torch.float32)

    ds               = TensorDataset(X_t, y_t)
    n_val            = int(0.1 * len(ds))
    train_ds, val_ds = random_split(ds, [len(ds) - n_val, n_val])
    train_ldr        = DataLoader(train_ds, batch_size=64, shuffle=True)
    val_ldr          = DataLoader(val_ds,   batch_size=128)

    model   = LSTMForecaster(hidden=128, n_layers=2, horizon=HORIZON).to(device)
    optim   = torch.optim.Adam(model.parameters(), lr=1e-3)
    sched   = torch.optim.lr_scheduler.ReduceLROnPlateau(optim, patience=5, factor=0.5, verbose=False)
    loss_fn = nn.MSELoss()

    best_val  = float("inf")
    best_state = None

    for epoch in range(1, epochs + 1):
        model.train()
        train_loss = 0.0
        for xb, yb in train_ldr:
            xb, yb = xb.to(device), yb.to(device)
            optim.zero_grad()
            loss = loss_fn(model(xb), yb)
            loss.backward()
            nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            optim.step()
            train_loss += loss.item() * len(xb)
        train_loss /= len(train_ds)

        model.eval()
        val_loss = 0.0
        with torch.no_grad():
            for xb, yb in val_ldr:
                xb, yb = xb.to(device), yb.to(device)
                val_loss += loss_fn(model(xb), yb).item() * len(xb)
        val_loss /= len(val_ds)
        sched.step(val_loss)

        if epoch % 10 == 0 or epoch == epochs:
            logger.info("Epoch %3d/%d | train=%.5f | val=%.5f | lr=%.6f",
                        epoch, epochs, train_loss, val_loss,
                        optim.param_groups[0]["lr"])

        if val_loss < best_val:
            best_val   = val_loss
            best_state = {k: v.clone() for k, v in model.state_dict().items()}

    model.load_state_dict(best_state)
    torch.save(model.state_dict(), FORECASTER_WEIGHTS)
    logger.info("Saved LSTM forecaster to %s (best val loss=%.5f)", FORECASTER_WEIGHTS, best_val)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--epochs",    type=int, default=100)
    parser.add_argument("--n-samples", type=int, default=10000)
    parser.add_argument("--device",    type=str, default=DEVICE)
    args = parser.parse_args()
    train(epochs=args.epochs, n_samples=args.n_samples, device=args.device)
