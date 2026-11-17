# rastreio

Os últimos ajustes que eu fiz, foi referente a variaveis, pois o api_token não deve ser passado como default  
com isso eu quero passar a variavel no gitlab quando estiver pipeline para melhores práticas de segurança.  
Isso segue o mesmo raciocinio para o vm_password do cloud init.  

Realizei a organização dos arquivo criando um diretório /scripts e movi o script  `provisioner-vms.sh`.  
criei o arquivo outputs.tf estou estudando uma melhor forma para resgatar esse outputs e quero entender  
mais sobre isso também para aprender de fato.  

### output.tf

É basicamente a informação que o terraform devolve após o apply. Então ele permiti dados estruturados  
sobre os recursos.  

