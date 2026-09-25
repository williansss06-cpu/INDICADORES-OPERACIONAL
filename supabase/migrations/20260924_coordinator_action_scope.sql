-- Escopo seguro de Planos de Ação para Coordenadores.
-- Preserva os registros existentes e usa responsavel_user_id como vínculo canônico.

ALTER TABLE public.sustentacao_plano_acao
  ADD COLUMN IF NOT EXISTS criado_por_user_id uuid REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS atualizado_por_user_id uuid REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS concluido_por_user_id uuid REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS concluido_at timestamptz,
  ADD COLUMN IF NOT EXISTS andamento text;

CREATE INDEX IF NOT EXISTS sustentacao_plano_acao_responsavel_idx
  ON public.sustentacao_plano_acao (responsavel_user_id, operacao_id);

CREATE INDEX IF NOT EXISTS sustentacao_plano_acao_prazo_idx
  ON public.sustentacao_plano_acao (operacao_id, data_fim, concluido);

COMMENT ON COLUMN public.sustentacao_plano_acao.responsavel_user_id IS
  'Responsável canônico da ação; vinculado ao auth.users.id e usado para o escopo do Coordenador.';
COMMENT ON COLUMN public.sustentacao_plano_acao.observacao IS
  'Observações, andamento e evidências registradas para a ação.';
COMMENT ON COLUMN public.sustentacao_plano_acao.criado_por_user_id IS
  'Usuário Auth que criou a ação; preenchido automaticamente em novos registros.';
COMMENT ON COLUMN public.sustentacao_plano_acao.atualizado_por_user_id IS
  'Usuário Auth da última atualização; preenchido automaticamente.';
COMMENT ON COLUMN public.sustentacao_plano_acao.concluido_por_user_id IS
  'Usuário Auth que marcou a ação como concluída.';
COMMENT ON COLUMN public.sustentacao_plano_acao.concluido_at IS
  'Data e hora em que a ação foi concluída.';
COMMENT ON COLUMN public.sustentacao_plano_acao.andamento IS
  'Andamento informado pelo responsável da ação.';

CREATE OR REPLACE FUNCTION public.eh_coordenador()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.sustentacao_usuarios su
    WHERE su.user_id = auth.uid()
      AND su.ativo = true
      AND su.perfil = 'coordenador'
  );
$$;

CREATE OR REPLACE FUNCTION public.tem_acesso_plano_acao_linha(
  p_operacao_id bigint,
  p_indicador_id bigint,
  p_acao text DEFAULT 'VIEW',
  p_responsavel_user_id uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  action_name text := upper(coalesce(p_acao, 'VIEW'));
  allowed boolean := false;
BEGIN
  IF public.eh_super_admin() THEN
    RETURN true;
  END IF;

  IF NOT public.eh_coordenador() THEN
    RETURN public.tem_acesso_plano_acao(p_operacao_id, p_indicador_id, action_name);
  END IF;

  IF p_responsavel_user_id IS DISTINCT FROM auth.uid() THEN
    RETURN false;
  END IF;

  IF NOT public.tem_acesso_modulo(
    p_operacao_id,
    'PLANO_ACAO',
    CASE WHEN action_name IN ('EDIT', 'UPDATE', 'STATUS', 'CONCLUDE') THEN 'EDIT' ELSE 'VIEW' END
  ) THEN
    RETURN false;
  END IF;

  SELECT CASE action_name
    WHEN 'EDIT' THEN pa.pode_editar
    WHEN 'STATUS' THEN pa.pode_alterar_status
    WHEN 'CONCLUDE' THEN pa.pode_concluir
    WHEN 'UPDATE' THEN (pa.pode_editar OR pa.pode_alterar_status OR pa.pode_concluir)
    ELSE pa.pode_visualizar
  END
  INTO allowed
  FROM public.sustentacao_usuario_plano_acao pa
  WHERE pa.user_id = auth.uid()
    AND pa.operacao_id = p_operacao_id
    AND pa.ativo = true;

  RETURN coalesce(allowed, false);
END;
$$;

CREATE OR REPLACE FUNCTION public.audit_sustentacao_plano_acao()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  actor uuid := auth.uid();
  is_coordinator boolean := public.eh_coordenador();
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.criado_por_user_id IS NULL THEN
      NEW.criado_por_user_id := actor;
    END IF;
    IF NEW.atualizado_por_user_id IS NULL THEN
      NEW.atualizado_por_user_id := actor;
    END IF;
    IF NEW.concluido IS TRUE AND NEW.concluido_at IS NULL THEN
      NEW.concluido_at := now();
      NEW.concluido_por_user_id := coalesce(NEW.concluido_por_user_id, actor);
    END IF;
    RETURN NEW;
  END IF;

  -- Metadados de criação são imutáveis para qualquer perfil.
  NEW.created_at := OLD.created_at;
  NEW.criado_por_user_id := OLD.criado_por_user_id;
  NEW.updated_at := now();
  NEW.atualizado_por_user_id := actor;

  IF is_coordinator THEN
    IF OLD.responsavel_user_id IS DISTINCT FROM actor THEN
      RAISE EXCEPTION 'Coordenador só pode atualizar ações atribuídas a ele';
    END IF;
    IF NEW.operacao_id IS DISTINCT FROM OLD.operacao_id
       OR NEW.indicador_id IS DISTINCT FROM OLD.indicador_id
       OR NEW.responsavel_user_id IS DISTINCT FROM OLD.responsavel_user_id
       OR NEW.acao IS DISTINCT FROM OLD.acao
       OR NEW.responsavel IS DISTINCT FROM OLD.responsavel
       OR NEW.data_inicio IS DISTINCT FROM OLD.data_inicio
       OR NEW.data_fim IS DISTINCT FROM OLD.data_fim
       OR NEW.ordem IS DISTINCT FROM OLD.ordem
       OR NEW.numero IS DISTINCT FROM OLD.numero
       OR NEW.origem IS DISTINCT FROM OLD.origem
       OR NEW.origem_contexto IS DISTINCT FROM OLD.origem_contexto
    THEN
      RAISE EXCEPTION 'Coordenador só pode atualizar status, observações e conclusão da própria ação';
    END IF;
    IF NEW.status IS DISTINCT FROM OLD.status
       AND NOT public.tem_acesso_plano_acao_linha(OLD.operacao_id, OLD.indicador_id, 'STATUS', actor)
    THEN
      RAISE EXCEPTION 'Coordenador sem permissão para atualizar o status desta ação';
    END IF;
    IF NEW.andamento IS DISTINCT FROM OLD.andamento
       OR NEW.observacao IS DISTINCT FROM OLD.observacao
    THEN
      IF NOT public.tem_acesso_plano_acao_linha(OLD.operacao_id, OLD.indicador_id, 'EDIT', actor) THEN
        RAISE EXCEPTION 'Coordenador sem permissão para registrar andamento ou evidências';
      END IF;
    END IF;
    IF NEW.concluido IS DISTINCT FROM OLD.concluido
       AND NOT public.tem_acesso_plano_acao_linha(OLD.operacao_id, OLD.indicador_id, 'CONCLUDE', actor)
    THEN
      RAISE EXCEPTION 'Coordenador sem permissão para concluir esta ação';
    END IF;
  END IF;

  IF NEW.concluido IS TRUE AND coalesce(OLD.concluido, false) IS FALSE THEN
    NEW.concluido_at := coalesce(NEW.concluido_at, now());
    NEW.concluido_por_user_id := actor;
  ELSIF NEW.concluido IS FALSE THEN
    NEW.concluido_at := NULL;
    NEW.concluido_por_user_id := NULL;
  ELSE
    NEW.concluido_at := OLD.concluido_at;
    NEW.concluido_por_user_id := OLD.concluido_por_user_id;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.validate_sustentacao_plano_acao_responsavel()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.responsavel_user_id IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM public.sustentacao_usuarios su
       JOIN public.sustentacao_usuario_operacoes suo
         ON suo.user_id = su.user_id
        AND suo.operacao_id = NEW.operacao_id
        AND suo.ativo = true
       WHERE su.user_id = NEW.responsavel_user_id
         AND su.ativo = true
     )
  THEN
    RAISE EXCEPTION 'Responsável não está ativo ou não possui vínculo com a operação da ação';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sustentacao_plano_acao_responsavel_validate ON public.sustentacao_plano_acao;
