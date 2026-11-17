# Provisionamento de Máquinas Virtuais no Proxmox com Terraform

## Visão geral

Este projeto utiliza **Terraform e o provider `bpg/proxmox`** para
automatizar o provisionamento e o gerenciamento de máquinas virtuais
(VMs) em um ambiente Proxmox VE.

A infraestrutura é definida como código (Infrastructure as Code -- IaC),
permitindo criar, configurar e gerenciar máquinas virtuais de maneira
declarativa, padronizada e reproduzível.

A implementação utiliza recursos do provider `bpg/proxmox`, incluindo:

-   Clonagem de máquinas virtuais a partir de templates existentes.
-   Distribuição automática de VMs entre os nós do cluster Proxmox.
-   Configuração dinâmica de CPU, memória e armazenamento.
-   Configuração de interfaces de rede e VLAN.
-   Provisionamento de endereçamento IP por DHCP ou configuração
    estática.
-   Inicialização das máquinas utilizando Cloud-Init.
-   Configuração do QEMU Guest Agent.

O projeto também utiliza estruturas dinâmicas do Terraform, como
`for_each`, `for`, `merge`, `lookup` e `element`, permitindo provisionar
tanto grupos de máquinas virtuais quanto máquinas individuais.

------------------------------------------------------------------------

## 1. Pré-requisitos

Para utilizar o projeto, são necessários:

-   Ambiente Proxmox VE instalado e configurado.
-   Acesso à API do Proxmox VE.
-   Usuário ou token de API com permissões adequadas para operações de
    gerenciamento de VMs.
-   Terraform instalado.
-   Provider `bpg/proxmox` configurado.
-   Templates de máquinas virtuais previamente preparados no Proxmox.
-   Configuração de Cloud-Init habilitada nos templates.

### 1.1. Acesso à API do Proxmox

O Terraform utiliza a API do Proxmox para executar operações de
provisionamento.

O endpoint padrão da API segue o formato:

``` text
https://<proxmox-host>:8006/api2/json
```

É recomendado utilizar um usuário dedicado para o Terraform, com
permissões específicas para as operações necessárias, evitando utilizar
diretamente a conta administrativa `root`.

A autenticação pode ser realizada utilizando tokens de API do Proxmox.

**Importante:** o token e suas credenciais devem ser armazenados em
variáveis sensíveis, evitando sua exposição no repositório.

------------------------------------------------------------------------

## 2. Configuração do provider

O projeto utiliza o provider `bpg/proxmox`, responsável pela comunicação
entre o Terraform e a API do Proxmox VE.

Diferentemente da implementação anterior, que utilizava o provider
`Telmate/proxmox`, a configuração atual utiliza recursos e blocos
específicos do provider `bpg/proxmox`.

O provider deve ser declarado na configuração Terraform, utilizando o
endereço:

``` text
bpg/proxmox
```

A configuração de autenticação e a versão do provider devem permanecer
centralizadas nos arquivos de configuração correspondentes do projeto.

Documentação oficial:

https://registry.terraform.io/providers/bpg/proxmox/latest/docs

------------------------------------------------------------------------

## 3. Estrutura e lógica do projeto

A implementação utiliza blocos `locals` para processar as configurações
das máquinas virtuais antes de enviá-las ao recurso responsável pelo
provisionamento.

Essa abordagem permite trabalhar com diferentes tipos de VMs sem
precisar declarar individualmente cada recurso.

A lógica está dividida em quatro etapas principais:

1.  Geração de VMs pertencentes a grupos ou clusters.
2.  Processamento de VMs individuais (standalone).
3.  Consolidação das configurações em uma única estrutura.
4.  Definição de mapas auxiliares para templates e armazenamento.

### 3.1. Geração de VMs em cluster

O bloco `generated_cluster_vms` utiliza estruturas dinâmicas do
Terraform para criar múltiplas VMs com base na configuração definida em
`var.cluster_vms_config`.

