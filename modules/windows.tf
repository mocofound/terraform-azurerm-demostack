data "template_file" "consulconfig" {
  depends_on = ["azurerm_public_ip.windows-pip"]
  count      = "${var.servers}"
  template   = "${file("${path.module}/templates/windows/consul.tpl")}"

  vars {
    location        = "${var.location}"
    hostname        = "${var.hostname}-servers-${count.index}"
    private_ip      = "${element(azurerm_network_interface.windows-nic.*.private_ip_address, count.index)}"
    public_ip       = "${element(azurerm_public_ip.windows-pip.*.ip_address, count.index)}"
    subscription_id = "${var.subscription_id}"
    tenant_id       = "${var.tenant_id}"
    client_id       = "${var.client_id}"
    client_secret   = "${var.client_secret}"
    node_name       = "${var.hostname}-servers-${count.index}"
    me_ca           = "${var.ca_cert_pem}"
    me_cert         = "${element(tls_locally_signed_cert.servers.*.cert_pem, count.index)}"
    me_key          = "${element(tls_private_key.servers.*.private_key_pem, count.index)}"

    # Consul
    consul_gossip_key     = "${var.consul_gossip_key}"
    consul_join_tag_key   = "ConsulJoin"
    consul_join_tag_name  = "demostack"
    consul_join_tag_value = "${var.consul_join_tag_value}"
    consul_master_token   = "${var.consul_master_token}"
    consul_servers        = "${var.servers}"
  }
}

data "template_file" "nomadconfig" {
  depends_on = ["azurerm_public_ip.windows-pip"]
  count      = "${var.servers}"
  template   = "${file("${path.module}/templates/windows/nomad.tpl")}"

  vars {
    location        = "${var.location}"
    hostname        = "${var.hostname}-windows-${count.index}"
    private_ip      = "${element(azurerm_network_interface.windows-nic.*.private_ip_address, count.index)}"
    public_ip       = "${element(azurerm_public_ip.windows-pip.*.ip_address, count.index)}"
    subscription_id = "${var.subscription_id}"
    tenant_id       = "${var.tenant_id}"
    client_id       = "${var.client_id}"
    client_secret   = "${var.client_secret}"
    node_name       = "${var.hostname}-windows-${count.index}"
    me_ca           = "${var.ca_cert_pem}"
    me_cert         = "${element(tls_locally_signed_cert.servers.*.cert_pem, count.index)}"
    me_key          = "${element(tls_private_key.servers.*.private_key_pem, count.index)}"

    # Nomad

    nomad_gossip_key = "${var.nomad_gossip_key}"
    nomad_servers    = "${var.servers}"
  }
}

resource "azurerm_public_ip" "windows-pip" {
  count               = "${var.servers}"
  name                = "${var.demo_prefix}-windows-ip-${count.index}"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.demostack.name}"
  allocation_method   = "Static"
  domain_name_label   = "${var.hostname}-windows-${count.index}"
  sku                 = "Standard"

  tags {
    name      = "Guy Barros"
    ttl       = "13"
    owner     = "guy@hashicorp.com"
    demostack = "${var.consul_join_tag_value}"
  }
}

resource "azurerm_network_interface" "windows-nic" {
  count                     = "${var.servers}"
  name                      = "${var.demo_prefix}windows-nic-${count.index}"
  location                  = "${var.location}"
  resource_group_name       = "${azurerm_resource_group.demostack.name}"
  network_security_group_id = "${azurerm_network_security_group.demostack-sg.id}"

  ip_configuration {
    name                          = "${var.demo_prefix}-${count.index}-winpconfig"
    subnet_id                     = "${azurerm_subnet.servers.id}"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = "${element(azurerm_public_ip.servers-pip.*.id, count.index)}"
  }

  tags {
    name      = "Guy Barros"
    ttl       = "13"
    owner     = "guy@hashicorp.com"
    demostack = "${var.consul_join_tag_value}"
  }
}

resource "azurerm_subnet" "windows" {
  name                 = "${var.demo_prefix}-windows"
  virtual_network_name = "${azurerm_virtual_network.awg.name}"
  resource_group_name  = "${azurerm_resource_group.demostack.name}"
  address_prefix       = "10.0.60.0/24"

 
}

