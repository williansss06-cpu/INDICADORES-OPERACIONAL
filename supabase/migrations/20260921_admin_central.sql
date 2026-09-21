-- Central Administrativa independente, hierarquia de perfis e escopo real por operação.
-- Migration aditiva e compatível: preserva IDs, históricos, operações e dados existentes.

ALTER TABLE public.sustentacao_operacoes
  ADD COLUMN IF NOT EXISTS responsavel_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE public.sustentacao_indicadores
  ADD COLUMN IF NOT EXISTS objetivo text,
  ADD COLUMN IF NOT EXISTS periodicidade text,
  ADD COLUMN IF NOT EXISTS responsavel_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE public.sustentacao_usuario_modulos
  ADD COLUMN IF NOT EXISTS nivel_acesso text NOT NULL DEFAULT 'NENHUM',
  ADD COLUMN IF NOT EXISTS pode_lancar_resultado boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS pode_administrar boolean NOT NULL DEFAULT false;

ALTER TABLE public.sustentacao_usuario_indicadores
  ADD COLUMN IF NOT EXISTS nivel_acesso text NOT NULL DEFAULT 'NENHUM',
  ADD COLUMN IF NOT EXISTS pode_lancar_resultado boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS pode_administrar boolean NOT NULL DEFAULT false;

ALTER TABLE public.sustentacao_usuario_modulos
  DROP CONSTRAINT IF EXISTS sustentacao_usuario_modulos_modulo_check;
ALTER TABLE public.sustentacao_usuario_modulos
  ADD CONSTRAINT sustentacao_usuario_modulos_modulo_check
  CHECK (modulo IN ('PLANO_SUSTENTACAO','SLA_NEOLOG','ABSENTEISMO','PLANO_ACAO','INVENTARIOS','VISAO_EXECUTIVA'));

ALTER TABLE public.sustentacao_usuarios
  DROP CONSTRAINT IF EXISTS sustentacao_usuarios_perfil_check;
ALTER TABLE public.sustentacao_usuarios
  ADD CONSTRAINT sustentacao_usuarios_perfil_check
  CHECK (perfil IN ('admin','super_admin','gestor','administrador_operacao','coordenador','usuario'));

-- Migração explícita do legado, preservando o comportamento efetivo de visualizar/editar.
UPDATE public.sustentacao_usuario_modulos
SET nivel_acesso = CASE WHEN pode_editar THEN 'EDITAR' WHEN pode_visualizar THEN 'VISUALIZAR' ELSE 'NENHUM' END,
    pode_lancar_resultado = pode_editar,
    pode_administrar = false,
    updated_at = now();

UPDATE public.sustentacao_usuario_indicadores
SET nivel_acesso = CASE WHEN pode_editar THEN 'EDITAR' WHEN pode_visualizar THEN 'VISUALIZAR' ELSE 'NENHUM' END,
    pode_lancar_resultado = pode_editar,
    pode_administrar = false,
    updated_at = now();

ALTER TABLE public.sustentacao_usuario_modulos
  DROP CONSTRAINT IF EXISTS sustentacao_usuario_modulos_edit_view_check;
ALTER TABLE public.sustentacao_usuario_modulos
  ADD CONSTRAINT sustentacao_usuario_modulos_access_consistency_check
  CHECK (
    nivel_acesso IN ('NENHUM','VISUALIZAR','LANCAR_RESULTADO','EDITAR','ADMINISTRAR')
    AND pode_visualizar = (nivel_acesso <> 'NENHUM')
    AND pode_lancar_resultado = (nivel_acesso IN ('LANCAR_RESULTADO','EDITAR','ADMINISTRAR'))
    AND pode_editar = (nivel_acesso IN ('EDITAR','ADMINISTRAR'))
    AND pode_administrar = (nivel_acesso = 'ADMINISTRAR')
  );

ALTER TABLE public.sustentacao_usuario_indicadores
  DROP CONSTRAINT IF EXISTS sustentacao_usuario_indicadores_edit_view_check;
