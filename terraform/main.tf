resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}

locals {
  name_suffix = random_string.suffix.result
  rg_name     = "${var.prefix}-${local.name_suffix}"
}

# ─── Resource Group ──────────────────────────────────────────────────
resource "azurerm_resource_group" "main" {
  name     = local.rg_name
  location = var.location
  tags     = var.tags
}

# ─── Virtual Network ─────────────────────────────────────────────────
resource "azurerm_virtual_network" "main" {
  name                = "${var.prefix}-vnet-${local.name_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.0.0.0/16"]
  tags                = var.tags
}

resource "azurerm_subnet" "host" {
  name                 = "HostSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "bastion" {
  count                = var.deploy_bastion ? 1 : 0
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/26"]
}

# ─── NSG ─────────────────────────────────────────────────────────────
resource "azurerm_network_security_group" "host" {
  name                = "${var.prefix}-nsg-${local.name_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_network_security_rule" "allow_rdp" {
  name                        = "Allow-RDP-Home"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "3389"
  source_address_prefix       = var.home_ip
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.host.name
}

resource "azurerm_subnet_network_security_group_association" "host" {
  subnet_id                 = azurerm_subnet.host.id
  network_security_group_id = azurerm_network_security_group.host.id
}

# ─── Log Analytics ───────────────────────────────────────────────────
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.prefix}-law-${local.name_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}
