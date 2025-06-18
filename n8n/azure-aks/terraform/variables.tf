# Azure AKS Terraform Variables

# Azure Authentication
variable "azure_subscription_id" {
  description = "Azure subscription ID"
  type        = string
  sensitive   = true
}

variable "azure_tenant_id" {
  description = "Azure tenant ID"
  type        = string
  sensitive   = true
}

variable "azure_client_id" {
  description = "Azure client ID (service principal)"
  type        = string
  sensitive   = true
}

variable "azure_client_secret" {
  description = "Azure client secret (service principal)"
  type        = string
  sensitive   = true
}

# Azure Configuration
variable "azure_location" {
  description = "Azure region for resources"
  type        = string
  default     = "East US"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
  default     = "n8n-dev"
}

variable "kubernetes_version" {
  description = "Kubernetes version for AKS cluster"
  type        = string
  default     = "1.28.5"
}

# Networking
variable "vnet_cidr" {
  description = "CIDR block for VNet"
  type        = string
  default     = "10.0.0.0/16"
}

variable "aks_subnet_cidr" {
  description = "CIDR block for AKS subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "services_subnet_cidr" {
  description = "CIDR block for Azure services subnet"
  type        = string
  default     = "10.0.2.0/24"
}

# AKS Node Pools
variable "system_node_count" {
  description = "Number of nodes in system node pool"
  type        = number
  default     = 2
}

variable "system_node_size" {
  description = "VM size for system node pool"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "main_node_count" {
  description = "Number of nodes in n8n main node pool"
  type        = number
  default     = 2
}

variable "main_node_size" {
  description = "VM size for n8n main node pool"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "worker_node_count" {
  description = "Number of nodes in n8n worker node pool"
  type        = number
  default     = 3
}

variable "worker_node_size" {
  description = "VM size for n8n worker node pool"
  type        = string
  default     = "Standard_D8s_v3"
}

# Redis Configuration
variable "redis_capacity" {
  description = "Capacity of Redis cache"
  type        = number
  default     = 1
}

variable "redis_family" {
  description = "Redis family (C, P)"
  type        = string
  default     = "C"
}

variable "redis_sku_name" {
  description = "Redis SKU name"
  type        = string
  default     = "Standard"
}

variable "redis_maxmemory_reserved" {
  description = "Redis max memory reserved"
  type        = number
  default     = 2
}

variable "redis_maxmemory_delta" {
  description = "Redis max memory delta"
  type        = number
  default     = 2
}

# PostgreSQL Configuration
variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "15"
}

variable "postgres_sku_name" {
  description = "PostgreSQL SKU name"
  type        = string
  default     = "B_Standard_B1ms"
}

variable "postgres_storage_mb" {
  description = "PostgreSQL storage in MB"
  type        = number
  default     = 32768
}

variable "postgres_admin_username" {
  description = "PostgreSQL administrator username"
  type        = string
  default     = "n8n_admin"
}

variable "postgres_admin_password" {
  description = "PostgreSQL administrator password"
  type        = string
  sensitive   = true
}

# Tags
variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default = {
    Terraform = "true"
    Project   = "n8n-scalable"
  }
} 