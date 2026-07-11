from pathlib import Path
from xml.etree import ElementTree


ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "securewave_app/android/app/src/main/AndroidManifest.xml"
MAIN_ACTIVITY = ROOT / (
    "securewave_app/android/app/src/main/kotlin/"
    "com/example/securewave_app/MainActivity.kt"
)
VPN_SERVICE = ROOT / (
    "securewave_app/android/app/src/main/kotlin/"
    "com/example/securewave_app/vpn/SecureWaveVpnService.kt"
)
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


def test_android_vpn_bridge_uses_compile_compatible_service_apis():
    activity_source = MAIN_ACTIVITY.read_text(encoding="utf-8")
    service_source = VPN_SERVICE.read_text(encoding="utf-8")

    assert "import com.example.securewave_app.vpn.SecureWaveVpnService" in activity_source
    activity_body = "\n".join(
        line for line in activity_source.splitlines() if not line.startswith("import ")
    )
    assert "vpn.SecureWaveVpnService" not in activity_body
    assert "registerForActivityResult" not in activity_source
    assert "Config.parse(BufferedReader(StringReader(configText)))" in service_source
