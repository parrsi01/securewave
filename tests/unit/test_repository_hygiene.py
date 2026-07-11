import importlib.util
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def _load_hygiene_module():
    spec = importlib.util.spec_from_file_location(
        "check_repository_hygiene", ROOT / "scripts/check_repository_hygiene.py"
    )
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def test_repository_hygiene_accepts_current_tracked_tree():
    hygiene = _load_hygiene_module()
    files = hygiene.tracked_files()
    assert hygiene.check_paths(files) == []
    assert hygiene.check_json(files) == []
    assert hygiene.check_workflows(files) == []
    assert hygiene.check_container_pins(files) == []


def test_repository_hygiene_rejects_mutable_action_and_raw_evidence(tmp_path, monkeypatch):
    hygiene = _load_hygiene_module()
    workflow = tmp_path / ".github/workflows/test.yml"
    workflow.parent.mkdir(parents=True)
    workflow.write_text(
        "permissions:\n  contents: read\njobs:\n  test:\n    steps:\n"
        "      - uses: actions/checkout@v4\n",
        encoding="utf-8",
    )
    monkeypatch.setattr(hygiene, "ROOT", tmp_path)

    workflow_failures = hygiene.check_workflows([".github/workflows/test.yml"])
    assert any("mutable action reference" in failure for failure in workflow_failures)
    path_failures = hygiene.check_paths(["artifacts/new/raw-output.log"])
    assert any("new raw evidence" in failure for failure in path_failures)
