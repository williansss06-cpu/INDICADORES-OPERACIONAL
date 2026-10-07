-- Corrige vínculos históricos do SLA NEOLOG da operação GLP_ACHE.
-- Preserva IDs, valores, meses, tipos e textos originais; atualiza somente indicador_id.
-- A migration é idempotente: somente registros ainda sem vínculo são atualizados.

BEGIN;

UPDATE public.sustentacao_sla_neolog_pontuacoes AS s
SET indicador_id = i.id,
    updated_at = now()
FROM public.sustentacao_indicadores AS i
WHERE s.operacao_id = 2
  AND s.indicador_id IS NULL
  AND i.operacao_id = s.operacao_id
  AND i.ativo = true
  AND i.nome = CASE s.indicador
    WHEN 'Segurança e BPDA' THEN 'Ocorrências Segurança e BPDA'
    WHEN 'Ocorrências Fora do Prazo' THEN 'Ocorrências Monitoramento'
    ELSE s.indicador
  END;

DO $$
DECLARE
  remaining_count integer;
BEGIN
  SELECT count(*)::integer
    INTO remaining_count
    FROM public.sustentacao_sla_neolog_pontuacoes
   WHERE operacao_id = 2
     AND indicador_id IS NULL;

  IF remaining_count > 0 THEN
    RAISE EXCEPTION 'Existem % lançamentos SLA GLP_ACHE sem indicador_id após a correção', remaining_count;
  END IF;
END $$;

COMMIT;

-- Reversão dos 16 vínculos corrigidos, caso necessária:
-- UPDATE public.sustentacao_sla_neolog_pontuacoes
-- SET indicador_id = NULL
-- WHERE id IN (51,68,87,108,120,133,160,2911,3129,3060,2984,2992,3207,2976,3199,7503);
