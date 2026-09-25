-- Compatibilidade da primeira fase de notificações.
-- Normaliza ações históricas que já tinham responsavel_user_id sem disparar e-mails retroativos.

CREATE OR REPLACE FUNCTION public.record_sustentacao_plano_acao_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  actor uuid := auth.uid();
  recipient text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.sustentacao_acao_eventos(action_id, operacao_id, tipo, actor_user_id, actor_type, metadata)
    VALUES (NEW.id, NEW.operacao_id, 'ACAO_CRIADA', actor, 'PLATAFORMA', jsonb_build_object('responsavel_tipo', NEW.responsavel_tipo));
    IF NEW.responsavel_email IS NOT NULL THEN
      INSERT INTO public.sustentacao_acao_eventos(action_id, operacao_id, tipo, actor_user_id, actor_type, metadata)
      VALUES (NEW.id, NEW.operacao_id, 'RESPONSAVEL_ATRIBUIDO', actor, CASE WHEN NEW.responsavel_tipo = 'EXTERNO' THEN 'EXTERNO' ELSE 'PLATAFORMA' END, jsonb_build_object('email', NEW.responsavel_email));
      INSERT INTO public.sustentacao_acao_notificacoes(action_id, operacao_id, tipo, destinatario_tipo, destinatario_user_id, destinatario_email, dedupe_key, payload)
      VALUES (NEW.id, NEW.operacao_id, 'ATRIBUICAO', NEW.responsavel_tipo, NEW.responsavel_user_id, NEW.responsavel_email, 'assignment:' || NEW.id::text || ':' || NEW.responsavel_email, jsonb_build_object('action_id', NEW.id))
      ON CONFLICT (dedupe_key) DO NOTHING;
    END IF;
    RETURN NEW;
  END IF;

  -- Para responsáveis internos, somente uma mudança real de user_id gera uma nova atribuição.
  -- A normalização de e-mail/tipo de registros antigos não deve disparar e-mail retroativo.
  IF NEW.responsavel_user_id IS DISTINCT FROM OLD.responsavel_user_id
     OR (NEW.responsavel_user_id IS NULL AND NEW.responsavel_email IS DISTINCT FROM OLD.responsavel_email) THEN
    recipient := coalesce(NEW.responsavel_email, '');
    IF recipient <> '' AND NEW.concluido = false THEN
      INSERT INTO public.sustentacao_acao_eventos(action_id, operacao_id, tipo, actor_user_id, actor_type, metadata)
      VALUES (NEW.id, NEW.operacao_id, 'RESPONSAVEL_ATRIBUIDO', actor, CASE WHEN NEW.responsavel_tipo = 'EXTERNO' THEN 'EXTERNO' ELSE 'PLATAFORMA' END, jsonb_build_object('email', recipient));
      INSERT INTO public.sustentacao_acao_notificacoes(action_id, operacao_id, tipo, destinatario_tipo, destinatario_user_id, destinatario_email, dedupe_key, payload)
      VALUES (NEW.id, NEW.operacao_id, 'ATRIBUICAO', NEW.responsavel_tipo, NEW.responsavel_user_id, recipient, 'assignment:' || NEW.id::text || ':' || recipient, jsonb_build_object('action_id', NEW.id))
      ON CONFLICT (dedupe_key) DO NOTHING;
    END IF;
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status OR NEW.concluido IS DISTINCT FROM OLD.concluido THEN
    INSERT INTO public.sustentacao_acao_eventos(action_id, operacao_id, tipo, actor_user_id, actor_type, metadata)
    VALUES (NEW.id, NEW.operacao_id, CASE WHEN NEW.concluido THEN 'ACAO_CONCLUIDA' ELSE 'STATUS_ALTERADO' END, actor, 'PLATAFORMA', jsonb_build_object('status', NEW.status, 'concluido', NEW.concluido));
    IF NEW.concluido THEN
      UPDATE public.sustentacao_acao_notificacoes
      SET status = 'CANCELADO', updated_at = now(), last_error = 'Ação concluída antes do envio.'
      WHERE action_id = NEW.id AND status IN ('PENDENTE', 'PROCESSANDO') AND tipo = 'LEMBRETE';
      UPDATE public.sustentacao_acao_portal_tokens
      SET expires_at = now() + interval '30 days', completed_read_until = now() + interval '30 days', updated_at = now()
      WHERE action_id = NEW.id AND revoked_at IS NULL;
    END IF;
  END IF;

  IF NEW.andamento IS DISTINCT FROM OLD.andamento OR NEW.observacao IS DISTINCT FROM OLD.observacao THEN
    INSERT INTO public.sustentacao_acao_eventos(action_id, operacao_id, tipo, actor_user_id, actor_type, metadata)
    VALUES (NEW.id, NEW.operacao_id, 'RESPOSTA_REGISTRADA', actor, 'PLATAFORMA', jsonb_build_object('tem_andamento', NEW.andamento IS NOT NULL, 'tem_observacao', NEW.observacao IS NOT NULL));
  END IF;
  RETURN NEW;
END;
$$;

UPDATE public.sustentacao_plano_acao a
SET responsavel_tipo = 'PLATAFORMA',
    responsavel_email = lower(su.email)
FROM public.sustentacao_usuarios su
WHERE a.responsavel_user_id = su.user_id
  AND a.responsavel_tipo <> 'PLATAFORMA';
