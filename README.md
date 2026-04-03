# Azure Arc Connectivity Demo

Multi-scenario demo environment for Azure Arc using nested Hyper-V virtualisation on a single Azure VM. Demonstrates Arc-enabled servers, Arc-enabled SQL Server, and Arc-enabled Kubernetes — all running as "on-premises" VMs inside a Hyper-V host.

![Architecture](docs/architecture.png)

## 🎯 Why This Demo Exists

Azure Arc extends Azure management to resources running **outside** of Azure. But demoing Arc with native Azure VMs defeats the purpose — the whole point is managing non-Azure infrastructure. This lab uses **nested virtualisation** so the guest VMs genuinely appear as on-premises machines to Arc.

## 🏗️ Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                     Azure (Resource Group)                           │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │              Hyper-V Host (D16s_v5 / Win Server 2025)        │    │
│  │              16 vCPU, 64 GB RAM, 256 GB SSD                  │    │
│  │                                                              │    │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────────────────┐  │    │
│  │  │ ArcWin2025 │  │ ArcWin2022 │  │      ArcUbuntu         │  │    │
│  │  │ Win 2025   │  │ Win 2022   │  │    Ubuntu 22.04        │  │    │
│  │  │ 2C / 4GB   │  │ 2C / 4GB   │  │    2C / 4GB            │  │    │
│  │  │            │  │            │  │                        │  │    │
│  │  │ Arc Server │  │ Arc Server │  │    Arc Server           │  │    │
│  │  └────────────┘  └────────────┘  └────────────────────────┘  │    │
│  │                                                              │    │
│  │  ┌────────────────────┐  ┌──────────────────────────────┐    │    │
│  │  │     ArcSQL          │  │         ArcK3s               │    │    │
│  │  │  Win 2022 + SQL     │  │    Ubuntu 22.04 + K3s        │    │    │
│  │  │  2C / 8GB           │  │    2C / 8GB                  │    │    │
│  │  │                     │  │                              │    │    │
│  │  │  Arc SQL Server     │  │    Arc-enabled Kubernetes    │    │    │
│  │  └────────────────────┘  └──────────────────────────────┘    │    │
│  │                                                              │    │
│  │  Internal vSwitch ──── NAT ──── Internet                     │    │
│  └──────────────────────────────────────────────────────────────┘    │
│                                                                      │
│  ┌─────────────┐  ┌──────────────────┐  ┌───────────────────────┐   │
│  │   Bastion    │  │  Log Analytics   │  │  Azure Policy         │   │
│  │  (Developer) │  │  Workspace       │  │  Guest Config         │   │
│  └─────────────┘  └──────────────────┘  └───────────────────────┘   │
└──────────────────────────────────────────────────────────────────────┘
```

## 📋 Demo Scenarios

### Scenario 1: Arc-Enabled Servers
**Covers:** Windows + Linux server onboarding and management
- Install the Connected Machine Agent (manual + scripted)
- View Arc-enabled servers in Azure Portal
- SSH access through Arc (no public IP needed)
- Run commands remotely via Arc
- Azure Policy guest configuration for compliance auditing
- Azure Monitor agent deployment via Arc extensions
- Azure Update Manager for OS patching
- Tagging, inventory, and resource organisation

### Scenario 2: Arc-Enabled SQL Server
**Covers:** SQL Server discovery, management, and security
- Onboard SQL Server 2022 to Azure Arc
- SQL Server best practices assessment
- Microsoft Defender for SQL
- Performance dashboard and monitoring
- License management (PAYG vs. license-included)

### Scenario 3: Arc-Enabled Kubernetes
**Covers:** Hybrid Kubernetes management
- Onboard K3s cluster to Azure Arc
- GitOps with Flux v2 (deploy apps from Git)
- Azure Policy on non-AKS clusters
- Azure Monitor Container Insights
- Cluster Connect for secure kubectl access from Azure

## 📁 Repository Structure

```
arc-connectivity-demo/
├── README.md
├── terraform/                       # Infrastructure as Code
│   ├── main.tf                      # Core resources (RG, VNet, NSG)
│   ├── hyperv-host.tf               # Hyper-V host VM + managed disk
│   ├── bastion.tf                   # Azure Bastion (Developer SKU)
│   ├── monitoring.tf                # Log Analytics + policies
│   ├── providers.tf                 # Provider config
│   ├── variables.tf                 # Input variables
│   ├── outputs.tf                   # Useful outputs
│   └── terraform.tfvars.example     # Example values (no secrets)
├── scripts/
│   ├── Configure-HyperVHost.ps1     # Hyper-V role + vSwitch + NAT setup
│   ├── Deploy-NestedVMs.ps1         # Create and configure all nested VMs
│   ├── Install-ArcAgent.ps1         # Onboard Windows VMs to Arc
│   ├── Install-ArcAgent-Linux.sh    # Onboard Linux VMs to Arc
│   ├── Install-ArcSQL.ps1           # Onboard SQL Server to Arc
│   ├── Install-ArcK8s.sh            # Install K3s + onboard to Arc
│   └── dsc/
│       └── HyperVHostConfig.ps1     # DSC configuration for host setup
├── scenarios/
│   ├── 01-arc-servers/
│   │   └── README.md                # Step-by-step Arc servers demo guide
│   ├── 02-arc-sql/
│   │   └── README.md                # Step-by-step Arc SQL demo guide
│   └── 03-arc-kubernetes/
│       └── README.md                # Step-by-step Arc K8s demo guide
├── docs/
│   ├── architecture.png             # Architecture diagram
│   └── setup-guide.md               # Full deployment walkthrough
└── .gitignore
```

## 🔧 Infrastructure

| Resource | Spec | Purpose | Est. Cost |
|----------|------|---------|-----------|
| **Hyper-V Host** | D16s_v5, 16 vCPU, 64GB | Hosts all nested VMs | ~$12/day |
| **OS Disk** | 128GB Premium SSD | Host OS | included |
| **Data Disk** | 256GB Premium SSD | VHDs for nested VMs | ~$1.50/day |
| **Bastion** | Developer SKU | Secure access (no public RDP) | ~$1.50/day |
| **Log Analytics** | Pay-as-you-go | Monitoring workspace | ~$0.10/day |
| **NSG** | Standard | Network security | free |
| **Total** | | | **~$15/day** |

## 🚀 Quick Start

```bash
# 1. Deploy infrastructure
cd terraform
terraform init -backend-config=~/workspace/tfvars/backend.hcl
terraform plan -var-file=~/workspace/tfvars/arc-connectivity.tfvars -out=tfplan
terraform apply tfplan

