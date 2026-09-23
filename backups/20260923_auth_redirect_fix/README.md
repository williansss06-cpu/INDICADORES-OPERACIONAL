# Correção de redirect de convite

Este diretório registra o ponto de reversão e os arquivos finais da correção do fluxo de convite e confirmação de usuários.

A versão anterior está nos arquivos `*.before-fix`. A versão corrigida faz os novos convites retornarem para:

`https://williansss06-cpu.github.io/INDICADORES-OPERACIONAL/`

Também reenvia um convite novo quando o usuário já existe no Auth, mas ainda não confirmou o e-mail, e exibe uma mensagem clara quando o Supabase retorna `otp_expired`.

A `Site URL` global do projeto ainda pode ser ajustada no painel Supabase para o mesmo endereço de produção. A Edge Function já usa `redirectTo` explícito, portanto novos convites não dependem dessa configuração padrão.
