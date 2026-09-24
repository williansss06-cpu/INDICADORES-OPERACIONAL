-- Corrige a ordenação mensal da RPC base do Assistente.
-- A função foi inicialmente criada com alias JSON x, mas os campos ano/mês
-- pertencem à subconsulta q. A correção é idempotente e não altera dados.
DO $$
DECLARE
  definition text;
BEGIN
  SELECT pg_get_functiondef(
    'public.assistente_obter_contexto(bigint,integer,integer,text,jsonb)'::regprocedure
  ) INTO definition;
  IF definition IS NULL THEN
    RAISE EXCEPTION 'Função de contexto não encontrada';
  END IF;
  definition := replace(definition, 'ORDER BY x.ano,x.mes', 'ORDER BY q.ano,q.mes');
  definition := replace(definition, 'ORDER BY x.ano, x.mes', 'ORDER BY q.ano, q.mes');
  EXECUTE definition;
END
$$;
