terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }
}

provider "azurerm" {
  features {}
  
  subscription_id = var.azure_subscription_id
  tenant_id       = var.azure_tenant_id
  client_id       = var.azure_client_id
  client_secret   = var.azure_client_secret
}

data "azurerm_client_config" "current" {}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "${var.cluster_name}-rg"
  location = var.azure_location
  
  tags = merge(var.tags, {
    Environment = var.environment
  })
}

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = "${var.cluster_name}-vnet"
  address_space       = [var.vnet_cidr]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  tags = merge(var.tags, {
    Environment = var.environment
  })
}

# Subnet for AKS
resource "azurerm_subnet" "aks" {
  name                 = "${var.cluster_name}-aks-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.aks_subnet_cidr]
}

# Subnet for Azure services
resource "azurerm_subnet" "services" {
  name                 = "${var.cluster_name}-services-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.services_subnet_cidr]
  
  delegation {
    name = "postgres-delegation"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# Network Security Group
resource "azurerm_network_security_group" "aks" {
  name                = "${var.cluster_name}-aks-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  security_rule {
    name                       = "AllowHTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  tags = merge(var.tags, {
    Environment = var.environment
  })
}

# Associate NSG with AKS subnet
resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.aks.id
  network_security_group_id = azurerm_network_security_group.aks.id
}

# Log Analytics Workspace for AKS monitoring
resource "azurerm_log_analytics_workspace" "aks" {
  name                = "${var.cluster_name}-logs"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  
  tags = merge(var.tags, {
    Environment = var.environment
  })
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version
  
  default_node_pool {
    name                = "system"
    node_count          = var.system_node_count
    vm_size             = var.system_node_size
    vnet_subnet_id      = azurerm_subnet.aks.id
    enable_auto_scaling = true
    min_count           = 1
    max_count           = 5
    
    node_labels = {
      "nodepool" = "system"
    }
  }
  
  # n8n Main node pool
  node_pool {
    name                = "n8nmain"
    node_count          = var.main_node_count
    vm_size             = var.main_node_size
    vnet_subnet_id      = azurerm_subnet.aks.id
    enable_auto_scaling = true
    min_count           = 2
    max_count           = 4
    
    node_labels = {
      "nodepool" = "n8n-main"
      "role"     = "main"
    }
    
    node_taints = [
      "n8n.io/main=true:NoSchedule"
    ]
  }
  
  # n8n Worker node pool
  node_pool {
    name                = "n8nworker"
    node_count          = var.worker_node_count
    vm_size             = var.worker_node_size
    vnet_subnet_id      = azurerm_subnet.aks.id
    enable_auto_scaling = true
    min_count           = 2
    max_count           = 20
    
    node_labels = {
      "nodepool" = "n8n-worker"
      "role"     = "worker"
    }
    
    node_taints = [
      "n8n.io/worker=true:NoSchedule"
    ]
  }
  
  identity {
    type = "SystemAssigned"
  }
  
  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
  }
  
  azure_policy_enabled = true
  
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.aks.id
  }
  
  tags = merge(var.tags, {
    Environment = var.environment
  })
}

# Azure Cache for Redis
resource "azurerm_redis_cache" "main" {
  name                = "${var.cluster_name}-redis"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  capacity            = var.redis_capacity
  family              = var.redis_family
  sku_name            = var.redis_sku_name
  enable_non_ssl_port = false
  minimum_tls_version = "1.2"
  
  redis_configuration {
    enable_authentication           = true
    maxmemory_reserved              = var.redis_maxmemory_reserved
    maxmemory_delta                 = var.redis_maxmemory_delta
    maxmemory_policy               = "allkeys-lru"
    rdb_backup_enabled             = true
    rdb_backup_frequency           = 60
    rdb_backup_max_snapshot_count  = 1
    rdb_storage_connection_string  = azurerm_storage_account.redis_backup.primary_blob_connection_string
  }
  
  tags = merge(var.tags, {
    Environment = var.environment
  })
}

# Storage account for Redis backups
resource "azurerm_storage_account" "redis_backup" {
  name                     = "${replace(var.cluster_name, "-", "")}redisbackup"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  tags = merge(var.tags, {
    Environment = var.environment
  })
}

# Private DNS Zone for PostgreSQL
resource "azurerm_private_dns_zone" "postgres" {
  name                = "${var.cluster_name}.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.main.name
  
  tags = merge(var.tags, {
    Environment = var.environment
  })
}

# Link DNS zone to VNet
resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "${var.cluster_name}-postgres-link"
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.main.id
  resource_group_name   = azurerm_resource_group.main.name
  
  tags = merge(var.tags, {
    Environment = var.environment
  })
}

# PostgreSQL Flexible Server
resource "azurerm_postgresql_flexible_server" "main" {
  name                   = "${var.cluster_name}-postgres"
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  version                = var.postgres_version
  delegated_subnet_id    = azurerm_subnet.services.id
  private_dns_zone_id    = azurerm_private_dns_zone.postgres.id
  administrator_login    = var.postgres_admin_username
  administrator_password = var.postgres_admin_password
  zone                   = "1"
  
  storage_mb = var.postgres_storage_mb
  sku_name   = var.postgres_sku_name
  
  backup_retention_days        = 7
  geo_redundant_backup_enabled = false
  
  high_availability {
    mode = "ZoneRedundant"
  }
  
  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]
  
  tags = merge(var.tags, {
    Environment = var.environment
  })
}

# PostgreSQL Database
resource "azurerm_postgresql_flexible_server_database" "n8n" {
  name      = "n8n"
  server_id = azurerm_postgresql_flexible_server.main.id
  collation = "en_US.utf8"
  charset   = "utf8"
}

# Key Vault for secrets
resource "azurerm_key_vault" "main" {
  name                       = "${var.cluster_name}-kv"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  purge_protection_enabled   = false
  soft_delete_retention_days = 7
  
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id
    
    secret_permissions = [
      "Get",
      "List",
      "Set",
      "Delete",
      "Purge",
      "Recover"
    ]
  }
  
  # Access policy for AKS
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
    
    secret_permissions = [
      "Get",
      "List"
    ]
  }
  
  tags = merge(var.tags, {
    Environment = var.environment
  })
}

# Random passwords
resource "random_password" "n8n_encryption_key" {
  length  = 32
  special = false
}

resource "random_password" "n8n_auth_password" {
  length  = 16
  special = true
}

# Store secrets in Key Vault
resource "azurerm_key_vault_secret" "n8n_encryption_key" {
  name         = "n8n-encryption-key"
  value        = random_password.n8n_encryption_key.result
  key_vault_id = azurerm_key_vault.main.id
  
  tags = merge(var.tags, {
    Environment = var.environment
  })
}

resource "azurerm_key_vault_secret" "postgres_password" {
  name         = "postgres-password"
  value        = var.postgres_admin_password
  key_vault_id = azurerm_key_vault.main.id
  
  tags = merge(var.tags, {
    Environment = var.environment
  })
}

resource "azurerm_key_vault_secret" "redis_password" {
  name         = "redis-password"
  value        = azurerm_redis_cache.main.primary_access_key
  key_vault_id = azurerm_key_vault.main.id
  
  tags = merge(var.tags, {
    Environment = var.environment
  })
}

resource "azurerm_key_vault_secret" "n8n_auth_password" {
  name         = "n8n-auth-password"
  value        = random_password.n8n_auth_password.result
  key_vault_id = azurerm_key_vault.main.id
  
  tags = merge(var.tags, {
    Environment = var.environment
  })
} 