ALTER TABLE public.sustentacao_usuario_indicadores
  ADD CONSTRAINT sustentacao_usuario_indicadores_access_consistency_check
  CHECK (
    nivel_acesso IN ('NENHUM','VISUALIZAR','LANCAR_RESULTADO','EDITAR','ADMINISTRAR')
    AND pode_visualizar = (nivel_acesso <> 'NENHUM')
    AND pode_lancar_resultado = (nivel_acesso IN ('LANCAR_RESULTADO','EDITAR','ADMINISTRAR'))
    AND pode_editar = (nivel_acesso IN ('EDITAR','ADMINISTRAR'))
    AND pode_administrar = (nivel_acesso = 'ADMINISTRAR')
  );

-- Perfis legados continuam aceitos no check para rollback lógico, mas os registros atuais
-- passam a usar a nomenclatura hierárquica nova.
UPDATE public.sustentacao_usuarios SET perfil = 'super_admin', updated_at = now() WHERE perfil = 'admin';
UPDATE public.sustentacao_usuarios SET perfil = 'administrador_operacao', updated_at = now() WHERE perfil = 'gestor';

-- O responsável passa a ser atributo da operação. Os valores já cadastrados na configuração
-- dos cards são a fonte de sincronização inicial.
UPDATE public.sustentacao_operacoes o
SET responsavel_user_id = c.responsavel_user_id,
    updated_at = now()
FROM public.sustentacao_configuracoes_operacao c
WHERE c.operacao_id = o.id
  AND c.ativo = true
  AND c.responsavel_user_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS sustentacao_operacoes_responsavel_idx
  ON public.sustentacao_operacoes (responsavel_user_id);
CREATE INDEX IF NOT EXISTS sustentacao_indicadores_responsavel_idx
  ON public.sustentacao_indicadores (operacao_id, responsavel_user_id);

CREATE OR REPLACE FUNCTION public.sincronizar_responsavel_operacao()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.sustentacao_operacoes
  SET responsavel_user_id = NEW.responsavel_user_id,
      updated_at = now()
  WHERE id = NEW.operacao_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sustentacao_configuracao_responsavel_sync ON public.sustentacao_configuracoes_operacao;
CREATE TRIGGER sustentacao_configuracao_responsavel_sync
AFTER INSERT OR UPDATE OF responsavel_user_id ON public.sustentacao_configuracoes_operacao
FOR EACH ROW EXECUTE FUNCTION public.sincronizar_responsavel_operacao();

CREATE OR REPLACE FUNCTION public.nivel_acesso_atende(p_nivel text, p_acao text DEFAULT 'VIEW')
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE upper(coalesce(p_acao, 'VIEW'))
    WHEN 'VIEW' THEN upper(coalesce(p_nivel, 'NENHUM')) IN ('VISUALIZAR','LANCAR_RESULTADO','EDITAR','ADMINISTRAR')
    WHEN 'LANCAR_RESULTADO' THEN upper(coalesce(p_nivel, 'NENHUM')) IN ('LANCAR_RESULTADO','EDITAR','ADMINISTRAR')
    WHEN 'EDIT' THEN upper(coalesce(p_nivel, 'NENHUM')) IN ('EDITAR','ADMINISTRAR')
    WHEN 'ADMIN' THEN upper(coalesce(p_nivel, 'NENHUM')) = 'ADMINISTRAR'
    ELSE false
  END;
$$;

CREATE OR REPLACE FUNCTION public.eh_super_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.sustentacao_usuarios su
    WHERE su.user_id = auth.uid()
      AND su.ativo = true
      AND su.perfil IN ('super_admin','admin')
  );
$$;

CREATE OR REPLACE FUNCTION public.tem_escopo_admin_operacao(p_operacao_id bigint)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.eh_super_admin()
      OR EXISTS (
        SELECT 1
        FROM public.sustentacao_usuarios su
        JOIN public.sustentacao_operacoes o ON o.responsavel_user_id = su.user_id
        JOIN public.sustentacao_usuario_operacoes suo
          ON suo.user_id = su.user_id AND suo.operacao_id = o.id AND suo.ativo = true
        WHERE su.user_id = auth.uid()
          AND su.ativo = true
          AND su.perfil IN ('administrador_operacao','gestor')
          AND o.id = p_operacao_id
          AND o.ativo = true
      );
$$;

