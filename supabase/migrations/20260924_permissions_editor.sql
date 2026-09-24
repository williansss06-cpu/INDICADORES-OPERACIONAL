-- Editor de permissões por usuário e operação.
-- Evolui o modelo existente sem criar tabelas por indicador e sem alterar dados de negócio.

ALTER TABLE public.sustentacao_usuario_modulos
  DROP CONSTRAINT IF EXISTS sustentacao_usuario_modulos_modulo_check;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'sustentacao_usuario_modulos_central_module_check'
      AND conrelid = 'public.sustentacao_usuario_modulos'::regclass
  ) THEN
    ALTER TABLE public.sustentacao_usuario_modulos
      ADD CONSTRAINT sustentacao_usuario_modulos_central_module_check
      CHECK (modulo IN (
        'PLANO_SUSTENTACAO',
        'SLA_NEOLOG',
        'ABSENTEISMO',
        'PLANO_ACAO',
        'INVENTARIOS',
        'VISAO_EXECUTIVA',
        'RESUMO_PERIODO',
        'DESTAQUES_MES',
        'PONTOS_ATENCAO',
        'EXPORTAR_PDF',
        'IMPORTAR_CSV'
      ));
  END IF;
END $$;

-- Administradores da operação recebem o conjunto padrão completo apenas quando a
-- operação é autorizada. O Super Administrador ainda pode remover qualquer item;
-- as alterações posteriores são preservadas pelo RPC administrativo.
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT DISTINCT su.user_id, uo.operacao_id
    FROM public.sustentacao_usuarios su
    JOIN public.sustentacao_usuario_operacoes uo
      ON uo.user_id = su.user_id
     AND uo.ativo = true
    JOIN public.sustentacao_operacoes o
      ON o.id = uo.operacao_id
     AND o.ativo = true
    WHERE su.ativo = true
      AND su.perfil IN ('administrador_operacao', 'gestor')
  LOOP
    INSERT INTO public.sustentacao_usuario_modulos (
      user_id, operacao_id, modulo, nivel_acesso,
      pode_visualizar, pode_lancar_resultado, pode_editar,
      pode_administrar, ativo, updated_at
    )
    SELECT
      r.user_id, r.operacao_id, modules.modulo, 'ADMINISTRAR',
      true, true, true, true, true, now()
    FROM unnest(ARRAY[
      'PLANO_SUSTENTACAO',
      'SLA_NEOLOG',
      'ABSENTEISMO',
      'PLANO_ACAO',
      'INVENTARIOS',
      'VISAO_EXECUTIVA',
      'RESUMO_PERIODO',
      'DESTAQUES_MES',
      'PONTOS_ATENCAO',
      'EXPORTAR_PDF',
      'IMPORTAR_CSV'
    ]::text[]) AS modules(modulo)
    ON CONFLICT (user_id, operacao_id, modulo) DO UPDATE SET
      nivel_acesso = 'ADMINISTRAR',
      pode_visualizar = true,
      pode_lancar_resultado = true,
      pode_editar = true,
      pode_administrar = true,
      ativo = true,
      updated_at = now();

    INSERT INTO public.sustentacao_usuario_indicadores (
      user_id, operacao_id, indicador_id, nivel_acesso,
      pode_visualizar, pode_lancar_resultado, pode_editar,
      pode_administrar, ativo, updated_at
    )
    SELECT
      r.user_id, r.operacao_id, i.id, 'ADMINISTRAR',
      true, true, true, true, true, now()
    FROM public.sustentacao_indicadores i
    WHERE i.operacao_id = r.operacao_id
      AND i.ativo = true
    ON CONFLICT (user_id, operacao_id, indicador_id) DO UPDATE SET
      nivel_acesso = 'ADMINISTRAR',
      pode_visualizar = true,
      pode_lancar_resultado = true,
      pode_editar = true,
      pode_administrar = true,
      ativo = true,
      updated_at = now();

    INSERT INTO public.sustentacao_usuario_plano_acao (
      user_id, operacao_id, pode_visualizar, pode_criar,
      pode_editar, pode_alterar_status, pode_concluir,
      pode_excluir, ativo, updated_at
    )
    VALUES (r.user_id, r.operacao_id, true, true, true, true, true, true, true, now())
    ON CONFLICT (user_id, operacao_id) DO UPDATE SET
      pode_visualizar = true,
      pode_criar = true,
      pode_editar = true,
      pode_alterar_status = true,
      pode_concluir = true,
      pode_excluir = true,
      ativo = true,
      updated_at = now();
  END LOOP;
