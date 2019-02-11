provider "azurerm" {
  version = "=1.22.0"
}

resource "azurerm_resource_group" "kubernetes" {
  name     = "kubernetes"
  location = "southcentralus"
}

resource "azurerm_network_security_group" "kubernetes-nsg" {
  name                = "kubernetes-nsg"
  resource_group_name = "${azurerm_resource_group.kubernetes.name}"
  location            = "${azurerm_resource_group.kubernetes.location}"

  security_rule {
    name                       = "kubernetes-allow-ssh"
    access                     = "allow"
    destination_address_prefix = "*"
    destination_port_range     = 22
    direction                  = "inbound"
    protocol                   = "tcp"
    source_address_prefix      = "*"
    source_port_range          = "*"
    priority                   = 1000
  }

  security_rule {
    name                       = "kubernetes-allow-api-server"
    access                     = "allow"
    destination_address_prefix = "*"
    destination_port_range     = 6443
    direction                  = "inbound"
    protocol                   = "tcp"
    source_address_prefix      = "*"
    source_port_range          = "*"
    priority                   = 1001
  }
}

resource "azurerm_virtual_network" "kubernetes-vnet" {
  name                = "kubernetes-vnet"
  location            = "${azurerm_resource_group.kubernetes.location}"
  resource_group_name = "${azurerm_resource_group.kubernetes.name}"
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "kubernetes-subnet" {
    name = "kubernetes-subnet"
    address_prefix = "10.240.0.0/24"
    resource_group_name = "${azurerm_resource_group.kubernetes.name}"
    virtual_network_name = "${azurerm_virtual_network.kubernetes-vnet.name}"
    # deprecated with v2 of azurerm
    network_security_group_id = "${azurerm_network_security_group.kubernetes-nsg.id}"
}

resource "azurerm_lb" "kubernetes-lb" {
  name                = "kubernetes-lb"
  location            = "${azurerm_resource_group.kubernetes.location}"
  resource_group_name = "${azurerm_resource_group.kubernetes.name}"

  frontend_ip_configuration {
    name                 = "kubernetes-lb-frontend"
    public_ip_address_id = "${azurerm_public_ip.kubernetes-pip.id}"
  }
}

resource "azurerm_lb_backend_address_pool" "kubernetes-lb-pool" {
  name = "kubernetes-lb-pool"

  resource_group_name = "${azurerm_resource_group.kubernetes.name}"
  loadbalancer_id     = "${azurerm_lb.kubernetes-lb.id}"
}

resource "azurerm_public_ip" "kubernetes-pip" {
  name                = "kubernetes-pip"
  location            = "${azurerm_resource_group.kubernetes.location}"
  resource_group_name = "${azurerm_resource_group.kubernetes.name}"
  allocation_method   = "Static"
}

resource "azurerm_availability_set" "controller-as" {
  name                = "controller-as"
  location            = "${azurerm_resource_group.kubernetes.location}"
  resource_group_name = "${azurerm_resource_group.kubernetes.name}"
}

resource "azurerm_public_ip" "controllers-pip" {
  count               = 3
  name                = "controller-${count.index}-pip"
  resource_group_name = "${azurerm_resource_group.kubernetes.name}"
  location            = "${azurerm_resource_group.kubernetes.location}"
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "nics" {
  count               = 3
  name                = "controller-${count.index}-nic"
  location            = "${azurerm_resource_group.kubernetes.location}"
  resource_group_name = "${azurerm_resource_group.kubernetes.name}"
  enable_ip_forwarding = true

  ip_configuration {
    name                          = "nic-${count.index}"
    private_ip_address            = "10.240.0.1${count.index}"
    private_ip_address_allocation = "Static"
    public_ip_address_id          = "${element(azurerm_public_ip.controllers-pip.*.id, count.index)}"
    subnet_id                     = "${azurerm_subnet.kubernetes-subnet.id}"
    # deprecated
    load_balancer_backend_address_pools_ids = ["${azurerm_lb_backend_address_pool.kubernetes-lb-pool.id}"]
  }
}

resource "azurerm_virtual_machine" "controllers" {
    count = 3
    name = "controller-${count.index}"
    location = "${azurerm_resource_group.kubernetes.location}"
    resource_group_name = "${azurerm_resource_group.kubernetes.name}"
    network_interface_ids = ["${element(azurerm_network_interface.nics.*.id, count.index)}"]
    vm_size = "Standard_DS1_v2"
}

