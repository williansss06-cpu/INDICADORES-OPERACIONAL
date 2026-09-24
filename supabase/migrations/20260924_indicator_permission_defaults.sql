-- Garante que novos indicadores de uma operação administrada apareçam
-- imediatamente no editor de permissões dos administradores daquela operação.
-- Não altera resultados, metas, IDs ou históricos.

CREATE OR REPLACE FUNCTION public.sincronizar_acesso_admin_novo_indicador()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.sustentacao_usuario_indicadores (
    user_id, operacao_id, indicador_id, nivel_acesso,
    pode_visualizar, pode_lancar_resultado, pode_editar,
    pode_administrar, ativo, updated_at
  )
  SELECT
    uo.user_id,
    NEW.operacao_id,
    NEW.id,
    'ADMINISTRAR',
    true,
    true,
    true,
    true,
    true,
    now()
  FROM public.sustentacao_usuarios su
  JOIN public.sustentacao_usuario_operacoes uo
    ON uo.user_id = su.user_id
   AND uo.operacao_id = NEW.operacao_id
   AND uo.ativo = true
  WHERE su.ativo = true
    AND su.perfil IN ('administrador_operacao', 'gestor')
  ON CONFLICT (user_id, operacao_id, indicador_id) DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sustentacao_indicadores_seed_admin_access
  ON public.sustentacao_indicadores;

CREATE TRIGGER sustentacao_indicadores_seed_admin_access
AFTER INSERT OR UPDATE OF operacao_id
ON public.sustentacao_indicadores
FOR EACH ROW
EXECUTE FUNCTION public.sincronizar_acesso_admin_novo_indicador();

REVOKE EXECUTE ON FUNCTION public.sincronizar_acesso_admin_novo_indicador() FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.sincronizar_acesso_admin_novo_indicador() IS
  'Semeia a permissão administrativa de novos indicadores para administradores da operação, preservando isolamento por operacao_id.';
