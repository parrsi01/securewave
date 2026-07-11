from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_runtime_images_include_every_backend_import_root():
    for filename in ("Dockerfile", "Dockerfile.simple"):
        content = (ROOT / filename).read_text(encoding="utf-8")
        for required_copy in (
            "COPY database/ ./database/",
            "COPY models/ ./models/",
            "COPY routers/ ./routers/",
            "COPY routes/ ./routes/",
            "COPY services/ ./services/",
            "COPY utils/ ./utils/",
            "COPY background_tasks.py .",
        ):
            assert required_copy in content, f"{filename} is missing {required_copy}"
        assert "alembic upgrade head" in content
