-- Contexto conversacional do Assistente.
-- Somente leitura: amplia a RPC para comparações mensais e recorrência do mês,
-- preservando RLS lógico, permissões e todos os dados existentes.
CREATE OR REPLACE FUNCTION public.assistente_obter_conversa_contexto(
  p_operacao_id bigint DEFAULT NULL,
  p_ano integer DEFAULT NULL,
  p_mes integer DEFAULT NULL,
  p_modulo text DEFAULT NULL,
  p_filtros jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_base jsonb;
  v_ops bigint[];
  v_year integer;
  v_month integer;
  v_mensal jsonb;
  v_recorrentes_mes jsonb;
BEGIN
  v_base := public.assistente_obter_contexto_v2(p_operacao_id, p_ano, p_mes, p_modulo, p_filtros);
  IF coalesce((v_base->>'permitido')::boolean, false) IS NOT TRUE THEN
    RETURN v_base;
  END IF;

  v_year := coalesce((v_base->>'ano')::integer, p_ano, extract(year FROM current_date)::integer);
  v_month := greatest(1, least(12, coalesce((v_base->>'mes')::integer, p_mes, 1)));

  SELECT coalesce(array_agg((x->>'id')::bigint ORDER BY (x->>'id')::bigint), '{}')
    INTO v_ops
  FROM jsonb_array_elements(coalesce(v_base->'operacoes', '[]'::jsonb)) x;

  IF cardinality(v_ops) IS NULL OR cardinality(v_ops) = 0 THEN
    RETURN v_base;
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'operacao_id', q.operacao_id,
      'ano', q.ano,
      'mes', q.mes,
      'colaboradores', q.colaboradores,
      'horas_improdutivas', q.horas_improdutivas,
      'horas_disponiveis', q.horas_disponiveis,
      'dias_afastamento', q.dias_afastamento,
      'indice_absenteismo', q.indice_absenteismo
    ) ORDER BY q.ano, q.mes), '[]'::jsonb)
    INTO v_mensal
  FROM (
    SELECT
      r.operacao_id,
      r.ano,
      r.mes,
      count(DISTINCT r.colaborador) AS colaboradores,
      coalesce(sum(r.horas_improdutivas), 0) AS horas_improdutivas,
      coalesce(sum(r.horas_disponiveis), 0) AS horas_disponiveis,
      coalesce(sum(coalesce(r.dias_falta, 0) + coalesce(r.dias_atestado, 0)), 0) AS dias_afastamento,
      CASE WHEN coalesce(sum(r.horas_disponiveis), 0) > 0
        THEN round((sum(coalesce(r.horas_improdutivas, 0)) / sum(r.horas_disponiveis)) * 100, 2)
        ELSE 0
      END AS indice_absenteismo
    FROM public.absenteismo_registros r
    WHERE r.operacao_id = ANY(v_ops)
      AND r.ano = v_year
      AND r.mes BETWEEN 1 AND v_month
      AND public.assistente_tem_permissao(r.operacao_id, 'absenteismo')
    GROUP BY r.operacao_id, r.ano, r.mes
  ) q;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'operacao_id', q.operacao_id,
      'colaborador', q.colaborador,
      'area', q.area,
      'meses', q.meses,
      'horas', q.horas
    ) ORDER BY q.horas DESC), '[]'::jsonb)
    INTO v_recorrentes_mes
  FROM (
    SELECT
      r.operacao_id,
      r.colaborador,
      max(coalesce(r.area, r.local)) AS area,
      count(DISTINCT r.mes) AS meses,
      coalesce(sum(r.horas_improdutivas), 0) AS horas
    FROM public.absenteismo_registros r
    WHERE r.operacao_id = ANY(v_ops)
      AND r.ano = v_year
      AND r.mes <= v_month
      AND public.assistente_tem_permissao(r.operacao_id, 'absenteismo')
    GROUP BY r.operacao_id, r.colaborador
    HAVING count(DISTINCT r.mes) >= 2
  ) q;

  v_base := jsonb_set(v_base, '{absenteismo,mensal}', v_mensal, true);
  v_base := jsonb_set(v_base, '{absenteismo,recorrentes_mes}', v_recorrentes_mes, true);
  RETURN v_base;
END;
$$;

REVOKE ALL ON FUNCTION public.assistente_obter_conversa_contexto(bigint,integer,integer,text,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.assistente_obter_conversa_contexto(bigint,integer,integer,text,jsonb) TO authenticated;
COMMENT ON FUNCTION public.assistente_obter_conversa_contexto(bigint,integer,integer,text,jsonb) IS 'Contexto somente leitura para conversa do Assistente, com série mensal e recorrência autorizadas.';
