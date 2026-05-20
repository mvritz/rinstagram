"""
Shared pytest fixtures for the rinstagram ML service test suite.

The `mock_app_client` fixture patches all four model loader functions so the
FastAPI lifespan returns lightweight MagicMock objects instead of training or
loading real PyTorch / LightGBM / DistilBERT models. This keeps the suite fast
and self-contained (no GPU, no HuggingFace downloads required for unit tests).
"""

from unittest.mock import MagicMock, patch

import pytest


def _make_mock_models():
    engagement = MagicMock()
    engagement.predict.return_value = [0.03, 0.08]

    bot = MagicMock()
    bot.predict.return_value = ([0.1, 0.85], ["low", "high"])

    forecaster = MagicMock()
    forecaster.predict.return_value = (
        ["2024-02-01", "2024-02-02"],
        [10000.0, 10100.0],
        [9800.0,  9900.0],
        [10200.0, 10300.0],
    )

    classifier = MagicMock()
    classifier.predict.return_value = (["fitness", "food"], [0.92, 0.88])

    return engagement, bot, forecaster, classifier


@pytest.fixture(scope="module")
def mock_app_client():
    """
    TestClient with all model loaders mocked out.

    The lifespan runs normally but calls the mocked loaders, so _models is
    populated with MagicMock instances. No model training or downloads occur.

    Skipped automatically when `fastapi` is not installed.
    """
    pytest.importorskip("fastapi", reason="fastapi not installed")
    from fastapi.testclient import TestClient

    engagement, bot, forecaster, classifier = _make_mock_models()

    from services.ml.app.main import app

    with (
        patch("services.ml.app.main.load_engagement_model",  return_value=engagement),
        patch("services.ml.app.main.load_bot_model",          return_value=bot),
        patch("services.ml.app.main.load_forecaster_model",   return_value=forecaster),
        patch("services.ml.app.main.load_classifier_model",   return_value=classifier),
    ):
        with TestClient(app, raise_server_exceptions=True) as client:
            yield client
