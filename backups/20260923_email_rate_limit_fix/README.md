# Correção do fluxo de convites e limite de e-mail

## Baseline

- Commit anterior: `ddbad696679935b3d38923602e0007119749813a`
- Arquivos preservados: `index.html.before-fix` e `index.ts.before-fix`.
- As somas SHA-256 estão em `SHA256SUMS`.

## Causa confirmada

O projeto usa `supabase.auth.admin.inviteUserByEmail` dentro da Edge Function `admin-users`. Os logs do Auth registraram `429`, `error_code=over_email_send_rate_limit`, em `/invite`, e também o mesmo limite em `/recover`. O remetente observado foi `noreply@mail.app.supabase.io`, confirmando que o provedor SMTP padrão do Supabase ainda estava ativo.

A interface não tinha duas chamadas de convite no mesmo botão, mas o salvamento de qualquer usuário existente ainda não confirmado chamava novamente `inviteUserByEmail` de forma automática. Isso misturava atualização de cadastro com reenvio de e-mail e podia consumir o limite ao repetir salvamentos.

## Correção aplicada

- `Salvar permissões` agora envia convite apenas para usuário ainda inexistente no `auth.users`.
- Usuário já existente e pendente é salvo de forma idempotente sem novo disparo de e-mail.
- Foi criado o botão explícito `Reenviar convite`, disponível somente para usuário já criado.
- A interface bloqueia duplo clique enquanto a operação está em andamento.
- A Edge Function continua usando Auth real e `admin_save_user_access`; não há bypass do Supabase Auth.
- Erros de limite são convertidos para mensagem amigável, sem exibir `email rate limit exceeded`.
- Se um convite falhar depois que o Auth já criou o usuário, a função preserva o `user_id` e tenta salvar o vínculo/permissões sem duplicar o usuário.
- O redirect permanece apontando para o GitHub Pages de produção.

## SMTP

A configuração de SMTP customizado ainda está desabilitada no projeto. Para produção, é necessário receber as credenciais do provedor corporativo ou transacional escolhido e configurar host, porta, usuário, senha, remetente e domínio autenticado. Nenhuma senha foi gravada no repositório ou no frontend.