CREATE OR REPLACE FUNCTION public.tem_acesso_central_administrativa()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.eh_super_admin()
      OR EXISTS (
        SELECT 1
        FROM public.sustentacao_usuarios su
        JOIN public.sustentacao_operacoes o ON o.responsavel_user_id = su.user_id
        JOIN public.sustentacao_usuario_operacoes suo
          ON suo.user_id = su.user_id AND suo.operacao_id = o.id AND suo.ativo = true
        WHERE su.user_id = auth.uid()
          AND su.ativo = true
          AND su.perfil IN ('administrador_operacao','gestor')
          AND o.ativo = true
      );
$$;

CREATE OR REPLACE FUNCTION public.tem_acesso_operacao(p_operacao_id bigint)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.eh_super_admin()
      OR public.tem_escopo_admin_operacao(p_operacao_id)
      OR EXISTS (
        SELECT 1
        FROM public.sustentacao_usuarios su
        JOIN public.sustentacao_usuario_operacoes suo ON suo.user_id = su.user_id
        WHERE su.user_id = auth.uid()
          AND su.ativo = true
          AND suo.ativo = true
          AND suo.operacao_id = p_operacao_id
      );
$$;

CREATE OR REPLACE FUNCTION public.tem_acesso_modulo(p_operacao_id bigint, p_modulo text, p_acao text DEFAULT 'VIEW')
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.eh_super_admin()
      OR public.tem_escopo_admin_operacao(p_operacao_id)
      OR EXISTS (
        SELECT 1
        FROM public.sustentacao_usuario_modulos m
        JOIN public.sustentacao_usuarios su ON su.user_id = m.user_id
        WHERE m.user_id = auth.uid()
          AND su.ativo = true
          AND m.operacao_id = p_operacao_id
          AND m.modulo = upper(p_modulo)
          AND m.ativo = true
          AND public.nivel_acesso_atende(m.nivel_acesso, p_acao)
      );
$$;

CREATE OR REPLACE FUNCTION public.tem_acesso_indicador(p_operacao_id bigint, p_indicador_id bigint, p_acao text DEFAULT 'VIEW')
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.eh_super_admin()
      OR public.tem_escopo_admin_operacao(p_operacao_id)
      OR EXISTS (
        SELECT 1
        FROM public.sustentacao_indicadores ind
        JOIN public.sustentacao_usuario_indicadores ui
          ON ui.indicador_id = ind.id AND ui.operacao_id = ind.operacao_id
        JOIN public.sustentacao_usuarios su ON su.user_id = ui.user_id
        WHERE ind.id = p_indicador_id
          AND ind.operacao_id = p_operacao_id
          AND ind.ativo = true
          AND ui.user_id = auth.uid()
          AND su.ativo = true
          AND ui.ativo = true
          AND public.nivel_acesso_atende(ui.nivel_acesso, p_acao)
      );
$$;

CREATE OR REPLACE FUNCTION public.tem_acesso_operacao_visualizacao(p_operacao_id bigint)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.eh_super_admin()
      OR (public.tem_acesso_operacao(p_operacao_id)
          AND public.tem_acesso_modulo(p_operacao_id, 'PLANO_SUSTENTACAO', 'VIEW'));
$$;

CREATE OR REPLACE FUNCTION public.tem_acesso_inventario(p_operacao_id bigint, p_resultado_id bigint, p_acao text DEFAULT 'VIEW')
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.eh_super_admin()
      OR (
        public.tem_acesso_modulo(p_operacao_id, 'INVENTARIOS', p_acao)
        AND EXISTS (
          SELECT 1 FROM public.sustentacao_resultados r
          WHERE r.id = p_resultado_id
            AND r.operacao_id = p_operacao_id
            AND public.tem_acesso_indicador(p_operacao_id, r.indicador_id, p_acao)
        )
      );
$$;

