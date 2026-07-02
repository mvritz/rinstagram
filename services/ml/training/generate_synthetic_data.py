"""
Synthetic data generators for all four rinstagram ML models.

All generators produce data that reflects realistic Instagram statistics:
- Engagement rates follow a power-law distribution (mega-influencers ~1–3 %,
  micro-influencers ~5–15 %)
- Bot accounts exhibit anomalously low engagement given their follower count
- Follower growth follows exponential or S-curve trajectories with noise
- Niche text uses characteristic keywords per content category
"""

from __future__ import annotations

import math
import random
from typing import List, Tuple

import numpy as np


# ── Engagement Predictor ────────────────────────────────────────────────────

def generate_engagement_data(n: int = 8000) -> Tuple[np.ndarray, np.ndarray]:
    """
    Returns (X, y) where:
        X : (n, 5)  feature matrix
        y : (n,)    engagement rate targets in [0, 0.3]
    """
    rng = np.random.default_rng(42)

    log_fc  = rng.uniform(3, 20, n)
    log_fwc = rng.uniform(2, 12, n)
    log_pc  = rng.uniform(1, 10, n)
    ff_ratio = np.clip(np.exp(log_fc - log_fwc) / 1000.0, 0, 1)

    base_er = 0.15 * np.exp(-0.3 * (log_fc - 3) / 17)
    noise   = rng.normal(0, 0.02, n)
    er      = np.clip(base_er + noise, 0.001, 0.5)

    log_avg_likes = log_fc + np.log1p(er) + rng.normal(0, 0.5, n)
    log_avg_likes = np.clip(log_avg_likes, 0, None)

    X = np.stack([log_fc, log_fwc, log_pc, ff_ratio, log_avg_likes], axis=1).astype(np.float32)
    y = er.astype(np.float32)
    return X, y


# ── Bot Detector ─────────────────────────────────────────────────────────────

def generate_bot_data(n: int = 10000) -> Tuple[np.ndarray, np.ndarray]:
    """
    Returns (X, y) where:
        X : (n, 6)  feature matrix
        y : (n,)    binary label  (0 = normal, 1 = bot)

    Bot characteristics:
    - High follower count, very low engagement (< 0.1 %)
    - Unusual follower/following ratio (very high or close to 1.0 for follow-farming)
    - Sparse or zero posting history
    """
    rng = np.random.default_rng(123)
    n_normal = int(n * 0.7)
    n_bot    = n - n_normal

    def make_normal(k):
        log_fc  = rng.uniform(4, 18, k)
        log_fwc = rng.uniform(2, 11, k)
        log_pc  = rng.uniform(2, 10, k)
        ff      = np.clip(np.exp(log_fc - log_fwc) / 1000.0, 0, 1)
        er      = np.clip(0.12 * np.exp(-0.28 * (log_fc - 4) / 14) + rng.normal(0, 0.015, k), 0.001, 0.5)
        expected_er  = np.maximum(0.001, 0.15 * (np.exp(log_fc) ** -0.3))
        er_deviation = np.clip((expected_er - er) / (expected_er + 1e-9), -5, 5)
        X = np.stack([log_fc, log_fwc, log_pc, ff, er_deviation, np.clip(er, 0, 1)], axis=1)
        y = np.zeros(k, dtype=np.float32)
        return X, y

    def make_bot(k):
        log_fc  = rng.uniform(8, 20, k)
        log_fwc = np.where(
            rng.random(k) < 0.5,
            rng.uniform(8, 20, k),
            rng.uniform(2,  5, k),
        )
        log_pc  = rng.uniform(0, 4, k)
        ff      = np.clip(np.exp(log_fc - log_fwc) / 1000.0, 0, 1)
        er      = rng.uniform(0, 0.002, k)
        expected_er  = np.maximum(0.001, 0.15 * (np.exp(log_fc) ** -0.3))
        er_deviation = np.clip((expected_er - er) / (expected_er + 1e-9), -5, 5)
        X = np.stack([log_fc, log_fwc, log_pc, ff, er_deviation, np.clip(er, 0, 1)], axis=1)
        y = np.ones(k, dtype=np.float32)
        return X, y

    X_n, y_n = make_normal(n_normal)
    X_b, y_b = make_bot(n_bot)

    X = np.vstack([X_n, X_b]).astype(np.float32)
    y = np.concatenate([y_n, y_b])

    perm = rng.permutation(len(X))
    return X[perm], y[perm]


# ── Growth Forecaster ─────────────────────────────────────────────────────────

