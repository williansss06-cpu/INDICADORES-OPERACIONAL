# Correção de visibilidade dos dados SLA NEOLOG

## Diagnóstico

Os lançamentos de agosto e setembro de 2026 existiam no Supabase, mas foram gravados com `indicador_id` nulo. A policy RLS de leitura do SLA exige `tem_acesso_indicador(operacao_id, indicador_id, 'VIEW')`; usuários Super Administradores conseguiam consultar os registros, enquanto usuários da operação, como André Bueno, não conseguiam.

A gravação anterior do frontend também não enviava `indicador_id` no payload do SLA.

## Escopo

- Preservar IDs, valores, meses, tipos, operação e textos dos lançamentos.
- Preencher somente `indicador_id` usando os indicadores oficiais da operação `GLP_ACHE`.
- Mapear `Segurança e BPDA` para `Ocorrências Segurança e BPDA`.
- Mapear `Ocorrências Fora do Prazo` para `Ocorrências Monitoramento`.
- Corrigir o frontend para que novos salvamentos também enviem o vínculo.

## Reversão

A lista original está em `sla_rows_before.csv`. A migration contém o comando de reversão dos 16 IDs corrigidos.
