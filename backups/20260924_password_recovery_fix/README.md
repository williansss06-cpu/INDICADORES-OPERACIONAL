# Correção do fluxo de recuperação e criação de senha — 2026-09-24

## Baseline

O ponto de reversão do frontend é `index.html.before-fix`, copiado antes da alteração. A soma SHA-256 está em `SHA256SUMS.before`. O commit de origem foi `57266104b99ac9b1e205682cc6d134f0ffa95147`.

## Correção aplicada

O fluxo de `resetPasswordForEmail` passa a usar explicitamente `https://williansss06-cpu.github.io/INDICADORES-OPERACIONAL/?reset-password=true`. A aplicação reconhece a rota de recuperação, o hash `type=recovery` e o evento `PASSWORD_RECOVERY` do Supabase Auth antes de chamar o login normal.

A tela de criação de senha é compartilhada com o primeiro acesso por convite e apresenta nova senha, confirmação, validação mínima de oito caracteres, atualização via `supabase.auth.updateUser({ password })`, mensagem de sucesso e retorno controlado ao login após `signOut`.

Nenhum usuário, permissão, tabela, indicador ou dado operacional foi alterado.

## Configuração Auth

A URL base de produção já estava permitida. Foi adicionada aos Redirect URLs do Supabase Auth a rota exata:

`https://williansss06-cpu.github.io/INDICADORES-OPERACIONAL/?reset-password=true`

## Pendência de teste manual

O teste ponta a ponta depende de abrir o e-mail real de recuperação, clicar em `Reset password`, cadastrar uma nova senha e entrar novamente. Essa etapa será validada no endereço publicado após o deploy.
