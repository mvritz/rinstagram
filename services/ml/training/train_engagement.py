"""
Train the engagement rate predictor and save weights to services/ml/weights/.

Usage:
    python -m services.ml.training.train_engagement [--epochs N] [--n-samples N] [--device cpu|cuda]
"""

import argparse
import logging
import sys
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset, random_split

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from services.ml.app.config import ENGAGEMENT_WEIGHTS, DEVICE
from services.ml.app.models.engagement import EngagementMLP, INPUT_DIM
from services.ml.training.generate_synthetic_data import generate_engagement_data

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)


def train(epochs: int = 80, n_samples: int = 20000, device: str = DEVICE, lr: float = 1e-3) -> None:
    logger.info("Generating %d synthetic samples ...", n_samples)
    X, y = generate_engagement_data(n=n_samples)
    X_t  = torch.tensor(X, dtype=torch.float32)
    y_t  = torch.tensor(y, dtype=torch.float32)

    ds              = TensorDataset(X_t, y_t)
    n_val           = int(0.15 * len(ds))
    train_ds, val_ds = random_split(ds, [len(ds) - n_val, n_val])
    train_loader    = DataLoader(train_ds, batch_size=256, shuffle=True)
    val_loader      = DataLoader(val_ds,   batch_size=512)

    model   = EngagementMLP(input_dim=INPUT_DIM).to(device)
    optim   = torch.optim.Adam(model.parameters(), lr=lr, weight_decay=1e-4)
    sched   = torch.optim.lr_scheduler.CosineAnnealingLR(optim, T_max=epochs)
    loss_fn = nn.MSELoss()

    best_val  = float("inf")
    best_state = None

    for epoch in range(1, epochs + 1):
        model.train()
        train_loss = 0.0
        for xb, yb in train_loader:
            xb, yb = xb.to(device), yb.to(device)
            optim.zero_grad()
            loss = loss_fn(model(xb), yb)
            loss.backward()
            optim.step()
            train_loss += loss.item() * len(xb)
        train_loss /= len(train_ds)
        sched.step()

        if epoch % 10 == 0 or epoch == epochs:
            model.eval()
            val_loss = 0.0
            with torch.no_grad():
                for xb, yb in val_loader:
                    xb, yb = xb.to(device), yb.to(device)
                    val_loss += loss_fn(model(xb), yb).item() * len(xb)
            val_loss /= len(val_ds)
            mae = val_loss ** 0.5
            logger.info("Epoch %3d/%d | train_loss=%.5f | val_rmse=%.5f", epoch, epochs, train_loss, mae)

            if val_loss < best_val:
                best_val   = val_loss
                best_state = {k: v.clone() for k, v in model.state_dict().items()}

    model.load_state_dict(best_state)
    torch.save(model.state_dict(), ENGAGEMENT_WEIGHTS)
    logger.info("Saved engagement model to %s  (best val RMSE=%.5f)", ENGAGEMENT_WEIGHTS, best_val ** 0.5)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--epochs",    type=int,   default=80)
    parser.add_argument("--n-samples", type=int,   default=20000)
    parser.add_argument("--device",    type=str,   default=DEVICE)
    parser.add_argument("--lr",        type=float, default=1e-3)
    args = parser.parse_args()

    train(epochs=args.epochs, n_samples=args.n_samples, device=args.device, lr=args.lr)
