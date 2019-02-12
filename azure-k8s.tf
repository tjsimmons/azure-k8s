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
  name                 = "kubernetes-subnet"
  address_prefix       = "10.240.0.0/24"
  resource_group_name  = "${azurerm_resource_group.kubernetes.name}"
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

resource "azurerm_availability_set" "worker-as" {
  name                = "worker-as"
  location            = "${azurerm_resource_group.kubernetes.location}"
  resource_group_name = "${azurerm_resource_group.kubernetes.name}"
}

resource "azurerm_public_ip" "controller-pips" {
  count               = 3
  name                = "controller-${count.index}-pip"
  resource_group_name = "${azurerm_resource_group.kubernetes.name}"
  location            = "${azurerm_resource_group.kubernetes.location}"
  allocation_method   = "Static"
}

resource "azurerm_public_ip" "worker-pips" {
  count               = 3
  name                = "worker-${count.index}-pip"
  resource_group_name = "${azurerm_resource_group.kubernetes.name}"
  location            = "${azurerm_resource_group.kubernetes.location}"
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "controller-nics" {
  count                = 3
  name                 = "controller-${count.index}-nic"
  location             = "${azurerm_resource_group.kubernetes.location}"
  resource_group_name  = "${azurerm_resource_group.kubernetes.name}"
  enable_ip_forwarding = true

  ip_configuration {
    name                          = "controller-nic-${count.index}"
    private_ip_address            = "10.240.0.1${count.index}"
    private_ip_address_allocation = "Static"
    public_ip_address_id          = "${element(azurerm_public_ip.controller-pips.*.id, count.index)}"
    subnet_id                     = "${azurerm_subnet.kubernetes-subnet.id}"

    # deprecated
    load_balancer_backend_address_pools_ids = ["${azurerm_lb_backend_address_pool.kubernetes-lb-pool.id}"]
  }
}

resource "azurerm_network_interface" "worker-nics" {
  count                = 3
  name                 = "worker-${count.index}-nic"
  location             = "${azurerm_resource_group.kubernetes.location}"
  resource_group_name  = "${azurerm_resource_group.kubernetes.name}"
  enable_ip_forwarding = true

  ip_configuration {
    name                          = "worker-nic-${count.index}"
    private_ip_address            = "10.240.0.1${count.index}"
    private_ip_address_allocation = "Static"
    public_ip_address_id          = "${element(azurerm_public_ip.worker-pips.*.id, count.index)}"
    subnet_id                     = "${azurerm_subnet.kubernetes-subnet.id}"
  }
}

resource "azurerm_virtual_machine" "controllers" {
  count                 = 3
  name                  = "controller-${count.index}"
  location              = "${azurerm_resource_group.kubernetes.location}"
  resource_group_name   = "${azurerm_resource_group.kubernetes.name}"
  network_interface_ids = ["${element(azurerm_network_interface.controller-nics.*.id, count.index)}"]
  vm_size               = "Standard_DS1_v2"
  availability_set_id   = "${azurerm_availability_set.controller-as.id}"

  os_profile_linux_config {
    disable_password_authentication = "true"

    ssh_keys {
      key_data = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDXUIzLabfNAiiSxPucR/QznuEeue68/KwNISJJ8KXiwv0rQkaaqfFYIiWU84VM4fGzRLeK1QqhNwux3/iYP6QdX+FIjPlMGRBLK+g70gVEtCyxbAHhH1rJUS4cxdVPB3hTT9ncE3rGlSeGXmlYDNWf+PFJ9/dXH2TcSSyJWX+5gKbfSibrYJXlviYIp8K9g6w5TDo/2DMTZdGjwg1bEL4PdqxnqHcwADA2XwgonBbzXWb+pj6c2j3y/xiweuCCu3esw+c+6LQTPMrovOuMl/+bRl3E282IHA6CCjrv0vIgii/aXi3PKn31mpx0If+870+gXh1Q+NluDFsE0IlDgci6i8tukeEoNnhu9vzJxtUTHk3XBrU0Msqo5f5HRJ4cLEQ0rc6szEmukfLy3jcIY8gal8Vmn3jwBTj5gFFqqVI5B/6E3RXuqSE7Exemi7BpTWcYAiemk2CrGlwcns7lBu2eGQkwjXZlsorzd30O7EkJ3tc2ZCSIodfAcOdqJfgXnhm6e6ttzw5ZPy+h4r33BHjDM44dxFC3vBjdo3rFpyRvbyclTaZ60fD1y9yhCfDmB3NrIRANyWHEB0qloOqQhPDRx4AMjXdMEDft9ppm2QrVOp7Czn7OPLoDCRIclzkl+lL0e4hcQ4kk2NbH42iZ9N/AWdppRUR5XBXCYwp8OsDX4Q== primary_yubikey"
      path     = "/home/admin/.ssh/authorized_keys"
    }
  }

  os_profile {
    computer_name  = "controller-${count.index}"
    admin_username = "admin"
  }

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name          = "controller-${count.index}-os"
    create_option = "FromImage"
    caching       = "ReadWrite"
    disk_size_gb  = "30"
    os_type       = "Linux"
  }
}

