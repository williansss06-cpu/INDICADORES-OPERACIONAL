-- Permite que cada indicador informe como seus valores devem ser exibidos.
-- Os indicadores existentes continuam percentuais, exceto os tipos GLP já definidos.
ALTER TABLE public.sustentacao_indicadores
  ADD COLUMN IF NOT EXISTS formato text NOT NULL DEFAULT 'PERCENT';

ALTER TABLE public.sustentacao_indicadores
  DROP CONSTRAINT IF EXISTS sustentacao_indicadores_formato_check;

ALTER TABLE public.sustentacao_indicadores
  ADD CONSTRAINT sustentacao_indicadores_formato_check
  CHECK (formato IN ('PERCENT', 'NUMBER', 'CURRENCY'));

UPDATE public.sustentacao_indicadores
SET formato = 'CURRENCY', updated_at = now()
WHERE operacao_id = (SELECT id FROM public.sustentacao_operacoes WHERE codigo = 'GLP_ACHE' LIMIT 1)
  AND nome = 'Avarias Valor';

UPDATE public.sustentacao_indicadores
SET formato = 'NUMBER', updated_at = now()
WHERE operacao_id = (SELECT id FROM public.sustentacao_operacoes WHERE codigo = 'GLP_ACHE' LIMIT 1)
  AND nome IN ('Ocorrências Monitoramento', 'Avarias Unidades');
