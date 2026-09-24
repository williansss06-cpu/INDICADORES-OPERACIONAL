-- Módulos específicos da análise gerencial de Absenteísmo.
-- O acesso continua sendo controlado pela mesma tabela e pelas mesmas funções/RLS.

ALTER TABLE public.sustentacao_usuario_modulos
  DROP CONSTRAINT IF EXISTS sustentacao_usuario_modulos_central_module_check;

ALTER TABLE public.sustentacao_usuario_modulos
  ADD CONSTRAINT sustentacao_usuario_modulos_central_module_check CHECK (modulo IN (
    'PLANO_SUSTENTACAO', 'SLA_NEOLOG', 'ABSENTEISMO', 'PLANO_ACAO', 'INVENTARIOS',
    'VISAO_EXECUTIVA', 'ABSENTEISMO_DADOS_INDIVIDUAIS', 'ABSENTEISMO_DIAGNOSTICO',
    'ABSENTEISMO_RECORRENTES', 'ABSENTEISMO_PLANO_ACAO', 'ABSENTEISMO_EXPORTAR',
    'RESUMO_PERIODO', 'DESTAQUES_MES', 'PONTOS_ATENCAO', 'EXPORTAR_PDF', 'IMPORTAR_CSV'
  ));
