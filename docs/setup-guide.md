# Deployment Setup Guide

Full walkthrough for deploying the Arc Connectivity Demo lab.

## Prerequisites

- Azure subscription with at least 16 DSv5 vCPUs in your target region
- `az` CLI installed and authenticated
- `terraform` >= 1.5
- Access to Windows Server and Ubuntu ISOs/VHDs (evaluation editions are fine)

## Step 1: Check vCPU Quota

```bash
az vm list-usage --location australiaeast --output table | grep -i "Standard DSv5"
```

You need at least **16 vCPUs** available for the Standard_D16s_v5 host.

## Step 2: Register Resource Providers

```bash
az provider register --namespace Microsoft.HybridCompute --wait
az provider register --namespace Microsoft.GuestConfiguration --wait
az provider register --namespace Microsoft.Kubernetes --wait
az provider register --namespace Microsoft.KubernetesConfiguration --wait
az provider register --namespace Microsoft.ExtendedLocation --wait
az provider register --namespace Microsoft.AzureArcData --wait
```

## Step 3: Create Service Principal for Arc Onboarding

```bash
SP=$(az ad sp create-for-rbac \
  --name "arc-connectivity-demo-sp" \
  --role "Azure Connected Machine Onboarding" \
  --scopes "/subscriptions/<your-sub-id>" \
  --output json)

echo $SP | jq .
# Save appId and password — you'll need them on the nested VMs
```

## Step 4: Deploy with Terraform

```bash
# Copy example tfvars
cp terraform/terraform.tfvars.example ~/workspace/tfvars/arc-connectivity.tfvars
# Edit with your values
vim ~/workspace/tfvars/arc-connectivity.tfvars

# Deploy
cd terraform
terraform init -backend-config=~/workspace/tfvars/backend.hcl
terraform plan -var-file=~/workspace/tfvars/arc-connectivity.tfvars -out=tfplan
terraform apply tfplan
```

## Step 5: Connect to the Hyper-V Host

Use Azure Bastion (Developer SKU) from the Azure Portal:
1. Azure Portal → Virtual Machines → select the host VM
2. Connect → Bastion
3. Enter credentials

## Step 6: Wait for Bootstrap

The Custom Script Extension runs automatically:
1. Installs Hyper-V role → reboots
2. Creates internal vSwitch + NAT
3. Creates 5 nested VMs

Check progress:
```powershell
Get-Content C:\ArcLab\bootstrap.log
Get-Content C:\ArcLab\deploy-vms.log
```

## Step 7: Install OS on Nested VMs

The VMs are created with empty VHDs. You need to:
1. Download evaluation ISOs or pre-built VHDs
2. Mount ISOs to VMs via Hyper-V Manager
3. Install the OS
4. Configure static IPs as per `C:\ArcLab\vm-config.json`

### Recommended: Pre-built VHDs
For faster setup, use pre-sysprepped VHDs:
- [Windows Server 2025 Evaluation VHD](https://www.microsoft.com/en-us/evalcenter/download-windows-server-2025)
- [Windows Server 2022 Evaluation VHD](https://www.microsoft.com/en-us/evalcenter/download-windows-server-2022)
- [Ubuntu 22.04 Cloud Image](https://cloud-images.ubuntu.com/jammy/current/)

## Step 8: Follow the Scenario Guides

1. [Scenario 1: Arc-Enabled Servers](../scenarios/01-arc-servers/README.md)
2. [Scenario 2: Arc-Enabled SQL Server](../scenarios/02-arc-sql/README.md)
3. [Scenario 3: Arc-Enabled Kubernetes](../scenarios/03-arc-kubernetes/README.md)

## Cleanup

```bash
cd terraform
terraform destroy -var-file=~/workspace/tfvars/arc-connectivity.tfvars
```

**Also clean up Arc resources** (they persist after VM deletion):
```bash
az resource list --resource-group <rg> --resource-type Microsoft.HybridCompute/machines --output table
# Delete each Arc resource
az resource delete --ids <resource-id>
```
