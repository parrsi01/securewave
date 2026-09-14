import importlib.util
import hashlib
import json
import plistlib
from pathlib import Path
from zipfile import ZipFile
import unittest
from tempfile import TemporaryDirectory

spec = importlib.util.spec_from_file_location(
    "verify_macos_download", Path(__file__).resolve().parents[2] / "scripts/verify_macos_download.py"
)
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


class MacDownloadIntegrityTest(unittest.TestCase):
    def fixture(self, root, version="4.0.0+10", checksum_valid=True):
        downloads = root / "static/downloads"
        downloads.mkdir(parents=True)
        artifact = downloads / "securewave-macos-arm64-ui-demo.zip"
        with ZipFile(artifact, "w") as archive:
            archive.writestr("SecureWave.app/Contents/Info.plist", plistlib.dumps({
                "CFBundleShortVersionString": "4.0.0", "CFBundleVersion": "10",
            }))
        digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
        (downloads / "manifest.json").write_text(json.dumps({"downloads": [{
            "platform": "macos", "status": "available", "filename": artifact.name,
            "version": version, "checksum_sha256": digest if checksum_valid else "bad",
        }]}))

    def test_matching_artifact(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            verifier.verify(root)

    def test_stale_binary_label_rejected(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root, version="4.0.0+11")
            with self.assertRaisesRegex(ValueError, "binary"):
                verifier.verify(root)

    def test_wrong_checksum_rejected(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root, checksum_valid=False)
            with self.assertRaisesRegex(ValueError, "SHA-256"):
                verifier.verify(root)
