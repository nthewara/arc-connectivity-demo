variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "australiaeast"
}

variable "prefix" {
  description = "Naming prefix for all resources"
  type        = string
  default     = "arclab"
}

variable "admin_username" {
  description = "Admin username for the Hyper-V host VM"
  type        = string
  default     = "arcadmin"
}

variable "admin_password" {
  description = "Admin password for the Hyper-V host VM"
  type        = string
  sensitive   = true
}

variable "home_ip" {
  description = "Your home/office IP for NSG rules (CIDR, e.g. 1.2.3.4/32)"
  type        = string
}

variable "host_vm_size" {
  description = "VM size for the Hyper-V host (must support nested virtualisation)"
  type        = string
  default     = "Standard_D16s_v5"
}

variable "deploy_bastion" {
  description = "Deploy Azure Bastion for secure access"
  type        = bool
  default     = true
}

variable "auto_shutdown_time" {
  description = "Auto-shutdown time in HHMM format (UTC)"
  type        = string
  default     = "1000"
}

variable "tags" {
  description = "Tags for all resources"
  type        = map(string)
  default = {
    project     = "arc-connectivity-demo"
    environment = "lab"
  }
}
