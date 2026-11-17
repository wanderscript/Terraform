output "vm_info" {
  value = {
    for in vm in proxmox_virtual_environment_vm.cluster_vms :
    vm.name => {
      node = vm.node_name
      vmid = vm.vm_id
      tags = vm.tags
    }
  }
}