``` hcl
generated_cluster_vms = merge([
  for prefix, config in var.cluster_vms_config : {
    for i in range(config.count) :
    format("%s-%02d", prefix, i + 1) => {
      memory  = config.memory
      cores   = config.cores
      sockets = config.sockets
      size    = config.size
      tags    = config.tags
      nodes   = element(var.nodes, i % length(var.nodes))
      ip      = "dhcp"
    }
  }
]...)
```

**Funcionamento:**

-   `for prefix, config`: percorre os grupos de VMs definidos nas
    variáveis.
-   `range(config.count)`: determina quantas máquinas serão criadas.
-   `format("%s-%02d", prefix, i + 1)`: gera nomes sequenciais para as
    máquinas.
-   `element(var.nodes, i % length(var.nodes))`: distribui as VMs entre
    os nós disponíveis.
-   `ip = "dhcp"`: define DHCP como configuração padrão de endereçamento
    para essas máquinas.
-   `merge(...)`: consolida os mapas gerados em uma única estrutura.

Exemplo: um grupo com prefixo `k8s-worker` e quantidade igual a três
gera:

``` text
k8s-worker-01
k8s-worker-02
k8s-worker-03
```

A distribuição entre os nós acontece automaticamente, utilizando uma
lógica de distribuição cíclica.

### 3.2. Processamento de VMs standalone

Além dos grupos de máquinas, o projeto permite criar VMs individuais com
configurações específicas.

Para isso, é utilizado o bloco `processed_standalone_vms`:

``` hcl
processed_standalone_vms = {
  for vm_name, config in var.standalone_vms :
  vm_name => merge(config, {
    nodes = element(
      var.nodes,
      (
        length(local.generated_cluster_vms) +
        index(keys(var.standalone_vms), vm_name)
      ) % length(var.nodes)
    )
  })
}
```

Nesse caso:

-   `var.standalone_vms` contém as configurações individuais.
-   `merge(config, {...})` preserva as configurações definidas para cada
    VM e adiciona o nó de destino.
-   `length(local.generated_cluster_vms)` considera as VMs geradas
    anteriormente.
-   `index(keys(var.standalone_vms), vm_name)` identifica a posição da
    VM na estrutura.
-   A operação de módulo permite continuar a distribuição entre os nós
    disponíveis.

Isso evita concentrar todas as máquinas individuais em um único nó do
cluster.

### 3.3. Consolidação das máquinas virtuais

Depois de processar os dois grupos, as configurações são reunidas em uma
única estrutura:

``` hcl
all_vms_to_create = merge(
  local.generated_cluster_vms,
  local.processed_standalone_vms
)
```

A variável local `all_vms_to_create` representa todas as máquinas que
deverão ser provisionadas.

Essa estrutura será utilizada posteriormente pelo `for_each` do recurso
principal.

------------------------------------------------------------------------

## 4. Mapeamento de templates e armazenamento

A implementação também utiliza mapas auxiliares para selecionar
automaticamente o template e o armazenamento de acordo com o nó de
destino.

### 4.1. Mapeamento de templates

``` hcl
node_template_map = {
  "pve00" = 191
  "pve01" = 190
  "pve02" = 193
  "pve03" = 194
  "pve04" = 195
}
```

Cada nó possui um identificador de template associado.

Durante o provisionamento, o Terraform consulta esse mapa para
identificar qual template deverá ser utilizado na clonagem da VM.

Caso o nó não esteja definido no mapa, é utilizado o valor de
`var.vm_id` como alternativa.

### 4.2. Mapeamento de armazenamento

``` hcl
node_storage_map = {
  "pve05" = "storage_raid05_pve05"
  "pve06" = "storage_raid05_pve06"
}
```

Esse mapa permite definir storages específicos para determinados nós do
Proxmox.

O recurso utiliza a função `lookup` para selecionar o armazenamento:

``` hcl
datastore_id = lookup(
  local.node_storage_map,
  each.value.nodes,
  "local-lvm"
)
```

