output "linux_web_app_hostname" {
  description = "The Linux Web App Hostname"
  value       = azurerm_linux_web_app.webapp.default_hostname
}

output "public_ip_adress" {
    description = "The IP of the App gateway"
    value       = azurerm_public_ip.pip1.ip_address
}