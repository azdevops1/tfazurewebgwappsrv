# Generate a random integer to create a globally unique name
resource "random_integer" "ri" {
  min = 10000
  max = 99999
}

# Create the resource group
resource "azurerm_resource_group" "rg" {
  name     = "myResourceGroup-${random_integer.ri.result}"
  location = "eastus"
}
# Managed Service identity

resource "azurerm_user_assigned_identity" "agw" {
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  name                = "demo-hub-agw1-msi"
  #tags                = data.azurerm_resource_group.rg.tags
}

# Key Vault

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "agw" {
  name                       = "demo-hub-kv1-${random_integer.ri.result}"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  #soft_delete_enabled        = true #The EnableSoftDelete feature must be used for TLS termination to function properly. If you're configuring Key Vault soft-delete through the Portal, the retention period must be kept at 90 days, the default value. Application Gateway doesn't support a different retention period yet.
  soft_delete_retention_days = 90
  purge_protection_enabled   = false
  sku_name                   = "standard"
    access_policy {
        tenant_id = data.azurerm_client_config.current.tenant_id
        object_id = data.azurerm_client_config.current.object_id

        certificate_permissions = [
        "Create",
        "Delete",
        "DeleteIssuers",
        "Get",
        "GetIssuers",
        "Import",
        "List",
        "ListIssuers",
        "ManageContacts",
        "ManageIssuers",
        "Purge",
        "SetIssuers",
        "Update",
        ]

        key_permissions = [
        "Backup",
        "Create",
        "Decrypt",
        "Delete",
        "Encrypt",
        "Get",
        "Import",
        "List",
        "Purge",
        "Recover",
        "Restore",
        "Sign",
        "UnwrapKey",
        "Update",
        "Verify",
        "WrapKey",
        ]

        secret_permissions = [
        "Backup",
        "Delete",
        "Get",
        "List",
        "Purge",
        "Recover",
        "Restore",
        "Set",
        ]
  }

  #tags = data.azurerm_resource_group.rg.tags
}

/*resource "azurerm_key_vault_access_policy" "builder" {
  key_vault_id = azurerm_key_vault.agw.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  certificate_permissions = [
    "Create",
    "Get",
    "List",
  ]
}*/

resource "azurerm_key_vault_access_policy" "agw" {
  key_vault_id = azurerm_key_vault.agw.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.agw.principal_id

  certificate_permissions = [
    "Create",
    "Get",
    "List",
  ]

  secret_permissions = [
    "Get",
  ]
}

# Generate certificate for HTTPS

resource "azurerm_key_vault_certificate" "mywebapp" {
  name         = "mywebapp"
  key_vault_id = azurerm_key_vault.agw.id

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = true
    }

    lifetime_action {
      action {
        action_type = "AutoRenew"
      }

      trigger {
        days_before_expiry = 30
      }
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      # Server Authentication = 1.3.6.1.5.5.7.3.1
      # Client Authentication = 1.3.6.1.5.5.7.3.2
      extended_key_usage = ["1.3.6.1.5.5.7.3.1"]

      key_usage = [
        "cRLSign",
        "dataEncipherment",
        "digitalSignature",
        "keyAgreement",
        "keyCertSign",
        "keyEncipherment",
      ]

      subject_alternative_names {
        dns_names = ["mywebapp.com"]
      }

      subject            = "CN=mywebapp.com"
      validity_in_months = 12
    }
  }
}

# Time Sleep

resource "time_sleep" "wait_60_seconds" {
  depends_on = [azurerm_key_vault_certificate.mywebapp]

  create_duration = "60s"
}

# Create the Linux App Service Plan
resource "azurerm_service_plan" "appserviceplan" {
  name                = "webapp-asp-${random_integer.ri.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  os_type             = "Linux"
  sku_name            = "B1"
}

# Create the web app, pass in the App Service Plan ID
resource "azurerm_linux_web_app" "webapp" {
  name                  = "webapp-${random_integer.ri.result}"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  service_plan_id       = azurerm_service_plan.appserviceplan.id
  https_only            = false
  site_config { 
    minimum_tls_version = "1.2"
  }
}

