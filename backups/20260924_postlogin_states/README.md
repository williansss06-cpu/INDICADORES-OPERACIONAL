# Correção do pós-login e autorização — 2026-09-24

## Problema

Após o login, a aplicação escondia o login antes de concluir a validação do usuário e das permissões. Qualquer erro ou atraso nas consultas seguintes disparava `signOut()`, exibindo “Acesso não validado” e, ao mesmo tempo, deixando parte do painel operacional renderizada.

## Correção

A aplicação agora possui estados separados: `AUTHENTICATING`, `AUTHENTICATED_LOADING`, `AUTHORIZED`, `NOT_AUTHORIZED` e `CONNECTION_ERROR`.

O painel inteiro fica oculto até que a sessão seja validada por `getSession()`, o usuário seja confirmado por `getUser()`, o vínculo UUID seja encontrado em `sustentacao_usuarios`, o status ativo seja confirmado e as consultas iniciais de permissões/operação/dados terminem.

Usuário autenticado sem cadastro ou sem autorização permanece em uma tela de **Acesso pendente de autorização**; não é desconectado automaticamente. Falhas temporárias mostram **Erro ao validar acesso**, preservam a sessão e disponibilizam nova tentativa.

O fluxo de recuperação/criação de senha não foi alterado.
