terraform {
  required_version = ">= 1.1.0"
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = ">= 2.9.5"
    }
     null = {
      source = "hashicorp/null"
      version = "3.2.1"
    }
  }
}

provider "proxmox" {
    pm_tls_insecure = true
    pm_api_url      = var.proxmox["pm_api_url"]
    pm_password     = var.proxmox["pm_password"]
    pm_user         = var.proxmox["pm_user"]
    pm_otp          = ""
}

resource "proxmox_vm_qemu" "master" {
    count       = length(var.masters)
    name        = "${var.masters[count.index]}"
    target_node = var.target_node
    vmid        = "${var.node-id-prefix}${count.index + 1}"
    clone       = var.clone-image

    
    agent   = 1
    os_type = "cloud-init"
    cores   = 4
    sockets = 1
    vcpus   = 0
    cpu     = "host"
    memory  = 2048
    scsihw  = "virtio-scsi-pci"

    disk {
        size     = "16G"
        type     = "scsi"
        storage  = "pve-ssd"
        iothread = 1
        ssd      = 1
        discard  = "on"
    }
    network {
        model  = "virtio"
        bridge = "vmbr0"
    }
    
    ipconfig0 = "ip=${var.master-ips[count.index]}/24,gw=${cidrhost(format("%s/24", var.master-ips[count.index]), 1)}"
    lifecycle {
      ignore_changes = [
      network
      ]
    }   


    connection {
        host        = var.master-ips[count.index]
        user        = var.user
        private_key = file(var.ssh_keys["priv"])
        agent       = false
        timeout     = "3m"
    }

    timeouts {
      create = "20m"
      delete = "20m"
    }
    provisioner "remote-exec" {
        inline = [ "echo 'Cool, we are ready for provisioning'"]
    }
    depends_on = [
      local_file.create-inventory-file
    ]
}


resource "proxmox_vm_qemu" "workers" {
    count       = length(var.workers)
    name        = "${var.workers[count.index]}"
    target_node = var.target_node
    vmid        = "60${count.index + 1}"
    clone       = var.clone-image

    
    agent   = 1
    os_type = "cloud-init"
    cores   = 4
    sockets = 1
    vcpus   = 0
    cpu     = "host"
    memory  = 2048
    scsihw  = "virtio-scsi-pci"

    disk {
        size     = "16G"
        type     = "scsi"
        storage  = "pve-ssd"
        iothread = 1
        ssd      = 1
        discard  = "on"
    }
    network {
        model  = "virtio"
        bridge = "vmbr0"
    }
    
    ipconfig0 = "ip=${var.worker-ips[count.index]}/24,gw=${cidrhost(format("%s/24", var.worker-ips[count.index]), 1)}"
    lifecycle {
      ignore_changes = [
      network
      ]
    }   

    connection {
        host        = var.worker-ips[count.index]
        user        = var.user
        private_key = file(var.ssh_keys["priv"])
        agent       = false
        timeout     = "3m"
    }

    timeouts {
      create = "20m"
      delete = "20m"
    }
    provisioner "remote-exec" {
        inline = [ "echo 'Cool, we are ready for provisioning'"]
    }

    depends_on = [
      proxmox_vm_qemu.master
    ]
}

resource "null_resource" "ansible" {
  provisioner "local-exec" {
    working_dir = "./ansible"
    command     = "ansible-playbook -u ${var.user} --key-file ${var.ssh_keys["priv"]} -i inventory.ini main.yaml"
  }
  
  depends_on = [
      proxmox_vm_qemu.workers
  ]
}
resource "local_file" "create-inventory-file" {
  filename = "${path.cwd}/ansible/inventory.ini"
  content  = <<-EOT
  [master]
  ${var.master-ips[0]} ansible_user=root
  
  [worker]
  ${var.worker-ips[0]} ansible_user=root

  [kube_agents]
  %{for ip in var.master-ips ~}
${ip} ansible_user=root
  %{endfor ~}
  %{for ip in var.worker-ips ~}
${ip} ansible_user=root
  %{endfor ~}
  EOT
}