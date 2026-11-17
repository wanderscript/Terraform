# Definição de variáveis

variable "proxmox_endpoint" {
    type        = string
    description = "URL para comunicação com a API do proxmox"
    default     = "https://192.168.1.32:8006/"
}

variable "proxmox_api_token" {
    type        = string
    description = "API para a conexão com o endpoint"
    sensitive   = true
}

variable "vm_id" {
    type        = number
    description = "ID númerico do template base para clonagem no proxmox"
    default     = 190
}

variable "nodes" {
    type        = list(string)
    description = "PVE onde será criada a VM"
}

variable "nameserver" {
    type        = string
    description = "Nameserver do AD"
    default     = "192.168.1.10 192.168.1.11"
}

variable "vm_password" {
    type        = string
    description = "Senha para o usuário do cloud init"
    sensitive   = true
}

variable "ip_network_base" {
    type        = string
    description = "Rede base IPs (ex: 192.168.2.0/24)."
}

variable "vm_gateway_ip" {
    type        = string
    description = "Gateway da rede."
}

# Definição de estrutura para VMs cluster (idênticas)
variable "cluster_vms_config" {
    type        = map(object({
        count   = number
        memory  = number
        cores   = number
        sockets = number
        size    = number
        tags    = list(string)
    }))
    description = "Mapa de configuração para o grupo de VMs a serem geradas em lote."
    default     = {}
}

# Definição de estrutura para VMs avulsas
variable "standalone_vms" {
    type        = map(object({
        memory  = number
        cores   = number
        sockets = number
        size    = number
        ip      = string
        tags    = list(string)
    }))
    description = "Mapa de VMs específicas com configuração manual."
    default     = {}
}
