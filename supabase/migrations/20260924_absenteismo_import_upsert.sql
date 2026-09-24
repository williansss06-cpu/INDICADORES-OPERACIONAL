-- Persistência idempotente da importação mensal de Absenteísmo.
-- A chave mantém os IDs existentes e evita duplicidade por operação/mês/colaborador.
-- A RLS existente continua exigindo acesso de edição ao módulo ABSENTEISMO.

CREATE UNIQUE INDEX IF NOT EXISTS absenteismo_registros_operacao_mes_colaborador_uidx
  ON public.absenteismo_registros (operacao_id, mes_referencia, colaborador);

COMMENT ON INDEX public.absenteismo_registros_operacao_mes_colaborador_uidx IS
  'Chave de upsert da carga mensal: operação, competência e colaborador';