resource "azurerm_virtual_machine" "windows" {
  count                 = "${var.servers}"
  name                  = "demostack-windows-0"
  location              = "${var.location}"
  resource_group_name   = "${azurerm_resource_group.demostack.name}"
  network_interface_ids = []
  vm_size               = "Standard_B2s"

  network_interface_ids         = ["${azurerm_network_interface.windows-nic.id}"]
  delete_os_disk_on_termination = "true"

  storage_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2016-Datacenter"

    // sku       = "2016-Datacenter-Server-Core-smalldisk"
    version = "latest"
  }

  storage_os_disk {
    name              = "server-os"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  tags {
    name      = "Guy Barros"
    ttl       = "13"
    owner     = "guy@hashicorp.com"
    demostack = "${var.consul_join_tag_value}"
  }

  os_profile {
    computer_name  = "windows-0"
    admin_username = "${var.admin_username}"
    admin_password = "${var.admin_password}"
  }

  os_profile_windows_config {
    enable_automatic_upgrades = true //Here defined autoupdate config and also vm agent config
    provision_vm_agent        = true

    winrm = {
      protocol = "http" //Here defined WinRM connectivity config
    }

    #Unattend config is to enable basic auth in WinRM, required for the provisioner stage.
    additional_unattend_config {
      pass         = "oobeSystem"
      component    = "Microsoft-Windows-Shell-Setup"
      setting_name = "FirstLogonCommands"
      content      = "${file("${path.module}/templates/windows/FirstLogonCommands.xml")}"
    }
  }

  provisioner "file" {
    source      = "${path.module}/templates/windows/InstallHashicorp.ps1"
    destination = "C:\\Hashicorp\\InstallHashicorp.ps1"

    connection {
      type     = "winrm"
      https    = false
      insecure = true
      user     = "${var.admin_username}"
      password = "${var.admin_password}"
      host     = "${azurerm_public_ip.windows-pip.fqdn}"
    }
  }

  provisioner "file" {
    content     = "${element(data.template_file.consulconfig.*.rendered, count.index)}"
    destination = "C:\\Hashicorp\\Consul\\config.json"

    connection {
      type     = "winrm"
      https    = false
      insecure = true
      user     = "${var.admin_username}"
      password = "${var.admin_password}"
      host     = "${azurerm_public_ip.windows-pip.fqdn}"
    }
  }

  provisioner "file" {
    content     = "${element(data.template_file.nomadconfig.*.rendered, count.index)}"
    destination = "C:\\Hashicorp\\Nomad\\config.json"

    connection {
      type     = "winrm"
      https    = false
      insecure = true
      user     = "${var.admin_username}"
      password = "${var.admin_password}"
      host     = "${azurerm_public_ip.windows-pip.fqdn}"
    }
  }

  provisioner "file" {
    content     = "${element(tls_private_key.servers.*.private_key_pem, count.index)}"
    destination = "C:\\Hashicorp\\Consul\\me.key"

    connection {
      type     = "winrm"
      https    = false
      insecure = true
      user     = "${var.admin_username}"
      password = "${var.admin_password}"
      host     = "${azurerm_public_ip.windows-pip.fqdn}"
    }
  }

  provisioner "file" {
    content     = "${element(tls_locally_signed_cert.servers.*.cert_pem, count.index)}"
    destination = "C:\\Hashicorp\\Consul\\me.crt"

    connection {
      type     = "winrm"
      https    = false
      insecure = true
      user     = "${var.admin_username}"
      password = "${var.admin_password}"
      host     = "${azurerm_public_ip.windows-pip.fqdn}"
    }
  }

  provisioner "file" {
    content     = "${var.ca_cert_pem}"
    destination = "C:\\Hashicorp\\Consul\\01-me.crt"

    connection {
      type     = "winrm"
      https    = false
      insecure = true
      user     = "${var.admin_username}"
      password = "${var.admin_password}"
      host     = "${azurerm_public_ip.windows-pip.fqdn}"
    }
  }
}