CREATE TRIGGER sustentacao_plano_acao_responsavel_validate
BEFORE INSERT OR UPDATE OF responsavel_user_id, operacao_id
ON public.sustentacao_plano_acao
FOR EACH ROW EXECUTE FUNCTION public.validate_sustentacao_plano_acao_responsavel();

DROP TRIGGER IF EXISTS sustentacao_plano_acao_audit ON public.sustentacao_plano_acao;
CREATE TRIGGER sustentacao_plano_acao_audit
BEFORE INSERT OR UPDATE
ON public.sustentacao_plano_acao
FOR EACH ROW EXECUTE FUNCTION public.audit_sustentacao_plano_acao();

DROP POLICY IF EXISTS sustentacao_plano_acao_select ON public.sustentacao_plano_acao;
CREATE POLICY sustentacao_plano_acao_select
ON public.sustentacao_plano_acao
FOR SELECT TO authenticated
USING (
  public.tem_acesso_plano_acao_linha(operacao_id, indicador_id, 'VIEW', responsavel_user_id)
);

DROP POLICY IF EXISTS sustentacao_plano_acao_insert ON public.sustentacao_plano_acao;
CREATE POLICY sustentacao_plano_acao_insert
ON public.sustentacao_plano_acao
FOR INSERT TO authenticated
WITH CHECK (
  NOT public.eh_coordenador()
  AND public.tem_acesso_plano_acao(operacao_id, indicador_id, 'CREATE')
);

DROP POLICY IF EXISTS sustentacao_plano_acao_update ON public.sustentacao_plano_acao;
CREATE POLICY sustentacao_plano_acao_update
ON public.sustentacao_plano_acao
FOR UPDATE TO authenticated
USING (
  public.tem_acesso_plano_acao_linha(operacao_id, indicador_id, 'UPDATE', responsavel_user_id)
)
WITH CHECK (
  public.tem_acesso_plano_acao_linha(operacao_id, indicador_id, 'UPDATE', responsavel_user_id)
);

DROP POLICY IF EXISTS sustentacao_plano_acao_delete ON public.sustentacao_plano_acao;
CREATE POLICY sustentacao_plano_acao_delete
ON public.sustentacao_plano_acao
FOR DELETE TO authenticated
USING (
  NOT public.eh_coordenador()
  AND public.tem_acesso_plano_acao(operacao_id, indicador_id, 'DELETE')
);

REVOKE EXECUTE ON FUNCTION public.eh_coordenador() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.tem_acesso_plano_acao_linha(bigint,bigint,text,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.eh_coordenador() TO authenticated;
GRANT EXECUTE ON FUNCTION public.tem_acesso_plano_acao_linha(bigint,bigint,text,uuid) TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.sustentacao_plano_acao TO authenticated;
