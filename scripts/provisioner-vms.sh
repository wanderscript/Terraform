#!/bin/bash

#############################################
# Autor: Wanderson Sousa e Thais Rebouças   #
# e-mail: wanderson.sousaa05@gmail.com      #
# Data: 14/10/2025                          #
# Versão: 1.0                               #
# Descrição: Assistente que inicializa ou   #
# edita o terraform.tfvars de forma robusta.#
#############################################

#set -xe
ARQUIVO_TFVARS="terraform.tfvars"

# Cores para a interface
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
RESET=$(tput sgr0)

# ===================================================================================
# FUNÇÃO ROBUSTA PARA INSERIR UM BLOCO DE TEXTO EM UM ARQUIVO
# Esta função lê o arquivo original e o reescreve em um temporário,
# inserindo o novo bloco de texto antes da linha do marcador.
# Argumentos: $1 -> ARQUIVO, $2 -> BLOCO DE TEXTO, $3 -> MARCADOR
# ===================================================================================
inserir_bloco_antes_do_marcador() {
    local arquivo="$1"
    local bloco_a_inserir="$2"
    local marcador="$3"
    
    local temp_file
    temp_file=$(mktemp)

    local inserido=false

    # Lê o arquivo original linha por linha
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Verifica se a linha atual contém o marcador
        if [[ "$line" == *"$marcador"* ]] && ! $inserido; then
            # Se encontrou o marcador, escreve o NOVO BLOCO primeiro
            echo -e "$bloco_a_inserir" >> "$temp_file"
            inserido=true
        fi
        # Escreve a linha original no arquivo temporário
        echo "$line" >> "$temp_file"
    done < "$arquivo"

    # Substitui o arquivo original pelo temporário já modificado
    mv "$temp_file" "$arquivo"
}


# ===================================================================================
# FUNÇÃO PARA ADICIONAR UM GRUPO DE VMS (CLUSTER/LOTE)
# ===================================================================================
adicionar_cluster() {
    echo ""
    echo "${BLUE}--- Modo de Criação em Lote (Cluster) ---${RESET}"
    read -p "Qual o prefixo para o nome das VMs (ex: k8s-worker)? " PREFIXO
    read -p "Quantas VMs você quer criar (ex: 3)? " COUNT
    read -p "Memória para CADA VM em MiB (ex: 8192): " MEMORY
    read -p "Cores/vCPUs para CADA VM (ex: 4): " CORES
    read -p "Sockets                   (ex: 2): " SOCKETS
    read -p "Tamanho do disco em GB para CADA VM (ex: 100): " SIZE
    read -p "Tags para TODAS as VMs (ex: k8s,worker): " TAGS
    TAGS_FORMATADA=$(echo "$TAGS" | sed 's/,/\", \"/g')
    
    local NOVO_BLOCO
    NOVO_BLOCO=$(cat <<EOF
  "${PREFIXO}" = {
    count  = ${COUNT}
    memory = ${MEMORY}
    cores  = ${CORES}
    sockets= ${SOCKETS}
    size   = ${SIZE}
    tags   = ["${TAGS}"]
  },
EOF
)
    local MARCADOR="# O SCRIPT IRÁ ADICIONAR NOVOS GRUPOS ACIMA DESTA LINHA"

    if grep -q "cluster_vms_config" "$ARQUIVO_TFVARS"; then
        echo " Inserindo novo grupo na seção 'cluster_vms_config' existente..."
        inserir_bloco_antes_do_marcador "$ARQUIVO_TFVARS" "$NOVO_BLOCO" "$MARCADOR"
    else
        echo " Seção 'cluster_vms_config' não encontrada. Criando agora..."
        cat <<EOF >> "$ARQUIVO_TFVARS"

// ===================================================================
// Opção 1: CLUSTER / VMs EM LOTE (Geração Automática)
// ===================================================================
cluster_vms_config = {
${NOVO_BLOCO}
  ${MARCADOR}
}
EOF
    fi

    echo "${GREEN} Seção 'cluster_vms_config' atualizada com sucesso!${RESET}"
}

# ===================================================================================
# FUNÇÃO PARA ADICIONAR UMA VM ESPECÍFICA (AVULSA)
# ===================================================================================
adicionar_vm_avulsa() {
    echo ""
    echo "${BLUE}--- Modo de Criação de VM Específica ---${RESET}"
    read -p "Qual o nome COMPLETO da VM (ex: docker-server-webapp)? " NOME_VM
    read -p "Memória em MiB (ex: 4096): " MEMORY
    read -p "Cores/vCPUs (ex: 2): " CORES
    read -p "Sockets      (ex: 2) " SOCKETS
    read -p "Tamanho do disco em GB (ex: 50): " SIZE
    read -p "Endereço IP ESTÁTICO (ex: 192.168.23.50): " IP
    read -p "Tags (ex: projeto-webapp,docker): " TAGS
    TAGS_FORMATADA=$(echo "$TAGS" | sed 's/,/\", \"/g')

    local NOVO_BLOCO
    NOVO_BLOCO=$(cat <<EOF
  "${NOME_VM}" = {
    memory = ${MEMORY}
    cores  = ${CORES}
    sockets= ${SOCKETS}
    size   = ${SIZE}
    ip     = "${IP}"
    tags   = ["${TAGS}]"
  },
EOF
)
    local MARCADOR="# O SCRIPT IRÁ ADICIONAR NOVAS VMS AVULSAS ACIMA DESTA LINHA"

    if grep -q "standalone_vms" "$ARQUIVO_TFVARS"; then
        echo " Inserindo nova VM na seção 'standalone_vms' existente..."
        inserir_bloco_antes_do_marcador "$ARQUIVO_TFVARS" "$NOVO_BLOCO" "$MARCADOR"
    else
        echo " Seção 'standalone_vms' não encontrada. Criando agora..."
        cat <<EOF >> "$ARQUIVO_TFVARS"

// ===================================================================
// opção 2: VMS AVULSAS (Definição Específica)
// ===================================================================
standalone_vms = {
${NOVO_BLOCO}
  ${MARCADOR}
}
EOF
    fi
    
    echo "${GREEN} Seção 'standalone_vms' atualizada com sucesso!${RESET}"
}

# ===================================================================================
# MENU PRINCIPAL
# ===================================================================================
touch "$ARQUIVO_TFVARS"

echo "${YELLOW}Assistente de Provisionamento de VMs Proxmox com Terraform${RESET}"
echo "---------------------------------------------------------"
echo "Este assistente irá editar diretamente o arquivo ${BLUE}$ARQUIVO_TFVARS${RESET}."
echo "O que você deseja fazer?"
echo "  ${GREEN}1)${RESET} Adicionar um grupo de VMs idênticas (Cluster/Lote)"
echo "  ${GREEN}2)${RESET} Adicionar uma VM específica (Projeto Avulso)"
echo ""

read -p "Escolha uma opção [1-2]: " ESCOLHA

case $ESCOLHA in
    1)
        adicionar_cluster
        ;;
    2)
        adicionar_vm_avulsa
        ;;
    *)
        echo "Opção inválida. Saindo."
        exit 1
        ;;
esac

echo "---------------------------------------------------------"
echo "Arquivo ${YELLOW}$ARQUIVO_TFVARS${RESET} foi atualizado. Execute ${GREEN}'terraform apply'${RESET} para provisionar."
