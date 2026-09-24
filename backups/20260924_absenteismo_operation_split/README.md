# Importação de Absenteísmo por operação — 2026-09-24

Backup reversível criado antes da melhoria do importador de planilhas.

A planilha de teste `ABSjulho.xlsx` contém a coluna `SETOR`, usada como identificador operacional:

- `OPERAÇÃO MATRIZ` → `MATRIZ`
- `ACHE` → `GLP_ACHE`

Validação realizada: 421 registros, 219 Matriz, 202 GLP/Aché e nenhum registro desconhecido.

A melhoria separa a planilha no navegador/localStorage por operação e não altera automaticamente os 840 registros históricos do Supabase.
