-- Meta percentual de Absenteísmo configurável por operação.
-- A coluna é anulável para preservar o estado "Não cadastrada" até o administrador informar um valor.
-- Não altera cálculos, registros históricos, Auth, RLS ou outras tabelas.
ALTER TABLE public.sustentacao_configuracoes_operacao
  ADD COLUMN IF NOT EXISTS abs_meta_percentual numeric(8,2);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'sustentacao_configuracoes_operacao_abs_meta_percentual_check'
      AND conrelid = 'public.sustentacao_configuracoes_operacao'::regclass
  ) THEN
    ALTER TABLE public.sustentacao_configuracoes_operacao
      ADD CONSTRAINT sustentacao_configuracoes_operacao_abs_meta_percentual_check
      CHECK (abs_meta_percentual IS NULL OR abs_meta_percentual BETWEEN 0 AND 100);
  END IF;
END
$$;

COMMENT ON COLUMN public.sustentacao_configuracoes_operacao.abs_meta_percentual
  IS 'Meta percentual de Absenteísmo da operação, na mesma escala exibida no painel (0 a 100).';
