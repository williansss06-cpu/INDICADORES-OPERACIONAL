-- Proteção de dados individuais do Absenteísmo.
-- Usuários com ABSENTEISMO_VIEW recebem análise consolidada via RPC;
-- nomes e registros individuais exigem ABSENTEISMO_DADOS_INDIVIDUAIS_VIEW.

CREATE OR REPLACE FUNCTION public.obter_absenteismo_consolidado(
  p_operacao_id bigint,
  p_ano integer
)
RETURNS TABLE (
  mes_referencia text,
  local text,
  area text,
  centro_custo text,
  setor text,
  motivo text,
  total_colaboradores bigint,
  ocorrencias bigint,
  horas_esperadas numeric,
  horas_disponiveis numeric,
  horas_trabalhadas numeric,
  horas_faltas numeric,
  horas_atestados numeric,
  horas_atrasos numeric,
  horas_improdutivas numeric,
  indice_absenteismo numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.tem_acesso_modulo(p_operacao_id, 'ABSENTEISMO', 'VIEW') THEN
    RAISE EXCEPTION 'Acesso não autorizado ao Absenteísmo desta operação';
  END IF;

  RETURN QUERY
  SELECT
    r.mes_referencia,
    r.local,
    r.area,
    r.centro_custo,
    r.setor,
    NULL::text AS motivo,
    count(DISTINCT r.colaborador) AS total_colaboradores,
    count(*) FILTER (WHERE coalesce(r.horas_improdutivas, 0) > 0) AS ocorrencias,
    sum(coalesce(r.horas_esperadas, 0)),
    sum(coalesce(r.horas_disponiveis, 0)),
    sum(coalesce(r.horas_trabalhadas, 0)),
    sum(coalesce(r.horas_faltas, 0)),
    sum(coalesce(r.horas_atestados, 0)),
    sum(coalesce(r.horas_atrasos, 0)),
    sum(coalesce(r.horas_improdutivas, 0)),
    CASE WHEN sum(coalesce(r.horas_esperadas, 0)) = 0 THEN 0
      ELSE sum(coalesce(r.horas_improdutivas, 0)) / sum(coalesce(r.horas_esperadas, 0))
    END
  FROM public.absenteismo_registros r
  WHERE r.operacao_id = p_operacao_id
    AND r.ano = p_ano
  GROUP BY r.mes_referencia, r.local, r.area, r.centro_custo, r.setor;
END;
$$;

REVOKE ALL ON FUNCTION public.obter_absenteismo_consolidado(bigint, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.obter_absenteismo_consolidado(bigint, integer) TO authenticated;

DROP POLICY IF EXISTS absenteismo_registros_acesso ON public.absenteismo_registros;
DROP POLICY IF EXISTS absenteismo_registros_individual_select ON public.absenteismo_registros;
DROP POLICY IF EXISTS absenteismo_registros_insert ON public.absenteismo_registros;
DROP POLICY IF EXISTS absenteismo_registros_update ON public.absenteismo_registros;
DROP POLICY IF EXISTS absenteismo_registros_delete ON public.absenteismo_registros;

CREATE POLICY absenteismo_registros_individual_select
  ON public.absenteismo_registros FOR SELECT TO authenticated
  USING (public.tem_acesso_modulo(operacao_id, 'ABSENTEISMO_DADOS_INDIVIDUAIS', 'VIEW'));

CREATE POLICY absenteismo_registros_insert
  ON public.absenteismo_registros FOR INSERT TO authenticated
  WITH CHECK (public.tem_acesso_modulo(operacao_id, 'ABSENTEISMO', 'EDIT'));

CREATE POLICY absenteismo_registros_update
  ON public.absenteismo_registros FOR UPDATE TO authenticated
  USING (public.tem_acesso_modulo(operacao_id, 'ABSENTEISMO', 'EDIT'))
  WITH CHECK (public.tem_acesso_modulo(operacao_id, 'ABSENTEISMO', 'EDIT'));

CREATE POLICY absenteismo_registros_delete
  ON public.absenteismo_registros FOR DELETE TO authenticated
  USING (public.tem_acesso_modulo(operacao_id, 'ABSENTEISMO', 'EDIT'));
