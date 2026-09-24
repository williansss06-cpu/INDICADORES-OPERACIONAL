-- Materializa as permissões específicas com o mesmo nível que o usuário já possuía em ABSENTEISMO.
-- Assim, a implantação não retira acesso atual e o administrador pode refiná-lo depois.

INSERT INTO public.sustentacao_usuario_modulos (
  user_id, operacao_id, modulo, nivel_acesso,
  pode_visualizar, pode_lancar_resultado, pode_editar, pode_administrar,
  ativo, updated_at
)
SELECT
  m.user_id,
  m.operacao_id,
  modules.modulo,
  m.nivel_acesso,
  m.pode_visualizar,
  m.pode_lancar_resultado,
  m.pode_editar,
  m.pode_administrar,
  m.ativo,
  now()
FROM public.sustentacao_usuario_modulos m
CROSS JOIN (VALUES
  ('ABSENTEISMO_DADOS_INDIVIDUAIS'),
  ('ABSENTEISMO_DIAGNOSTICO'),
  ('ABSENTEISMO_RECORRENTES'),
  ('ABSENTEISMO_PLANO_ACAO'),
  ('ABSENTEISMO_EXPORTAR')
) AS modules(modulo)
WHERE m.modulo = 'ABSENTEISMO'
ON CONFLICT (user_id, operacao_id, modulo) DO NOTHING;
