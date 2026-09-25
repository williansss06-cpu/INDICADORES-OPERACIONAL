-- Separa o vínculo usuário x operação das permissões de módulos.
-- Um usuário autorizado para uma operação deve conseguir resolver essa operação
-- após o login; as policies dos módulos continuam controlando o conteúdo e as ações.
-- A policy mantém o isolamento: tem_acesso_operacao(id) só retorna operações
-- vinculadas ao auth.uid() atual, ou operações permitidas ao escopo administrativo.

DROP POLICY IF EXISTS sustentacao_operacoes_acesso ON public.sustentacao_operacoes;

CREATE POLICY sustentacao_operacoes_acesso
ON public.sustentacao_operacoes
FOR SELECT TO authenticated
USING (public.tem_acesso_operacao(id));

COMMENT ON POLICY sustentacao_operacoes_acesso ON public.sustentacao_operacoes IS
  'Visibilidade operacional é determinada pelo vínculo usuário-operação; permissões de módulo são avaliadas separadamente nas tabelas de negócio.';
