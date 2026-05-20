"""Service-wide configuration."""

import os
from pathlib import Path

BASE_DIR    = Path(__file__).resolve().parent.parent
WEIGHTS_DIR = BASE_DIR / "weights"
WEIGHTS_DIR.mkdir(exist_ok=True)

ENGAGEMENT_WEIGHTS  = WEIGHTS_DIR / "engagement_mlp.pt"
BOT_MLP_WEIGHTS     = WEIGHTS_DIR / "bot_mlp.pt"
BOT_GBM_WEIGHTS     = WEIGHTS_DIR / "bot_lgbm.txt"
FORECASTER_WEIGHTS  = WEIGHTS_DIR / "forecaster_lstm.pt"
CLASSIFIER_WEIGHTS  = WEIGHTS_DIR / "niche_classifier.pt"
CLASSIFIER_LABELS   = WEIGHTS_DIR / "niche_labels.json"

NICHE_LABELS = ["fitness", "food", "travel", "fashion", "tech", "lifestyle", "art", "sports", "other"]

DEVICE = os.getenv("TORCH_DEVICE", "cpu")
