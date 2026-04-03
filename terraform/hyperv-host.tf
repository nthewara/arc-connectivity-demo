# ─── Hyper-V Host VM ─────────────────────────────────────────────────

resource "azurerm_public_ip" "host" {
  name                = "${var.prefix}-host-pip-${local.name_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "host" {
  name                = "${var.prefix}-host-nic-${local.name_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.host.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.host.id
  }
}

resource "azurerm_windows_virtual_machine" "host" {
  name                  = "${var.prefix}-host-${local.name_suffix}"
  location              = azurerm_resource_group.main.location
  resource_group_name   = azurerm_resource_group.main.name
  size                  = var.host_vm_size
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  network_interface_ids = [azurerm_network_interface.host.id]
  tags                  = var.tags

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 128
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2025-datacenter-g2"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }

  # Allows the Custom Script Extension to run unattended
  provision_vm_agent       = true
  allow_extension_operations = true
}

# ─── Data Disk for VHDs ─────────────────────────────────────────────
resource "azurerm_managed_disk" "vhd_data" {
  name                 = "${var.prefix}-vhd-disk-${local.name_suffix}"
  location             = azurerm_resource_group.main.location
  resource_group_name  = azurerm_resource_group.main.name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = 256
  tags                 = var.tags
}

resource "azurerm_virtual_machine_data_disk_attachment" "vhd_data" {
  managed_disk_id    = azurerm_managed_disk.vhd_data.id
  virtual_machine_id = azurerm_windows_virtual_machine.host.id
  lun                = 0
  caching            = "ReadWrite"
}

# ─── Auto-Shutdown ───────────────────────────────────────────────────
resource "azurerm_dev_test_global_vm_shutdown_schedule" "host" {
  virtual_machine_id    = azurerm_windows_virtual_machine.host.id
  location              = azurerm_resource_group.main.location
  enabled               = true
  daily_recurrence_time = var.auto_shutdown_time
  timezone              = "UTC"

  notification_settings {
    enabled = false
  }

  tags = var.tags
}

# ─── Custom Script Extension — Bootstrap Hyper-V + Nested VMs ───────
resource "azurerm_virtual_machine_extension" "bootstrap" {
  name                 = "bootstrap-hyperv"
  virtual_machine_id   = azurerm_windows_virtual_machine.host.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = jsonencode({
    commandToExecute = "powershell -ExecutionPolicy Bypass -File C:\\ArcLab\\Configure-HyperVHost.ps1"
  })

  protected_settings = jsonencode({
    fileUris = [
      "https://raw.githubusercontent.com/nthewara/arc-connectivity-demo/main/scripts/Configure-HyperVHost.ps1",
      "https://raw.githubusercontent.com/nthewara/arc-connectivity-demo/main/scripts/Deploy-NestedVMs.ps1",
      "https://raw.githubusercontent.com/nthewara/arc-connectivity-demo/main/scripts/Install-ArcAgent.ps1",
      "https://raw.githubusercontent.com/nthewara/arc-connectivity-demo/main/scripts/Install-ArcAgent-Linux.sh",
      "https://raw.githubusercontent.com/nthewara/arc-connectivity-demo/main/scripts/Install-ArcSQL.ps1",
      "https://raw.githubusercontent.com/nthewara/arc-connectivity-demo/main/scripts/Install-ArcK8s.sh"
    ]
  })

  depends_on = [azurerm_virtual_machine_data_disk_attachment.vhd_data]
  tags       = var.tags
}
