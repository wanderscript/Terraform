terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.101.1"
    }
  }
}

provider "proxmox" {
    endpoint  = var.proxmox_endpoint
    api_token = var.proxmox_api_token 
    insecure    = true # eu coloquei insecure por conta que a URL do proxmox não tem certificado válido
}
