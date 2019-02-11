provider "azurerm" {
  version = "=1.22.0"
}

resource "azurerm_resource_group" "kubernetes" {
  name      = "kubernetes"
  location  = "southcentralus"
}

resource "azurerm_network_security_group" "kubernetes-nsg" {
    name                = "kubernetes-nsg"
    resource_group_name = "${azurerm_resource_group.kubernetes.name}"
    location            = "${azurerm_resource_group.kubernetes.location}"
    
    security_rule {
        name = "kubernetes-allow-ssh"
        access = "allow"
        destination_address_prefix = "*"
        destination_port_range = 22
        direction = "inbound"
        protocol = "tcp"
        source_address_prefix = "*"
        source_port_range = "*"
        priority = 1000
    }

    security_rule {
        name = "kubernetes-allow-api-server"
        access = "allow"
        destination_address_prefix = "*"
        destination_port_range = 6443
        direction = "inbound"
        protocol = "tcp"
        source_address_prefix = "*"
        source_port_range = "*"
        priority = 1001
    }
}

resource "azurerm_virtual_network"  "kubernetes-vnet" {
    name                = "kubernetes-vnet"
    location            = "${azurerm_resource_group.kubernetes.location}"
    resource_group_name = "${azurerm_resource_group.kubernetes.name}"
    address_space       = ["10.0.0.0/16"]
    
    subnet {
        name            = "kubernetes-subnet"
        address_prefix  = "10.244.0.0/24"
        security_group = "${azurerm_network_security_group.kubernetes-nsg.id}"
    }
}

resource "azurerm_lb" "kubernetes-lb" {
    name = "kubernetes-lb"
    location = "${azurerm_resource_group.kubernetes.location}"
    resource_group_name = "${azurerm_resource_group.kubernetes.name}"

    frontend_ip_configuration {
        name = "kubernetes-lb-frontend"
        public_ip_address_id = "${azurerm_public_ip.kubernetes-pip.id}"
    }
}

resource "azurerm_lb_backend_address_pool" "kubernetes-lb-pool" {
    name = "kubernetes-lb-pool"
    location = "${azurerm_resource_group.kubernetes.location}"
    resource_group_name = "${azurerm_resource_group.kubernetes.name}"
    loadbalancer_id = "${azurerm_lb.kubernetes-lb.id}"
}

resource "azurerm_public_ip" "kubernetes-pip" {
    name = "kubernetes-pip"
    location = "${azurerm_resource_group.kubernetes.location}"
    resource_group_name = "${azurerm_resource_group.kubernetes.name}"
    allocation_method = "Static"
}