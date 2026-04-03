#!/bin/bash
# Install-ArcAgent-Linux.sh
# Onboard a Linux VM to Azure Arc-enabled servers
#
# Run this script ON each Linux nested VM (ArcUbuntu, ArcK3s)
# Usage: sudo ./Install-ArcAgent-Linux.sh \
#   --tenant-id <tid> \
#   --subscription-id <sid> \
#   --resource-group <rg> \
#   --location <loc> \
#   [--service-principal-id <spid> --service-principal-secret <sps>]

set -euo pipefail

echo "=== Azure Arc — Connected Machine Agent Installation (Linux) ==="
echo "Machine: $(hostname)"
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tenant-id)          TENANT_ID="$2"; shift 2 ;;
        --subscription-id)    SUBSCRIPTION_ID="$2"; shift 2 ;;
        --resource-group)     RESOURCE_GROUP="$2"; shift 2 ;;
        --location)           LOCATION="$2"; shift 2 ;;
        --service-principal-id)     SP_ID="$2"; shift 2 ;;
        --service-principal-secret) SP_SECRET="$2"; shift 2 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

TAGS="project=arc-connectivity-demo,environment=lab"

# ── 1. Download and install the agent ────────────────────────────────
echo "[1/2] Installing Azure Connected Machine Agent..."
if ! command -v azcmagent &> /dev/null; then
    wget -q https://aka.ms/azcmagent -O /tmp/install_linux_azcmagent.sh
    bash /tmp/install_linux_azcmagent.sh
    echo "  Agent installed"
else
    echo "  Agent already installed"
fi

# ── 2. Connect to Azure Arc ─────────────────────────────────────────
echo "[2/2] Connecting to Azure Arc..."

CONNECT_ARGS=(
    connect
    --resource-group "$RESOURCE_GROUP"
    --tenant-id "$TENANT_ID"
    --location "$LOCATION"
    --subscription-id "$SUBSCRIPTION_ID"
    --tags "$TAGS"
)

if [[ -n "${SP_ID:-}" && -n "${SP_SECRET:-}" ]]; then
    CONNECT_ARGS+=(--service-principal-id "$SP_ID" --service-principal-secret "$SP_SECRET")
    echo "  Using service principal authentication"
else
    echo "  Using interactive authentication"
fi

azcmagent "${CONNECT_ARGS[@]}"

if [[ $? -eq 0 ]]; then
    echo ""
    echo "SUCCESS: $(hostname) is now an Azure Arc-enabled server!"
    echo "Check: Azure Portal > Azure Arc > Servers"
else
    echo ""
    echo "FAILED: azcmagent connect failed"
    echo "Check logs: /var/opt/azcmagent/log/"
fi