#  Deploy code from a public GitHub repo
resource "azurerm_app_service_source_control" "sourcecontrol" {
  app_id             = azurerm_linux_web_app.webapp.id
  repo_url           = "https://github.com/Azure-Samples/nodejs-docs-hello-world"
  branch             = "master"
  use_manual_integration = true
  use_mercurial      = false
}

resource "azurerm_virtual_network" "vnet1" {
  name                = "myVNet"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  address_space       = ["10.21.0.0/16"]
}

resource "azurerm_subnet" "frontend" {
  name                 = "myAGSubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet1.name
  address_prefixes     = ["10.21.0.0/24"]
}

resource "azurerm_subnet" "backend" {
  name                 = "myBackendSubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet1.name
  address_prefixes     = ["10.21.1.0/24"]
}

# Create Public IP

resource "azurerm_public_ip" "pip1" {
  name                = "myAGPublicIPAddress"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Create Application Gateway

resource "azurerm_application_gateway" "network" {
  depends_on          = [azurerm_key_vault_certificate.mywebapp, time_sleep.wait_60_seconds]
  name                = "myAppGateway"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.agw.id]
  }

  gateway_ip_configuration {
    name      = "my-gateway-ip-configuration"
    subnet_id = azurerm_subnet.frontend.id
  }

  frontend_port {
    name = "${var.frontend_port_name}-443"
    port = 443
  }

  frontend_port {
    name = "${var.frontend_port_name}-80"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "${var.frontend_ip_configuration_name}-public"
    public_ip_address_id = azurerm_public_ip.pip1.id
  }

  backend_address_pool {
    name = var.backend_address_pool_name
    fqdns = ["${azurerm_linux_web_app.webapp.name}.azurewebsites.net"]
  }

  ssl_certificate {
    name                = azurerm_key_vault_certificate.mywebapp.name
    key_vault_secret_id = azurerm_key_vault_certificate.mywebapp.secret_id
  }

  backend_http_settings {
    name                                = var.http_setting_name
    cookie_based_affinity               = "Disabled"
    port                                = 443
    protocol                            = "Https"
    request_timeout                     = 60
    pick_host_name_from_backend_address = true
  }

  http_listener {
    name                           = "${var.listener_name}-http"
    frontend_ip_configuration_name = "${var.frontend_ip_configuration_name}-public"
    frontend_port_name             = "${var.frontend_port_name}-80"
    protocol                       = "Http"
  }

  http_listener {
    name                           = "${var.listener_name}-https"
    frontend_ip_configuration_name = "${var.frontend_ip_configuration_name}-public"
    frontend_port_name             = "${var.frontend_port_name}-443"
    protocol                       = "Https"
    ssl_certificate_name           = azurerm_key_vault_certificate.mywebapp.name
  }

  request_routing_rule {
    name                       = "${var.request_routing_rule_name}-https"
    rule_type                  = "Basic"
    http_listener_name         = "${var.listener_name}-https"
    backend_address_pool_name  = var.backend_address_pool_name
    backend_http_settings_name = var.http_setting_name
    priority                  = 10
  }

    redirect_configuration {
    name                 = var.redirect_configuration_name
    redirect_type        = "Permanent"
    include_path         = true
    include_query_string = true
    target_listener_name = "${var.listener_name}-https"
  }

  request_routing_rule {
    name                        = "${var.request_routing_rule_name}-http"
    rule_type                   = "Basic"
    http_listener_name          = "${var.listener_name}-http"
    redirect_configuration_name = var.redirect_configuration_name
    priority                    = 20
  }
}

/*resource "azurerm_network_interface" "nic" {
  count = 2
  name                = "nic-${count.index+1}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "nic-ipconfig-${count.index+1}"
    subnet_id                     = azurerm_subnet.backend.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface_application_gateway_backend_address_pool_association" "nic-assoc01" {
  count = 2
  network_interface_id    = azurerm_network_interface.nic[count.index].id
  ip_configuration_name   = "nic-ipconfig-${count.index+1}"
  backend_address_pool_id = tolist(azurerm_application_gateway.network.backend_address_pool).0.id
}*/

