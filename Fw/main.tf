resource "azurerm_resource_group" "rg" {
   name     = var.rg_name
   location = var.rg_location
}

resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  depends_on = [ azurerm_resource_group.rg ]
}

resource "azurerm_subnet" "Firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
  depends_on = [ azurerm_virtual_network.vnet ]
}

resource "azurerm_subnet" "subnet" {
  name                 = "Subnet1"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
  depends_on = [ azurerm_virtual_network.vnet ]
}

resource "azurerm_network_interface" "subnet_nic" {
  name                = "VM-NIC"
  resource_group_name = azurerm_resource_group.rg.name
  location = azurerm_resource_group.rg.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
  }

  depends_on = [ azurerm_virtual_network.vnet ,azurerm_subnet.subnet ]
}

output "vm_private_ip" {
  value = azurerm_network_interface.subnet_nic.ip_configuration[0].private_ip_address
}


resource "azurerm_windows_virtual_machine" "VM" {
  name = "Test-VM"
  resource_group_name = azurerm_resource_group.rg.name
  location = azurerm_resource_group.rg.location
  size                  = "Standard_DS1_v2"
  admin_username      = "azureuser"
  admin_password      = "Password1234!"

  
  network_interface_ids = [azurerm_network_interface.subnet_nic.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }
  depends_on = [ azurerm_network_interface.subnet_nic]
}

resource "azurerm_route_table" "route_table" {
  name                = "Fw-route-table"
  resource_group_name = azurerm_resource_group.rg.name
  location = azurerm_resource_group.rg.location
  depends_on = [ azurerm_resource_group.rg , azurerm_subnet.subnet ]
}

resource "azurerm_route" "route_01" {
  name                   = "To-Fw"
  resource_group_name    = azurerm_resource_group.rg.name
  route_table_name       = azurerm_route_table.route_table.name
  address_prefix         = "0.0.0.0/0"  # Any
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = "10.0.1.4"  # Azure Firewall private IP

  depends_on = [
    azurerm_route_table.route_table,
    azurerm_firewall.firewall
  ]
}

resource "azurerm_subnet_route_table_association" "RT-ass" {
   subnet_id                 = azurerm_subnet.subnet.id
   route_table_id = azurerm_route_table.route_table.id
   depends_on = [ azurerm_subnet.subnet , azurerm_route_table.route_table ]
}

resource "azurerm_public_ip" "public_ip" {
  name = "Fw-IP"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  depends_on = [ azurerm_resource_group.rg ]
}

resource "azurerm_firewall_policy" "firewall_policy" {
  name                = "Firewall-policy"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku = "Standard"
  depends_on = [ azurerm_resource_group.rg ]
}

resource "azurerm_firewall" "firewall" {
  name                = "Az_Firewall"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku_name = "AZFW_VNet"
  sku_tier = "Standard"

  ip_configuration {
    name                 = "firewallconfiguration"
    subnet_id            = azurerm_subnet.Firewall.id
    public_ip_address_id = azurerm_public_ip.public_ip.id
  }
  firewall_policy_id = azurerm_firewall_policy.firewall_policy.id

  depends_on = [ azurerm_resource_group.rg , azurerm_public_ip.public_ip , 
                azurerm_subnet.Firewall , azurerm_firewall_policy.firewall_policy ]
}


resource "azurerm_firewall_policy_rule_collection_group" "fw_policy_rule_collection" {
  name                = "app-rule-collection-group"
  firewall_policy_id  = azurerm_firewall_policy.firewall_policy.id
  priority            = 100
   
   nat_rule_collection {
    name     = "dnat-rule-collection"
    priority = 400
    action = "Dnat"


    rule {
      name                  = "Allow-rdp"
      protocols             = ["TCP"]
      source_addresses      = ["*"]
      destination_address = azurerm_public_ip.public_ip.ip_address
      destination_ports     = ["3389"]
      translated_address = azurerm_network_interface.subnet_nic.ip_configuration[0].private_ip_address
      translated_port       = "3389"
    }

    rule {
    name                  = "Allow-HTTP"
    protocols             = ["TCP"]
    source_addresses      = ["*"]
    destination_address   = azurerm_public_ip.public_ip.ip_address
    destination_ports     = ["80"]
    translated_address    = azurerm_network_interface.subnet_nic.ip_configuration[0].private_ip_address
    translated_port       = "80"
  }
  }

  # network_rule_collection {
  #   name     = "network-rule-collection"
  #   priority = 300
  #   action   = "Allow"

  #   rule {
  #     name                  = "allow-IIS"
  #     source_addresses      = [azurerm_network_interface.subnet_nic.ip_configuration[0].private_ip_address]  # Private IP of VM
  #     destination_addresses = [azurerm_public_ip.public_ip.ip_address]
  #     destination_ports     = ["80"]
  #     protocols             = ["TCP"]
  #   }
  # }

  application_rule_collection {
    name     = "app-rule-collection"
    priority = 200
    action   = "Allow"

    rule {
      name             = "allow-microsoft-site"
      source_addresses = [azurerm_network_interface.subnet_nic.ip_configuration[0].private_ip_address]  # Private IP of VM
      protocols {
        type = "Https"
        port = 443
      }
      protocols {
        type = "Http"
        port = 80
      }
      destination_fqdns = ["*.microsoft.com"]

    }
  }
  depends_on = [ azurerm_firewall.firewall , azurerm_public_ip.public_ip , azurerm_network_interface.subnet_nic ]
}

