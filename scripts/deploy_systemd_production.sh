#!/usr/bin/env bash
set -Eeuo pipefail

readonly DEPLOY_ROOT="/opt/securewave-beta"
readonly API_SERVICE="securewave-api.service"
readonly HELPER_SERVICE="securewave-wg-helper.service"
readonly SOCKET_GROUP="securewave-wg"
readonly BACKUP_DIR="/var/backups/securewave-production-20260927T231614Z"
readonly API_UNIT_DIR="/etc/systemd/system/securewave-api.service.d"
readonly API_DROPIN="${API_UNIT_DIR}/securewave-wg-helper.conf"
readonly HELPER_UNIT="/etc/systemd/system/securewave-wg-helper.service"

usage() {
    printf 'Usage: %s TESTED_SOURCE_DIRECTORY\n' "$0" >&2
    exit 2
}

fail() {
    printf 'Deployment stopped: %s\n' "$1" >&2
    exit 1
}

[[ $# -eq 1 ]] || usage
[[ ${EUID} -eq 0 ]] || fail 'must run as root in the authorized production shell'

SOURCE_ROOT="$(cd -- "$1" && pwd -P)" || fail 'source directory is unavailable'
SOURCE_COMMIT="$(git -C "${SOURCE_ROOT}" rev-parse --verify 'HEAD^{commit}' 2>/dev/null)" \
    || fail 'source directory is not a committed Git checkout'
SOURCE_CHANGES="$(git -C "${SOURCE_ROOT}" status --porcelain --untracked-files=all)" \
    || fail 'could not verify the source Git worktree'
[[ -z "${SOURCE_CHANGES}" ]] || fail 'source Git worktree is not clean'
for relative_path in \
    routes/auth.py \
    routes/vpn.py \
    services/wireguard_helper.py \
    services/wireguard_helper_client.py \
    infrastructure/systemd/securewave-wg-helper.service \
    infrastructure/systemd/securewave-api.service.d/securewave-wg-helper.conf \
    tests/test_vpn_client_owned_config.py \
    tests/test_wireguard_helper.py; do
    [[ -f "${SOURCE_ROOT}/${relative_path}" ]] || fail "tested source is missing ${relative_path}"
done

[[ -d "${DEPLOY_ROOT}/releases" && -L "${DEPLOY_ROOT}/current" ]] \
    || fail 'active systemd release layout did not match the verified deployment'
ACTIVE_RELEASE="$(readlink -f -- "${DEPLOY_ROOT}/current")"
case "${ACTIVE_RELEASE}" in
    "${DEPLOY_ROOT}"/releases/*) ;;
    *) fail 'current release does not resolve inside the verified releases directory' ;;
esac
[[ -x "${ACTIVE_RELEASE}/.venv/bin/gunicorn" && -x "${ACTIVE_RELEASE}/.venv/bin/python" ]] \
    || fail 'active release backend Python environment is unavailable'

EXEC_START="$(systemctl --no-pager --property=ExecStart --value show "${API_SERVICE}")"
[[ "${EXEC_START}" == *"${DEPLOY_ROOT}/current/.venv/bin/gunicorn"* ]] \
    || fail 'active API ExecStart no longer matches the verified systemd release layout'
API_USER="$(systemctl --no-pager --property=User --value show "${API_SERVICE}")"
NO_NEW_PRIVILEGES="$(systemctl --no-pager --property=NoNewPrivileges --value show "${API_SERVICE}")"
API_CAPABILITIES="$(systemctl --no-pager --property=CapabilityBoundingSet --value show "${API_SERVICE}")"
API_AMBIENT_CAPABILITIES="$(systemctl --no-pager --property=AmbientCapabilities --value show "${API_SERVICE}")"
[[ "${API_USER}" == securewave && "${NO_NEW_PRIVILEGES}" == yes ]] \
    || fail 'API service privilege boundary differs from the verified non-root configuration'
case "${API_CAPABILITIES} ${API_AMBIENT_CAPABILITIES}" in
    *CAP_NET_ADMIN*|*cap_net_admin*) fail 'API service already has CAP_NET_ADMIN; refusing to widen or alter privileges' ;;
esac
systemctl is-active --quiet "${API_SERVICE}" || fail 'API service is not active before deployment'

[[ -f "${BACKUP_DIR}/SHA256SUMS" ]] || fail 'verified production backup manifest is unavailable'
(cd -- "${BACKUP_DIR}" && sha256sum --check SHA256SUMS) \
    || fail 'production recovery backup checksum verification failed'

PREVIOUS_TARGET="$(readlink -- "${DEPLOY_ROOT}/current")"
SWITCHED=0
API_NEEDS_RESTART=0
CREATED_HELPER_UNIT=0
CREATED_API_DROPIN=0
NEW_RELEASE=""
rollback() {
    local status=$?
    local rollback_error=0
    local rollback_link
    trap - EXIT
    if [[ ${status} -ne 0 ]]; then
        if [[ ${SWITCHED} -eq 1 ]]; then
            rollback_link="${DEPLOY_ROOT}/current.rollback.$$"
            if [[ ! -e "${rollback_link}" ]] \
                && ln -s -- "${PREVIOUS_TARGET}" "${rollback_link}" \
                && mv -Tf -- "${rollback_link}" "${DEPLOY_ROOT}/current"; then
                SWITCHED=0
            else
                rollback_error=1
                rm -f -- "${rollback_link}" || true
            fi
        fi
        if [[ ${CREATED_HELPER_UNIT} -eq 1 ]]; then
            systemctl disable --now "${HELPER_SERVICE}" >/dev/null 2>&1 || rollback_error=1
            rm -f -- "${HELPER_UNIT}" || rollback_error=1
        elif [[ ${API_NEEDS_RESTART} -eq 1 ]] && systemctl is-active --quiet "${HELPER_SERVICE}"; then
            systemctl restart "${HELPER_SERVICE}" >/dev/null 2>&1 || rollback_error=1
        fi
        if [[ ${CREATED_API_DROPIN} -eq 1 ]]; then
            rm -f -- "${API_DROPIN}" || rollback_error=1
        fi
        systemctl daemon-reload >/dev/null 2>&1 || rollback_error=1
        if [[ ${API_NEEDS_RESTART} -eq 1 ]]; then
            systemctl restart "${API_SERVICE}" >/dev/null 2>&1 || rollback_error=1
        fi
        rm -f -- "${DEPLOY_ROOT}/current.new.$$" || rollback_error=1
        if [[ ${rollback_error} -eq 0 ]]; then
            printf 'Deployment failed; prior release and service configuration were restored.\n' >&2
        else
            printf 'Deployment failed and rollback was incomplete; inspect current release and service state before retrying.\n' >&2
        fi
    fi
    exit "${status}"
}
trap rollback EXIT

if ! getent group "${SOCKET_GROUP}" >/dev/null; then
    groupadd --system "${SOCKET_GROUP}"
else
    GROUP_ENTRY="$(getent group "${SOCKET_GROUP}")"
    GROUP_GID="${GROUP_ENTRY#*:*:}"
    GROUP_GID="${GROUP_GID%%:*}"
    GROUP_MEMBERS="${GROUP_ENTRY##*:}"
    [[ -z "${GROUP_MEMBERS}" ]] || fail 'helper socket group already has explicit members'
    if getent passwd | awk -F: -v gid="${GROUP_GID}" '$4 == gid { found=1 } END { exit !found }'; then
        fail 'helper socket group is already a primary group for a local user'
    fi
fi

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
NEW_RELEASE="${DEPLOY_ROOT}/releases/${STAMP}-wireguard-helper-$$"
[[ ! -e "${NEW_RELEASE}" ]] || fail 'new release path already exists'
mkdir -- "${NEW_RELEASE}"
cp -a -- "${ACTIVE_RELEASE}/." "${NEW_RELEASE}/" \
    || fail 'could not create a preserving copy of the active release'
printf '%s\n' "${SOURCE_COMMIT}" > "${NEW_RELEASE}/.securewave-source-commit"
chmod 0444 -- "${NEW_RELEASE}/.securewave-source-commit"

install_app_file() {
    local relative_path="$1"
    local reference_path="$2"
    local source_file="${SOURCE_ROOT}/${relative_path}"
    local destination_file="${NEW_RELEASE}/${relative_path}"
    [[ -f "${source_file}" && -f "${NEW_RELEASE}/${reference_path}" ]] \
        || fail "cannot install ${relative_path} into the new release"
    local owner group mode
    if [[ -f "${destination_file}" ]]; then
        owner="$(stat -c '%U' -- "${destination_file}")"
        group="$(stat -c '%G' -- "${destination_file}")"
        mode="$(stat -c '%a' -- "${destination_file}")"
    else
        owner="$(stat -c '%U' -- "${NEW_RELEASE}/${reference_path}")"
        group="$(stat -c '%G' -- "${NEW_RELEASE}/${reference_path}")"
        mode="$(stat -c '%a' -- "${NEW_RELEASE}/${reference_path}")"
    install -d -- "$(dirname -- "${destination_file}")"
    fi
    install -o "${owner}" -g "${group}" -m "${mode}" -- "${source_file}" "${destination_file}"
}

install_app_file routes/auth.py services/vpn_peer_manager.py
install_app_file routes/vpn.py services/vpn_peer_manager.py
install_app_file services/wireguard_helper.py services/vpn_peer_manager.py
install_app_file services/wireguard_helper_client.py services/vpn_peer_manager.py
"${NEW_RELEASE}/.venv/bin/python" -m py_compile \
    "${NEW_RELEASE}/routes/auth.py" \
    "${NEW_RELEASE}/routes/vpn.py" \
    "${NEW_RELEASE}/services/wireguard_helper.py" \
    "${NEW_RELEASE}/services/wireguard_helper_client.py" \
    || fail 'production Python compilation failed'

HELPER_UNIT_SOURCE="${SOURCE_ROOT}/infrastructure/systemd/securewave-wg-helper.service"
DROPIN_SOURCE="${SOURCE_ROOT}/infrastructure/systemd/securewave-api.service.d/securewave-wg-helper.conf"
if [[ -e "${HELPER_UNIT}" ]]; then
    cmp -s -- "${HELPER_UNIT_SOURCE}" "${HELPER_UNIT}" \
        || fail 'an existing WireGuard helper unit differs from this reviewed unit'
else
    install -o root -g root -m 0644 -- "${HELPER_UNIT_SOURCE}" "${HELPER_UNIT}"
    CREATED_HELPER_UNIT=1
fi
install -d -o root -g root -m 0755 -- "${API_UNIT_DIR}"
if [[ -e "${API_DROPIN}" ]]; then
    cmp -s -- "${DROPIN_SOURCE}" "${API_DROPIN}" \
        || fail 'an existing API drop-in differs from the reviewed socket-group change'
else
    install -o root -g root -m 0644 -- "${DROPIN_SOURCE}" "${API_DROPIN}"
    CREATED_API_DROPIN=1
fi

ln -s -- "${NEW_RELEASE}" "${DEPLOY_ROOT}/current.new.$$"
mv -Tf -- "${DEPLOY_ROOT}/current.new.$$" "${DEPLOY_ROOT}/current"
SWITCHED=1
API_NEEDS_RESTART=1
systemctl daemon-reload
systemctl enable "${HELPER_SERVICE}"
if systemctl is-active --quiet "${HELPER_SERVICE}"; then
    systemctl restart "${HELPER_SERVICE}"
else
    systemctl start "${HELPER_SERVICE}"
fi
systemctl restart "${API_SERVICE}"
systemctl is-active --quiet "${HELPER_SERVICE}" || fail 'WireGuard helper did not become active'
systemctl is-active --quiet "${API_SERVICE}" || fail 'API service did not remain active'
curl --fail --silent --show-error --max-time 15 http://127.0.0.1:8080/api/ready
printf '\nSystemd deployment completed and local API readiness check passed.\n'
trap - EXIT
