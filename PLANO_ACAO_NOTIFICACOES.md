# Notificações e portal de Planos de Ação

## Escopo implementado

A implementação é aditiva ao Plano de Sustentação existente. A tabela `sustentacao_plano_acao` continua sendo a fonte das ações e preserva IDs, operação, indicador, responsável, datas, status e histórico. Foram acrescentados campos para distinguir responsável da plataforma e responsável externo, e para registrar autoria, atualização e conclusão por UUID e timestamp.

A fila `sustentacao_acao_notificacoes` registra atribuição, reenvio e lembrete como estados independentes da ação. A ação é salva primeiro; falha de e-mail não desfaz o INSERT/UPDATE. O worker registra `PENDENTE`, `PROCESSANDO`, `ENVIADO`, `FALHA` ou `CANCELADO` e faz novas tentativas com intervalo progressivo.

`pg_cron` acorda o worker a cada cinco minutos. O cálculo padrão do lembrete é semanal às 09:00 em `America/Sao_Paulo`; a tabela `sustentacao_acao_lembrete_config` já está preparada para as estratégias semanal, três dias antes, no vencimento e após vencimento, por operação.

## Responsáveis

Para usuário interno, o cadastro guarda `responsavel_user_id` e o e-mail é obtido do vínculo administrativo. O link da mensagem direciona para `?action-id=<id>` e a aplicação exige a sessão Auth do usuário. Para responsável externo, o backend gera token aleatório, grava somente o hash para validação e mantém o token cifrado no backend. O link abre somente a ação individual; não concede acesso ao dashboard.

A conclusão bloqueia novas alterações pelo portal e mantém o token em modo somente leitura por 30 dias. O administrador pode revogar ou regenerar o acesso. O histórico registra criação, atribuição, envio, falha, reenvio, acesso ao portal, alterações, evidências, conclusão e revogação/regeneração.

## Evidências

O bucket privado `plano-acao-evidencias` aceita imagens e PDF até 10 MB. O backend emite URL de upload assinada após validar o token, o tipo MIME, o tamanho e o prefixo da ação. O acesso não é público e a policy de leitura exige permissão para a própria ação/operação.

## Edge Function

A função `action-notifications` possui autenticação própria por três caminhos: chave interna exclusiva para o Cron, sessão JWT para administradores internos e token individual para portal externo. O endpoint não usa Service Role no frontend. A função usa `SUPABASE_SERVICE_ROLE_KEY` apenas no ambiente protegido da Edge Function.

O envio operacional usa API HTTP do Resend, porque a plataforma hospedada do Supabase bloqueia conexões de saída SMTP nas portas 25 e 587. O Gmail existente permanece exclusivamente no Supabase Auth.

## Configuração pendente do Resend

Nenhuma chave foi inserida nesta entrega. Para ativar os envios:

1. Criar uma conta em [Resend](https://resend.com/).
2. Em **Domains**, adicionar o domínio corporativo que será usado no remetente, por exemplo `mundiallogistics.com.br`.
3. Publicar no DNS os registros SPF, DKIM e, quando solicitado, DMARC apresentados pelo Resend. Aguardar o status **Verified**.
4. Em **API Keys**, criar uma chave com permissão de envio. Copiar a chave somente no momento do cadastro; ela não deve ser enviada por chat nem commitada.
5. No Supabase definitivo `nemvssopcgmfxjndpmlw`, abrir **Project Settings → Edge Functions → Secrets** e criar:
   - `RESEND_API_KEY`: a chave da API do Resend;
   - `ACTION_EMAIL_FROM`: remetente verificado completo, por exemplo `Plano de Sustentação <acoes@mundiallogistics.com.br>`.
6. Não alterar os secrets SMTP do Gmail em **Authentication → SMTP Settings**. Eles continuam destinados aos convites e à recuperação de senha do Supabase Auth.

Antes de cadastrar esses dois secrets, a fila pode permanecer pendente com a mensagem `Resend ainda não configurado`; isso não impede o salvamento das ações. Depois do cadastro, o próximo ciclo do Cron processa as notificações pendentes.

## Migrações

- `20260924_action_notifications_portal.sql`: estrutura principal, triggers, fila, RLS, bucket e Cron.
- `20260924_action_notifications_compat.sql`: normalização segura de responsáveis históricos sem e-mails retroativos.
- `20260924_action_audit_fields.sql`: autoria, atualização e conclusão por usuário e timestamp.
