# ─── Azure Bastion (Developer SKU) ───────────────────────────────────
# Developer SKU: no public IP on Bastion, connect via Azure Portal only
# Much cheaper than Standard SKU — perfect for lab environments

resource "azurerm_bastion_host" "main" {
  count               = var.deploy_bastion ? 1 : 0
  name                = "${var.prefix}-bastion-${local.name_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Developer"
  virtual_network_id  = azurerm_virtual_network.main.id
  tags                = var.tags
}