CREATE OR REPLACE FUNCTION public.tem_acesso_plano_acao(p_operacao_id bigint, p_indicador_id bigint, p_acao text DEFAULT 'VIEW')
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.eh_super_admin()
      OR public.tem_escopo_admin_operacao(p_operacao_id)
      OR (
        public.tem_acesso_modulo(p_operacao_id, 'PLANO_ACAO', CASE WHEN upper(coalesce(p_acao,'VIEW')) IN ('CREATE','EDIT','STATUS','CONCLUDE','DELETE') THEN 'EDIT' ELSE 'VIEW' END)
        AND (p_indicador_id IS NULL OR public.tem_acesso_indicador(p_operacao_id, p_indicador_id, 'VIEW'))
        AND EXISTS (
          SELECT 1 FROM public.sustentacao_usuario_plano_acao pa
          WHERE pa.user_id = auth.uid()
            AND pa.operacao_id = p_operacao_id
            AND pa.ativo = true
            AND CASE upper(coalesce(p_acao, 'VIEW'))
              WHEN 'CREATE' THEN pa.pode_criar
              WHEN 'EDIT' THEN pa.pode_editar
              WHEN 'STATUS' THEN pa.pode_alterar_status
              WHEN 'CONCLUDE' THEN pa.pode_concluir
              WHEN 'DELETE' THEN pa.pode_excluir
              ELSE pa.pode_visualizar
            END
        )
      );
$$;

CREATE OR REPLACE FUNCTION public.tem_acesso_admin_usuario(p_user_id uuid, p_operacao_id bigint DEFAULT NULL)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.eh_super_admin()
      OR EXISTS (
        SELECT 1
        FROM public.sustentacao_usuarios caller
        JOIN public.sustentacao_operacoes op ON op.responsavel_user_id = caller.user_id
        JOIN public.sustentacao_usuario_operacoes caller_op
          ON caller_op.user_id = caller.user_id AND caller_op.operacao_id = op.id AND caller_op.ativo = true
        JOIN public.sustentacao_usuario_operacoes target_op
          ON target_op.user_id = p_user_id AND target_op.operacao_id = op.id AND target_op.ativo = true
        WHERE caller.user_id = auth.uid()
          AND caller.ativo = true
          AND caller.perfil IN ('administrador_operacao','gestor')
          AND op.ativo = true
          AND (p_operacao_id IS NULL OR op.id = p_operacao_id)
      );
$$;

CREATE OR REPLACE FUNCTION public.eh_admin_sustentacao()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$ SELECT public.eh_super_admin(); $$;

-- Impede que a identidade operacional de um indicador ou histórico seja transferida.
CREATE OR REPLACE FUNCTION public.bloquear_troca_operacao()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.operacao_id IS DISTINCT FROM OLD.operacao_id THEN
    RAISE EXCEPTION 'A operação de um registro histórico não pode ser alterada';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sustentacao_indicadores_operacao_immutable ON public.sustentacao_indicadores;
CREATE TRIGGER sustentacao_indicadores_operacao_immutable
BEFORE UPDATE ON public.sustentacao_indicadores
FOR EACH ROW EXECUTE FUNCTION public.bloquear_troca_operacao();

DROP TRIGGER IF EXISTS sustentacao_resultados_operacao_immutable ON public.sustentacao_resultados;
CREATE TRIGGER sustentacao_resultados_operacao_immutable
BEFORE UPDATE ON public.sustentacao_resultados
FOR EACH ROW EXECUTE FUNCTION public.bloquear_troca_operacao();

DROP TRIGGER IF EXISTS sustentacao_inventarios_operacao_immutable ON public.sustentacao_inventarios;
CREATE TRIGGER sustentacao_inventarios_operacao_immutable
BEFORE UPDATE ON public.sustentacao_inventarios
FOR EACH ROW EXECUTE FUNCTION public.bloquear_troca_operacao();

DROP TRIGGER IF EXISTS sustentacao_plano_acao_operacao_immutable ON public.sustentacao_plano_acao;
CREATE TRIGGER sustentacao_plano_acao_operacao_immutable
BEFORE UPDATE ON public.sustentacao_plano_acao
FOR EACH ROW EXECUTE FUNCTION public.bloquear_troca_operacao();

DROP TRIGGER IF EXISTS sustentacao_sla_operacao_immutable ON public.sustentacao_sla_neolog_pontuacoes;
CREATE TRIGGER sustentacao_sla_operacao_immutable
BEFORE UPDATE ON public.sustentacao_sla_neolog_pontuacoes
FOR EACH ROW EXECUTE FUNCTION public.bloquear_troca_operacao();

