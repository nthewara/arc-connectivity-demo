# Scenario 1: Arc-Enabled Servers

Step-by-step guide for onboarding Windows and Linux nested VMs to Azure Arc-enabled servers.

## Prerequisites

- Hyper-V host deployed and nested VMs running
- OS installed on ArcWin2025, ArcWin2022, and ArcUbuntu
- Static IPs configured (192.168.100.10-12)
- Internet access working from nested VMs (via NAT)
- Service principal created with `Azure Connected Machine Onboarding` role

## Create Service Principal

```bash
# On your workstation (not on the nested VMs)
az ad sp create-for-rbac \
  --name "arc-connectivity-demo-sp" \
  --role "Azure Connected Machine Onboarding" \
  --scopes "/subscriptions/<subscription-id>/resourceGroups/<rg-name>"
```

Save the `appId` and `password` — you'll use them in the onboarding scripts.

## Step 1: Onboard Windows Server 2025

1. Connect to the Hyper-V host via Bastion
2. Open Hyper-V Manager → connect to **ArcWin2025**
3. Open PowerShell as Administrator and run:

```powershell
C:\ArcLab\scripts\Install-ArcAgent.ps1 `
  -TenantId "<your-tenant-id>" `
  -SubscriptionId "<your-subscription-id>" `
  -ResourceGroup "<your-rg>" `
  -Location "australiaeast" `
  -ServicePrincipalId "<sp-app-id>" `
  -ServicePrincipalSecret "<sp-password>"
```

4. Verify in Azure Portal → Azure Arc → Servers

## Step 2: Onboard Windows Server 2022

Repeat the same process on **ArcWin2022** (192.168.100.11).

## Step 3: Onboard Ubuntu 22.04

1. Connect to **ArcUbuntu** via Hyper-V console or SSH from the host
2. Run:

```bash
sudo bash /mnt/scripts/Install-ArcAgent-Linux.sh \
  --tenant-id "<your-tenant-id>" \
  --subscription-id "<your-subscription-id>" \
  --resource-group "<your-rg>" \
  --location "australiaeast" \
  --service-principal-id "<sp-app-id>" \
  --service-principal-secret "<sp-password>"
```

## Step 4: Demo — Azure Management Capabilities

Once all 3 servers are onboarded, demonstrate:

### SSH Access via Arc
```bash
az ssh arc --resource-group <rg> --name ArcUbuntu
```

### Run Commands
```bash
az connectedmachine run-command create \
  --resource-group <rg> --machine-name ArcWin2025 \
  --run-command-name "check-uptime" \
  --script "systeminfo | findstr /B /C:\"System Boot Time\""
```

### Azure Policy Guest Configuration
- Show compliance state in Azure Portal → Azure Arc → Servers → select a machine → Policies
- Built-in policies: audit password policy, installed software, open ports

### Azure Update Manager
- Azure Portal → Azure Arc → Servers → select machine → Updates
- Show available patches, schedule update deployment

### Azure Monitor
- If AMA policy is assigned (deployed by Terraform), the agent auto-deploys
- Show VM Insights, performance metrics, log queries

## Key Demo Talking Points

- "These machines have no public IP, no VPN, no ExpressRoute"
- "The Arc agent establishes an outbound HTTPS connection to Azure — that's it"
- "Once connected, they get the same management plane as native Azure VMs"
- "Policy compliance, patching, monitoring — all from one portal"
