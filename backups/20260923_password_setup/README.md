# Fluxo de criação de senha após convite

A versão anterior está em `index.html.before-fix` e a versão corrigida em `index.html.after-fix`.

A aplicação agora:

1. mostra `CRIAR / RECUPERAR SENHA` no login;
2. envia um link de recuperação para o e-mail informado, usando o endereço publicado como redirect;
3. identifica links de convite/recuperação autenticados;
4. apresenta uma tela para o usuário criar e confirmar a própria senha;
5. atualiza a senha com `supabase.auth.updateUser`, sem que o administrador veja ou cadastre a senha.