DROP TRIGGER IF EXISTS absenteismo_areas_operacao_immutable ON public.absenteismo_areas;
CREATE TRIGGER absenteismo_areas_operacao_immutable
BEFORE UPDATE ON public.absenteismo_areas
FOR EACH ROW EXECUTE FUNCTION public.bloquear_troca_operacao();

DROP TRIGGER IF EXISTS absenteismo_registros_operacao_immutable ON public.absenteismo_registros;
CREATE TRIGGER absenteismo_registros_operacao_immutable
BEFORE UPDATE ON public.absenteismo_registros
FOR EACH ROW EXECUTE FUNCTION public.bloquear_troca_operacao();

-- Políticas de leitura da Central. O administrador da operação só enxerga o próprio escopo.
DROP POLICY IF EXISTS sustentacao_usuarios_admin_select ON public.sustentacao_usuarios;
CREATE POLICY sustentacao_usuarios_admin_select ON public.sustentacao_usuarios
FOR SELECT TO authenticated
USING (public.eh_super_admin() OR public.tem_acesso_admin_usuario(user_id) OR user_id = auth.uid());

DROP POLICY IF EXISTS sustentacao_usuario_operacoes_admin_select ON public.sustentacao_usuario_operacoes;
CREATE POLICY sustentacao_usuario_operacoes_admin_select ON public.sustentacao_usuario_operacoes
FOR SELECT TO authenticated
USING (public.eh_super_admin() OR public.tem_acesso_admin_usuario(user_id, operacao_id) OR user_id = auth.uid());

DROP POLICY IF EXISTS sustentacao_usuario_modulos_admin ON public.sustentacao_usuario_modulos;
CREATE POLICY sustentacao_usuario_modulos_admin ON public.sustentacao_usuario_modulos
FOR SELECT TO authenticated
USING (public.eh_super_admin() OR public.tem_acesso_admin_usuario(user_id, operacao_id) OR user_id = auth.uid());

DROP POLICY IF EXISTS sustentacao_usuario_indicadores_admin ON public.sustentacao_usuario_indicadores;
CREATE POLICY sustentacao_usuario_indicadores_admin ON public.sustentacao_usuario_indicadores
FOR SELECT TO authenticated
USING (public.eh_super_admin() OR public.tem_acesso_admin_usuario(user_id, operacao_id) OR user_id = auth.uid());

DROP POLICY IF EXISTS sustentacao_usuario_plano_acao_admin ON public.sustentacao_usuario_plano_acao;
CREATE POLICY sustentacao_usuario_plano_acao_admin ON public.sustentacao_usuario_plano_acao
FOR SELECT TO authenticated
USING (public.eh_super_admin() OR public.tem_acesso_admin_usuario(user_id, operacao_id) OR user_id = auth.uid());

DROP POLICY IF EXISTS sustentacao_operacoes_acesso ON public.sustentacao_operacoes;
CREATE POLICY sustentacao_operacoes_acesso ON public.sustentacao_operacoes
FOR SELECT TO authenticated
USING (public.tem_acesso_operacao_visualizacao(id));

CREATE POLICY sustentacao_operacoes_super_insert ON public.sustentacao_operacoes
FOR INSERT TO authenticated WITH CHECK (public.eh_super_admin());
CREATE POLICY sustentacao_operacoes_super_update ON public.sustentacao_operacoes
FOR UPDATE TO authenticated USING (public.eh_super_admin()) WITH CHECK (public.eh_super_admin());
CREATE POLICY sustentacao_operacoes_super_delete ON public.sustentacao_operacoes
FOR DELETE TO authenticated USING (public.eh_super_admin());

