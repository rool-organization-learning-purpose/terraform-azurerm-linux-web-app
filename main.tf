# test
resource "azurerm_application_insights" "this" {
  count               = var.enable_appinsights ? 1 : 0
  name                = "web-${var.project}-${var.env}-${var.location}-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group
  application_type    = var.application_type
  workspace_id        = var.analytics_workspace_id
  tags                = var.tags
}

data "azurerm_monitor_diagnostic_categories" "this" {
  count       = var.enable_diagnostic_setting ? 1 : 0
  resource_id = azurerm_linux_web_app.this.id
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  count                          = var.enable_diagnostic_setting ? 1 : 0
  name                           = "web-${var.project}-${var.env}-${var.location}-${var.name}"
  target_resource_id             = azurerm_linux_web_app.this.id
  log_analytics_workspace_id     = var.analytics_workspace_id
  log_analytics_destination_type = var.analytics_destination_type

  dynamic "enabled_log" {
    for_each = data.azurerm_monitor_diagnostic_categories.this[0].log_category_types
    content {
      category = enabled_log.value
    }
  }

  dynamic "metric" {
    for_each = data.azurerm_monitor_diagnostic_categories.this[0].metrics
    content {
      category = metric.value
    }
  }
  lifecycle {
    ignore_changes = [log_analytics_destination_type] # TODO remove when issue is fixed: https://github.com/Azure/azure-rest-api-specs/issues/9281
  }
}

locals {
  app_settings = {
    WEBSITES_ENABLE_APP_SERVICE_STORAGE        = "true"
    WEBSITE_ENABLE_SYNC_UPDATE_SITE            = "true"
    JAVA_OPTS                                  = var.application_type == "java" ? "-Dlog4j2.formatMsgNoLookups=true" : null
    LOG4J_FORMAT_MSG_NO_LOOKUPS                = var.application_type == "java" ? "true" : null
    WEBSITE_USE_PLACEHOLDER                    = "0"
    AZURE_LOG_LEVEL                            = "info"
    APPINSIGHTS_INSTRUMENTATIONKEY             = var.enable_appinsights ? azurerm_application_insights.this[0].instrumentation_key : null
    ApplicationInsightsAgent_EXTENSION_VERSION = var.enable_appinsights && var.application_type == "java" ? "~3" : null
  }
  application_stack_struct = {
    docker_image        = null
    docker_image_tag    = null
    dotnet_version      = null
    java_server         = null
    java_server_version = null
    java_version        = null
    php_version         = null
    python_version      = null
    node_version        = null
    ruby_version        = null
  }
  application_stack = merge(local.application_stack_struct, var.application_stack)
}

resource "azurerm_linux_web_app" "this" {
  name                    = "web-${var.project}-${var.env}-${var.location}-${var.name}"
  location                = var.location
  resource_group_name     = var.resource_group
  service_plan_id         = var.service_plan_id
  https_only              = true
  enabled                 = true
  tags                    = var.tags
  app_settings            = merge(local.app_settings, var.app_settings)
  client_affinity_enabled = var.client_affinity_enabled

  identity {
    type         = var.identity_ids == null ? "SystemAssigned" : "SystemAssigned, UserAssigned"
    identity_ids = var.identity_ids
  }
  site_config {
    always_on                                     = var.site_config.always_on
    container_registry_managed_identity_client_id = var.site_config.container_registry_managed_identity_client_id
    container_registry_use_managed_identity       = var.site_config.container_registry_use_managed_identity
    ftps_state                                    = var.site_config.ftps_state
    http2_enabled                                 = var.site_config.http2_enabled
    use_32_bit_worker                             = var.site_config.use_32_bit_worker
    websockets_enabled                            = var.site_config.websockets_enabled
    worker_count                                  = var.site_config.worker_count
    dynamic "ip_restriction" {
      for_each = var.ip_restriction
      content {
        name                      = ip_restriction.value.name
        ip_address                = ip_restriction.value.ip_address
        service_tag               = ip_restriction.value.service_tag
        virtual_network_subnet_id = ip_restriction.value.virtual_network_subnet_id
        priority                  = ip_restriction.value.priority
        action                    = ip_restriction.value.action
        dynamic "headers" {
          for_each = ip_restriction.value.headers
          content {
            x_azure_fdid      = headers.value.x_azure_fdid
            x_fd_health_probe = headers.value.x_fd_health_probe
            x_forwarded_for   = headers.value.x_forwarded_for
            x_forwarded_host  = headers.value.x_forwarded_host
          }
        }
      }
    }
    dynamic "scm_ip_restriction" {
      for_each = var.scm_ip_restriction
      content {
        name                      = scm_ip_restriction.value.name
        ip_address                = scm_ip_restriction.value.ip_address
        service_tag               = scm_ip_restriction.value.service_tag
        virtual_network_subnet_id = scm_ip_restriction.value.virtual_network_subnet_id
        priority                  = scm_ip_restriction.value.priority
        action                    = scm_ip_restriction.value.action
        dynamic "headers" {
          for_each = scm_ip_restriction.value.headers
          content {
            x_azure_fdid      = headers.value.x_azure_fdid
            x_fd_health_probe = headers.value.x_fd_health_probe
            x_forwarded_for   = headers.value.x_forwarded_for
            x_forwarded_host  = headers.value.x_forwarded_host
          }
        }
      }
    }
    application_stack {
      docker_image        = local.application_stack["docker_image"]
      docker_image_tag    = local.application_stack["docker_image_tag"]
      dotnet_version      = local.application_stack["dotnet_version"]
      java_server         = local.application_stack["java_server"]
      java_server_version = local.application_stack["java_server_version"]
      java_version        = local.application_stack["java_version"]
      php_version         = local.application_stack["php_version"]
      python_version      = local.application_stack["python_version"]
      node_version        = local.application_stack["node_version"]
      ruby_version        = local.application_stack["ruby_version"]
    }
  }
  logs {
    detailed_error_messages = var.logs.detailed_error_messages
    failed_request_tracing  = var.logs.failed_request_tracing
    http_logs {
      file_system {
        retention_in_days = var.logs.http_logs.file_system.retention_in_days
        retention_in_mb   = var.logs.http_logs.file_system.retention_in_mb
      }
    }
  }
  dynamic "storage_account" {
    for_each = var.storage_account
    content {
      access_key   = storage_account.value.access_key
      account_name = storage_account.value.account_name
      name         = storage_account.value.name
      share_name   = storage_account.value.share_name
      type         = storage_account.value.type
      mount_path   = storage_account.value.mount_path
    }
  }

  lifecycle {
    ignore_changes = [
      tags["hidden-link: /app-insights-conn-string"],
      tags["hidden-link: /app-insights-instrumentation-key"],
      tags["hidden-link: /app-insights-resource-id"],
      virtual_network_subnet_id
    ]
  }
}

resource "azurerm_key_vault_access_policy" "this" {
  count               = var.key_vault.id == null ? 0 : 1
  key_vault_id        = var.key_vault.id
  tenant_id           = azurerm_linux_web_app.this.identity[0].tenant_id
  object_id           = azurerm_linux_web_app.this.identity[0].principal_id
  key_permissions     = var.key_vault.key_permissions
  secret_permissions  = var.key_vault.secret_permissions
  storage_permissions = var.key_vault.storage_permissions
}

resource "azurerm_app_service_virtual_network_swift_connection" "this" {
  count          = var.use_private_net ? 1 : 0
  app_service_id = azurerm_linux_web_app.this.id
  subnet_id      = var.subnet_id
}
