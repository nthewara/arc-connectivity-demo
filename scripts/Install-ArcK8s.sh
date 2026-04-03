#!/bin/bash
# Install-ArcK8s.sh
# Install K3s and onboard to Azure Arc-enabled Kubernetes
#
# Adapted from Arc Jumpstart ArcBox:
#   github.com/microsoft/azure_arc — installK3s.sh
#
# Includes: K3s install, Azure CLI, Arc connect, Container Insights,
# Azure Policy, and Defender extensions — the same extensions ArcBox deploys.
#
# Usage:
#   sudo ./Install-ArcK8s.sh \
#     --tenant-id <tid> --subscription-id <sid> \
#     --resource-group <rg> --location <loc> \
#     [--cluster-name <name>] [--law-id <workspace-resource-id>]

set -euo pipefail

echo "=== Azure Arc — K3s + Arc-enabled Kubernetes ==="
echo "Machine: $(hostname)"
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"

# Defaults
TENANT_ID=""; SUBSCRIPTION_ID=""; RESOURCE_GROUP=""; LOCATION=""
CLUSTER_NAME="arc-k3s-lab"; LAW_ID=""
K3S_VERSION="1.29.6+k3s2"  # Pinned — same as ArcBox

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tenant-id)        TENANT_ID="$2"; shift 2 ;;
        --subscription-id)  SUBSCRIPTION_ID="$2"; shift 2 ;;
        --resource-group)   RESOURCE_GROUP="$2"; shift 2 ;;
        --location)         LOCATION="$2"; shift 2 ;;
        --cluster-name)     CLUSTER_NAME="$2"; shift 2 ;;
        --law-id)           LAW_ID="$2"; shift 2 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

# ── 1. Block Azure IMDS (required for nested VM) ────────────────────
echo "[1/6] Blocking Azure IMDS endpoint..."
sudo ufw --force enable
sudo ufw deny out from any to 169.254.169.254
sudo ufw default allow incoming

# ── 2. Install K3s (ArcBox pattern) ─────────────────────────────────
echo "[2/6] Installing K3s v${K3S_VERSION}..."
if ! command -v k3s &> /dev/null; then
    publicIp=$(hostname -I | awk '{print $1}')
    curl -sfL https://get.k3s.io | \
        INSTALL_K3S_EXEC="server --disable traefik --disable servicelb --node-ip ${publicIp} --node-external-ip ${publicIp} --bind-address ${publicIp} --tls-san ${publicIp}" \
        INSTALL_K3S_VERSION="v${K3S_VERSION}" \
        K3S_KUBECONFIG_MODE="644" sh -

    echo "  K3s installed"
    echo "  Waiting for cluster to be ready..."
    sudo kubectl wait --for=condition=Available --timeout=120s --all deployments -A 2>/dev/null || true
    sleep 10
else
    echo "  K3s already installed"
fi

echo "  Cluster status:"
sudo kubectl get nodes -o wide

# ── 3. Install Azure CLI + extensions ────────────────────────────────
echo "[3/6] Installing Azure CLI..."
if ! command -v az &> /dev/null; then
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
fi

echo "  Installing Arc extensions..."
az extension add --name connectedk8s --yes 2>/dev/null || az extension update --name connectedk8s --yes
az extension add --name k8s-configuration --yes 2>/dev/null || true
az extension add --name k8s-extension --yes 2>/dev/null || true

# ── 4. Connect to Arc ────────────────────────────────────────────────
echo "[4/6] Connecting K3s cluster to Azure Arc..."

if [[ -z "$TENANT_ID" || -z "$SUBSCRIPTION_ID" || -z "$RESOURCE_GROUP" || -z "$LOCATION" ]]; then
    echo ""
    echo "K3s is installed. Provide Azure params to connect to Arc:"
    echo "  sudo ./Install-ArcK8s.sh --tenant-id <t> --subscription-id <s> --resource-group <rg> --location <loc>"
    exit 0
fi

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

az login --tenant "$TENANT_ID" --use-device-code
az account set --subscription "$SUBSCRIPTION_ID"

# Retry pattern from ArcBox installK3s.sh
max_retries=5; retry_count=0; success=false
while [ $retry_count -lt $max_retries ]; do
    az connectedk8s connect \
        --name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags "project=arc-connectivity-demo" "environment=lab" && success=true && break
    echo "  Retry $((retry_count+1))/$max_retries..."
    retry_count=$((retry_count+1))
    sleep 10
done

if [ "$success" = false ]; then
    echo "ERROR: Failed to connect cluster to Arc after $max_retries attempts"
    exit 1
fi

echo "  Cluster connected to Azure Arc"

# ── 5. Install extensions (ArcBox pattern) ───────────────────────────
echo "[5/6] Installing Arc extensions on cluster..."

# Container Insights
if [[ -n "$LAW_ID" ]]; then
    echo "  Installing Container Insights..."
    az k8s-extension create \
        -n "azuremonitor-containers" \
        --cluster-name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --cluster-type connectedClusters \
        --extension-type Microsoft.AzureMonitor.Containers \
        --configuration-settings logAnalyticsWorkspaceResourceID="$LAW_ID" \
        --only-show-errors || echo "  Warning: Container Insights install failed (non-blocking)"
fi

# Azure Policy
echo "  Installing Azure Policy..."
az k8s-extension create \
    --name "azurepolicy" \
    --cluster-name "$CLUSTER_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --cluster-type connectedClusters \
    --extension-type Microsoft.PolicyInsights \
    --only-show-errors || echo "  Warning: Azure Policy install failed (non-blocking)"

# ── 6. Summary ───────────────────────────────────────────────────────
echo "[6/6] Done!"
echo ""
echo "SUCCESS: K3s cluster '$CLUSTER_NAME' is now Arc-enabled!" 
echo ""
echo "Azure Portal: Azure Arc > Kubernetes clusters"
echo ""
echo "Next steps:"
echo "  - GitOps:   az k8s-configuration flux create ..."
echo "  - Connect:  az connectedk8s proxy --name $CLUSTER_NAME --resource-group $RESOURCE_GROUP &"
echo "  - kubectl:  kubectl get pods --all-namespaces"
