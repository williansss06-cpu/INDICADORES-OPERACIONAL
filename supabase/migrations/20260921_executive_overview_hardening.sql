-- Hardening da Visão Executiva: somente usuários autenticados podem executar a RPC.
REVOKE ALL ON FUNCTION public.obter_visao_executiva(bigint, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.obter_visao_executiva(bigint, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.obter_visao_executiva(bigint, integer) TO authenticated;
