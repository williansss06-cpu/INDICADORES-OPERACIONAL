# Replicação de cadastro e permissões

Backup criado antes da implementação da replicação administrativa.

## Arquivos preservados

- `index.html.before`: versão anterior do frontend.
- `admin-users.index.ts.before`: versão anterior da Edge Function administrativa.

## Comportamento novo

Na Administração → Usuários, ao editar um usuário já vinculado, o Super Administrador ou administrador autorizado pode selecionar outro usuário como origem e clicar em **Replicar agora**.

A operação exige confirmação explícita e é executada pela RPC `admin_replicate_user_permissions` como uma transação única. São replicados:

- perfil e status, quando a opção estiver marcada;
- operações autorizadas;
- permissões por módulo;
- permissões por indicador;
- permissões do Plano de Ação;
- permissões do Assistente Inteligente.

Não são copiados senha, identidade do Auth, IDs de registros ou dados operacionais.

Em caso de falha, a RPC interrompe a operação e não aplica cópia parcial. A ação é registrada em `sustentacao_auditoria_permissoes` quando concluída.
