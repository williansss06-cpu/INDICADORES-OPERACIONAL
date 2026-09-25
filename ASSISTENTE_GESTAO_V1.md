# Assistente de Gestão — V1

## Objetivo

O Assistente de Gestão é um módulo somente leitura da aplicação **Plano de Sustentação Matriz / INDICADORES-OPERACIONAL**. Ele interpreta o contexto da tela atual e produz uma leitura executiva baseada nos dados autorizados do Supabase: resultado, desvios, concentrações, recorrências, impactos, ações e pontos para decisão. O módulo não grava indicadores, resultados, Absenteísmo, SLA ou planos de ação.

A experiência principal é um painel lateral aberto pelo botão **Pergunte aos Indicadores**. A pergunta pode ser livre ou escolhida por atalhos de gestão: atenção prioritária, indicadores abaixo da meta, piora do mês, explicação do mês, Absenteísmo, ofensores, recorrências, ações atrasadas, Operação Aché e Pontuação Neolog.

## Fontes e contrato de contexto

O contexto é montado exclusivamente no Supabase definitivo `nemvssopcgmfxjndpmlw`, por meio das funções `assistente_obter_contexto` e `assistente_obter_contexto_v2`. A função valida a sessão Auth, a operação, o vínculo operacional, as permissões do Assistente e as permissões existentes dos módulos/indicadores/plano de ação antes de retornar dados.

| Domínio | Fonte | Uso no Assistente |
|---|---|---|
| Indicadores | `sustentacao_indicadores` | Nome, meta, peso, polaridade, formato e ordem |
| Resultados | `sustentacao_resultados` | Resultado do ano/mês corrente e campos operacionais disponíveis |
| Absenteísmo | `absenteismo_registros` | Horas improdutivas, horas disponíveis, índice, motivos, áreas, pessoas e recorrência |
| SLA | `sustentacao_sla_neolog_pontuacoes` | Pontuações e valores do contexto autorizado; inclui registros históricos sem `indicador_id` |
| Plano de ação | `sustentacao_plano_acao` | Ações abertas, responsáveis, status, prazos e atraso |
| Operações | `sustentacao_operacoes` | Nome e escopo da operação |

A saída inclui uma linha de fonte, período e atualização. A opção **Ver dados utilizados** expõe apenas o resumo que já foi autorizado para a sessão atual.

## Permissões

Foi criada a tabela `sustentacao_assistente_permissoes`, com uma linha por usuário e operação. Ela possui capacidades independentes para acesso geral, indicadores, Absenteísmo, Plano de Ação, SLA/Pontuação Neolog, Visão Executiva e análise consolidada. O escopo consolidado é reservado ao Super Administrador.

A Central Administrativa recebeu o bloco **ASSISTENTE INTELIGENTE** no editor de permissões. O administrador pode liberar ou retirar as capacidades por operação; o Super Administrador também pode liberar a análise consolidada. A Edge Function `admin-users` persiste essas permissões por meio da RPC `admin_save_assistant_access`. A validação ocorre novamente no backend; ocultar o botão não é a única barreira.

A tabela `sustentacao_assistente_historico` registra somente a pergunta, usuário, operação, módulo, período, modo e horário. Não armazena senha, token, chave de API, prompt secreto ou resposta da IA.

## Backend e privacidade

A Edge Function `assistant-management` exige JWT e valida o usuário pelo Supabase Auth. Ela chama a RPC de contexto com o JWT do usuário, portanto as decisões de escopo e autorização continuam no banco. O frontend utiliza somente a chave pública do Supabase e nunca recebe Service Role Key ou chave de modelo.

A análise padrão é determinística e funciona sem serviço externo. Ela calcula a leitura a partir dos dados existentes e explicita quando uma concentração não prova causalidade. Não são criados números fictícios, metas implícitas ou classificações contratuais não cadastradas.

A função possui adaptador opcional para modelo generativo no backend. Para habilitá-lo em produção, configurar no ambiente da Edge Function, por mecanismo seguro de secrets do Supabase:

- `OPENAI_API_KEY` ou `ASSISTENTE_MODEL_API_KEY`;
- opcionalmente `OPENAI_API_BASE`;
- opcionalmente `ASSISTENTE_MODEL`.

Sem esses secrets, o produto permanece operacional usando o motor determinístico, sem tentar enviar dados para um modelo externo.

## Fluxo de uso

