# Relatório técnico — Análise Gerencial de Absenteísmo

**Projeto:** `INDICADORES-OPERACIONAL`  
**Supabase:** `Plano Sustentacao Matriz` (`nemvssopcgmfxjndpmlw`)  
**Commit publicado:** `5e9b71c26f99efe86bf793b7655167cf3645d21b`  
**Aplicação publicada:** [INDICADORES-OPERACIONAL](https://williansss06-cpu.github.io/INDICADORES-OPERACIONAL/?v=5e9b71c)

## Resultado

A aba **Análise de Absenteísmo** passou a conter uma camada de apoio à decisão baseada nos dados reais da operação ativa, do ano/mês selecionado e dos filtros existentes. O cálculo não utiliza números fixos de colaboradores, horas ou motivos no HTML.

Foram incorporados diagnóstico do período, prioridades, tendência mensal de horas improdutivas/ocorrências/HC equivalente, Pareto de colaboradores, ranking por área/setor, análise por motivo, matriz de criticidade, comparação entre novos casos e recorrentes, além da criação de plano de ação com contexto de origem do Absenteísmo.

A lógica de recorrência, criticidade e atenção utiliza parâmetros configuráveis por operação na área **Administração → Operações**. Os defaults iniciais são: 176 horas mensais por HC; recorrência a partir de 3 meses e 3 ocorrências; criticidade a partir de 40 horas, 3 ocorrências e 30% de crescimento; atenção a partir de 16 horas, 2 ocorrências e 15% de crescimento.

## Segurança e permissões

O Supabase agora fornece duas formas de leitura:

| Perfil de acesso | Fonte | Dados retornados |
|---|---|---|
| Visualização de Absenteísmo | `obter_absenteismo_consolidado` | Totais por mês, local, área, centro de custo e setor, sem nomes ou matrículas |
| Dados individuais | `absenteismo_registros` protegido por RLS | Colaborador, matrícula e detalhes individuais, apenas quando o módulo `ABSENTEISMO_DADOS_INDIVIDUAIS` está liberado |

A RPC é `SECURITY DEFINER`, verifica o módulo `ABSENTEISMO` para a operação solicitada e possui execução revogada para `PUBLIC`, ficando disponível somente a usuários autenticados. A RLS também restringe inserção, atualização e exclusão ao nível de edição do módulo da operação correspondente.

Importação, exportação, drill-down individual e criação de plano de ação possuem verificações específicas no frontend e no banco. Ocultar botões não é a única proteção.

## Importação mensal e separação operacional

O parser foi corrigido para:

- ler múltiplas abas da mesma planilha;
- utilizar a coluna **Mês** quando presente;
- usar o nome da aba como fallback mensal quando a coluna estiver ausente;
- identificar `MATRIZ` e `GLP_ACHE` pela coluna de operação ou, na planilha recebida, pela coluna **SETOR**;
- permitir a mesma pessoa em meses diferentes sem descartá-la por deduplicação global;
- manter a gravação idempotente pela chave `operacao_id + mes_referencia + colaborador`.

O teste com a planilha recebida, com abas `Junho`, `Julho` e `Agosto`, retornou **1.215 linhas válidas**, sem operação/mês desconhecidos, distribuídas exclusivamente entre `MATRIZ` e `GLP_ACHE`.

## Validações executadas

| Validação | Resultado |
|---|---|
| Sintaxe JavaScript com `node --check` | Aprovada |
| `git diff --check` | Aprovada |
| Parser da planilha real | Aprovado; 1.215 linhas válidas, zero desconhecidas |
| Separação por operação e mês | Aprovada; somente MATRIZ/GLP_ACHE |
| RPC consolidada no Supabase | Instalada e `SECURITY DEFINER` |
| RLS de registros individuais | Policies de SELECT/INSERT/UPDATE/DELETE ativas |
| Configurações por operação | 2 registros persistidos, um por operação |
| Preservação das tabelas de negócio | Sem alteração estrutural nos dados históricos de indicadores/resultados/inventários/planos |
| Página pública | HTTP 200; marcadores da análise presentes |
| GitHub Pages | Workflow `36059851364` concluído com sucesso |
| Git remoto | `origin/main` igual ao commit publicado |

A versão pública sem sessão mostra corretamente a tela de login. O teste autenticado de upload depende de uma sessão real do administrador no navegador; a implementação foi validada estaticamente, no Supabase e com a planilha real, mas o clique final de confirmação da carga deve ser realizado com um usuário que possua `ABSENTEISMO` no nível `Editar`.

## Estado atual consultado no Supabase

| Tabela | Registros atuais |
|---|---:|
| `sustentacao_indicadores` | 17 |
| `sustentacao_resultados` | 137 |
| `sustentacao_inventarios` | 4 |
| `sustentacao_plano_acao` | 9 |
| `absenteismo_registros` | 1.858 |
| `absenteismo_areas` | 4 |

A contagem de Absenteísmo inclui o histórico existente e cargas mensais já persistidas no projeto; a operação é sempre filtrada por `operacao_id`.

## Arquivos versionados

- `index.html`
- `supabase/migrations/20260924_absenteismo_decision_support.sql`
- `supabase/migrations/20260924_absenteismo_individual_rls.sql`
- `supabase/migrations/20260924_absenteismo_permission_modules.sql`
- `supabase/migrations/20260924_absenteismo_permission_defaults.sql`
- `backups/20260924_abs_decision_support/`

O backup reversível contém `index.html.before`, `SHA256SUMS` e o manifesto da alteração.
