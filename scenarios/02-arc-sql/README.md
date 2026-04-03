# Scenario 2: Arc-Enabled SQL Server

Step-by-step guide for onboarding SQL Server 2022 to Azure Arc.

## Prerequisites

- ArcSQL VM running with Windows Server 2022 + SQL Server 2022 installed
- Arc Connected Machine Agent already installed (Scenario 1)
- Internet access from the VM

## Step 1: Verify Arc Agent is Connected

On the ArcSQL VM, run:

```powershell
& "$env:ProgramW6432\AzureConnectedMachineAgent\azcmagent.exe" show
```

Should show `Status: Connected`.

## Step 2: Install the SQL Server Extension

### Option A: Azure Portal
1. Azure Portal → Azure Arc → SQL Server → **+ Add**
2. Select the Arc-enabled server (ArcSQL)
3. Configure:
   - License type: **Pay-as-you-go** (for demo)
   - Enable best practices assessment: **Yes**
   - Enable Defender for SQL: **Yes**

### Option B: Azure CLI
```bash
az connectedmachine extension create \
  --machine-name ArcSQL \
  --resource-group <rg> \
  --name "WindowsAgent.SqlServer" \
  --type "WindowsAgent.SqlServer" \
  --publisher "Microsoft.AzureData" \
  --location "australiaeast" \
  --settings '{"LicenseType":"PAYG","enableBPA":true}'
```

## Step 3: Demo — SQL Server Management

### Best Practices Assessment
- Portal → Azure Arc → SQL Server → select instance → Best practices assessment
- Shows recommendations for performance, security, availability

### Microsoft Defender for SQL
- Portal → Azure Arc → SQL Server → select instance → Security
- Shows vulnerability assessment, threat detection alerts
- To trigger a test alert, run this SQL query on the VM:
  ```sql
  -- Triggers a SQL injection detection alert
  EXEC sp_executesql N'SELECT * FROM sys.databases WHERE name = ''' + 'test' + ''''
  ```

### Performance Dashboard
- Portal → Azure Arc → SQL Server → select instance → Performance dashboard
- Shows CPU, memory, I/O, wait stats

### Inventory
- Shows SQL Server version, edition, databases, features installed
- All visible from Azure without connecting directly to the VM

## Key Demo Talking Points

- "SQL Server running on-prem, but managed from Azure"
- "Best practices assessment runs automatically — no SSMS needed"
- "Defender for SQL gives the same threat protection as Azure SQL"
- "License management: track SQL Server instances across your estate"
- "Pay-as-you-go licensing available through Arc — no SA required"
