-- Restrição explícita da RPC de replicação.
-- A execução direta fica disponível somente para sessões autenticadas;
-- a própria função ainda valida usuário operacional, Central e escopo.
REVOKE ALL ON FUNCTION public.admin_replicate_user_permissions(uuid, uuid, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_replicate_user_permissions(uuid, uuid, boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_replicate_user_permissions(uuid, uuid, boolean) TO authenticated;
