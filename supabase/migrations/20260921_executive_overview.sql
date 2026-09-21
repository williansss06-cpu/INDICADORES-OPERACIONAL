-- Visão Executiva: consolidação somente leitura e autorização por operação/módulo/indicador.
-- Não altera dados existentes nem cria tabelas de negócio.

CREATE OR REPLACE FUNCTION public.obter_visao_executiva(
  p_operacao_id bigint,
  p_ano integer
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
SELECT CASE
  WHEN NOT EXISTS (
    SELECT 1
    FROM public.sustentacao_operacoes o
    WHERE o.id = p_operacao_id
      AND o.ativo = true
  )
  OR NOT public.tem_acesso_modulo(p_operacao_id, 'VISAO_EXECUTIVA', 'VIEW')
  THEN jsonb_build_object(
    'permitido', false,
    'operacao', NULL,
    'indicadores', '[]'::jsonb,
    'resultados', '[]'::jsonb,
    'sla', '[]'::jsonb,
    'acoes', '[]'::jsonb,
    'absenteismo', jsonb_build_object('permitido', false, 'mensal', '[]'::jsonb, 'motivos', '[]'::jsonb, 'areas', '[]'::jsonb, 'pessoas', '[]'::jsonb),
    'acessos', jsonb_build_object('visao_executiva', false, 'plano_acao', false, 'sla_neolog', false, 'absenteismo', false)
  )
  ELSE jsonb_build_object(
    'permitido', true,
    'operacao', (
      SELECT jsonb_build_object('id', o.id, 'codigo', o.codigo, 'nome', o.nome)
      FROM public.sustentacao_operacoes o
      WHERE o.id = p_operacao_id
    ),
    'indicadores', COALESCE((
      SELECT jsonb_agg(x ORDER BY x->>'ordem')
      FROM (
        SELECT jsonb_build_object(
          'id', i.id,
          'nome', i.nome,
          'meta', i.meta,
          'peso', i.peso,
          'polaridade', i.polaridade,
          'ordem', i.ordem,
          'formato', i.formato,
          'ativo', i.ativo
        ) AS x
        FROM public.sustentacao_indicadores i
        WHERE i.operacao_id = p_operacao_id
          AND i.ativo = true
          AND public.tem_acesso_indicador(p_operacao_id, i.id, 'VIEW')
        ORDER BY i.ordem, i.id
      ) q
    ), '[]'::jsonb),
    'resultados', COALESCE((
      SELECT jsonb_agg(x ORDER BY (x->>'mes')::integer, (x->>'indicador_id')::bigint)
      FROM (
        SELECT jsonb_build_object(
          'id', r.id,
          'indicador_id', r.indicador_id,
          'ano', r.ano,
          'mes', r.mes,
          'resultado', r.resultado,
          'observacao', r.observacao,
          'volume_produto', r.volume_produto,
          'total_processado', r.total_processado,
          'total_fora_meta', r.total_fora_meta
        ) AS x
        FROM public.sustentacao_resultados r
        JOIN public.sustentacao_indicadores i ON i.id = r.indicador_id AND i.operacao_id = r.operacao_id
        WHERE r.operacao_id = p_operacao_id
          AND r.ano = p_ano
          AND i.ativo = true
          AND public.tem_acesso_indicador(p_operacao_id, r.indicador_id, 'VIEW')
        ORDER BY r.mes, r.indicador_id
      ) q
    ), '[]'::jsonb),
    'sla', COALESCE((
      SELECT jsonb_agg(x ORDER BY (x->>'mes')::integer, x->>'indicador')
      FROM (
        SELECT jsonb_build_object(
          'id', s.id,
          'operacao_id', s.operacao_id,
          'ano', s.ano,
          'indicador', s.indicador,
          'indicador_id', COALESCE(s.indicador_id, mapped.id),
          'mes', s.mes,
          'tipo', s.tipo,
          'valor', s.valor
        ) AS x
        FROM public.sustentacao_sla_neolog_pontuacoes s
        LEFT JOIN public.sustentacao_indicadores mapped
          ON mapped.operacao_id = s.operacao_id
         AND (
              mapped.id = s.indicador_id
              OR mapped.nome = s.indicador
              OR (s.indicador = 'Ocorrências Fora do Prazo' AND mapped.nome = 'Ocorrências Monitoramento')
              OR (s.indicador = 'Segurança e BPDA' AND mapped.nome = 'Ocorrências Segurança e BPDA')
         )
        WHERE s.operacao_id = p_operacao_id
          AND s.ano = p_ano
          AND public.tem_acesso_modulo(p_operacao_id, 'SLA_NEOLOG', 'VIEW')
          AND mapped.id IS NOT NULL
          AND public.tem_acesso_indicador(p_operacao_id, mapped.id, 'VIEW')
        ORDER BY s.mes, s.indicador
      ) q
    ), '[]'::jsonb),
    'acoes', COALESCE((
      SELECT jsonb_agg(x ORDER BY (x->>'data_fim') NULLS LAST, (x->>'ordem')::integer)
      FROM (
        SELECT jsonb_build_object(
          'id', p.id,
          'indicador_id', p.indicador_id,
          'acao', p.acao,
          'responsavel', p.responsavel,
          'data_inicio', p.data_inicio,
          'data_fim', p.data_fim,
          'status', p.status,
          'observacao', p.observacao,
          'concluido', p.concluido,
          'ordem', p.ordem
        ) AS x
        FROM public.sustentacao_plano_acao p
        WHERE p.operacao_id = p_operacao_id
          AND public.tem_acesso_modulo(p_operacao_id, 'PLANO_ACAO', 'VIEW')
          AND (p.indicador_id IS NULL OR public.tem_acesso_indicador(p_operacao_id, p.indicador_id, 'VIEW'))
        ORDER BY p.data_fim NULLS LAST, p.ordem, p.id
      ) q
    ), '[]'::jsonb),
    'absenteismo', jsonb_build_object(
      'permitido', public.tem_acesso_modulo(p_operacao_id, 'ABSENTEISMO', 'VIEW'),
      'mensal', CASE WHEN public.tem_acesso_modulo(p_operacao_id, 'ABSENTEISMO', 'VIEW') THEN COALESCE((
        SELECT jsonb_agg(x ORDER BY (x->>'ano')::integer, (x->>'mes')::integer)
        FROM (
          SELECT jsonb_build_object(
            'ano', r.ano,
            'mes', r.mes,
            'colaboradores', count(DISTINCT r.colaborador),
            'horas_improdutivas', COALESCE(sum(r.horas_improdutivas), 0),
            'horas_disponiveis', COALESCE(sum(r.horas_disponiveis), 0),
            'horas_esperadas', COALESCE(sum(r.horas_esperadas), 0),
            'dias_afastamento', COALESCE(sum(COALESCE(r.dias_falta, 0) + COALESCE(r.dias_atestado, 0)), 0),
            'indice_absenteismo', CASE WHEN COALESCE(sum(r.horas_disponiveis), 0) > 0 THEN round((sum(COALESCE(r.horas_improdutivas, 0)) / sum(r.horas_disponiveis)) * 100, 2) ELSE 0 END
          ) AS x
          FROM public.absenteismo_registros r
          WHERE r.operacao_id = p_operacao_id
          GROUP BY r.ano, r.mes
          ORDER BY r.ano, r.mes
        ) q
      ), '[]'::jsonb) ELSE '[]'::jsonb END,
      'motivos', CASE WHEN public.tem_acesso_modulo(p_operacao_id, 'ABSENTEISMO', 'VIEW') THEN COALESCE((
        SELECT jsonb_agg(x ORDER BY (x->>'ano')::integer, (x->>'mes')::integer, x->>'horas' DESC)
        FROM (
          SELECT jsonb_build_object('ano', r.ano, 'mes', r.mes, 'motivo', COALESCE(NULLIF(r.motivo, ''), 'Não informado'), 'horas', COALESCE(sum(r.horas_improdutivas), 0)) AS x
          FROM public.absenteismo_registros r
          WHERE r.operacao_id = p_operacao_id
          GROUP BY r.ano, r.mes, COALESCE(NULLIF(r.motivo, ''), 'Não informado')
          ORDER BY r.ano, r.mes, sum(r.horas_improdutivas) DESC
        ) q
      ), '[]'::jsonb) ELSE '[]'::jsonb END,
      'areas', CASE WHEN public.tem_acesso_modulo(p_operacao_id, 'ABSENTEISMO', 'VIEW') THEN COALESCE((
        SELECT jsonb_agg(x ORDER BY (x->>'ano')::integer, (x->>'mes')::integer, x->>'horas' DESC)
        FROM (
          SELECT jsonb_build_object('ano', r.ano, 'mes', r.mes, 'area', COALESCE(NULLIF(r.area, ''), NULLIF(r.local, ''), 'Não informado'), 'local', r.local, 'centro_custo', r.centro_custo, 'horas', COALESCE(sum(r.horas_improdutivas), 0), 'horas_disponiveis', COALESCE(sum(r.horas_disponiveis), 0), 'indice_absenteismo', CASE WHEN COALESCE(sum(r.horas_disponiveis), 0) > 0 THEN round((sum(COALESCE(r.horas_improdutivas, 0)) / sum(r.horas_disponiveis)) * 100, 2) ELSE 0 END) AS x
          FROM public.absenteismo_registros r
          WHERE r.operacao_id = p_operacao_id
          GROUP BY r.ano, r.mes, COALESCE(NULLIF(r.area, ''), NULLIF(r.local, ''), 'Não informado'), r.local, r.centro_custo
          ORDER BY r.ano, r.mes, sum(r.horas_improdutivas) DESC
        ) q
      ), '[]'::jsonb) ELSE '[]'::jsonb END,
      'pessoas', CASE WHEN public.tem_acesso_modulo(p_operacao_id, 'ABSENTEISMO', 'VIEW') THEN COALESCE((
        SELECT jsonb_agg(x ORDER BY (x->>'ano')::integer, (x->>'mes')::integer, x->>'horas' DESC)
        FROM (
          SELECT jsonb_build_object('ano', r.ano, 'mes', r.mes, 'colaborador', r.colaborador, 'horas', COALESCE(sum(r.horas_improdutivas), 0)) AS x
          FROM public.absenteismo_registros r
          WHERE r.operacao_id = p_operacao_id
          GROUP BY r.ano, r.mes, r.colaborador
          ORDER BY r.ano, r.mes, sum(r.horas_improdutivas) DESC
        ) q
      ), '[]'::jsonb) ELSE '[]'::jsonb END
    ),
    'acessos', jsonb_build_object(
      'visao_executiva', true,
      'plano_acao', public.tem_acesso_modulo(p_operacao_id, 'PLANO_ACAO', 'VIEW'),
      'sla_neolog', public.tem_acesso_modulo(p_operacao_id, 'SLA_NEOLOG', 'VIEW'),
      'absenteismo', public.tem_acesso_modulo(p_operacao_id, 'ABSENTEISMO', 'VIEW')
    )
  )
END;
$$;

REVOKE ALL ON FUNCTION public.obter_visao_executiva(bigint, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.obter_visao_executiva(bigint, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.obter_visao_executiva(bigint, integer) TO authenticated;
COMMENT ON FUNCTION public.obter_visao_executiva(bigint, integer) IS 'Consolidação executiva somente leitura, filtrada por Visão Executiva, operação, módulos e indicadores autorizados.';

-- Mantém a permissão de módulo centralizada na tabela já existente.
-- A Administração poderá criar/editar VISAO_EXECUTIVA para usuários não administradores.
CREATE INDEX IF NOT EXISTS sustentacao_usuario_modulos_visao_executiva_idx
  ON public.sustentacao_usuario_modulos (user_id, operacao_id, modulo)
  WHERE ativo = true AND modulo = 'VISAO_EXECUTIVA';
