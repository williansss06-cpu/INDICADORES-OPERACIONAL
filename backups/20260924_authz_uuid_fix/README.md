# Correção de autorização pós-login por UUID Auth — 2026-09-24

## Causa confirmada

O usuário `williansss06@gmail.com` autenticava no Supabase Auth com o UUID `1a9afbd6-6d45-4b2d-8b89-be7c65578f7d`, mas não possuía linha correspondente em `public.sustentacao_usuarios`. O frontend consultava a autorização por e-mail, e a ausência do cadastro administrativo fazia o login terminar em “Acesso não autorizado”.

## Correção

O cadastro administrativo foi vinculado ao UUID Auth existente, com perfil `super_admin`, ativo e escopo global. A migration `20260924_auth_uuid_authorization.sql` formaliza `sustentacao_usuarios.user_id` como UUID canônico de `auth.users.id`, mantém FK/índice e publica uma RPC somente leitura para consultar o cadastro pelo `auth.uid()`.

O frontend passa a consultar `sustentacao_usuarios.user_id = authUser.id`, e a Central identifica Auth sem cadastro como `Pendente de vínculo`, além dos estados `Ativo`, `Convite pendente` e `Bloqueado`.

O usuário `willian.soares@mundiallogistics.com.br` não foi substituído nem removido.