def _growth_curve(n_steps: int, start: float, growth_rate: float, noise_std: float, rng) -> np.ndarray:
    """Exponential growth with Gaussian noise."""
    t    = np.arange(n_steps)
    base = start * np.exp(growth_rate * t / n_steps)
    noise = rng.normal(0, noise_std * base, n_steps)
    return np.maximum(base + noise, 1)


def generate_growth_data(
    n: int = 3000, seq_len: int = 30, horizon: int = 90
) -> Tuple[np.ndarray, np.ndarray]:
    """
    Returns (X, y) where:
        X : (n, seq_len)     normalised input sequences
        y : (n, horizon)     normalised future sequences
    """
    rng = np.random.default_rng(777)
    total = seq_len + horizon

    X_list, y_list = [], []

    for _ in range(n):
        start       = rng.uniform(1000, 5_000_000)
        growth_rate = rng.normal(0.5, 0.3)
        noise_std   = rng.uniform(0.01, 0.08)
        curve       = _growth_curve(total, start, growth_rate, noise_std, rng)

        mn, mx = curve.min(), curve.max()
        if mx == mn:
            norm = np.zeros(total)
        else:
            norm = (curve - mn) / (mx - mn)

        X_list.append(norm[:seq_len])
        y_list.append(norm[seq_len:])

    return np.array(X_list, dtype=np.float32), np.array(y_list, dtype=np.float32)


# ── Niche Classifier ──────────────────────────────────────────────────────────

_NICHE_TEMPLATES = {
    "fitness": [
        "gym workout training muscle fit athlete health strong body",
        "morning workout fitness motivation gym grind abs cardio",
        "personal trainer certified fitness coach transformation body",
        "weightlifting powerlifting CrossFit HIIT marathon runner",
    ],
    "food": [
        "recipe cooking delicious homemade food eat restaurant chef",
        "foodie brunch lunch dinner tasty yummy baking dessert",
        "culinary arts kitchen cooking tutorial meal prep healthy",
        "restaurant review food blog eating out taste test menu",
    ],
    "travel": [
        "travel explore adventure trip wanderlust vacation destination",
        "backpacking solo travel digital nomad passport stamps world",
        "travel photography landscape beautiful places bucket list",
        "road trip camping hiking nature outdoor adventure travel",
    ],
    "fashion": [
        "fashion style outfit wear clothes OOTD model streetwear",
        "luxury brand designer shopping wardrobe looks aesthetic",
        "fashion blogger stylist editorial photoshoot collection",
        "vintage thrift sustainable fashion slow fashion conscious",
    ],
    "tech": [
        "tech software developer code programming AI machine learning",
        "startup entrepreneur SaaS product launch engineering build",
        "data science Python JavaScript React cloud AWS developer",
        "cybersecurity blockchain crypto NFT Web3 decentralized",
    ],
    "lifestyle": [
        "lifestyle daily morning routine wellness mindfulness calm",
        "productivity habits journaling self improvement growth",
        "minimalism home decor interior design aesthetics cozy",
        "mental health therapy self care wellbeing positive life",
    ],
    "art": [
        "art design creative draw paint photography visual digital",
        "illustration graphic design typography branding portfolio",
        "photography portrait studio lightroom editing aesthetic",
        "digital art NFT generative abstract contemporary artist",
    ],
    "sports": [
        "football basketball soccer player game score championship",
        "sports athlete team competition training professional",
        "tennis golf swimming cycling triathlon performance sport",
        "esports gaming streamer competitive player tournament",
    ],
    "other": [
        "content creator influencer collab brand partnerships social",
        "personal blog sharing thoughts opinions life updates misc",
        "humor comedy memes entertainment funny viral relatable",
        "music singer musician producer DJ concert live performance",
    ],
}


def generate_niche_data(n_per_class: int = 200) -> Tuple[List[str], List[int]]:
    """
    Returns (texts, labels) for DistilBERT classification head training.
    Each text is an augmented sample from the niche templates.
    """
    random.seed(99)
    labels_list = list(_NICHE_TEMPLATES.keys())
    texts, labels = [], []

    for label_idx, (niche, templates) in enumerate(_NICHE_TEMPLATES.items()):
        for _ in range(n_per_class):
            base = random.choice(templates).split()
            random.shuffle(base)
            n_words = random.randint(5, len(base))
            sample  = " ".join(base[:n_words])
            texts.append(sample)
            labels.append(label_idx)

    combined = list(zip(texts, labels))
    random.shuffle(combined)
    texts, labels = zip(*combined)
    return list(texts), list(labels)
