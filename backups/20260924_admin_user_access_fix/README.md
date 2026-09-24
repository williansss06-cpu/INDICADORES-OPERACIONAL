# Correção do cadastro administrativo — 2026-09-24

## Causa confirmada

A Edge Function criava primeiro a identidade em `auth.users` e depois chamava `admin_save_user_access`. O RPC inseria as permissões em `sustentacao_usuario_modulos` e `sustentacao_usuario_indicadores` com os quatro flags de acesso como `false`, embora o campo `nivel_acesso` já estivesse em `ADMINISTRAR`, `EDITAR` ou `LANCAR_RESULTADO`. A constraint de consistência rejeitava a linha antes da atualização posterior dos flags. O resultado era um usuário criado no Auth, mas com uma resposta HTTP 400 e uma mensagem genérica na Administração.

## Correção

A migration `20260924_admin_user_access_consistency.sql` grava `nivel_acesso` e flags derivados na mesma inserção, preservando a constraint e tornando a operação atômica. A Edge Function `admin-users` foi publicada com logging interno do erro real do RPC e resposta segura para o frontend. O frontend mantém o `user_id` devolvido em falhas de vínculo, orientando o administrador a salvar novamente sem criar outro `auth.users`.

## Validações

- Teste transacional do RPC com `ROLLBACK`: retornou `ok=true` para o cenário do Hellry.
- Hellry: uma identidade Auth; perfil `administrador_operacao`; vínculo ativo com duas operações.
- André Bueno Leite: perfil `administrador_operacao`; vínculo ativo com uma operação; preservado.
- Willian Soares: perfil `super_admin`; vínculo ativo com duas operações; preservado.
- A Edge Function ativa ficou com JWT obrigatório na versão 11.

Os arquivos `.before-fix` são pontos de reversão exata dos arquivos alterados nesta correção.

## Limitação

O envio de e-mail continua dependente do provedor padrão do Supabase até que SMTP corporativo seja configurado no projeto. Isso é independente da falha de vínculo corrigida nesta alteração.

## Integridade do backup

- `index.html.before-fix`: `4acf97c35f4bafe785899bb9b554c4a6bc5781f2a7449186cfa3c36ae8132f3d`
- `admin-users.index.ts.before-fix`: `fe534860035fbe76b201fce9aff8a80616c81de8e193e968fcff272e71bd57a8`