DROP POLICY IF EXISTS sustentacao_configuracoes_operacao_insert ON public.sustentacao_configuracoes_operacao;
CREATE POLICY sustentacao_configuracoes_operacao_insert ON public.sustentacao_configuracoes_operacao
FOR INSERT TO authenticated WITH CHECK (public.eh_super_admin() OR public.tem_escopo_admin_operacao(operacao_id));
DROP POLICY IF EXISTS sustentacao_configuracoes_operacao_update ON public.sustentacao_configuracoes_operacao;
CREATE POLICY sustentacao_configuracoes_operacao_update ON public.sustentacao_configuracoes_operacao
FOR UPDATE TO authenticated USING (public.eh_super_admin() OR public.tem_escopo_admin_operacao(operacao_id)) WITH CHECK (public.eh_super_admin() OR public.tem_escopo_admin_operacao(operacao_id));
DROP POLICY IF EXISTS sustentacao_configuracoes_operacao_delete ON public.sustentacao_configuracoes_operacao;
CREATE POLICY sustentacao_configuracoes_operacao_delete ON public.sustentacao_configuracoes_operacao
FOR DELETE TO authenticated USING (public.eh_super_admin() OR public.tem_escopo_admin_operacao(operacao_id));

-- Cadastro/edição de indicadores é administração. Resultados são lançados com nível próprio.
DROP POLICY IF EXISTS sustentacao_indicadores_insert ON public.sustentacao_indicadores;
CREATE POLICY sustentacao_indicadores_insert ON public.sustentacao_indicadores
FOR INSERT TO authenticated WITH CHECK (public.tem_acesso_modulo(operacao_id, 'PLANO_SUSTENTACAO', 'ADMIN'));
DROP POLICY IF EXISTS sustentacao_indicadores_update ON public.sustentacao_indicadores;
CREATE POLICY sustentacao_indicadores_update ON public.sustentacao_indicadores
FOR UPDATE TO authenticated USING (public.tem_acesso_modulo(operacao_id, 'PLANO_SUSTENTACAO', 'ADMIN') AND public.tem_acesso_indicador(operacao_id, id, 'ADMIN'))
WITH CHECK (public.tem_acesso_modulo(operacao_id, 'PLANO_SUSTENTACAO', 'ADMIN') AND public.tem_acesso_indicador(operacao_id, id, 'ADMIN'));
DROP POLICY IF EXISTS sustentacao_indicadores_delete ON public.sustentacao_indicadores;
CREATE POLICY sustentacao_indicadores_delete ON public.sustentacao_indicadores
FOR DELETE TO authenticated USING (public.tem_acesso_modulo(operacao_id, 'PLANO_SUSTENTACAO', 'ADMIN') AND public.tem_acesso_indicador(operacao_id, id, 'ADMIN'));

DROP POLICY IF EXISTS sustentacao_resultados_insert ON public.sustentacao_resultados;
CREATE POLICY sustentacao_resultados_insert ON public.sustentacao_resultados
FOR INSERT TO authenticated WITH CHECK (public.tem_acesso_modulo(operacao_id, 'PLANO_SUSTENTACAO', 'LANCAR_RESULTADO') AND public.tem_acesso_indicador(operacao_id, indicador_id, 'LANCAR_RESULTADO'));
DROP POLICY IF EXISTS sustentacao_resultados_update ON public.sustentacao_resultados;
CREATE POLICY sustentacao_resultados_update ON public.sustentacao_resultados
FOR UPDATE TO authenticated USING (public.tem_acesso_modulo(operacao_id, 'PLANO_SUSTENTACAO', 'LANCAR_RESULTADO') AND public.tem_acesso_indicador(operacao_id, indicador_id, 'LANCAR_RESULTADO'))
WITH CHECK (public.tem_acesso_modulo(operacao_id, 'PLANO_SUSTENTACAO', 'LANCAR_RESULTADO') AND public.tem_acesso_indicador(operacao_id, indicador_id, 'LANCAR_RESULTADO'));

