-- Corrige a gravação atômica dos níveis de acesso administrativos.
-- A versão anterior inseria os flags como false e tentava corrigir depois,
-- violando a constraint de consistência antes do UPDATE.
CREATE OR REPLACE FUNCTION public.admin_save_user_access(
  p_user_id uuid,
  p_email text,
  p_nome text,
  p_perfil text,
  p_ativo boolean,
  p_operation_ids bigint[] DEFAULT '{}',
  p_module_permissions jsonb DEFAULT '[]',
  p_indicator_permissions jsonb DEFAULT '[]',
  p_action_permissions jsonb DEFAULT '[]'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  actor uuid := auth.uid();
  is_super boolean := public.eh_super_admin();
  ops bigint[] := coalesce(p_operation_ids, '{}');
  old_user jsonb;
  new_user jsonb;
  old_admin_count integer;
BEGIN
  IF actor IS NULL OR NOT EXISTS (SELECT 1 FROM public.sustentacao_usuarios WHERE user_id = actor AND ativo = true) THEN
    RAISE EXCEPTION 'Sessão sem usuário operacional ativo';
  END IF;
  IF NOT is_super AND NOT public.tem_acesso_central_administrativa() THEN
    RAISE EXCEPTION 'Usuário sem permissão para administrar a Central';
  END IF;
  IF p_user_id IS NULL OR NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'Usuário Auth inexistente';
  END IF;
  IF lower(coalesce(p_perfil,'')) NOT IN ('super_admin','administrador_operacao','coordenador','usuario','admin','gestor') THEN
    RAISE EXCEPTION 'Perfil inválido';
  END IF;
  IF NOT is_super AND lower(p_perfil) IN ('super_admin','admin','administrador_operacao','gestor') THEN
    RAISE EXCEPTION 'Administrador da operação só pode cadastrar coordenadores e usuários';
  END IF;
  IF NOT is_super AND EXISTS (
    SELECT 1 FROM public.sustentacao_usuarios target
    WHERE target.user_id = p_user_id
      AND NOT public.tem_acesso_admin_usuario(target.user_id)
      AND target.user_id <> actor
  ) THEN
    RAISE EXCEPTION 'Usuário fora do escopo operacional do administrador';
  END IF;
  IF NOT is_super AND EXISTS (
    SELECT 1 FROM unnest(ops) x
    WHERE NOT public.tem_escopo_admin_operacao(x)
  ) THEN
    RAISE EXCEPTION 'Operação fora do escopo do administrador';
  END IF;
  IF EXISTS (SELECT 1 FROM unnest(ops) x WHERE NOT EXISTS (SELECT 1 FROM public.sustentacao_operacoes o WHERE o.id=x AND o.ativo=true)) THEN
    RAISE EXCEPTION 'Operação inválida ou inativa';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_to_recordset(coalesce(p_module_permissions,'[]'::jsonb)) x(operacao_id bigint) WHERE NOT (x.operacao_id = ANY(ops))) THEN
    RAISE EXCEPTION 'Permissão de módulo fora do escopo informado';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_to_recordset(coalesce(p_indicator_permissions,'[]'::jsonb)) x(operacao_id bigint) WHERE NOT (x.operacao_id = ANY(ops))) THEN
    RAISE EXCEPTION 'Permissão de indicador fora do escopo informado';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_to_recordset(coalesce(p_action_permissions,'[]'::jsonb)) x(operacao_id bigint) WHERE NOT (x.operacao_id = ANY(ops))) THEN
    RAISE EXCEPTION 'Permissão de plano de ação fora do escopo informado';
  END IF;
  IF NOT is_super AND lower(p_perfil) IN ('coordenador','usuario') AND cardinality(ops) = 0 THEN
    RAISE EXCEPTION 'Informe a operação do coordenador ou usuário';
  END IF;

  SELECT jsonb_build_object(
    'usuario', to_jsonb(su)-'id',
    'operacoes', coalesce((SELECT jsonb_agg(suo.operacao_id ORDER BY suo.operacao_id) FROM public.sustentacao_usuario_operacoes suo WHERE suo.user_id=p_user_id),'[]'::jsonb),
    'modulos', coalesce((SELECT jsonb_agg(to_jsonb(m)-'id'-'user_id' ORDER BY m.id) FROM public.sustentacao_usuario_modulos m WHERE m.user_id=p_user_id),'[]'::jsonb),
    'indicadores', coalesce((SELECT jsonb_agg(to_jsonb(i)-'id'-'user_id' ORDER BY i.id) FROM public.sustentacao_usuario_indicadores i WHERE i.user_id=p_user_id),'[]'::jsonb),
    'plano_acao', coalesce((SELECT jsonb_agg(to_jsonb(pa)-'id'-'user_id' ORDER BY pa.id) FROM public.sustentacao_usuario_plano_acao pa WHERE pa.user_id=p_user_id),'[]'::jsonb)
  ) INTO old_user
  FROM public.sustentacao_usuarios su WHERE su.user_id=p_user_id;

  IF EXISTS (SELECT 1 FROM public.sustentacao_usuarios su WHERE su.user_id=p_user_id AND su.perfil IN ('super_admin','admin') AND su.ativo=true)
     AND (lower(p_perfil) NOT IN ('super_admin','admin') OR p_ativo=false)
  THEN
    SELECT count(*) INTO old_admin_count FROM public.sustentacao_usuarios su
    WHERE su.perfil IN ('super_admin','admin') AND su.ativo=true AND su.user_id<>p_user_id;
    IF old_admin_count=0 THEN RAISE EXCEPTION 'Não é permitido desativar o último Super Administrador ativo'; END IF;
  END IF;

  INSERT INTO public.sustentacao_usuarios(user_id,email,nome,perfil,ativo,updated_at)
  VALUES(p_user_id,lower(trim(p_email)),nullif(trim(p_nome),''),lower(p_perfil),p_ativo,now())
  ON CONFLICT(user_id) DO UPDATE SET email=excluded.email,nome=excluded.nome,perfil=excluded.perfil,ativo=excluded.ativo,updated_at=now();

  IF lower(p_perfil) IN ('super_admin','admin') THEN
    SELECT coalesce(array_agg(id ORDER BY id),'{}') INTO ops FROM public.sustentacao_operacoes WHERE ativo=true;
  END IF;

  DELETE FROM public.sustentacao_usuario_operacoes WHERE user_id=p_user_id;
  INSERT INTO public.sustentacao_usuario_operacoes(user_id,operacao_id,ativo,updated_at)
  SELECT p_user_id,x,true,now() FROM unnest(ops) x;

  DELETE FROM public.sustentacao_usuario_modulos WHERE user_id=p_user_id;
  INSERT INTO public.sustentacao_usuario_modulos(user_id,operacao_id,modulo,nivel_acesso,pode_visualizar,pode_lancar_resultado,pode_editar,pode_administrar,ativo,updated_at)
  SELECT p_user_id,x.operacao_id,upper(x.modulo),access.nivel_acesso,
    access.nivel_acesso <> 'NENHUM',
    access.nivel_acesso IN ('LANCAR_RESULTADO','EDITAR','ADMINISTRAR'),
    access.nivel_acesso IN ('EDITAR','ADMINISTRAR'),
    access.nivel_acesso = 'ADMINISTRAR',
    true,now()
  FROM jsonb_to_recordset(coalesce(p_module_permissions,'[]'::jsonb)) x(operacao_id bigint,modulo text,nivel_acesso text,pode_visualizar boolean,pode_lancar_resultado boolean,pode_editar boolean,pode_administrar boolean)
  CROSS JOIN LATERAL (
    SELECT CASE upper(coalesce(x.nivel_acesso,''))
      WHEN 'ADMIN' THEN 'ADMINISTRAR'
      WHEN 'ADMINISTRAR' THEN 'ADMINISTRAR'
      WHEN 'EDIT' THEN 'EDITAR'
      WHEN 'EDITAR' THEN 'EDITAR'
      WHEN 'LANCAR_RESULTADO' THEN 'LANCAR_RESULTADO'
      WHEN 'VISUALIZAR' THEN 'VISUALIZAR'
      ELSE CASE WHEN coalesce(x.pode_editar,false) THEN 'EDITAR' WHEN coalesce(x.pode_visualizar,false) THEN 'VISUALIZAR' ELSE 'NENHUM' END
    END AS nivel_acesso
  ) access
  WHERE x.operacao_id=ANY(ops);
  UPDATE public.sustentacao_usuario_modulos m
  SET pode_visualizar = m.nivel_acesso <> 'NENHUM',
      pode_lancar_resultado = m.nivel_acesso IN ('LANCAR_RESULTADO','EDITAR','ADMINISTRAR'),
      pode_editar = m.nivel_acesso IN ('EDITAR','ADMINISTRAR'),
      pode_administrar = m.nivel_acesso = 'ADMINISTRAR'
  WHERE m.user_id=p_user_id;

  DELETE FROM public.sustentacao_usuario_indicadores WHERE user_id=p_user_id;
  INSERT INTO public.sustentacao_usuario_indicadores(user_id,operacao_id,indicador_id,nivel_acesso,pode_visualizar,pode_lancar_resultado,pode_editar,pode_administrar,ativo,updated_at)
  SELECT p_user_id,x.operacao_id,x.indicador_id,access.nivel_acesso,
    access.nivel_acesso <> 'NENHUM',
    access.nivel_acesso IN ('LANCAR_RESULTADO','EDITAR','ADMINISTRAR'),
    access.nivel_acesso IN ('EDITAR','ADMINISTRAR'),
    access.nivel_acesso = 'ADMINISTRAR',
    true,now()
  FROM jsonb_to_recordset(coalesce(p_indicator_permissions,'[]'::jsonb)) x(operacao_id bigint,indicador_id bigint,nivel_acesso text,pode_visualizar boolean,pode_lancar_resultado boolean,pode_editar boolean,pode_administrar boolean)
  CROSS JOIN LATERAL (
    SELECT CASE upper(coalesce(x.nivel_acesso,''))
      WHEN 'ADMIN' THEN 'ADMINISTRAR'
      WHEN 'ADMINISTRAR' THEN 'ADMINISTRAR'
      WHEN 'EDIT' THEN 'EDITAR'
      WHEN 'EDITAR' THEN 'EDITAR'
      WHEN 'LANCAR_RESULTADO' THEN 'LANCAR_RESULTADO'
      WHEN 'VISUALIZAR' THEN 'VISUALIZAR'
      ELSE CASE WHEN coalesce(x.pode_editar,false) THEN 'EDITAR' WHEN coalesce(x.pode_visualizar,false) THEN 'VISUALIZAR' ELSE 'NENHUM' END
    END AS nivel_acesso
  ) access
  WHERE x.operacao_id=ANY(ops)
    AND EXISTS (SELECT 1 FROM public.sustentacao_indicadores ind WHERE ind.id=x.indicador_id AND ind.operacao_id=x.operacao_id);
  UPDATE public.sustentacao_usuario_indicadores i
  SET pode_visualizar = i.nivel_acesso <> 'NENHUM',
      pode_lancar_resultado = i.nivel_acesso IN ('LANCAR_RESULTADO','EDITAR','ADMINISTRAR'),
      pode_editar = i.nivel_acesso IN ('EDITAR','ADMINISTRAR'),
      pode_administrar = i.nivel_acesso = 'ADMINISTRAR'
  WHERE i.user_id=p_user_id;

  DELETE FROM public.sustentacao_usuario_plano_acao WHERE user_id=p_user_id;
  INSERT INTO public.sustentacao_usuario_plano_acao(user_id,operacao_id,pode_visualizar,pode_criar,pode_editar,pode_alterar_status,pode_concluir,pode_excluir,ativo,updated_at)
  SELECT p_user_id,x.operacao_id,coalesce(x.pode_visualizar,false),coalesce(x.pode_criar,false),coalesce(x.pode_editar,false),coalesce(x.pode_alterar_status,false),coalesce(x.pode_concluir,false),coalesce(x.pode_excluir,false),true,now()
  FROM jsonb_to_recordset(coalesce(p_action_permissions,'[]'::jsonb)) x(operacao_id bigint,pode_visualizar boolean,pode_criar boolean,pode_editar boolean,pode_alterar_status boolean,pode_concluir boolean,pode_excluir boolean)
  WHERE x.operacao_id=ANY(ops);

  SELECT jsonb_build_object('usuario',jsonb_build_object('user_id',p_user_id,'email',lower(trim(p_email)),'nome',nullif(trim(p_nome),''),'perfil',lower(p_perfil),'ativo',p_ativo),'operacoes',to_jsonb(ops)) INTO new_user;
  INSERT INTO public.sustentacao_auditoria_permissoes(ator_user_id,alvo_user_id,tipo_alteracao,permissoes_anteriores,permissoes_novas,operacao_id)
  VALUES(actor,p_user_id,CASE WHEN old_user IS NULL THEN 'CADASTRO_USUARIO_PERMISSOES' ELSE 'ATUALIZACAO_USUARIO_PERMISSOES' END,coalesce(old_user,'{}'::jsonb),coalesce(new_user,'{}'::jsonb),CASE WHEN cardinality(ops)=1 THEN ops[1] ELSE NULL END);
  RETURN jsonb_build_object('ok',true,'user_id',p_user_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_save_user_access(uuid,text,text,text,boolean,bigint[],jsonb,jsonb,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_save_user_access(uuid,text,text,text,boolean,bigint[],jsonb,jsonb,jsonb) TO authenticated;