resource "azurerm_virtual_machine" "workers" {
  count                 = 3
  name                  = "worker-${count.index}"
  location              = "${azurerm_resource_group.kubernetes.location}"
  resource_group_name   = "${azurerm_resource_group.kubernetes.name}"
  network_interface_ids = ["${element(azurerm_network_interface.worker-nics.*.id, count.index)}"]
  vm_size               = "Standard_DS1_v2"
  availability_set_id   = "${azurerm_availability_set.worker-as.id}"

  os_profile_linux_config {
    disable_password_authentication = "true"

    ssh_keys {
      key_data = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDXUIzLabfNAiiSxPucR/QznuEeue68/KwNISJJ8KXiwv0rQkaaqfFYIiWU84VM4fGzRLeK1QqhNwux3/iYP6QdX+FIjPlMGRBLK+g70gVEtCyxbAHhH1rJUS4cxdVPB3hTT9ncE3rGlSeGXmlYDNWf+PFJ9/dXH2TcSSyJWX+5gKbfSibrYJXlviYIp8K9g6w5TDo/2DMTZdGjwg1bEL4PdqxnqHcwADA2XwgonBbzXWb+pj6c2j3y/xiweuCCu3esw+c+6LQTPMrovOuMl/+bRl3E282IHA6CCjrv0vIgii/aXi3PKn31mpx0If+870+gXh1Q+NluDFsE0IlDgci6i8tukeEoNnhu9vzJxtUTHk3XBrU0Msqo5f5HRJ4cLEQ0rc6szEmukfLy3jcIY8gal8Vmn3jwBTj5gFFqqVI5B/6E3RXuqSE7Exemi7BpTWcYAiemk2CrGlwcns7lBu2eGQkwjXZlsorzd30O7EkJ3tc2ZCSIodfAcOdqJfgXnhm6e6ttzw5ZPy+h4r33BHjDM44dxFC3vBjdo3rFpyRvbyclTaZ60fD1y9yhCfDmB3NrIRANyWHEB0qloOqQhPDRx4AMjXdMEDft9ppm2QrVOp7Czn7OPLoDCRIclzkl+lL0e4hcQ4kk2NbH42iZ9N/AWdppRUR5XBXCYwp8OsDX4Q== primary_yubikey"
      path     = "/home/admin/.ssh/authorized_keys"
    }
  }

  os_profile {
    computer_name  = "worker-${count.index}"
    admin_username = "admin"
  }

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name          = "worker-${count.index}-os"
    create_option = "FromImage"
    caching       = "ReadWrite"
    disk_size_gb  = "30"
    os_type       = "Linux"
  }

  tags {
    pod-cidr = "10.200.${count.index}.0/24"
  }
}