-- RPC segura de usuários/permissões. O escopo enviado pelo navegador é sempre revalidado no banco.
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
  SELECT p_user_id,x.operacao_id,upper(x.modulo),
    CASE upper(coalesce(x.nivel_acesso,'')) WHEN 'ADMIN' THEN 'ADMINISTRAR' WHEN 'ADMINISTRAR' THEN 'ADMINISTRAR' WHEN 'EDIT' THEN 'EDITAR' WHEN 'EDITAR' THEN 'EDITAR' WHEN 'LANCAR_RESULTADO' THEN 'LANCAR_RESULTADO' WHEN 'VISUALIZAR' THEN 'VISUALIZAR' ELSE CASE WHEN coalesce(x.pode_editar,false) THEN 'EDITAR' WHEN coalesce(x.pode_visualizar,false) THEN 'VISUALIZAR' ELSE 'NENHUM' END END,
    false,false,false,false,true,now()
  FROM jsonb_to_recordset(coalesce(p_module_permissions,'[]'::jsonb)) x(operacao_id bigint,modulo text,nivel_acesso text,pode_visualizar boolean,pode_lancar_resultado boolean,pode_editar boolean,pode_administrar boolean)
  WHERE x.operacao_id=ANY(ops);
  UPDATE public.sustentacao_usuario_modulos m
  SET pode_visualizar = m.nivel_acesso <> 'NENHUM',
      pode_lancar_resultado = m.nivel_acesso IN ('LANCAR_RESULTADO','EDITAR','ADMINISTRAR'),
      pode_editar = m.nivel_acesso IN ('EDITAR','ADMINISTRAR'),
      pode_administrar = m.nivel_acesso = 'ADMINISTRAR'
  WHERE m.user_id=p_user_id;

  DELETE FROM public.sustentacao_usuario_indicadores WHERE user_id=p_user_id;
  INSERT INTO public.sustentacao_usuario_indicadores(user_id,operacao_id,indicador_id,nivel_acesso,pode_visualizar,pode_lancar_resultado,pode_editar,pode_administrar,ativo,updated_at)
  SELECT p_user_id,x.operacao_id,x.indicador_id,
    CASE upper(coalesce(x.nivel_acesso,'')) WHEN 'ADMIN' THEN 'ADMINISTRAR' WHEN 'ADMINISTRAR' THEN 'ADMINISTRAR' WHEN 'EDIT' THEN 'EDITAR' WHEN 'EDITAR' THEN 'EDITAR' WHEN 'LANCAR_RESULTADO' THEN 'LANCAR_RESULTADO' WHEN 'VISUALIZAR' THEN 'VISUALIZAR' ELSE CASE WHEN coalesce(x.pode_editar,false) THEN 'EDITAR' WHEN coalesce(x.pode_visualizar,false) THEN 'VISUALIZAR' ELSE 'NENHUM' END END,
    false,false,false,false,true,now()
  FROM jsonb_to_recordset(coalesce(p_indicator_permissions,'[]'::jsonb)) x(operacao_id bigint,indicador_id bigint,nivel_acesso text,pode_visualizar boolean,pode_lancar_resultado boolean,pode_editar boolean,pode_administrar boolean)
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
REVOKE EXECUTE ON FUNCTION public.eh_super_admin() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.tem_escopo_admin_operacao(bigint) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.tem_acesso_central_administrativa() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.tem_acesso_admin_usuario(uuid,bigint) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.nivel_acesso_atende(text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_save_user_access(uuid,text,text,text,boolean,bigint[],jsonb,jsonb,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.eh_super_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.tem_escopo_admin_operacao(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tem_acesso_central_administrativa() TO authenticated;
GRANT EXECUTE ON FUNCTION public.tem_acesso_admin_usuario(uuid,bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nivel_acesso_atende(text,text) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.eh_admin_sustentacao() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.tem_acesso_indicador(bigint,bigint,text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.tem_acesso_inventario(bigint,bigint,text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.tem_acesso_modulo(bigint,text,text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.tem_acesso_operacao(bigint) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.tem_acesso_operacao_visualizacao(bigint) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.tem_acesso_plano_acao(bigint,bigint,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.eh_admin_sustentacao() TO authenticated;
GRANT EXECUTE ON FUNCTION public.tem_acesso_indicador(bigint,bigint,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tem_acesso_inventario(bigint,bigint,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tem_acesso_modulo(bigint,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tem_acesso_operacao(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tem_acesso_operacao_visualizacao(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tem_acesso_plano_acao(bigint,bigint,text) TO authenticated;

COMMENT ON COLUMN public.sustentacao_operacoes.responsavel_user_id IS 'Responsável administrativo da operação; não é proprietário dos históricos.';
COMMENT ON COLUMN public.sustentacao_indicadores.responsavel_user_id IS 'Responsável atual pelo indicador; resultados e metas continuam pertencendo à operação.';
