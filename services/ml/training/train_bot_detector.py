"""
Train the bot detector ensemble (LightGBM + MLP) and save weights.

Usage:
    python -m services.ml.training.train_bot_detector [--n-samples N] [--device cpu|cuda]
"""

import argparse
import logging
import sys
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
from sklearn.metrics import roc_auc_score, classification_report
from torch.utils.data import DataLoader, TensorDataset

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

import lightgbm as lgb

from services.ml.app.config import BOT_MLP_WEIGHTS, BOT_GBM_WEIGHTS, DEVICE
from services.ml.app.models.bot_detector import BotMLP
from services.ml.training.generate_synthetic_data import generate_bot_data

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)


def train(n_samples: int = 30000, device: str = DEVICE) -> None:
    logger.info("Generating %d synthetic bot/normal samples ...", n_samples)
    X, y = generate_bot_data(n=n_samples)

    split              = int(0.80 * len(X))
    X_train, X_test    = X[:split], X[split:]
    y_train, y_test    = y[:split], y[split:]

    # ── LightGBM ─────────────────────────────────────────────────────────────
    logger.info("Training LightGBM classifier ...")
    train_ds = lgb.Dataset(X_train, label=y_train)
    val_ds   = lgb.Dataset(X_test,  label=y_test, reference=train_ds)

    params = {
        "objective":        "binary",
        "metric":           "binary_logloss",
        "num_leaves":       63,
        "learning_rate":    0.05,
        "feature_fraction": 0.8,
        "bagging_fraction": 0.8,
        "bagging_freq":     5,
        "min_child_samples": 20,
        "verbose":          -1,
        "n_jobs":           -1,
    }
    gbm = lgb.train(
        params, train_ds, num_boost_round=400,
        valid_sets=[val_ds],
        callbacks=[lgb.early_stopping(30, verbose=False), lgb.log_evaluation(50)],
    )
    lgb_preds = gbm.predict(X_test)
    logger.info("LightGBM — AUC: %.4f", roc_auc_score(y_test, lgb_preds))
    gbm.save_model(str(BOT_GBM_WEIGHTS))
    logger.info("Saved LightGBM model to %s", BOT_GBM_WEIGHTS)

    # ── MLP ──────────────────────────────────────────────────────────────────
    logger.info("Training MLP classifier ...")
    X_t = torch.tensor(X_train, dtype=torch.float32)
    y_t = torch.tensor(y_train, dtype=torch.float32)
    ds  = TensorDataset(X_t, y_t)
    ldr = DataLoader(ds, batch_size=256, shuffle=True)

    mlp     = BotMLP().to(device).train()
    optim   = torch.optim.Adam(mlp.parameters(), lr=5e-4, weight_decay=1e-4)
    loss_fn = nn.BCELoss()

    for epoch in range(50):
        for xb, yb in ldr:
            xb, yb = xb.to(device), yb.to(device)
            optim.zero_grad()
            loss_fn(mlp(xb), yb).backward()
            optim.step()
        if (epoch + 1) % 10 == 0:
            logger.info("MLP epoch %d/50", epoch + 1)

    mlp.eval()
    with torch.no_grad():
        X_test_t  = torch.tensor(X_test, dtype=torch.float32).to(device)
        mlp_preds = mlp(X_test_t).cpu().numpy()

    ensemble_preds = (mlp_preds + lgb_preds) / 2.0
    logger.info("Ensemble — AUC: %.4f", roc_auc_score(y_test, ensemble_preds))
    logger.info("\n%s", classification_report(y_test, (ensemble_preds >= 0.5).astype(int),
                                              target_names=["normal", "bot"]))

    torch.save(mlp.state_dict(), BOT_MLP_WEIGHTS)
    logger.info("Saved MLP weights to %s", BOT_MLP_WEIGHTS)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--n-samples", type=int, default=30000)
    parser.add_argument("--device",    type=str, default=DEVICE)
    args = parser.parse_args()
    train(n_samples=args.n_samples, device=args.device)