# 2. Connect to Hyper-V host via Bastion
#    (Bastion Developer SKU — no public IP on the host VM)

# 3. Nested VMs auto-provision via Custom Script Extension
#    Wait ~15 min for all 5 VMs to come up

# 4. Follow scenario guides in scenarios/
```

## 📊 Demo Flow

### Setup (~20 min)
1. Deploy infrastructure via Terraform
2. Connect to Hyper-V host via Bastion
3. Verify all 5 nested VMs are running in Hyper-V Manager
4. Confirm internet connectivity from nested VMs

### Arc Servers Demo (~15 min)
1. Show the nested VMs — they look like on-prem machines
2. Run the Arc onboarding script on Windows + Linux guests
3. Show them appearing in Azure Portal → Arc → Servers
4. Demo SSH through Arc, run commands, view compliance

### Arc SQL Demo (~10 min)
1. Show SQL Server running on the ArcSQL VM
2. Onboard to Arc-enabled SQL Server
3. Show best practices assessment + Defender integration

### Arc Kubernetes Demo (~10 min)
1. Show K3s running on ArcK3s VM
2. Onboard to Arc-enabled Kubernetes
3. Deploy a sample app via GitOps from Azure
4. Show Container Insights metrics

### Wrap-up (~5 min)
- Single pane of glass: all resources visible in Azure Portal
- Arc manages servers, SQL, and Kubernetes from one place
- No VPN, no ExpressRoute — just the Arc agent

## 📚 References

- [Azure Arc Overview](https://learn.microsoft.com/en-us/azure/azure-arc/overview)
- [Arc-enabled Servers](https://learn.microsoft.com/en-us/azure/azure-arc/servers/overview)
- [Arc-enabled SQL Server](https://learn.microsoft.com/en-us/sql/sql-server/azure-arc/overview)
- [Arc-enabled Kubernetes](https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/overview)
- [Nested Virtualisation in Azure](https://learn.microsoft.com/en-us/azure/virtual-machines/acu)
- [Arc Jumpstart ArcBox](https://jumpstart.azure.com/azure_jumpstart_arcbox)
- [Connected Machine Agent](https://learn.microsoft.com/en-us/azure/azure-arc/servers/agent-overview)
