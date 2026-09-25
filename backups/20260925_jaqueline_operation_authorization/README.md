# Correção de autorização por operação — 2025-09-25

## Diagnóstico

- Auth da Jaqueline: `df299c57-911d-4cc2-83c0-9f149fcb10d9`.
- Cadastro administrativo: existente, ativo e com perfil `coordenador`.
- Vínculo operacional: `user_id` igual ao UUID Auth, `operacao_id = 1`, código `MATRIZ`, ativo.
- Permissão de módulo: `PLANO_SUSTENTACAO` estava como `NENHUM`.
- Causa: a policy de `sustentacao_operacoes` utilizava `tem_acesso_operacao_visualizacao(id)`, que exigia simultaneamente vínculo operacional e permissão `PLANO_SUSTENTACAO`.

## Correção

A policy passa a usar somente `tem_acesso_operacao(id)` para resolver as operações autorizadas. As policies de indicadores, resultados, Absenteísmo, SLA, Plano de Ação e demais módulos continuam aplicando as permissões específicas.

## Preservação

Este backup contém o `index.html` anterior à correção. A alteração de banco é aditiva/reversível por nova migration e não altera usuários, senhas, dados operacionais ou permissões existentes.
