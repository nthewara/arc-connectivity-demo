output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "host_public_ip" {
  value = azurerm_public_ip.host.ip_address
}

output "host_vm_name" {
  value = azurerm_windows_virtual_machine.host.name
}

output "host_vm_id" {
  value = azurerm_windows_virtual_machine.host.id
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.main.id
}

output "bastion_name" {
  value = var.deploy_bastion ? azurerm_bastion_host.main[0].name : "not deployed"
}
