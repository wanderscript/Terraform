locals {
  #  Processamento de VMs em cluster com count
  generated_cluster_vms = merge([
    for prefix, config in var.cluster_vms_config : {
      for i in range(config.count) :
      format("%s-%02d", prefix, i + 1) => {
        memory      = config.memory
        cores       = config.cores
        sockets     = config.sockets
        size        = config.size
        tags        = config.tags
        nodes       = element(var.nodes, i % length(var.nodes))
        ip          = "dhcp"
      }
    }
  ]...)

  # VMs sem o count, exclusivas 
  processed_standalone_vms = {
    for vm_name, config in var.standalone_vms :
    vm_name => merge(config, {
      nodes = element(var.nodes, (length(local.generated_cluster_vms) + index(keys(var.standalone_vms), vm_name)) % length(var.nodes))
    })
  }

  # Juntando tudo em "all_vms_to_create" isso é a variavel local.
  all_vms_to_create = merge(local.generated_cluster_vms, local.processed_standalone_vms)

  node_template_map = {
    "pve00" = 191
    "pve01" = 190 
    "pve02" = 193 
    "pve03" = 194
    "pve04" = 195
  }

  # Mapa inteligente de storage por nó
  node_storage_map = {
    "pve05" = "storage_raid05_pve05"
    "pve06" = "storage_raid05_pve06"
  }
}

# Bloco de configuração
resource "proxmox_virtual_environment_vm" "cluster_vms" {

    for_each = local.all_vms_to_create

    name        = each.key
    node_name   = each.value.nodes
    tags        = each.value.tags
    description = "Managed by Terraform"

    clone {
        vm_id     = lookup(local.node_template_map, each.value.nodes, var.vm_id)
        node_name = each.value.nodes
        full      = true
    }

    agent {
        enabled = true
    }

    cpu {
        cores   = each.value.cores
        sockets = each.value.sockets
    }

    memory {
        dedicated = each.value.memory
  }

    network_device {
        bridge     = "vmbr0"
        model      = "virtio"
        vlan_id    = 2
  }

   disk {
        datastore_id = lookup(local.node_storage_map, each.value.nodes, "local-lvm")
        interface    = "scsi0"
        size         = each.value.size
        file_format  = "raw"
        ssd          = true
  }

  initialization {
    ip_config {
      ipv4 {
        address = each.value.ip == "dhcp" ? "dhcp" : "${each.value.ip}/${split("/", var.ip_network_base)[1]}"
        gateway = each.value.ip == "dhcp" ? null : var.vm_gateway_ip
      }
    }

    dns {
      servers = ["192.168.1.10", "192.168.1.11"]
      domain  = "mydomain.local"
    }

    user_account {
      username = "teste1"
      password = var.vm_password
    }
  }
}