**Comportamento:**

-   Se o nó estiver definido em `node_storage_map`, será utilizado o
    storage correspondente.
-   Caso contrário, será utilizado `local-lvm`.

Essa abordagem permite trabalhar com diferentes configurações de
armazenamento dentro do mesmo cluster.

------------------------------------------------------------------------

## 5. Provisionamento das máquinas virtuais

O provisionamento é realizado pelo recurso
`proxmox_virtual_environment_vm`, disponibilizado pelo provider
`bpg/proxmox`.

``` hcl
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
    bridge  = "vmbr0"
    model   = "virtio"
    vlan_id = 2
  }

  disk {
    datastore_id = lookup(
      local.node_storage_map,
      each.value.nodes,
      "local-lvm"
    )

    interface   = "scsi0"
    size        = each.value.size
    file_format = "raw"
    ssd         = true
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
```

### 5.1. Utilização do for_each

``` hcl
for_each = local.all_vms_to_create
```

O `for_each` permite criar um recurso para cada entrada existente na
estrutura `all_vms_to_create`.

Cada máquina recebe sua própria configuração, acessível através de:

-   `each.key`: nome da VM.
-   `each.value`: configurações associadas à VM.

Dessa forma, não é necessário duplicar blocos `resource` para cada
máquina virtual.

### 5.2. Clonagem de templates

``` hcl
clone {
  vm_id     = lookup(local.node_template_map, each.value.nodes, var.vm_id)
  node_name = each.value.nodes
  full      = true
}
```

A clonagem utiliza templates previamente preparados no Proxmox.

O identificador do template é selecionado dinamicamente conforme o nó de
destino.

O parâmetro `full = true` determina que a clonagem seja realizada como
uma cópia completa, em vez de um clone vinculado.

### 5.3. Configuração de hardware

A configuração de hardware é realizada através dos blocos `cpu`,
`memory` e `disk`.

**CPU:**

``` hcl
cpu {
  cores   = each.value.cores
  sockets = each.value.sockets
}
```

Define a quantidade de cores e sockets de cada máquina.

**Memória:**

``` hcl
memory {
  dedicated = each.value.memory
}
```

Define a quantidade de memória dedicada à VM.

**Disco:**

``` hcl
disk {
  datastore_id = lookup(local.node_storage_map, each.value.nodes, "local-lvm")
  interface    = "scsi0"
  size         = each.value.size
  file_format  = "raw"
  ssd          = true
}
```

Define o armazenamento, a interface do disco, seu tamanho e formato.

### 5.4. Configuração de rede

``` hcl
network_device {
  bridge  = "vmbr0"
  model   = "virtio"
  vlan_id = 2
}
```

A interface de rede utiliza:

-   Bridge `vmbr0`.
-   Modelo de interface `virtio`.
-   VLAN ID `2`.

Essa configuração é aplicada às máquinas provisionadas pelo recurso.

### 5.5. Configuração de Cloud-Init

O bloco `initialization` é responsável pela configuração inicial do
sistema operacional.

A implementação utiliza Cloud-Init para configurar:

-   Endereçamento IPv4.
-   Gateway.
-   Servidores DNS.
-   Domínio DNS.
-   Usuário.
-   Senha.

O endereçamento pode ser configurado de duas maneiras:

**DHCP:**

``` hcl
address = "dhcp"
```

**IP estático:**

``` hcl
address = "${each.value.ip}/${split("/", var.ip_network_base)[1]}"
gateway = var.vm_gateway_ip
```

A configuração verifica se o endereço da VM é `dhcp`. Caso contrário,
utiliza o endereço IP informado e obtém o prefixo de rede através de
`var.ip_network_base`.

------------------------------------------------------------------------

## 6. Script auxiliar de provisionamento

Além da configuração Terraform, o projeto possui um script Bash auxiliar
responsável por facilitar a edição do arquivo `terraform.tfvars`.