1. O usuário entra normalmente na aplicação e recebe o perfil, operações e permissões.
2. O botão **Pergunte aos Indicadores** aparece somente em uma operação liberada para o Assistente.
3. Ao abrir o painel, a operação, módulo, ano, mês e filtros ativos são enviados como contexto.
4. A Edge Function valida o JWT e obtém apenas o contexto permitido.
5. A pergunta é registrada no histórico mínimo; a resposta é gerada pelo motor determinístico ou pelo modelo backend configurado.
6. A resposta retorna ao painel lateral, sem modificar dados operacionais.

## Conversa orientada por intenção

O Assistente agora diferencia a pergunta atual antes de montar a resposta. As intenções cobertas incluem **Resumo Executivo**, **Absenteísmo**, **contribuidores**, **recorrência**, **tendência**, **indicadores abaixo da meta**, **quedas**, **ofensores**, **ações atrasadas**, **SLA NEOLOG**, **operação** e **análise da tela**. A intenção é usada para selecionar o contexto mínimo necessário; uma pergunta sobre Absenteísmo, por exemplo, não precisa carregar todos os resultados de indicadores e ações.

Cada resposta informa a operação, período e atualização, além da intenção identificada, fontes consultadas e quantidade de registros utilizados. O frontend registra a pergunta e a resposta na conversa da sessão, mostra claramente o usuário e o Assistente, e apresenta sugestões de continuidade geradas conforme os dados realmente disponíveis. Ao trocar de operação ou encerrar a sessão, a conversa é limpa para impedir mistura de contexto.

A série mensal e a identificação de recorrentes são calculadas pela RPC somente leitura `assistente_obter_conversa_contexto`, que reutiliza a autorização da RPC base e mantém o filtro por operação e permissão de Absenteísmo. A Edge Function registra no console operacional um rastreamento resumido no formato **pergunta → intenção → fontes → registros**, sem expor tokens, chaves ou dados fora do escopo autorizado.

Na **Visão Executiva**, o Assistente também é apresentado diretamente no dashboard, antes dos cards e gráficos. Esse bloco mostra uma saudação contextual, o período analisado, o resumo de performance, pontos de atenção, ações em aberto, evolução positiva e, quando autorizado, Absenteísmo e SLA Neolog. A primeira leitura é limitada a três prioridades e usa o mesmo conjunto de dados autorizado da visão executiva; não abre pop-up automaticamente. O campo **Pergunte ao Assistente...** permite iniciar uma conversa diretamente no bloco, enquanto **Ver análise completa** abre o painel lateral.

Nas telas de Matriz, GLP/Aché, Absenteísmo e Plano de Ação, um botão contextual discreto **Pergunte sobre esta tela** abre o mesmo painel já vinculado à operação, período, módulo e filtros atuais. A Visão Executiva não recebe esse botão adicional porque já contém a experiência integrada.

## Arquivos da implementação

- `index.html`: botão, painel lateral, perguntas rápidas, renderização da resposta e editor de permissões.
- `supabase/migrations/20260924_assistente_gestao_v1.sql`: tabelas, RLS, permissões iniciais e RPCs.
- `supabase/migrations/20260924_assistente_gestao_sla_compat.sql`: compatibilidade dos lançamentos SLA históricos sem `indicador_id`.
- `supabase/functions/assistant-management/index.ts`: Edge Function JWT, contexto e análise.
- `supabase/migrations/20260925_assistente_conversa_contexto.sql`: RPC somente leitura para série mensal e recorrência usadas pela conversa.
- `supabase/migrations/20260925_assistente_resultados_historico.sql`: ampliação da mesma RPC com resultados históricos autorizados para responder comparações de piora.
- `supabase/functions/admin-users/index.ts`: persistência das permissões do Assistente no fluxo administrativo.
- `backups/20260924_assistente_gestao_v1/`: cópia reversível do frontend e da Edge Function administrativa antes da alteração.
- `backups/20260925_assistente_conversacional/`: backup do frontend e da Edge Function anterior à evolução conversacional.

## Limites conhecidos da V1

A análise identifica padrões e concentrações, mas não diagnostica causalidade clínica, trabalhista ou operacional sem evidência adicional. O histórico de perguntas não é um repositório de respostas. A análise consolidada entre operações exige Super Administrador e uma permissão global explícita. O modelo generativo é opcional; a V1 não depende dele para funcionar.
