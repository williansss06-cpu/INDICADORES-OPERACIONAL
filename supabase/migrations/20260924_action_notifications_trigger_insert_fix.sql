-- Corrige a guarda de TG_OP no trigger de normalização.
CREATE OR REPLACE FUNCTION public.normalize_sustentacao_plano_acao_notification_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  email_value text;
BEGIN
  IF NEW.responsavel_user_id IS NOT NULL THEN
    SELECT lower(email) INTO email_value
    FROM public.sustentacao_usuarios
    WHERE user_id = NEW.responsavel_user_id
    LIMIT 1;
    NEW.responsavel_tipo := 'PLATAFORMA';
    NEW.responsavel_email := coalesce(email_value, nullif(lower(btrim(NEW.responsavel_email)), ''));
  ELSIF upper(coalesce(NEW.responsavel_tipo, '')) = 'EXTERNO'
        AND nullif(btrim(coalesce(NEW.responsavel_email, '')), '') IS NOT NULL THEN
    NEW.responsavel_tipo := 'EXTERNO';
    NEW.responsavel_email := lower(btrim(NEW.responsavel_email));
  ELSE
    NEW.responsavel_tipo := 'NENHUM';
    NEW.responsavel_email := nullif(lower(btrim(coalesce(NEW.responsavel_email, ''))), '');
  END IF;

  IF TG_OP = 'UPDATE' AND NEW.concluido = true AND coalesce(OLD.concluido, false) = false THEN
    NEW.external_access_expires_at := now() + interval '30 days';
  ELSIF TG_OP = 'UPDATE' AND NEW.concluido = false AND OLD.concluido = true THEN
    NEW.external_access_expires_at := null;
  END IF;

  IF NEW.proximo_lembrete_em IS NULL
     AND NEW.concluido = false
     AND NEW.responsavel_email IS NOT NULL THEN
    NEW.proximo_lembrete_em := public.action_next_weekly_reminder(now());
  END IF;
  RETURN NEW;
END;
$$;
