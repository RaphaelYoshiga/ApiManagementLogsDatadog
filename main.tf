terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = ">= 2.26"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "apim_name" {
  type        = string
  description = "The APIM instance name"
}

variable "resource_group" {
  type        = string
  description = "The ResourceGroup"
}

variable "datadog_event_hub_namespace" {
  type        = string  
}

variable "datadog_event_hub" {
  type        = string  
}

variable "datadog_function_app" {
  type        = string  
}

variable "datadog_function_app_plan" {
  type        = string  
}

variable "datadog_tags" {
  type        = string  
}

variable "function_storage" {
  type        = string  
}

variable "datadog_api_key" {
  type        = string  
}

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group
  location = "westeurope"
}

resource "azurerm_api_management" "apim" {
  name                = var.apim_name
  location            = "uksouth"
  resource_group_name = azurerm_resource_group.rg.name
  publisher_name      = "RYoshiga"
  publisher_email     = "does_not_exists@none.com"

  sku_name = "Developer_1"
}

resource "azurerm_eventhub_namespace" "logs" {
  name                = var.datadog_event_hub_namespace
  location            = "uksouth"
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"
  capacity            = 1
}

resource "azurerm_eventhub" "logs" {
  name                = var.datadog_event_hub
  namespace_name      = azurerm_eventhub_namespace.logs.name
  resource_group_name = azurerm_resource_group.rg.name
  partition_count     = 1
  message_retention   = 1
}

resource "azurerm_eventhub_namespace_authorization_rule" "sender" {
  name                = "sender"
  namespace_name      = azurerm_eventhub_namespace.logs.name
  resource_group_name = azurerm_resource_group.rg.name

  listen = true
  send   = true
  manage = true
}

resource "azurerm_monitor_diagnostic_setting" "datadog" {
  name               = "datadog"
  target_resource_id = azurerm_api_management.apim.id
  eventhub_name      = var.datadog_event_hub
  eventhub_authorization_rule_id  = azurerm_eventhub_namespace_authorization_rule.sender.id

  log {
    category = "GatewayLogs"
    enabled  = true

    retention_policy {
      enabled = false
    }
  }
}

resource "azurerm_storage_account" "function" {
  name                     = var.function_storage
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = "uksouth"
  account_tier             = "Standard"
  account_replication_type = "GRS"
}

resource "azurerm_app_service_plan" "datadog" {
  name                = var.datadog_function_app_plan
  location            = "uksouth"
  resource_group_name = azurerm_resource_group.rg.name
  kind                = "FunctionApp"

  sku {
    tier = "Dynamic"
    size = "Y1"
  }
}

resource "azurerm_function_app" "function_account" {
  name                       = var.datadog_function_app
  location                   = azurerm_app_service_plan.datadog.location
  resource_group_name        = azurerm_resource_group.rg.name
  app_service_plan_id        = azurerm_app_service_plan.datadog.id
  storage_account_name       = azurerm_storage_account.function.name
  storage_account_access_key = azurerm_storage_account.function.primary_access_key
  version                    = "~3"
  
  app_settings               = {
    DD_SERVICE = "my-service"
    DD_SOURCE = "my-service-source"
    DD_SOURCE_CATEGORY = "my_source"
    DD_SITE = "datadoghq.eu"
    DD_TAGS = var.datadog_tags
    DD_API_KEY = var.datadog_api_key
    FUNCTIONS_WORKER_RUNTIME = "node"
    WEBSITE_NODE_DEFAULT_VERSION = "~12"
    "datadog-apim-test-logs_RootManageSharedAccessKey_EVENTHUB" = azurerm_eventhub_namespace_authorization_rule.sender.primary_connection_string
  }
  connection_string {
    name = "EventHubConnection"
    type = "EventHub"
    value = azurerm_eventhub_namespace_authorization_rule.sender.primary_connection_string
  }
}
