-- Auditoria explícita de autoria e conclusão dos Planos de Ação.
-- Aditiva e compatível com registros existentes.

ALTER TABLE public.sustentacao_plano_acao
  ADD COLUMN IF NOT EXISTS criado_por_user_id uuid REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS criado_em timestamptz,
  ADD COLUMN IF NOT EXISTS atualizado_por_user_id uuid REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS concluido_por_user_id uuid REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS concluido_em timestamptz;

UPDATE public.sustentacao_plano_acao
SET criado_em = coalesce(criado_em, created_at, now()),
    concluido_em = CASE WHEN concluido THEN coalesce(concluido_em, updated_at, now()) ELSE concluido_em END
WHERE criado_em IS NULL OR (concluido = true AND concluido_em IS NULL);

CREATE OR REPLACE FUNCTION public.populate_sustentacao_plano_acao_audit_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  actor uuid := auth.uid();
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.criado_por_user_id := coalesce(NEW.criado_por_user_id, actor);
    NEW.criado_em := coalesce(NEW.criado_em, now());
    NEW.atualizado_por_user_id := coalesce(NEW.atualizado_por_user_id, actor);
    IF NEW.concluido = true THEN
      NEW.concluido_por_user_id := coalesce(NEW.concluido_por_user_id, actor);
      NEW.concluido_em := coalesce(NEW.concluido_em, now());
    END IF;
  ELSE
    NEW.atualizado_por_user_id := coalesce(actor, NEW.atualizado_por_user_id);
    IF NEW.concluido = true AND coalesce(OLD.concluido, false) = false THEN
      NEW.concluido_por_user_id := coalesce(actor, NEW.concluido_por_user_id);
      NEW.concluido_em := coalesce(NEW.concluido_em, now());
    ELSIF NEW.concluido = false AND coalesce(OLD.concluido, false) = true THEN
      NEW.concluido_por_user_id := null;
      NEW.concluido_em := null;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sustentacao_plano_acao_audit_fields ON public.sustentacao_plano_acao;
CREATE TRIGGER sustentacao_plano_acao_audit_fields
BEFORE INSERT OR UPDATE ON public.sustentacao_plano_acao
FOR EACH ROW EXECUTE FUNCTION public.populate_sustentacao_plano_acao_audit_fields();

CREATE INDEX IF NOT EXISTS sustentacao_plano_acao_created_by_idx
  ON public.sustentacao_plano_acao (criado_por_user_id, criado_em DESC);
CREATE INDEX IF NOT EXISTS sustentacao_plano_acao_completed_by_idx
  ON public.sustentacao_plano_acao (concluido_por_user_id, concluido_em DESC);
