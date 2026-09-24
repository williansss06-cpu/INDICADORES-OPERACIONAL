-- Parâmetros configuráveis da análise gerencial de Absenteísmo.
-- Reutiliza a configuração existente por operação e o plano de ação existente.

ALTER TABLE public.sustentacao_configuracoes_operacao
  ADD COLUMN IF NOT EXISTS abs_horas_base_hc numeric(10,2) NOT NULL DEFAULT 176,
  ADD COLUMN IF NOT EXISTS abs_recorrencia_min_meses integer NOT NULL DEFAULT 3,
  ADD COLUMN IF NOT EXISTS abs_recorrencia_min_ocorrencias integer NOT NULL DEFAULT 3,
  ADD COLUMN IF NOT EXISTS abs_critico_horas_min numeric(10,2) NOT NULL DEFAULT 40,
  ADD COLUMN IF NOT EXISTS abs_critico_ocorrencias_min integer NOT NULL DEFAULT 3,
  ADD COLUMN IF NOT EXISTS abs_critico_crescimento_pct numeric(10,2) NOT NULL DEFAULT 30,
  ADD COLUMN IF NOT EXISTS abs_atencao_horas_min numeric(10,2) NOT NULL DEFAULT 16,
  ADD COLUMN IF NOT EXISTS abs_atencao_ocorrencias_min integer NOT NULL DEFAULT 2,
  ADD COLUMN IF NOT EXISTS abs_atencao_crescimento_pct numeric(10,2) NOT NULL DEFAULT 15;

ALTER TABLE public.sustentacao_plano_acao
  ADD COLUMN IF NOT EXISTS origem text,
  ADD COLUMN IF NOT EXISTS origem_contexto jsonb NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE public.sustentacao_configuracoes_operacao
  DROP CONSTRAINT IF EXISTS sustentacao_configuracoes_operacao_abs_recorrencia_min_meses_check,
  DROP CONSTRAINT IF EXISTS sustentacao_configuracoes_operacao_abs_recorrencia_min_ocorrencias_check,
  DROP CONSTRAINT IF EXISTS sustentacao_configuracoes_operacao_abs_critico_horas_min_check,
  DROP CONSTRAINT IF EXISTS sustentacao_configuracoes_operacao_abs_critico_ocorrencias_min_check,
  DROP CONSTRAINT IF EXISTS sustentacao_configuracoes_operacao_abs_critico_crescimento_pct_check,
  DROP CONSTRAINT IF EXISTS sustentacao_configuracoes_operacao_abs_atencao_horas_min_check,
  DROP CONSTRAINT IF EXISTS sustentacao_configuracoes_operacao_abs_atencao_ocorrencias_min_check,
  DROP CONSTRAINT IF EXISTS sustentacao_configuracoes_operacao_abs_atencao_crescimento_pct_check;

ALTER TABLE public.sustentacao_configuracoes_operacao
  ADD CONSTRAINT sustentacao_configuracoes_operacao_abs_recorrencia_min_meses_check CHECK (abs_recorrencia_min_meses BETWEEN 1 AND 24),
  ADD CONSTRAINT sustentacao_configuracoes_operacao_abs_recorrencia_min_ocorrencias_check CHECK (abs_recorrencia_min_ocorrencias BETWEEN 1 AND 1000),
  ADD CONSTRAINT sustentacao_configuracoes_operacao_abs_critico_horas_min_check CHECK (abs_critico_horas_min >= 0),
  ADD CONSTRAINT sustentacao_configuracoes_operacao_abs_critico_ocorrencias_min_check CHECK (abs_critico_ocorrencias_min >= 1),
  ADD CONSTRAINT sustentacao_configuracoes_operacao_abs_critico_crescimento_pct_check CHECK (abs_critico_crescimento_pct >= 0),
  ADD CONSTRAINT sustentacao_configuracoes_operacao_abs_atencao_horas_min_check CHECK (abs_atencao_horas_min >= 0),
  ADD CONSTRAINT sustentacao_configuracoes_operacao_abs_atencao_ocorrencias_min_check CHECK (abs_atencao_ocorrencias_min >= 1),
  ADD CONSTRAINT sustentacao_configuracoes_operacao_abs_atencao_crescimento_pct_check CHECK (abs_atencao_crescimento_pct >= 0);

DROP POLICY IF EXISTS sustentacao_configuracoes_operacao_select ON public.sustentacao_configuracoes_operacao;
CREATE POLICY sustentacao_configuracoes_operacao_select
  ON public.sustentacao_configuracoes_operacao
  FOR SELECT TO authenticated
  USING (
    tem_acesso_modulo(operacao_id, 'PLANO_SUSTENTACAO', 'VIEW')
    OR tem_acesso_modulo(operacao_id, 'ABSENTEISMO', 'VIEW')
  );

COMMENT ON COLUMN public.sustentacao_configuracoes_operacao.abs_horas_base_hc IS 'Horas mensais por HC usadas no cálculo de capacidade perdida';
COMMENT ON COLUMN public.sustentacao_configuracoes_operacao.abs_recorrencia_min_meses IS 'Quantidade mínima de meses com ocorrência para classificar recorrência';
COMMENT ON COLUMN public.sustentacao_configuracoes_operacao.abs_recorrencia_min_ocorrencias IS 'Quantidade mínima de ocorrências para classificar recorrência';
COMMENT ON COLUMN public.sustentacao_plano_acao.origem IS 'Origem do plano, por exemplo ABSENTEISMO';
COMMENT ON COLUMN public.sustentacao_plano_acao.origem_contexto IS 'Contexto determinístico que originou o plano de ação';
