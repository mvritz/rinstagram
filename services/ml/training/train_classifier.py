"""
Train the DistilBERT niche classification head and save weights.

Usage:
    python -m services.ml.training.train_classifier [--epochs N] [--full-finetune]

By default only the classification head is trained (backbone frozen).
Pass --full-finetune to also update the DistilBERT encoder weights (slower,
better accuracy, requires GPU).
"""

import argparse
import logging
import sys
from pathlib import Path

import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset, random_split

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from services.ml.app.config import CLASSIFIER_WEIGHTS, DEVICE
from services.ml.app.models.classifier import NICHE_LABELS, NicheClassificationHead, NicheClassifierModel
from services.ml.training.generate_synthetic_data import generate_niche_data

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)


def train(epochs: int = 20, n_per_class: int = 500, device: str = DEVICE, full_finetune: bool = False) -> None:
    try:
        from transformers import DistilBertModel, DistilBertTokenizerFast
    except ImportError:
        logger.error("transformers is not installed. Run: pip install transformers")
        sys.exit(1)

    logger.info("Loading DistilBERT tokenizer and model ...")
    tokenizer = DistilBertTokenizerFast.from_pretrained("distilbert-base-uncased")
    bert      = DistilBertModel.from_pretrained("distilbert-base-uncased")
    head      = NicheClassificationHead(num_classes=len(NICHE_LABELS))
    model     = NicheClassifierModel(bert, head).to(device)

    if not full_finetune:
        for param in model.distilbert.parameters():
            param.requires_grad = False
        logger.info("Backbone frozen — training classification head only.")
    else:
        logger.info("Full fine-tuning enabled — training all parameters.")

    logger.info("Generating %d synthetic text samples per class (%d total) ...",
                n_per_class, n_per_class * len(NICHE_LABELS))
    texts, labels = generate_niche_data(n_per_class=n_per_class)

    encodings    = tokenizer(texts, padding=True, truncation=True, max_length=64, return_tensors="pt")
    label_tensor = torch.tensor(labels, dtype=torch.long)

    ds               = TensorDataset(encodings["input_ids"], encodings["attention_mask"], label_tensor)
    n_val            = int(0.15 * len(ds))
    train_ds, val_ds = random_split(ds, [len(ds) - n_val, n_val])
    train_ldr        = DataLoader(train_ds, batch_size=32, shuffle=True)
    val_ldr          = DataLoader(val_ds,   batch_size=64)

    params_to_train = model.parameters() if full_finetune else model.head.parameters()
    optim   = torch.optim.AdamW(params_to_train, lr=2e-4 if not full_finetune else 2e-5, weight_decay=0.01)
    loss_fn = nn.CrossEntropyLoss()

    best_val  = float("inf")
    best_state = None

    for epoch in range(1, epochs + 1):
        model.train()
        train_loss = 0.0
        for ids, mask, ys in train_ldr:
            ids, mask, ys = ids.to(device), mask.to(device), ys.to(device)
            optim.zero_grad()
            loss = loss_fn(model(ids, mask), ys)
            loss.backward()
            nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            optim.step()
            train_loss += loss.item() * len(ys)
        train_loss /= len(train_ds)

        model.eval()
        correct, total, val_loss = 0, 0, 0.0
        with torch.no_grad():
            for ids, mask, ys in val_ldr:
                ids, mask, ys = ids.to(device), mask.to(device), ys.to(device)
                logits   = model(ids, mask)
                val_loss += loss_fn(logits, ys).item() * len(ys)
                correct  += (logits.argmax(-1) == ys).sum().item()
                total    += len(ys)
        val_loss /= len(val_ds)
        acc = correct / total

        logger.info("Epoch %2d/%d | train_loss=%.4f | val_loss=%.4f | val_acc=%.3f",
                    epoch, epochs, train_loss, val_loss, acc)

        if val_loss < best_val:
            best_val   = val_loss
            best_state = {k: v.clone() for k, v in model.head.state_dict().items()}

    model.head.load_state_dict(best_state)
    torch.save(model.head.state_dict(), CLASSIFIER_WEIGHTS)
    logger.info("Saved classifier head to %s (best val loss=%.4f)", CLASSIFIER_WEIGHTS, best_val)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--epochs",        type=int,  default=20)
    parser.add_argument("--n-per-class",   type=int,  default=500)
    parser.add_argument("--device",        type=str,  default=DEVICE)
    parser.add_argument("--full-finetune", action="store_true")
    args = parser.parse_args()
    train(epochs=args.epochs, n_per_class=args.n_per_class, device=args.device, full_finetune=args.full_finetune)
