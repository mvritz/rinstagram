"""
Content Niche Classifier — DistilBERT Fine-tuned (HuggingFace Transformers)

Architecture:
    DistilBERT (distilbert-base-uncased) — pre-trained encoder
        → CLS token hidden state (768-dim)
        → Dropout(0.3)
        → Linear(768 → 256)
        → GELU
        → Linear(256 → 9)
        → Softmax

Classes (9):
    fitness, food, travel, fashion, tech, lifestyle, art, sports, other

Training:
    The classification head is fine-tuned on synthetic labelled text constructed
    from keyword patterns characteristic of each niche. The DistilBERT backbone
    uses the pre-trained weights from HuggingFace and is NOT fine-tuned during
    the bootstrap training to keep start-up time reasonable.

    For production quality, replace synthetic data with a real labelled dataset
    (e.g. the public Instagram influencer dataset on Kaggle) and run
    training/train_classifier.py with --full-finetune.
"""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import List, Tuple

import torch
import torch.nn as nn

logger = logging.getLogger(__name__)

NICHE_LABELS = ["fitness", "food", "travel", "fashion", "tech", "lifestyle", "art", "sports", "other"]


class NicheClassificationHead(nn.Module):
    def __init__(self, hidden_size: int = 768, num_classes: int = 9) -> None:
        super().__init__()
        self.classifier = nn.Sequential(
            nn.Dropout(0.3),
            nn.Linear(hidden_size, 256),
            nn.GELU(),
            nn.Linear(256, num_classes),
        )

    def forward(self, cls_output: torch.Tensor) -> torch.Tensor:
        return self.classifier(cls_output)


class NicheClassifierModel(nn.Module):
    def __init__(self, distilbert, head: NicheClassificationHead) -> None:
        super().__init__()
        self.distilbert = distilbert
        self.head       = head

    def forward(self, input_ids: torch.Tensor, attention_mask: torch.Tensor) -> torch.Tensor:
        outputs = self.distilbert(input_ids=input_ids, attention_mask=attention_mask)
        cls     = outputs.last_hidden_state[:, 0, :]
        return self.head(cls)


class NicheClassifier:
    """DistilBERT-based niche classifier."""

    def __init__(self, model: NicheClassifierModel, tokenizer, labels: List[str], device: str = "cpu") -> None:
        self.model     = model.to(device).eval()
        self.tokenizer = tokenizer
        self.labels    = labels
        self.device    = device

    def predict(self, profiles: list) -> Tuple[List[str], List[float]]:
        texts = [
            f"{p.bio} {p.captions}".strip() or p.username
            for p in profiles
        ]

        encoding = self.tokenizer(
            texts,
            padding        = True,
            truncation     = True,
            max_length     = 128,
            return_tensors = "pt",
        )
        input_ids      = encoding["input_ids"].to(self.device)
        attention_mask = encoding["attention_mask"].to(self.device)

        with torch.no_grad():
            logits  = self.model(input_ids, attention_mask)
            probs   = torch.softmax(logits, dim=-1)
            top_cls = probs.argmax(dim=-1).cpu().tolist()
            top_conf = probs.max(dim=-1).values.cpu().tolist()

        niches      = [self.labels[i] for i in top_cls]
        confidences = [round(float(c), 4) for c in top_conf]
        return niches, confidences


def load_classifier_model(weights_path: Path, device: str = "cpu") -> NicheClassifier:
    try:
        from transformers import DistilBertModel, DistilBertTokenizerFast
    except ImportError:
        logger.error("transformers package is not installed. Falling back to keyword classifier.")
        return _keyword_fallback_classifier()

    tokenizer = DistilBertTokenizerFast.from_pretrained("distilbert-base-uncased")
    bert      = DistilBertModel.from_pretrained("distilbert-base-uncased")
    head      = NicheClassificationHead(num_classes=len(NICHE_LABELS))
    model     = NicheClassifierModel(bert, head)

    if weights_path.exists():
        try:
            state = torch.load(weights_path, map_location=device, weights_only=True)
            model.head.load_state_dict(state)
            logger.info("Loaded niche classifier head weights from %s", weights_path)
        except Exception as exc:
            logger.warning("Could not load classifier weights: %s — training fresh head.", exc)
            model = _train_classification_head(model, tokenizer, device)
    else:
        logger.info("No classifier weights found — training classification head.")
        model = _train_classification_head(model, tokenizer, device)
        torch.save(model.head.state_dict(), weights_path)

    return NicheClassifier(model, tokenizer, NICHE_LABELS, device)


def _train_classification_head(model: NicheClassifierModel, tokenizer, device: str) -> NicheClassifierModel:
    try:
        from ...training.generate_synthetic_data import generate_niche_data  # noqa: PLC0415
    except ImportError:
        from training.generate_synthetic_data import generate_niche_data  # noqa: PLC0415

    texts, labels = generate_niche_data(n_per_class=200)
    encodings     = tokenizer(texts, padding=True, truncation=True, max_length=64, return_tensors="pt")
    label_tensor  = torch.tensor(labels, dtype=torch.long)

    ds     = torch.utils.data.TensorDataset(encodings["input_ids"], encodings["attention_mask"], label_tensor)
    loader = torch.utils.data.DataLoader(ds, batch_size=32, shuffle=True)

    model  = model.to(device).train()

    for param in model.distilbert.parameters():
        param.requires_grad = False

    optim   = torch.optim.Adam(model.head.parameters(), lr=2e-4)
    loss_fn = nn.CrossEntropyLoss()

    for epoch in range(15):
        for ids, mask, ys in loader:
            ids, mask, ys = ids.to(device), mask.to(device), ys.to(device)
            optim.zero_grad()
            loss = loss_fn(model(ids, mask), ys)
            loss.backward()
            optim.step()
        if (epoch + 1) % 5 == 0:
            logger.info("Classifier epoch %d/15", epoch + 1)

    return model.eval()


class _KeywordFallbackClassifier:
    """Keyword-based fallback when transformers is not available."""

    KEYWORDS = {
        "fitness":   ["gym", "workout", "fit", "muscle", "training", "health", "athlete"],
        "food":      ["recipe", "food", "cooking", "eat", "restaurant", "chef", "yummy"],
        "travel":    ["travel", "explore", "adventure", "trip", "wanderlust", "vacation"],
        "fashion":   ["fashion", "style", "outfit", "wear", "clothes", "ootd", "model"],
        "tech":      ["tech", "code", "software", "developer", "programming", "ai", "data"],
        "lifestyle": ["life", "daily", "morning", "routine", "wellness", "mindfulness"],
        "art":       ["art", "design", "creative", "draw", "paint", "photography", "visual"],
        "sports":    ["sport", "football", "basketball", "soccer", "player", "game", "score"],
    }

    def predict(self, profiles) -> Tuple[List[str], List[float]]:
        niches, confs = [], []
        for p in profiles:
            text   = f"{p.bio} {p.captions}".lower()
            scores = {niche: sum(kw in text for kw in kws) for niche, kws in self.KEYWORDS.items()}
            best   = max(scores, key=scores.get)
            total  = sum(scores.values())
            conf   = (scores[best] / total) if total > 0 else 1.0 / 9
            niches.append(best if scores[best] > 0 else "other")
            confs.append(round(min(conf, 1.0), 4))
        return niches, confs


def _keyword_fallback_classifier():
    class _Wrapper:
        def __init__(self):
            self._inner = _KeywordFallbackClassifier()
        def predict(self, profiles):
            return self._inner.predict(profiles)
    return _Wrapper()
