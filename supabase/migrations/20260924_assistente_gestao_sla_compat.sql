-- Compatibilidade: alguns lançamentos SLA históricos não têm indicador_id.
-- Reutiliza o contexto já autorizado e acrescenta somente os lançamentos da operação
-- para os quais o usuário tem permissão de SLA, sem relaxar a operação autorizada.
CREATE OR REPLACE FUNCTION public.assistente_obter_contexto_v2(
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
  v_sla jsonb;
BEGIN
  v_base := public.assistente_obter_contexto(p_operacao_id, p_ano, p_mes, p_modulo, p_filtros);
  SELECT coalesce(array_agg((x->>'id')::bigint), '{}')
    INTO v_ops
  FROM jsonb_array_elements(coalesce(v_base->'operacoes', '[]'::jsonb)) x;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', s.id,
      'operacao_id', s.operacao_id,
      'ano', s.ano,
      'mes', s.mes,
      'indicador', s.indicador,
      'indicador_id', s.indicador_id,
      'tipo', s.tipo,
      'valor', s.valor
    ) ORDER BY s.operacao_id, s.mes, s.indicador), '[]'::jsonb)
    INTO v_sla
  FROM public.sustentacao_sla_neolog_pontuacoes s
  WHERE s.operacao_id = ANY(v_ops)
    AND s.ano = coalesce(p_ano, extract(year FROM current_date)::integer)
    AND public.assistente_tem_permissao(s.operacao_id, 'sla_neolog')
    AND (
      s.indicador_id IS NULL
      OR public.tem_acesso_indicador(s.operacao_id, s.indicador_id, 'VIEW')
    );

  RETURN jsonb_set(v_base, '{sla}', v_sla, true);
END;
$$;

REVOKE ALL ON FUNCTION public.assistente_obter_contexto_v2(bigint,integer,integer,text,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.assistente_obter_contexto_v2(bigint,integer,integer,text,jsonb) TO authenticated;
COMMENT ON FUNCTION public.assistente_obter_contexto_v2(bigint,integer,integer,text,jsonb) IS 'Contexto do Assistente com compatibilidade para lançamentos SLA históricos sem indicador_id.';
