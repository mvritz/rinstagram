<p align="center">
  <img src="assets/banner.png" alt="rinstagram banner">
</p>

<p align="center">
  <b>Instagram Analytics &amp; Intelligence Platform — R + Python + Neural Networks</b>
</p>

<p align="center">
  <a href="https://github.com/mvritz/rinstagram/actions/workflows/r-check.yml">
    <img src="https://github.com/mvritz/rinstagram/actions/workflows/r-check.yml/badge.svg" alt="R CI">
  </a>
  <a href="https://github.com/mvritz/rinstagram/actions/workflows/python-tests.yml">
    <img src="https://github.com/mvritz/rinstagram/actions/workflows/python-tests.yml/badge.svg" alt="Python CI">
  </a>
  <a href="https://codecov.io/gh/mvritz/rinstagram">
    <img src="https://codecov.io/gh/mvritz/rinstagram/branch/master/graph/badge.svg" alt="Coverage">
  </a>
  <a href="https://github.com/mvritz/rinstagram/blob/master/LICENSE">
    <img src="https://img.shields.io/github/license/mvritz/rinstagram?style=flat&color=purple" alt="License">
  </a>
  <img src="https://img.shields.io/badge/version-2.0.0-purple" alt="Version">
</p>

---

## Overview

**rinstagram** is an end-to-end Instagram analytics platform built in R with Python ML microservices. It goes far beyond scraping — it scrapes, stores, analyses, and applies neural networks to reveal deep insights about any Instagram profile.

### What it does

| Layer | Technology | Capability |
|-------|-----------|-----------|
| Data collection | R (`httr`) | Anonymous + authenticated Instagram scraping |
| Persistence | SQLite (`DBI` + `RSQLite`) | Time-series snapshots for growth tracking |
| Analytics | R | Engagement rate, Gini coefficient, follower ratios |
| Backend service | Python / FastAPI (`:8001`) | Encryption + 4 neural network models in one process |
| Visualisation | R / plotly + Shiny | Interactive dashboard |
| CI/CD | GitHub Actions + Docker | Automated testing across R and Python |

### Machine Learning Models

| Model | Architecture | Task |
|-------|-------------|------|
| **Engagement Predictor** | 3-layer MLP (256→128→64), BatchNorm, Dropout | Predict engagement rate from profile features |
| **Bot Detector** | Soft-vote ensemble: LightGBM + 2-layer MLP | Classify bot/fake accounts with probability score |
| **Growth Forecaster** | 2-layer LSTM + MC Dropout uncertainty | Multi-step follower count forecasting (30/60/90 days) |
| **Niche Classifier** | DistilBERT fine-tuned classification head | Classify account into 9 content niches |

---

## Architecture

```
┌────────────────────────────────────────────────────┐
│              R Package (rinstagram)                │
│                                                    │
│  scrape()  lscrape()  track()  compare()           │
│  analyze()  predict_engagement()  detect_bots()    │
│  forecast_growth()  classify_niche()               │
│  plot_growth()  plot_comparison()  plot_bot_risk() │
│  launch_dashboard()                                │
└──────────────────────┬─────────────────────────────┘
                       │
                       ▼
          ┌────────────────────────────┐
          │  rinstagram Service        │
          │  (FastAPI :8001)           │
          │                            │
          │  POST /encrypt             │
          │  POST /predict/engagement  │
          │  POST /predict/bot         │
          │  POST /predict/growth      │
          │  POST /predict/niche       │
          │  GET  /health              │
          └────────────┬───────────────┘
                       │
                       ▼
              ┌───────────────┐
              │  SQLite DB    │
              │  profiles     │
              │  snapshots    │
              └───────────────┘
```

---

## Installation

### R Package

```r
remotes::install_github("mvritz/rinstagram")
```

### Python Service (Docker — recommended)

```bash
git clone https://github.com/mvritz/rinstagram.git
cd rinstagram
docker compose up --build
```

The service starts on `:8001` and serves all endpoints including `/encrypt`.

### Python Service (local)

```bash
cd services/ml
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8001
```

### Environment variable (R)

Add to `~/.Renviron`:

```
RINSTAGRAM_ML_URL=http://localhost:8001
```

All R functions — including `lscrape()` encryption — read `RINSTAGRAM_ML_URL` automatically.

---

## Usage

### Scraping

```r
library(rinstagram)

# Anonymous scraping (no login required)
data <- scrape(c("cristiano", "leomessi", "neymarjr"))

# Authenticated scraping (post-level data: likes, comments, dates)
# Use a throwaway account — never your personal account
data <- lscrape(c("cristiano", "leomessi"),
                profile_username = "my_dummy_account",
                profile_password = "my_password")
```

### Analytics

