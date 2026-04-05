# ─── Azure Policy Assignments for Arc ────────────────────────────────
# These policies auto-deploy monitoring agents when Arc servers appear

resource "azurerm_resource_group_policy_assignment" "monitor_windows" {
  name                 = "deploy-ama-windows-arc"
  resource_group_id    = azurerm_resource_group.main.id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/94f686d6-9a24-4e19-91f1-de937dc171a4"
  display_name         = "Configure Windows Arc machines with Azure Monitor Agent"
  location             = azurerm_resource_group.main.location

  identity {
    type = "SystemAssigned"
  }

  parameters = jsonencode({})
}

resource "azurerm_resource_group_policy_assignment" "monitor_linux" {
  name                 = "deploy-ama-linux-arc"
  resource_group_id    = azurerm_resource_group.main.id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/845857af-0333-4c5d-bbbc-6076697da122"
  display_name         = "Configure Linux Arc machines with Azure Monitor Agent"
  location             = azurerm_resource_group.main.location

  identity {
    type = "SystemAssigned"
  }

  parameters = jsonencode({})
}
