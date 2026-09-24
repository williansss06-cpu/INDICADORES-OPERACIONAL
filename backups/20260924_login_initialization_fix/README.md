# Correção do fluxo de inicialização e login — 2026-09-24

## Causa

O IIFE `loadAbsenteismo` era executado durante a avaliação do `index.html`, antes da declaração de `operationConfigs`. Isso fazia `absRenderDashboard()` acessar uma variável em Temporal Dead Zone e produzir `Cannot access 'operationConfigs' before initialization`.

O estado `authState` também permanecia declarado tardiamente, próximo ao cliente Supabase e às funções de login, deixando o fluxo vulnerável a chamadas antecipadas durante a inicialização.

## Correções

- `operationConfigs` e `authState` foram movidos para o bloco inicial de estado, antes das funções executáveis.
- O IIFE de Absenteísmo foi removido.
- O Absenteísmo agora é inicializado somente quando o usuário autorizado abre o módulo.
- Falhas do Absenteísmo ficam restritas ao módulo e não interrompem a sessão.
- O login agora conclui sessão, perfil e permissões antes de abrir o sistema.
- O carregamento operacional ocorre depois da autorização, sem bloquear a abertura da aplicação.
- `try/catch/finally` foi mantido no login, com restauração garantida do botão `ENTRAR`.
- O bootstrap do Auth possui tratamento de erro próprio.
- O estado de operação, permissões e dados carregados é limpo no logout e antes de um novo login.
- Nenhum `setTimeout` foi usado para corrigir a ordem de inicialização.

## Validação

- `node --check` aprovado.
- `git diff --check` aprovado.
- Carregamento headless sem sessão: nenhum `ReferenceError`, `Cannot access`, `Uncaught` ou `SyntaxError` encontrado.
- Apenas um bloco de declaração existe para `operationConfigs` e `authState`.
- Não existe mais IIFE de carregamento antecipado do Absenteísmo.
