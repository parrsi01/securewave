"""Static contracts for a safe, importable Docker source layout.

These checks intentionally validate build inputs only. They do not claim that
database migrations, a running container, or production configuration work.
"""

from pathlib import Path


DOCKERFILES = (Path("Dockerfile"), Path("Dockerfile.simple"))
RUNTIME_COPY_STATEMENTS = (
    "COPY main.py .",
    "COPY background_tasks.py .",
    "COPY database/ ./database/",
    "COPY models/ ./models/",
    "COPY routers/ ./routers/",
    "COPY routes/ ./routes/",
    "COPY services/ ./services/",
    "COPY utils/ ./utils/",
    "COPY alembic/ ./alembic/",
    "COPY static/ ./static/",
)


def test_dockerfiles_copy_main_runtime_import_roots():
    for dockerfile in DOCKERFILES:
        contents = dockerfile.read_text(encoding="utf-8")
        for statement in RUNTIME_COPY_STATEMENTS:
            assert statement in contents, f"{dockerfile} is missing: {statement}"


def test_dockerignore_excludes_known_local_secret_and_generated_paths():
    contents = Path(".dockerignore").read_text(encoding="utf-8")
    for entry in (
        "securewave_private/",
        "static/.env",
        "static/.dart_tool/",
        "artifacts/",
        ".venv/",
    ):
        assert entry in contents
