-- Modos de replicação para usuários existentes:
-- REPLACE: substitui a configuração operacional do destino.
-- MERGE: adiciona apenas chaves de permissão ausentes no destino.

CREATE OR REPLACE FUNCTION public.admin_replicate_user_permissions(
  p_source_user_id uuid,
  p_target_user_id uuid,
  p_copy_profile boolean DEFAULT true,
  p_mode text DEFAULT 'REPLACE'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  actor uuid := auth.uid();
  is_super boolean := public.eh_super_admin();
  mode text := upper(coalesce(p_mode, 'REPLACE'));
  source_profile public.sustentacao_usuarios%ROWTYPE;
  target_profile public.sustentacao_usuarios%ROWTYPE;
  other_active_super_count integer := 0;
  source_operations integer := 0;
  source_modules integer := 0;
  source_indicators integer := 0;
  source_actions integer := 0;
  source_assistant integer := 0;
  target_operations_before integer := 0;
  target_modules_before integer := 0;
  target_indicators_before integer := 0;
  target_actions_before integer := 0;
  target_assistant_before integer := 0;
  copied_operations integer := 0;
  copied_modules integer := 0;
  copied_indicators integer := 0;
  copied_actions integer := 0;
  copied_assistant integer := 0;
BEGIN
  IF mode NOT IN ('REPLACE', 'MERGE') THEN
    RAISE EXCEPTION 'Modo de replicação inválido';
  END IF;
  IF actor IS NULL OR NOT EXISTS (SELECT 1 FROM public.sustentacao_usuarios WHERE user_id = actor AND ativo = true) THEN
    RAISE EXCEPTION 'Sessão sem usuário operacional ativo';
  END IF;
  IF p_source_user_id IS NULL OR p_target_user_id IS NULL OR p_source_user_id = p_target_user_id THEN
    RAISE EXCEPTION 'Informe usuários de origem e destino diferentes';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_source_user_id)
     OR NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_target_user_id) THEN
    RAISE EXCEPTION 'Usuário de origem ou destino não existe no Auth';
  END IF;
  IF NOT is_super AND NOT public.tem_acesso_central_administrativa() THEN
    RAISE EXCEPTION 'Usuário sem permissão para administrar a Central';
  END IF;

  SELECT * INTO source_profile FROM public.sustentacao_usuarios WHERE user_id = p_source_user_id;
  SELECT * INTO target_profile FROM public.sustentacao_usuarios WHERE user_id = p_target_user_id;
  IF source_profile.user_id IS NULL OR target_profile.user_id IS NULL THEN
    RAISE EXCEPTION 'Origem e destino precisam possuir cadastro administrativo antes da replicação';
  END IF;

  IF NOT is_super THEN
    IF NOT public.tem_acesso_admin_usuario(p_source_user_id) OR NOT public.tem_acesso_admin_usuario(p_target_user_id) THEN
      RAISE EXCEPTION 'Usuário de origem ou destino fora do escopo operacional do administrador';
    END IF;
    IF source_profile.perfil IN ('super_admin','admin','administrador_operacao','gestor') THEN
      RAISE EXCEPTION 'Administrador da operação só pode replicar configurações de coordenadores e usuários';
    END IF;
    IF EXISTS (
      SELECT 1 FROM public.sustentacao_usuario_operacoes link
      WHERE link.user_id IN (p_source_user_id, p_target_user_id)
        AND link.ativo = true
        AND NOT public.tem_escopo_admin_operacao(link.operacao_id)
    ) THEN
      RAISE EXCEPTION 'A replicação contém operação fora do escopo do administrador';
    END IF;
  END IF;

  IF p_copy_profile AND target_profile.ativo = true AND target_profile.perfil IN ('super_admin','admin') AND source_profile.ativo = false THEN
    SELECT count(*) INTO other_active_super_count
    FROM public.sustentacao_usuarios
    WHERE ativo = true AND perfil IN ('super_admin','admin') AND user_id <> p_target_user_id;
    IF other_active_super_count = 0 THEN
      RAISE EXCEPTION 'Não é permitido desativar o último Super Administrador ativo';
    END IF;
  END IF;

  SELECT count(*) INTO source_operations FROM public.sustentacao_usuario_operacoes WHERE user_id = p_source_user_id;
  SELECT count(*) INTO source_modules FROM public.sustentacao_usuario_modulos WHERE user_id = p_source_user_id;
  SELECT count(*) INTO source_indicators FROM public.sustentacao_usuario_indicadores WHERE user_id = p_source_user_id;
  SELECT count(*) INTO source_actions FROM public.sustentacao_usuario_plano_acao WHERE user_id = p_source_user_id;
  SELECT count(*) INTO source_assistant FROM public.sustentacao_assistente_permissoes WHERE user_id = p_source_user_id;
  SELECT count(*) INTO target_operations_before FROM public.sustentacao_usuario_operacoes WHERE user_id = p_target_user_id;
  SELECT count(*) INTO target_modules_before FROM public.sustentacao_usuario_modulos WHERE user_id = p_target_user_id;
  SELECT count(*) INTO target_indicators_before FROM public.sustentacao_usuario_indicadores WHERE user_id = p_target_user_id;
  SELECT count(*) INTO target_actions_before FROM public.sustentacao_usuario_plano_acao WHERE user_id = p_target_user_id;
  SELECT count(*) INTO target_assistant_before FROM public.sustentacao_assistente_permissoes WHERE user_id = p_target_user_id;

  IF p_copy_profile THEN
    UPDATE public.sustentacao_usuarios
    SET perfil = source_profile.perfil, ativo = source_profile.ativo, updated_at = now()
    WHERE user_id = p_target_user_id;
  END IF;

  IF mode = 'REPLACE' THEN
    DELETE FROM public.sustentacao_usuario_operacoes WHERE user_id = p_target_user_id;
    DELETE FROM public.sustentacao_usuario_modulos WHERE user_id = p_target_user_id;
    DELETE FROM public.sustentacao_usuario_indicadores WHERE user_id = p_target_user_id;
    DELETE FROM public.sustentacao_usuario_plano_acao WHERE user_id = p_target_user_id;
    DELETE FROM public.sustentacao_assistente_permissoes WHERE user_id = p_target_user_id;
  END IF;

  INSERT INTO public.sustentacao_usuario_operacoes(user_id, operacao_id, ativo, created_at, updated_at)
  SELECT p_target_user_id, s.operacao_id, s.ativo, now(), now()
  FROM public.sustentacao_usuario_operacoes s
  WHERE s.user_id = p_source_user_id
    AND (mode = 'REPLACE' OR NOT EXISTS (SELECT 1 FROM public.sustentacao_usuario_operacoes t WHERE t.user_id = p_target_user_id AND t.operacao_id = s.operacao_id));
  GET DIAGNOSTICS copied_operations = ROW_COUNT;

  INSERT INTO public.sustentacao_usuario_modulos(user_id, operacao_id, modulo, pode_visualizar, pode_editar, ativo, created_at, updated_at, nivel_acesso, pode_lancar_resultado, pode_administrar)
  SELECT p_target_user_id, s.operacao_id, s.modulo, s.pode_visualizar, s.pode_editar, s.ativo, now(), now(), s.nivel_acesso, s.pode_lancar_resultado, s.pode_administrar
  FROM public.sustentacao_usuario_modulos s
  WHERE s.user_id = p_source_user_id
    AND (mode = 'REPLACE' OR NOT EXISTS (SELECT 1 FROM public.sustentacao_usuario_modulos t WHERE t.user_id = p_target_user_id AND t.operacao_id = s.operacao_id AND t.modulo = s.modulo));
  GET DIAGNOSTICS copied_modules = ROW_COUNT;

  INSERT INTO public.sustentacao_usuario_indicadores(user_id, operacao_id, indicador_id, pode_visualizar, pode_editar, ativo, created_at, updated_at, nivel_acesso, pode_lancar_resultado, pode_administrar)
  SELECT p_target_user_id, s.operacao_id, s.indicador_id, s.pode_visualizar, s.pode_editar, s.ativo, now(), now(), s.nivel_acesso, s.pode_lancar_resultado, s.pode_administrar
  FROM public.sustentacao_usuario_indicadores s
  WHERE s.user_id = p_source_user_id
    AND (mode = 'REPLACE' OR NOT EXISTS (SELECT 1 FROM public.sustentacao_usuario_indicadores t WHERE t.user_id = p_target_user_id AND t.operacao_id = s.operacao_id AND t.indicador_id = s.indicador_id));
  GET DIAGNOSTICS copied_indicators = ROW_COUNT;

  INSERT INTO public.sustentacao_usuario_plano_acao(user_id, operacao_id, pode_visualizar, pode_criar, pode_editar, pode_alterar_status, pode_concluir, pode_excluir, ativo, created_at, updated_at)
  SELECT p_target_user_id, s.operacao_id, s.pode_visualizar, s.pode_criar, s.pode_editar, s.pode_alterar_status, s.pode_concluir, s.pode_excluir, s.ativo, now(), now()
  FROM public.sustentacao_usuario_plano_acao s
  WHERE s.user_id = p_source_user_id
    AND (mode = 'REPLACE' OR NOT EXISTS (SELECT 1 FROM public.sustentacao_usuario_plano_acao t WHERE t.user_id = p_target_user_id AND t.operacao_id = s.operacao_id));
  GET DIAGNOSTICS copied_actions = ROW_COUNT;

  INSERT INTO public.sustentacao_assistente_permissoes(user_id, operacao_id, pode_acessar, pode_consultar_indicadores, pode_consultar_absenteismo, pode_consultar_plano_acao, pode_consultar_sla_neolog, pode_consultar_visao_executiva, pode_analisar_consolidado, created_at, updated_at)
  SELECT p_target_user_id, s.operacao_id, s.pode_acessar, s.pode_consultar_indicadores, s.pode_consultar_absenteismo, s.pode_consultar_plano_acao, s.pode_consultar_sla_neolog, s.pode_consultar_visao_executiva, s.pode_analisar_consolidado, now(), now()
  FROM public.sustentacao_assistente_permissoes s
  WHERE s.user_id = p_source_user_id
    AND (mode = 'REPLACE' OR NOT EXISTS (SELECT 1 FROM public.sustentacao_assistente_permissoes t WHERE t.user_id = p_target_user_id AND coalesce(t.operacao_id, 0) = coalesce(s.operacao_id, 0)));
  GET DIAGNOSTICS copied_assistant = ROW_COUNT;

  INSERT INTO public.sustentacao_auditoria_permissoes(ator_user_id, alvo_user_id, tipo_alteracao, permissoes_anteriores, permissoes_novas, operacao_id)
  VALUES (
    actor,
    p_target_user_id,
    'REPLICACAO_PERMISSOES_USUARIO',
    jsonb_build_object('origem_user_id', p_source_user_id, 'modo', mode, 'perfil_anterior', target_profile.perfil, 'ativo_anterior', target_profile.ativo, 'operacoes_anteriores', target_operations_before, 'modulos_anteriores', target_modules_before, 'indicadores_anteriores', target_indicators_before, 'plano_acao_anterior', target_actions_before, 'assistente_anterior', target_assistant_before),
    jsonb_build_object('origem_user_id', p_source_user_id, 'modo', mode, 'copiar_perfil', p_copy_profile, 'operacoes', copied_operations, 'modulos', copied_modules, 'indicadores', copied_indicators, 'plano_acao', copied_actions, 'assistente', copied_assistant),
    NULL
  );

  RETURN jsonb_build_object('ok', true, 'source_user_id', p_source_user_id, 'target_user_id', p_target_user_id, 'mode', mode, 'copied_profile', p_copy_profile, 'copied', jsonb_build_object('operacoes', copied_operations, 'modulos', copied_modules, 'indicadores', copied_indicators, 'plano_acao', copied_actions, 'assistente', copied_assistant));
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_replicate_user_permissions(
  p_source_user_id uuid,
  p_target_user_id uuid,
  p_copy_profile boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.admin_replicate_user_permissions($1, $2, $3, 'REPLACE');
$$;

REVOKE ALL ON FUNCTION public.admin_replicate_user_permissions(uuid, uuid, boolean, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_replicate_user_permissions(uuid, uuid, boolean, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_replicate_user_permissions(uuid, uuid, boolean, text) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_replicate_user_permissions(uuid, uuid, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_replicate_user_permissions(uuid, uuid, boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_replicate_user_permissions(uuid, uuid, boolean) TO authenticated;
