#!/bin/bash
# Install-ArcAgent-Linux.sh
# Onboard a Linux VM to Azure Arc-enabled servers
#
# Adapted from Arc Jumpstart ArcBox:
#   github.com/microsoft/azure_arc — installArcAgentUbuntu.sh
#
# Key pattern from ArcBox: block Azure IMDS (169.254.169.254) so the Arc
# agent doesn't detect it's running inside Azure and refuse to onboard.
#
# Usage:
#   sudo ./Install-ArcAgent-Linux.sh \
#     --tenant-id <tid> --subscription-id <sid> \
#     --resource-group <rg> --location <loc> \
#     [--access-token <token>]
#     [--service-principal-id <spid> --service-principal-secret <sps>]

set -euo pipefail

echo "=== Azure Arc — Connected Machine Agent Installation (Linux) ==="
echo "Machine: $(hostname)"
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"

# Parse arguments
TENANT_ID=""; SUBSCRIPTION_ID=""; RESOURCE_GROUP=""; LOCATION=""
SP_ID=""; SP_SECRET=""; ACCESS_TOKEN=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tenant-id)             TENANT_ID="$2"; shift 2 ;;
        --subscription-id)       SUBSCRIPTION_ID="$2"; shift 2 ;;
        --resource-group)        RESOURCE_GROUP="$2"; shift 2 ;;
        --location)              LOCATION="$2"; shift 2 ;;
        --access-token)          ACCESS_TOKEN="$2"; shift 2 ;;
        --service-principal-id)     SP_ID="$2"; shift 2 ;;
        --service-principal-secret) SP_SECRET="$2"; shift 2 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

TAGS="project=arc-connectivity-demo,environment=lab"

# ── 1. Block Azure IMDS ─────────────────────────────────────────────
# From ArcBox: prevents Arc agent from detecting it's inside Azure
# This is REQUIRED for nested VM scenarios
echo "[1/3] Blocking Azure IMDS endpoint..."
sudo ufw --force enable
sudo ufw deny out from any to 169.254.169.254
sudo ufw default allow incoming
echo "  IMDS blocked via UFW"

# ── 2. Download and install the agent ────────────────────────────────
echo "[2/3] Installing Azure Connected Machine Agent..."
if ! command -v azcmagent &> /dev/null; then
    wget -q https://aka.ms/azcmagent -O ~/install_linux_azcmagent.sh
    bash ~/install_linux_azcmagent.sh
    echo "  Agent installed"
else
    echo "  Agent already installed"
fi

# ── 3. Connect to Azure Arc ─────────────────────────────────────────
echo "[3/3] Connecting to Azure Arc..."

# Capitalise hostname for Azure resource name (ArcBox pattern)
ArcResourceName=$(hostname | sed -e "s/\b\(.\)/\u\1/g")

CONNECT_ARGS=(
    connect
    --resource-group "$RESOURCE_GROUP"
    --resource-name "$ArcResourceName"
    --tenant-id "$TENANT_ID"
    --location "$LOCATION"
    --subscription-id "$SUBSCRIPTION_ID"
    --tags "$TAGS"
    --cloud "AzureCloud"
)

# Prefer access token (from managed identity on host), then SP, then interactive
if [[ -n "${ACCESS_TOKEN:-}" ]]; then
    CONNECT_ARGS+=(--access-token "$ACCESS_TOKEN")
    echo "  Using access token authentication"
elif [[ -n "${SP_ID:-}" && -n "${SP_SECRET:-}" ]]; then
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
