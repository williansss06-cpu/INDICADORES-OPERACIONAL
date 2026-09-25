# Backup — Minhas Ações do Coordenador

Este diretório preserva o `index.html` e a migration local anteriores à implementação da visão **Minhas Ações** e do escopo por `responsavel_user_id`.

A alteração adiciona a visão restrita do perfil `coordenador`, os campos de andamento e auditoria na tabela `sustentacao_plano_acao`, além de políticas RLS e triggers que preservam a operação, o indicador, o responsável e a data original da ação durante atualizações do Coordenador.

Os registros históricos existentes não foram excluídos, recriados ou reordenados. O usuário Auth é a referência canônica para responsável, criador, último atualizador e concluidor quando esses eventos ocorrerem após a migration.