END $$;

-- O perfil administrativo não é um bypass de negócio: ele recebe permissões
-- padrão gravadas e pode ter qualquer permissão retirada pelo Super Administrador.
CREATE OR REPLACE FUNCTION public.tem_acesso_modulo(
  p_operacao_id bigint,
  p_modulo text,
  p_acao text DEFAULT 'VIEW'
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.eh_super_admin()
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

CREATE OR REPLACE FUNCTION public.tem_acesso_indicador(
  p_operacao_id bigint,
  p_indicador_id bigint,
  p_acao text DEFAULT 'VIEW'
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.eh_super_admin()
      OR EXISTS (
        SELECT 1
        FROM public.sustentacao_indicadores ind
        JOIN public.sustentacao_usuario_indicadores ui
          ON ui.indicador_id = ind.id
         AND ui.operacao_id = ind.operacao_id
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
  SELECT public.tem_acesso_operacao(p_operacao_id)
      AND public.tem_acesso_modulo(p_operacao_id, 'PLANO_SUSTENTACAO', 'VIEW');
$$;

CREATE OR REPLACE FUNCTION public.tem_acesso_inventario(
  p_operacao_id bigint,
  p_resultado_id bigint,
  p_acao text DEFAULT 'VIEW'
)
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
          SELECT 1
          FROM public.sustentacao_resultados r
          WHERE r.id = p_resultado_id
            AND r.operacao_id = p_operacao_id
            AND public.tem_acesso_indicador(p_operacao_id, r.indicador_id, p_acao)
        )
      );
$$;

CREATE OR REPLACE FUNCTION public.tem_acesso_plano_acao(
  p_operacao_id bigint,
  p_indicador_id bigint,
  p_acao text DEFAULT 'VIEW'
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.eh_super_admin()
      OR (
        public.tem_acesso_modulo(
          p_operacao_id,
          'PLANO_ACAO',
          CASE
            WHEN upper(coalesce(p_acao, 'VIEW')) IN ('CREATE','EDIT','STATUS','CONCLUDE','DELETE') THEN 'EDIT'
            ELSE 'VIEW'
          END
        )
        AND (p_indicador_id IS NULL OR public.tem_acesso_indicador(p_operacao_id, p_indicador_id, 'VIEW'))
        AND EXISTS (
          SELECT 1
          FROM public.sustentacao_usuario_plano_acao pa
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

REVOKE EXECUTE ON FUNCTION public.tem_acesso_modulo(bigint,text,text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.tem_acesso_indicador(bigint,bigint,text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.tem_acesso_operacao_visualizacao(bigint) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.tem_acesso_inventario(bigint,bigint,text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.tem_acesso_plano_acao(bigint,bigint,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tem_acesso_modulo(bigint,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tem_acesso_indicador(bigint,bigint,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tem_acesso_operacao_visualizacao(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tem_acesso_inventario(bigint,bigint,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tem_acesso_plano_acao(bigint,bigint,text) TO authenticated;

COMMENT ON TABLE public.sustentacao_usuario_modulos IS 'Permissões por usuário e operação; nível_acesso é a fonte canônica e os flags mantêm compatibilidade.';
COMMENT ON TABLE public.sustentacao_usuario_indicadores IS 'Permissões por indicador dentro da operação; novos indicadores aparecem no catálogo administrativo automaticamente.';
