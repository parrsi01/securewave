from pathlib import Path
from xml.etree import ElementTree


ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "securewave_app/android/app/src/main/AndroidManifest.xml"
ANDROID = "{http://schemas.android.com/apk/res/android}"


def test_android_vpn_service_uses_supported_foreground_service_type():
    root = ElementTree.parse(MANIFEST).getroot()
    permissions = {
        node.attrib[f"{ANDROID}name"] for node in root.findall("uses-permission")
    }
    assert "android.permission.FOREGROUND_SERVICE" in permissions
    assert "android.permission.FOREGROUND_SERVICE_SYSTEM_EXEMPTED" in permissions

    service = next(
        node
        for node in root.findall("./application/service")
        if node.attrib.get(f"{ANDROID}name") == ".vpn.SecureWaveVpnService"
    )
    assert service.attrib[f"{ANDROID}permission"] == "android.permission.BIND_VPN_SERVICE"
    assert service.attrib[f"{ANDROID}foregroundServiceType"] == "systemExempted"
    assert service.attrib[f"{ANDROID}exported"] == "false"
