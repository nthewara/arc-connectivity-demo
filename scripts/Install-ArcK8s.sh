#!/bin/bash
# Install-ArcK8s.sh
# Install K3s and onboard to Azure Arc-enabled Kubernetes
#
# Run this script ON the ArcK3s nested VM
# Prerequisites: Ubuntu 22.04, internet access, Arc agent already connected (optional)

set -euo pipefail

echo "=== Azure Arc — K3s + Arc-enabled Kubernetes Installation ==="
echo "Machine: $(hostname)"
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"

# Parse arguments
TENANT_ID=""
SUBSCRIPTION_ID=""
RESOURCE_GROUP=""
LOCATION=""
CLUSTER_NAME="arc-k3s-lab"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tenant-id)        TENANT_ID="$2"; shift 2 ;;
        --subscription-id)  SUBSCRIPTION_ID="$2"; shift 2 ;;
        --resource-group)   RESOURCE_GROUP="$2"; shift 2 ;;
        --location)         LOCATION="$2"; shift 2 ;;
        --cluster-name)     CLUSTER_NAME="$2"; shift 2 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

# ── 1. Install K3s ──────────────────────────────────────────────────
echo "[1/4] Installing K3s..."
if ! command -v k3s &> /dev/null; then
    curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644
    echo "  K3s installed"
    # Wait for K3s to be ready
    echo "  Waiting for K3s to be ready..."
    sleep 15
    kubectl wait --for=condition=Ready node --all --timeout=120s
else
    echo "  K3s already installed"
fi

echo "  K3s status:"
kubectl get nodes

# ── 2. Install Azure CLI ────────────────────────────────────────────
echo "[2/4] Installing Azure CLI..."
if ! command -v az &> /dev/null; then
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
    echo "  Azure CLI installed"
else
    echo "  Azure CLI already installed"
fi

# ── 3. Install connectedk8s extension ───────────────────────────────
echo "[3/4] Installing Azure CLI connectedk8s extension..."
az extension add --name connectedk8s --yes 2>/dev/null || az extension update --name connectedk8s --yes

# ── 4. Connect K3s cluster to Azure Arc ─────────────────────────────
echo "[4/4] Connecting K3s cluster to Azure Arc..."

if [[ -z "$TENANT_ID" || -z "$SUBSCRIPTION_ID" || -z "$RESOURCE_GROUP" || -z "$LOCATION" ]]; then
    echo ""
    echo "Missing required parameters. Run with:"
    echo "  sudo ./Install-ArcK8s.sh \\"
    echo "    --tenant-id <your-tenant-id> \\"
    echo "    --subscription-id <your-subscription-id> \\"
    echo "    --resource-group <your-rg> \\"
    echo "    --location australiaeast \\"
    echo "    --cluster-name $CLUSTER_NAME"
    echo ""
    echo "K3s is installed and running. Connect to Arc manually when ready."
    exit 0
fi

# Set kubeconfig for az CLI
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

az login --tenant "$TENANT_ID"
az account set --subscription "$SUBSCRIPTION_ID"

az connectedk8s connect \
    --name "$CLUSTER_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --tags "project=arc-connectivity-demo" "environment=lab"

echo ""
echo "SUCCESS: K3s cluster '$CLUSTER_NAME' is now an Azure Arc-enabled Kubernetes cluster!"
echo "Check: Azure Portal > Azure Arc > Kubernetes clusters"
echo ""
echo "Next steps:"
echo "  - Enable GitOps: az k8s-configuration flux create ..."
echo "  - Enable monitoring: az k8s-extension create --extension-type Microsoft.AzureMonitor.Containers ..."
echo "  - Enable Azure Policy: az k8s-extension create --extension-type Microsoft.PolicyInsights ..."
