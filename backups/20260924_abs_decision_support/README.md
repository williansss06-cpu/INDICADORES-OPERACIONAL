# Análise gerencial de Absenteísmo — backup e reversão

## Escopo

Esta alteração adiciona uma camada analítica executiva na própria aba **Análise de Absenteísmo**. A camada utiliza os registros reais do Supabase, a operação ativa, o ano/mês e os filtros atuais. Não recria tabelas de negócio nem altera IDs históricos.

Foram adicionados: diagnóstico do período, prioridades, tendência de horas/ocorrências/HC equivalente, Pareto de colaboradores, ranking de área/setor, análise de motivos, matriz de criticidade, comparação de novos casos e recorrentes e criação de plano de ação com `origem = ABSENTEISMO` e `origem_contexto`.

## Parâmetros administrativos

Os limites iniciais ficam persistidos em `sustentacao_configuracoes_operacao` e podem ser ajustados em **Administração → Operações**. Valores iniciais: 176 horas mensais por HC; recorrência a partir de 3 meses e 3 ocorrências; crítico a partir de 40 horas, 3 ocorrências e 30% de crescimento; atenção a partir de 16 horas, 2 ocorrências e 15% de crescimento.

Esses valores são defaults explícitos, não números ocultos no JavaScript. A lógica deve ser recalculada depois de qualquer alteração salva na configuração da operação.

## Segurança

Usuários com permissão específica de dados individuais consultam nomes/matrículas. Usuários com apenas visualização do Absenteísmo recebem a RPC `obter_absenteismo_consolidado`, que agrega por mês/local/área/setor e não retorna nomes. Importação, exportação, nomes, drill-down individual e criação de plano de ação são protegidos por módulos específicos e RLS.

## Reversão

O ponto de reversão do frontend está em `index.html.before`. As migrations são aditivas; a reversão de schema deve ser feita somente após confirmar que nenhum plano de ação utiliza `origem_contexto` e que os parâmetros não são mais necessários.
