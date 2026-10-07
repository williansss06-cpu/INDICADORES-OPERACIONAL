# Correção de visibilidade — Segurança e BPDA

## Diagnóstico

André Bueno possui no Supabase a permissão ativa para o indicador oficial `Ocorrências Segurança e BPDA` na operação `GLP_ACHE`, além do módulo `SLA_NEOLOG`.

O quadro SLA exibe o rótulo amigável `Segurança e BPDA`, mas o frontend consultava esse texto literalmente para localizar o indicador. Como o cadastro oficial possui o prefixo `Ocorrências`, a permissão não era encontrada e a linha era ocultada.

## Correção

O frontend passou a mapear `Segurança e BPDA` para `Ocorrências Segurança e BPDA` antes de consultar a permissão. Nenhum dado, usuário, indicador, RLS ou permissão do Supabase foi alterado.

## Reversão

Restaurar `index.html.before` sobre `index.html` e publicar novamente, se necessário.
