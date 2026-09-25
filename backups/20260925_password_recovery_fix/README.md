# Correção do fluxo de criação e recuperação de senha

Este backup preserva a versão do `index.html` anterior à correção do fluxo de autenticação.

A alteração do frontend é restrita ao ciclo de senha: mensagem de sucesso após `resetPasswordForEmail`, detecção antecipada de callbacks PKCE e hash do Supabase, suporte à tela de primeiro acesso por convite, tratamento de `PASSWORD_RECOVERY`, validação de link expirado e encerramento da sessão temporária após a troca de senha.

Não foram alterados usuários, permissões, RLS, tabelas, dados operacionais, indicadores ou configurações do Supabase. O Gmail do Supabase Auth permanece inalterado.

A URL de produção usada no redirecionamento é:

`https://williansss06-cpu.github.io/INDICADORES-OPERACIONAL/?reset-password=true`
