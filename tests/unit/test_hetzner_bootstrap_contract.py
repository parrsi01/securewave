from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BOOTSTRAP = ROOT / "scripts" / "hetzner_bootstrap.sh"


def test_existing_operator_is_added_to_required_deployment_groups():
    source = BOOTSTRAP.read_text(encoding="utf-8")

    create_guard = source.index('if ! id "${ADMIN_USER}"')
    guard_end = source.index("\nfi", create_guard)
    group_assignment = source.index('usermod -aG sudo,docker "${ADMIN_USER}"')

    assert group_assignment > guard_end
