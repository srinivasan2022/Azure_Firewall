output "rg" {
  value = azurerm_resource_group.rg
}

output "vnet" {
  value = azurerm_virtual_network.vnet
}

output "subnet" {
  value = azurerm_subnet.subnet
}

output "NIC" {
  value = azurerm_network_interface.subnet_nic
}

# output "Vm" {
#   value = azurerm_windows_virtual_machine.VM
# }

output "public_ip" {
  value = azurerm_public_ip.public_ip
}

output "Firewall" {
  value = azurerm_firewall.firewall
}

