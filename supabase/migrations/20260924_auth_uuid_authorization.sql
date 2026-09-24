-- Correção estrutural do vínculo Auth -> autorização administrativa.
-- O campo sustentacao_usuarios.user_id é o UUID canônico de auth.users.id.
-- Migration aditiva: não substitui usuários, permissões ou dados operacionais.

COMMENT ON COLUMN public.sustentacao_usuarios.user_id IS
  'UUID canônico de auth.users.id. A autorização da aplicação deve ser resolvida por este vínculo, nunca somente pelo e-mail.';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'sustentacao_usuarios_user_id_fkey'
      AND conrelid = 'public.sustentacao_usuarios'::regclass
  ) THEN
    ALTER TABLE public.sustentacao_usuarios
      ADD CONSTRAINT sustentacao_usuarios_user_id_fkey
      FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
  END IF;
END
$$;

CREATE UNIQUE INDEX IF NOT EXISTS sustentacao_usuarios_auth_user_id_uidx
  ON public.sustentacao_usuarios (user_id)
  WHERE user_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.obter_usuario_operacional_atual()
RETURNS TABLE (
  user_id uuid,
  email text,
  nome text,
  perfil text,
  ativo boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT su.user_id, su.email, su.nome, su.perfil, su.ativo
  FROM public.sustentacao_usuarios su
  WHERE su.user_id = auth.uid()
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.obter_usuario_operacional_atual() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.obter_usuario_operacional_atual() TO authenticated;

COMMENT ON FUNCTION public.obter_usuario_operacional_atual() IS
  'Retorna o cadastro administrativo do usuário autenticado pelo UUID auth.uid().';

-- Verificação de integridade: todo cadastro administrativo preenchido deve apontar
-- para uma identidade existente no Supabase Auth.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.sustentacao_usuarios su
    LEFT JOIN auth.users au ON au.id = su.user_id
    WHERE su.user_id IS NOT NULL AND au.id IS NULL
  ) THEN
    RAISE EXCEPTION 'Existem cadastros administrativos com user_id sem identidade Auth correspondente';
  END IF;
END
$$;
