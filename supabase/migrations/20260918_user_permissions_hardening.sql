-- Restringe as funções de autorização ao papel autenticado.
-- A aplicação usa essas funções nas policies RLS e na RPC administrativa.
REVOKE EXECUTE ON FUNCTION public.admin_save_user_access(uuid,text,text,text,boolean,bigint[],jsonb,jsonb,jsonb) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.eh_admin_sustentacao() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.tem_acesso_indicador(bigint,bigint,text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.tem_acesso_inventario(bigint,bigint,text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.tem_acesso_modulo(bigint,text,text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.tem_acesso_operacao(bigint) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.tem_acesso_operacao_visualizacao(bigint) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.tem_acesso_plano_acao(bigint,bigint,text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.tem_acesso_sustentacao() FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.admin_save_user_access(uuid,text,text,text,boolean,bigint[],jsonb,jsonb,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.eh_admin_sustentacao() TO authenticated;
GRANT EXECUTE ON FUNCTION public.tem_acesso_indicador(bigint,bigint,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tem_acesso_inventario(bigint,bigint,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tem_acesso_modulo(bigint,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tem_acesso_operacao(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tem_acesso_operacao_visualizacao(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tem_acesso_plano_acao(bigint,bigint,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tem_acesso_sustentacao() TO authenticated;
