# Diagnóstico e proteção do fluxo de e-mails de autenticação — 2026-09-24

## Diagnóstico

O projeto `nemvssopcgmfxjndpmlw` está com **Enable custom SMTP** desligado em Authentication → Emails → SMTP Settings. Os logs do Auth confirmam respostas `429 over_email_send_rate_limit` no endpoint `/recover`, usando o remetente padrão `noreply@mail.app.supabase.io`.

## Campos exigidos pelo Supabase

Para habilitar SMTP customizado são necessários: endereço de remetente verificado, nome do remetente, host SMTP, porta SMTP, usuário SMTP e senha SMTP. A tela também possui intervalo mínimo por usuário; o valor atual exibido é 60 segundos. As portas usuais são 465 (TLS implícito) e 587 (STARTTLS); a escolha deve seguir o provedor de e-mail.

A senha SMTP deve ser uma senha de aplicativo/token quando o provedor exigir, e o endereço de remetente deve estar autorizado no domínio do provedor. O Supabase informa que, após habilitar SMTP customizado, o limite de e-mails passa para 30 por hora e pode ser ajustado na tela Rate Limits; isso não significa limite ilimitado.

## Ajuste aplicado no frontend

O fluxo `CRIAR / RECUPERAR SENHA` agora traduz erros de rate limit para uma mensagem amigável e bloqueia novas solicitações por 60 segundos após uma solicitação bem-sucedida. Os botões de entrar e salvar a primeira senha também possuem trava contra duplo clique. O fluxo do Supabase Auth foi preservado.

## Backup

- `index.html.before-fix`: `1de3a8b55859d9ad5730fa7dee472f9ea66fe234c3e45127553dbb8d975bd605`

Nenhum usuário, permissão, tabela ou configuração do banco foi alterado nesta etapa.