```r
# Enrich with engagement rate, Gini coefficient, and follower ratios
enriched <- analyze(data)

# Full comparison summary (saved to CSV)
compare(enriched, "data/summary.csv")
```

### Machine Learning

```r
# Predict engagement rates (MLP neural network)
enriched <- predict_engagement(analyze(data))

# Detect bot accounts (LightGBM + MLP ensemble)
enriched <- detect_bots(enriched)

# Classify content niche (DistilBERT)
enriched <- classify_niche(enriched)

# View results
print(enriched[, c("username", "engagement_rate", "ml_predicted_engagement",
                   "bot_probability", "bot_risk_label", "niche")])
```

### Growth Tracking & Forecasting

```r
# Track profiles over time (run daily via cron or taskscheduleR)
track(c("cristiano", "leomessi"))

# Forecast next 30 days with LSTM + uncertainty intervals
forecast <- forecast_growth("cristiano", horizon = 30)

# Visualise
plot_growth("cristiano", forecast = forecast)
```

### Visualisation

```r
# Interactive engagement bar chart
plot_engagement_dist(enriched)

# Radar comparison of multiple profiles
plot_comparison(enriched)

# Bot risk chart
plot_bot_risk(enriched)
```

### Shiny Dashboard

```r
# Launch the interactive analytics dashboard
# (requires shiny, shinydashboard, DT — installed automatically)
launch_dashboard()
```

The dashboard provides five tabs:
- **Profile Explorer** — real-time scrape + ML scores (engagement, bot risk, niche)
- **Growth Tracker** — plotly growth chart with LSTM forecast and confidence band
- **Comparison** — radar chart of normalised metrics across profiles
- **Leaderboard** — sortable, exportable table ranked by engagement rate
- **Bot Detector** — colour-coded risk chart and results table

---

## Training ML Models

Pre-built weights are generated automatically on first service start using synthetic data. To train with more samples or on real scraped data:

```bash
cd services/ml

# Engagement predictor (MLP)
python -m training.train_engagement --epochs 100 --n-samples 50000

# Bot detector (LightGBM + MLP ensemble)
python -m training.train_bot_detector --n-samples 100000

# Growth forecaster (LSTM)
python -m training.train_forecaster --epochs 150 --n-samples 30000

# Niche classifier (DistilBERT head — backbone frozen)
python -m training.train_classifier --epochs 30 --n-per-class 1000

# Full DistilBERT fine-tuning (GPU recommended)
python -m training.train_classifier --epochs 20 --full-finetune --device cuda
```

Weights are saved to `services/ml/weights/` and loaded automatically on the next service start.

---

## Repository Structure

```
rinstagram/
├── R/                        # R package source
│   ├── functions.R           # scrape, lscrape, compare
│   ├── analytics.R           # analyze, predict_*, detect_*, forecast_*, classify_*
│   ├── track.R               # track() — time-series snapshots
│   ├── visualize.R           # plot_* functions
│   ├── db.R                  # SQLite persistence layer
│   ├── shiny.R               # launch_dashboard()
│   ├── login.R               # Instagram authentication
│   ├── graphql.R             # GraphQL scraping
│   ├── profile.R             # Anonymous profile scraping
│   ├── types.R               # S4 classes
│   └── utils.R               # Utilities
├── inst/shiny/               # Shiny dashboard app
│   ├── app.R
│   ├── ui.R
│   └── server.R
├── tests/testthat/           # R unit tests
├── services/ml/              # Unified backend service (encryption + ML)
│   ├── app/
│   │   ├── main.py           # FastAPI — all endpoints
│   │   ├── encryption.py     # Instagram v10 AES-GCM + NaCl encryption
│   │   ├── models/           # 4 ML model implementations
│   │   ├── schemas.py        # Pydantic request/response schemas
│   │   └── config.py
│   ├── training/             # Training scripts + synthetic data generator
│   ├── notebooks/            # Jupyter EDA + model exploration
│   ├── weights/              # Saved model weights (auto-generated)
│   └── Dockerfile
├── docker-compose.yml
├── .github/workflows/
│   ├── r-check.yml           # R CMD check + lintr + coverage
│   └── python-tests.yml      # pytest + Docker build
└── DESCRIPTION
```

---

## Running Tests

Run both suites from the repository root:

```bash
# R tests
Rscript -e "testthat::test_local()"

# Python — unified service (encryption + ML)
pytest services/ml/tests/ -v
```

---

## Contributing

Pull requests are welcome. Please run the full test suite before opening a PR.

---

## License

MIT — see [LICENSE](LICENSE).

## Disclaimer

This package is for educational and research purposes only. Use a throwaway Instagram account for authenticated scraping. The author is not responsible for any misuse. This project is not affiliated with or endorsed by Instagram / Meta.
