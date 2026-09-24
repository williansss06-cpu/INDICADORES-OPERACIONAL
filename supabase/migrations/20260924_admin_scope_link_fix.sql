-- Escopo de Administrador da Operação por vínculo explícito.
-- O responsável formal da operação continua existindo para governança,
-- mas não é usado como única condição para autorização administrativa.

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
        JOIN public.sustentacao_usuario_operacoes suo
          ON suo.user_id = su.user_id
         AND suo.operacao_id = p_operacao_id
         AND suo.ativo = true
        JOIN public.sustentacao_operacoes o
          ON o.id = suo.operacao_id
         AND o.ativo = true
        WHERE su.user_id = auth.uid()
          AND su.ativo = true
          AND su.perfil IN ('administrador_operacao', 'gestor')
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
        JOIN public.sustentacao_usuario_operacoes suo
          ON suo.user_id = su.user_id
         AND suo.ativo = true
        JOIN public.sustentacao_operacoes o
          ON o.id = suo.operacao_id
         AND o.ativo = true
        WHERE su.user_id = auth.uid()
          AND su.ativo = true
          AND su.perfil IN ('administrador_operacao', 'gestor')
      );
$$;

REVOKE EXECUTE ON FUNCTION public.tem_escopo_admin_operacao(bigint) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.tem_acesso_central_administrativa() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tem_escopo_admin_operacao(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tem_acesso_central_administrativa() TO authenticated;

COMMENT ON FUNCTION public.tem_escopo_admin_operacao(bigint) IS
  'Autoriza administrador da operação pelo vínculo ativo e explícito com a operação; não depende apenas do responsável formal.';
