#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# Solutionz RMM - SNMP Predeploy Discovery Bootstrap (Pinned)
# =========================================================
# End-user experience (run ONE command):
#   curl -fsSL <PINNED_SETUP_URL> | sudo bash
#
# This bootstrap pulls *pinned* versions of the discovery scripts (Python + snmp wrapper)
# from a specific commit SHA, installs dependencies via APT (no pip), prompts for the
# required inputs, and generates CSV outputs.
#
# Pinned commit SHA for BOTH scripts:
PINNED_SHA="0d9ab96f8e786f980b790a048d31cb812e30df89"

# Pinned raw URLs (do not use refs/heads/main here)
PY_URL="https://raw.githubusercontent.com/SLZEngineering/discovery/${PINNED_SHA}/Python"
SNMP_URL="https://raw.githubusercontent.com/SLZEngineering/discovery/${PINNED_SHA}/snmp"

# Where to store scripts + outputs on the device
WORKDIR="/opt/solutionz/discovery"
OUTDIR="/var/lib/solutionz/discovery/out"

# Local filenames expected by the snmp wrapper
PY_LOCAL="${WORKDIR}/generic_switch_snmp_predeploy_Updated_NoPip.py"
SNMP_LOCAL="${WORKDIR}/snmp"
OUI_LOCAL="${WORKDIR}/oui.csv"

mkdir -p "${WORKDIR}" "${OUTDIR}"

echo "==> Solutionz RMM Discovery Bootstrap (Pinned SHA: ${PINNED_SHA})"

# Ensure curl exists
if ! command -v curl >/dev/null 2>&1; then
  echo "==> Installing curl..."
  apt-get update -y
  apt-get install -y curl
fi

echo "==> Downloading pinned scripts from GitHub..."
curl -fsSL "${PY_URL}"   -o "${PY_LOCAL}"
curl -fsSL "${SNMP_URL}" -o "${SNMP_LOCAL}"
chmod 750 "${SNMP_LOCAL}"

# Guard against downloading HTML (wrong URL / blocked)
if head -n 2 "${PY_LOCAL}" | grep -qi "<!doctype html"; then
  echo "ERROR: PY_URL returned HTML, not a python file."
  echo "PY_URL: ${PY_URL}"
  exit 1
fi
if head -n 2 "${SNMP_LOCAL}" | grep -qi "<!doctype html"; then
  echo "ERROR: SNMP_URL returned HTML, not a shell script."
  echo "SNMP_URL: ${SNMP_URL}"
  exit 1
fi

# Prompt for inputs
read -r -p "Switch management IP/hostname (required): " SWITCH
if [[ -z "${SWITCH}" ]]; then
  echo "ERROR: Switch IP/hostname is required."
  exit 1
fi

read -r -s -p "SNMP read-only community (required, hidden): " COMMUNITY
echo
if [[ -z "${COMMUNITY}" ]]; then
  echo "ERROR: SNMP community is required."
  exit 1
fi

read -r -p "ARP host(s) (gateway/core) comma-separated (optional, recommended for IP addresses): " ARP_HOSTS

read -r -p "Download IEEE oui.csv for Make lookup? (Y/n): " OUI_ANSWER
OUI_ANSWER="${OUI_ANSWER:-Y}"

read -r -p "Output prefix (optional, e.g., Client_Site_Rooms): " OUT_PREFIX
if [[ -z "${OUT_PREFIX}" ]]; then
  OUT_PREFIX="discovery"
fi

read -r -p "Install SNMP CLI tools (snmpget/snmpwalk) for testing? (y/N): " SNMP_TOOLS_ANSWER
SNMP_TOOLS_ANSWER="${SNMP_TOOLS_ANSWER:-N}"

read -r -p "Run quick SNMP tests before discovery? (y/N): " TEST_ANSWER
TEST_ANSWER="${TEST_ANSWER:-N}"

# Build args to pass to the snmp wrapper
ARGS=(--switch "${SWITCH}" --community "${COMMUNITY}" --out-prefix "${OUTDIR}/${OUT_PREFIX}_$(date +%F)")

# Parse ARP_HOSTS into repeated --arp-host args
if [[ -n "${ARP_HOSTS}" ]]; then
  IFS=',' read -r -a ARP_ARRAY <<< "${ARP_HOSTS}"
  for ah in "${ARP_ARRAY[@]}"; do
    ah_trim="$(echo "${ah}" | xargs)"
    [[ -n "${ah_trim}" ]] && ARGS+=(--arp-host "${ah_trim}")
  done
fi

# OUI option
if [[ "${OUI_ANSWER}" =~ ^[Yy]$ ]]; then
  ARGS+=(--download-oui)
fi

# Optional SNMP tools and tests
if [[ "${SNMP_TOOLS_ANSWER}" =~ ^[Yy]$ ]]; then
  ARGS+=(--install-snmp-tools)
fi
if [[ "${TEST_ANSWER}" =~ ^[Yy]$ ]]; then
  ARGS+=(--test)
fi

echo "==> Running discovery..."
cd "${WORKDIR}"
bash "${SNMP_LOCAL}" "${ARGS[@]}"

echo
echo "==> Done."
echo "Outputs saved under: ${OUTDIR}"
ls -1 "${OUTDIR}"/*_customer.csv "${OUTDIR}"/*_debug.csv 2>/dev/null || true
