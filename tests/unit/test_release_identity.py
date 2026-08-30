import json

from utils import release_identity


def test_release_identity_prefers_environment(monkeypatch, tmp_path):
    metadata = tmp_path / ".release.json"
    metadata.write_text(json.dumps({"version": "4.0.0+10", "commit": "a" * 40}))
    monkeypatch.setattr(release_identity, "RELEASE_METADATA_PATH", metadata)
    monkeypatch.setenv("APP_VERSION", "4.0.0+11")
    monkeypatch.setenv("GIT_SHA", "b" * 40)

    assert release_identity.get_release_identity() == ("4.0.0+11", "b" * 40)


def test_release_identity_uses_deployment_metadata(monkeypatch, tmp_path):
    metadata = tmp_path / ".release.json"
    metadata.write_text(json.dumps({"version": "4.0.0+10", "commit": "a" * 40}))
    monkeypatch.setattr(release_identity, "RELEASE_METADATA_PATH", metadata)
    monkeypatch.delenv("APP_VERSION", raising=False)
    monkeypatch.delenv("GIT_SHA", raising=False)

    assert release_identity.get_release_identity() == ("4.0.0+10", "a" * 40)


def test_release_identity_fails_closed_to_defaults(monkeypatch, tmp_path):
    metadata = tmp_path / ".release.json"
    metadata.write_text("not-json")
    monkeypatch.setattr(release_identity, "RELEASE_METADATA_PATH", metadata)
    monkeypatch.delenv("APP_VERSION", raising=False)
    monkeypatch.delenv("GIT_SHA", raising=False)

    assert release_identity.get_release_identity(default_version="test") == ("test", "")
