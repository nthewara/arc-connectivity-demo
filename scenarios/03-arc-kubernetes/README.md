# Scenario 3: Arc-Enabled Kubernetes

Step-by-step guide for onboarding a K3s cluster to Azure Arc-enabled Kubernetes.

## Prerequisites

- ArcK3s VM running with Ubuntu 22.04
- K3s installed (the Install-ArcK8s.sh script handles this)
- Internet access from the VM
- Azure CLI installed with `connectedk8s` extension

## Step 1: Install K3s and Connect to Arc

On the ArcK3s VM, run:

```bash
sudo bash /mnt/scripts/Install-ArcK8s.sh \
  --tenant-id "<your-tenant-id>" \
  --subscription-id "<your-subscription-id>" \
  --resource-group "<your-rg>" \
  --location "australiaeast" \
  --cluster-name "arc-k3s-lab"
```

This installs K3s, Azure CLI, and connects the cluster to Arc.

## Step 2: Verify Connection

```bash
# On the VM
kubectl get nodes
kubectl get pods -n azure-arc

# From your workstation
az connectedk8s show --name arc-k3s-lab --resource-group <rg>
```

## Step 3: Deploy a Sample App via GitOps

### Create a GitOps Configuration (Flux v2)

```bash
az k8s-configuration flux create \
  --name sample-app \
  --cluster-name arc-k3s-lab \
  --resource-group <rg> \
  --cluster-type connectedClusters \
  --scope cluster \
  --namespace flux-system \
  --url https://github.com/Azure/arc-k8s-demo \
  --branch main \
  --kustomization name=app path=./manifests prune=true
```

This deploys a sample app from a Git repo — managed entirely from Azure.

## Step 4: Enable Monitoring

### Container Insights Extension

```bash
az k8s-extension create \
  --name azuremonitor-containers \
  --cluster-name arc-k3s-lab \
  --resource-group <rg> \
  --cluster-type connectedClusters \
  --extension-type Microsoft.AzureMonitor.Containers \
  --configuration-settings logAnalyticsWorkspaceResourceID="<law-id>"
```

## Step 5: Enable Azure Policy

```bash
az k8s-extension create \
  --name azure-policy \
  --cluster-name arc-k3s-lab \
  --resource-group <rg> \
  --cluster-type connectedClusters \
  --extension-type Microsoft.PolicyInsights
```

Then assign policies:
- "Kubernetes cluster should not allow privileged containers"
- "Kubernetes clusters should use internal load balancers"

## Step 6: Cluster Connect (Secure kubectl from Azure)

```bash
# From your workstation — no VPN or direct network needed
az connectedk8s proxy \
  --name arc-k3s-lab \
  --resource-group <rg> &

# Now use kubectl against the Arc proxy
kubectl get pods --all-namespaces
```

## Key Demo Talking Points

- "K3s running 'on-prem' — but managed from Azure"
- "GitOps deploys apps from Git, not kubectl apply — audit trail built in"
- "Same Container Insights experience as AKS, on any K8s cluster"
- "Azure Policy enforces compliance on non-AKS clusters"
- "Cluster Connect gives secure kubectl access without VPN or public endpoint"
- "All from a single control plane in the Azure Portal"