O objetivo é simplificar a inclusão de novas máquinas virtuais, evitando
que o usuário precise editar manualmente toda a estrutura de variáveis.

O script trabalha com duas categorias:

-   `cluster_vms_config`: grupos de máquinas virtuais com configurações
    padronizadas.
-   `standalone_vms`: máquinas virtuais individuais com configurações
    específicas.

### 6.1. Funcionamento

O script apresenta uma interface interativa para o usuário.

A partir dela, é possível:

1.  Selecionar a criação de um grupo de VMs ou uma VM individual.
2.  Informar os parâmetros de configuração.
3.  Gerar ou atualizar as entradas correspondentes no arquivo
    `terraform.tfvars`.

Entre as configurações utilizadas estão:

-   Nome ou prefixo da VM.
-   Quantidade de máquinas.
-   Memória.
-   Cores de CPU.
-   Sockets.
-   Tamanho do disco.
-   Tags.
-   Endereço IP, quando aplicável.

### 6.2. Benefícios

-   Redução de erros durante a edição das variáveis.
-   Padronização das configurações.
-   Facilidade para adicionar novas máquinas.
-   Simplificação do provisionamento de ambientes.
-   Integração com a estrutura dinâmica utilizada pelo Terraform.

**Observação:** o script deve gerar as variáveis `cluster_vms_config`,
`standalone_vms` e utilizar os nomes de atributos esperados pela
implementação atual.

------------------------------------------------------------------------

## 7. Execução do Terraform

Para executar os comandos Terraform, o projeto utiliza um contêiner
Docker com o diretório do projeto montado como volume.

Essa abordagem mantém o ambiente de execução isolado e facilita uma
futura integração com pipelines de CI/CD.

Exemplo de acesso ao contêiner:

``` bash
docker exec -ti terraform sh
```

### 7.1. Principais comandos

**Formatação:**

``` bash
terraform fmt
```

Formata os arquivos de configuração Terraform.

**Inicialização:**

``` bash
terraform init
```

Inicializa o diretório de trabalho, instala os providers necessários e
configura o backend, quando definido.

**Validação:**

``` bash
terraform validate
```

Verifica a consistência sintática e estrutural da configuração.

**Planejamento:**

``` bash
terraform plan
```

Apresenta as alterações que serão realizadas na infraestrutura.

**Aplicação:**

``` bash
terraform apply
```

Executa as alterações aprovadas e provisiona os recursos definidos na
configuração.

**Destruição:**

``` bash
terraform destroy
```

Remove os recursos gerenciados pelo Terraform, conforme o plano
apresentado.

------------------------------------------------------------------------

## 8. Benefícios da implementação

A utilização do Terraform com o provider `bpg/proxmox` permite
automatizar o gerenciamento de máquinas virtuais em ambientes Proxmox
VE.

Entre os principais benefícios estão:

-   **Infraestrutura como código:** configuração declarativa e
    versionada.
-   **Escalabilidade:** criação de múltiplas VMs através de estruturas
    dinâmicas.
-   **Padronização:** utilização de templates e configurações
    consistentes.
-   **Distribuição automática:** alocação das máquinas entre diferentes
    nós.
-   **Flexibilidade:** suporte a grupos de VMs e máquinas individuais.
-   **Automação:** integração com scripts auxiliares e possibilidade de
    implementação de CI/CD.
-   **Manutenibilidade:** centralização das configurações e redução de
    blocos duplicados.

------------------------------------------------------------------------

## 9. Referências

-   [Documentação oficial do Proxmox
    VE](https://pve.proxmox.com/pve-docs/)
-   [Terraform Registry -- Provider
    bpg/proxmox](https://registry.terraform.io/providers/bpg/proxmox/latest/docs)
-   [Documentação oficial do
    Terraform](https://developer.hashicorp.com/terraform/docs)
-   [Documentação da linguagem
    HCL](https://developer.hashicorp.com/terraform/language)