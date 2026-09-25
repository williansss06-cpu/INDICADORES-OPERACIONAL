# Notificações e portal externo de Planos de Ação

Esta entrega prepara, de forma aditiva, notificações imediatas, lembretes, portal externo seguro, eventos de auditoria e evidências privadas para `sustentacao_plano_acao`.

O Gmail atual permanece exclusivo do Supabase Auth. As notificações operacionais usam a API HTTP do Resend por Edge Function. A chave `RESEND_API_KEY` não é armazenada neste repositório.

A primeira tentativa de aplicar a migration foi interrompida porque `pg_cron` ainda não estava ativo; a migration foi ajustada para habilitar `pg_cron` e `pg_net` antes de criar o agendamento. Nenhum dado operacional foi alterado pela tentativa com erro.

O envio fica pendente até a criação de uma conta Resend, verificação do domínio/remetente e cadastro de `RESEND_API_KEY` em Supabase Dashboard → Edge Functions → Secrets.
