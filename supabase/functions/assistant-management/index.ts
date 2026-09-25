import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const APP_ORIGIN = "https://williansss06-cpu.github.io";
const corsHeaders = {
  "Access-Control-Allow-Origin": APP_ORIGIN,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
};

const MONTHS = ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"];

type Context = {
  permitido?: boolean;
  operacoes?: Array<{ id: number; codigo: string; nome: string }>;
  ano?: number;
  mes?: number;
  modulo?: string | null;
  filtros?: Record<string, unknown>;
  atualizado_em?: string;
  indicadores?: Array<Record<string, unknown>>;
  resultados?: Array<Record<string, unknown>>;
  resultados_historico?: Array<Record<string, unknown>>;
  sla?: Array<Record<string, unknown>>;
  absenteismo?: {
    permitido?: boolean;
    mensal?: Array<Record<string, unknown>>;
    motivos?: Array<Record<string, unknown>>;
    areas?: Array<Record<string, unknown>>;
    pessoas?: Array<Record<string, unknown>>;
    recorrentes?: Array<Record<string, unknown>>;
    recorrentes_mes?: Array<Record<string, unknown>>;
  };
  acoes?: Array<Record<string, unknown>>;
  acessos?: Record<string, boolean>;
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: corsHeaders });
}

function number(value: unknown) {
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

function brNumber(value: unknown, digits = 2) {
  return number(value).toLocaleString("pt-BR", { minimumFractionDigits: digits, maximumFractionDigits: digits });
}

function brDate(value: unknown) {
  if (!value) return "sem prazo";
  const d = new Date(String(value));
  return Number.isNaN(d.getTime()) ? String(value) : d.toLocaleDateString("pt-BR");
}

function operationLabel(context: Context) {
  return (context.operacoes ?? []).map((x) => x.nome || x.codigo).join(" + ") || "operação autorizada";
}

function contextHeader(context: Context) {
  return `Fonte: ${operationLabel(context)} | Período analisado: ${MONTHS[Math.max(0, number(context.mes) - 1)] ?? "mês"}/${context.ano ?? "ano"} | Dados atualizados: ${context.atualizado_em ? new Date(context.atualizado_em).toLocaleString("pt-BR") : "agora"}`;
}

function calculateIndicatorStatus(indicator: Record<string, unknown>, result: Record<string, unknown> | undefined) {
  if (!result || result.resultado === null || result.resultado === undefined) return "sem resultado";
  const actual = number(result.resultado);
  const target = number(indicator.meta);
  const lowerIsBetter = String(indicator.polaridade ?? "MAIOR").toUpperCase() === "MENOR";
  const good = lowerIsBetter ? actual <= target : actual >= target;
  return good ? "dentro da meta" : "abaixo da meta";
}

function summarizeIndicators(context: Context) {
  const results = context.resultados ?? [];
  return (context.indicadores ?? []).map((indicator) => {
    const result = results.find((x) => Number(x.indicador_id) === Number(indicator.id));
    return {
      name: String(indicator.nome ?? "Indicador"),
      result: result?.resultado === null || result?.resultado === undefined ? null : number(result.resultado),
      target: number(indicator.meta),
      weight: number(indicator.peso),
      format: String(indicator.formato ?? "PERCENT"),
      polarity: String(indicator.polaridade ?? "MAIOR"),
      status: calculateIndicatorStatus(indicator, result),
    };
  });
}

type Intent =
  | "executive_summary"
  | "absenteismo"
  | "absenteismo_contribuidores"
  | "absenteismo_recorrencia"
  | "absenteismo_tendencia"
  | "indicadores_abaixo_meta"
  | "indicador_queda"
  | "ofensores"
  | "acoes_atrasadas"
  | "sla_neolog"
  | "operacao"
  | "screen"
  | "unknown";

type ConversationTurn = { role: "user" | "assistant"; content: string; intent?: string };

type IntentResult = { intent: Intent; label: string; reason: string };

function normalizeText(value: unknown) {
  return String(value ?? "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .trim();
}

function lastConversationIntent(conversation: ConversationTurn[]) {
  return [...conversation].reverse().find((turn) => turn.role === "assistant" && turn.intent)?.intent as Intent | undefined;
}

function inferIntent(question: string, mode: string, conversation: ConversationTurn[] = []): IntentResult {
  if (mode === "monthly") return { intent: "executive_summary", label: "Análise Executiva do Mês", reason: "modo mensal solicitado" };
  if (mode === "screen") return { intent: "screen", label: "Análise da tela atual", reason: "análise contextual solicitada" };
  const q = normalizeText(question);
  const previous = lastConversationIntent(conversation);
  const followUp = /\b(esse|esta|isso|eles|essas pessoas|esse grupo|quanto eles|e quanto|por que isso|qual deles)\b/.test(q);
  const abs = /absenteismo|afastamento|faltas?|atestado|improdutiv|dias de afastamento/.test(q);
  if (/sla|neolog|pontuacao/.test(q)) return { intent: "sla_neolog", label: "SLA NEOLOG", reason: "termos de pontuação SLA/NEOLOG encontrados" };
  if (/acao|acoes|plano de acao|vencid|atrasad|prazo/.test(q)) return { intent: "acoes_atrasadas", label: "Planos de Ação", reason: "termos de ação, prazo ou atraso encontrados" };
  if (/abaixo da meta|fora da meta|indicadores? .*meta|metas? .*indicador/.test(q)) return { intent: "indicadores_abaixo_meta", label: "Indicadores abaixo da meta", reason: "pergunta sobre meta e desvio" };
  if (/piorou|piora|caiu|queda|deterior|compar(e|ar)|mes anterior|ultimos? (2|3|4|5|6|meses)|tendencia|evolucao/.test(q)) {
    if (abs || previous?.startsWith("absenteismo")) return { intent: "absenteismo_tendencia", label: "Tendência de Absenteísmo", reason: "comparação ou tendência no contexto de absenteísmo" };
    return { intent: "indicador_queda", label: "Quedas e pioras", reason: "pergunta sobre queda ou comparação" };
  }
  if (/quem mais|quem contribuiu|contribuiram|ofensor|principais ofensores|maior impacto|concentr/.test(q)) {
    if (abs || previous?.startsWith("absenteismo")) return { intent: "absenteismo_contribuidores", label: "Contribuidores do Absenteísmo", reason: "pergunta sobre concentração de horas improdutivas" };
    return { intent: "ofensores", label: "Principais ofensores", reason: "pergunta sobre impacto e concentração" };
  }
  if (/recorrent|representam do total|percentual do total|motivos? .*grupo|area .*concentr/.test(q)) {
    if (abs || previous?.startsWith("absenteismo")) return { intent: "absenteismo_recorrencia", label: "Recorrência do Absenteísmo", reason: "pergunta sobre recorrentes e concentração" };
  }
  if (abs) return { intent: "absenteismo", label: "Absenteísmo", reason: "termos de absenteísmo encontrados" };
  if (/operacao|ache|glp|matriz/.test(q)) return { intent: "operacao", label: "Operação", reason: "pergunta sobre a operação atual" };
  if (/atencao|prioriz|resumo|visao executiva|situacao geral/.test(q)) return { intent: "executive_summary", label: "Resumo Executivo", reason: "pergunta sobre prioridades e visão geral" };
  if (followUp && previous) return { intent: previous, label: previous, reason: "continuidade da intenção anterior" };
  return { intent: "unknown", label: "Consulta operacional", reason: "nenhum domínio específico identificado" };
}

function periodLabel(context: Context) {
  return `${MONTHS[Math.max(0, number(context.mes) - 1)] ?? "mês"}/${context.ano ?? "ano"}`;
}

function indicatorDeteriorations(context: Context) {
  const history = context.resultados_historico ?? [];
  const groups = new Map<number, Array<Record<string, unknown>>>();
  for (const row of history) {
    const id = Number(row.indicador_id);
    if (!Number.isFinite(id)) continue;
    const list = groups.get(id) ?? [];
    list.push(row);
    groups.set(id, list);
  }
  const output: Array<Record<string, unknown>> = [];
  for (const rows of groups.values()) {
    rows.sort((a, b) => Number(a.mes) - Number(b.mes));
    if (rows.length < 2) continue;
    const previous = rows.at(-2);
    const current = rows.at(-1);
    if (current?.resultado === null || current?.resultado === undefined || previous?.resultado === null || previous?.resultado === undefined) continue;
    const currentValue = number(current.resultado);
    const previousValue = number(previous.resultado);
    const lowerIsBetter = String(current.polaridade ?? 'MAIOR').toUpperCase() === 'MENOR';
    const worsened = lowerIsBetter ? currentValue > previousValue : currentValue < previousValue;
    if (worsened) output.push({
      indicador_id: current.indicador_id,
      indicador: current.indicador,
      mes_anterior: previous.mes,
      mes_atual: current.mes,
      anterior: previousValue,
      atual: currentValue,
      variacao: currentValue - previousValue,
      polaridade: current.polaridade,
    });
  }
  return output.sort((a, b) => Math.abs(number(b.variacao)) - Math.abs(number(a.variacao)));
}

function recurringRows(context: Context) {
  const abs = context.absenteismo ?? {};
  return Array.isArray(abs.recorrentes_mes) ? abs.recorrentes_mes : (abs.recorrentes ?? []);
}

function currentAbsRows(context: Context) {
  const abs = context.absenteismo ?? {};
  const month = number(context.mes);
  return {
    abs,
    current: (abs.mensal ?? []).find((x) => Number(x.mes) === month) ?? (abs.mensal ?? []).at(-1),
    previous: (abs.mensal ?? []).find((x) => Number(x.mes) === Math.max(1, month - 1)),
  };
}

function recordsUsedForIntent(context: Context, intent: Intent) {
  const abs = context.absenteismo ?? {};
  const counts: Record<string, number> = {};
  const add = (source: string, value: unknown) => { counts[source] = Array.isArray(value) ? value.length : 0; };
  if (["absenteismo", "absenteismo_contribuidores", "absenteismo_recorrencia", "absenteismo_tendencia", "ofensores"].includes(intent)) {
    add("absenteismo_registros.mensal", abs.mensal);
    add("absenteismo_registros.motivos", abs.motivos);
    add("absenteismo_registros.areas", abs.areas);
    add("absenteismo_registros.pessoas", abs.pessoas);
    add("absenteismo_registros.recorrentes", recurringRows(context));
  }
  if (["indicadores_abaixo_meta", "indicador_queda", "ofensores", "executive_summary", "screen", "unknown"].includes(intent)) {
    add("sustentacao_indicadores", context.indicadores);
    add("sustentacao_resultados", context.resultados);
    if (intent === "indicador_queda") add("sustentacao_resultados_historicos", context.resultados_historico);
  }
  if (["acoes_atrasadas", "executive_summary", "screen", "unknown"].includes(intent)) add("sustentacao_plano_acao", context.acoes);
  if (["sla_neolog", "executive_summary", "screen", "unknown"].includes(intent)) add("sustentacao_sla_neolog_pontuacoes", context.sla);
  if (intent === "operacao") add("sustentacao_operacoes", context.operacoes);
  return counts;
}

function sourcesForIntent(context: Context, intent: Intent) {
  return Object.keys(recordsUsedForIntent(context, intent));
}

function compactContext(context: Context, intent: Intent) {
  const base = { header: contextHeader(context), period: periodLabel(context), access: context.acessos ?? {}, operation: context.operacoes ?? [] };
  const abs = context.absenteismo ?? {};
  switch (intent) {
    case "absenteismo":
      return { ...base, absenteismo: { mensal: abs.mensal ?? [], motivos: (abs.motivos ?? []).slice(0, 10), areas: (abs.areas ?? []).slice(0, 10), pessoas: (abs.pessoas ?? []).slice(0, 10), recorrentes: recurringRows(context).slice(0, 10) } };
    case "absenteismo_contribuidores":
      return { ...base, absenteismo: { mensal: abs.mensal ?? [], pessoas: (abs.pessoas ?? []).slice(0, 10), recorrentes: recurringRows(context).slice(0, 20), areas: (abs.areas ?? []).slice(0, 10) } };
    case "absenteismo_recorrencia":
      return { ...base, absenteismo: { mensal: abs.mensal ?? [], recorrentes: recurringRows(context).slice(0, 20), areas: (abs.areas ?? []).slice(0, 10), motivos: (abs.motivos ?? []).slice(0, 10) } };
    case "absenteismo_tendencia":
      return { ...base, absenteismo: { mensal: abs.mensal ?? [], motivos: (abs.motivos ?? []).slice(0, 10), areas: (abs.areas ?? []).slice(0, 10) } };
    case "indicadores_abaixo_meta":
    case "indicador_queda":
      return { ...base, indicadores: summarizeIndicators(context), resultados: context.resultados ?? [], resultados_historico: (context.resultados_historico ?? []).slice(0, 100), acoes: context.acoes ?? [] };
    case "ofensores":
      return { ...base, indicadores: summarizeIndicators(context), absenteismo: { mensal: abs.mensal ?? [], pessoas: (abs.pessoas ?? []).slice(0, 10), areas: (abs.areas ?? []).slice(0, 10), motivos: (abs.motivos ?? []).slice(0, 10) }, acoes: context.acoes ?? [] };
    case "acoes_atrasadas":
      return { ...base, acoes: context.acoes ?? [], indicadores: summarizeIndicators(context) };
    case "sla_neolog":
      return { ...base, sla: (context.sla ?? []).slice(0, 100), indicadores: summarizeIndicators(context) };
    case "operacao":
      return { ...base };
    case "executive_summary":
    case "screen":
    case "unknown":
    default:
      return { ...base, indicadores: summarizeIndicators(context), absenteismo: { mensal: abs.mensal ?? [], motivos: (abs.motivos ?? []).slice(0, 10), areas: (abs.areas ?? []).slice(0, 10), pessoas: (abs.pessoas ?? []).slice(0, 10), recorrentes: recurringRows(context).slice(0, 10) }, sla: (context.sla ?? []).slice(0, 100), acoes: (context.acoes ?? []).slice(0, 100) };
  }
}

function suggestionsForIntent(intent: Intent, context: Context, answer: string) {
  const suggestions: string[] = [];
  const abs = context.absenteismo ?? {};
  const access = context.acessos ?? {};
  const push = (value: string, condition = true) => { if (condition && !suggestions.includes(value)) suggestions.push(value); };
  if (["absenteismo", "absenteismo_tendencia", "absenteismo_contribuidores", "absenteismo_recorrencia"].includes(intent)) {
    push("Quem mais contribuiu para esse resultado?", (abs.pessoas ?? []).length > 0);
    push("Quanto os recorrentes representam do total?", recurringRows(context).length > 0);
    push("Qual área teve a maior concentração?", (abs.areas ?? []).length > 0);
    push("Compare com os últimos 3 meses", (abs.mensal ?? []).length >= 3);
    push("Quais ações devemos acompanhar?", access.plano_acao === true && (context.acoes ?? []).length > 0);
  }
  if (intent === "absenteismo_contribuidores") {
    push("Esses colaboradores são recorrentes?", recurringRows(context).length > 0);
    push("Qual percentual do total eles representam?", (abs.pessoas ?? []).length > 0);
    push("Existe concentração em alguma área?", (abs.areas ?? []).length > 0);
    push("Compare a concentração com o mês anterior", (abs.mensal ?? []).length >= 2);
  }
  if (intent === "absenteismo_recorrencia") {
    push("Quem são os recorrentes com mais horas?", recurringRows(context).length > 0);
    push("Qual área concentra mais recorrentes?", (abs.areas ?? []).length > 0);
    push("Quais motivos mais aparecem no período?", (abs.motivos ?? []).length > 0);
  }
  if (["indicadores_abaixo_meta", "indicador_queda"].includes(intent)) {
    const below = summarizeIndicators(context).filter((x) => x.status === "abaixo da meta");
    push("Por que este indicador caiu?", below.length > 0);
    push("Há plano de ação relacionado?", below.length > 0 && access.plano_acao === true);
    push("Esse problema é recorrente?", below.length > 0);
    push("Quais indicadores ainda estão dentro da meta?", summarizeIndicators(context).length > 0);
  }
  if (intent === "acoes_atrasadas") {
    const overdue = (context.acoes ?? []).filter((x) => x.data_fim && new Date(String(x.data_fim)).getTime() < Date.now());
    push("Quais responsáveis concentram mais ações atrasadas?", overdue.length > 0);
    push("Quais ações têm indicador relacionado?", overdue.some((x) => x.indicador_id != null));
    push("Qual ação deve ser priorizada primeiro?", overdue.length > 0);
  }
  if (intent === "sla_neolog") {
    push("Como a pontuação evoluiu nos meses disponíveis?", (context.sla ?? []).length > 1);
    push("Qual indicador mais contribuiu para a pontuação?", (context.sla ?? []).length > 0);
    push("Há risco concentrado em algum indicador?", (context.sla ?? []).length > 0);
  }
  if (intent === "executive_summary" || intent === "screen" || intent === "unknown") {
    const below = summarizeIndicators(context).filter((x) => x.status === "abaixo da meta");
    push("Quais indicadores estão abaixo da meta?", below.length > 0);
    push("Analise o absenteísmo.", access.absenteismo === true && (abs.mensal ?? []).length > 0);
    push("Quais ações estão atrasadas?", access.plano_acao === true && (context.acoes ?? []).length > 0);
    push("Qual o risco atual da pontuação Neolog?", access.sla_neolog === true && (context.sla ?? []).length > 0);
  }
  return suggestions.slice(0, 5);
}

function answerForIntent(question: string, context: Context, intent: Intent) {
  const period = periodLabel(context);
  const abs = context.absenteismo ?? {};
  const { current, previous } = currentAbsRows(context);
  const indicators = summarizeIndicators(context);
  const below = indicators.filter((x) => x.status === "abaixo da meta");
  const openActions = context.acoes ?? [];
  const overdueActions = openActions.filter((x) => x.data_fim && new Date(String(x.data_fim)).getTime() < Date.now());
  const topPeople = (abs.pessoas ?? []).slice(0, 5);
  const topAreas = (abs.areas ?? []).slice(0, 5);
  const topReasons = (abs.motivos ?? []).slice(0, 5);
  const currentHours = number(current?.horas_improdutivas);
  const totalPeopleHours = (abs.pessoas ?? []).reduce((sum, x) => sum + number(x.horas), 0);
  const recurringHours = recurringRows(context).reduce((sum, x) => sum + number(x.horas), 0);
  const recurringPct = totalPeopleHours > 0 ? (recurringHours / totalPeopleHours) * 100 : 0;
  const source = contextHeader(context);
  const noData = (label: string) => `Não há dados suficientes para responder sobre ${label} no contexto autorizado. ${source}`;
  const questionLine = `\n\nPergunta analisada: ${question}`;

  switch (intent) {
    case "absenteismo": {
      if (!current) return noData("Absenteísmo");
      const variation = previous ? number(current.indice_absenteismo) - number(previous.indice_absenteismo) : null;
      return `## Absenteísmo\n${source}\n\nNo período de ${period}, foram registradas ${brNumber(currentHours)} horas improdutivas sobre ${brNumber(current.horas_disponiveis)} horas disponíveis, com índice de ${brNumber(current.indice_absenteismo)}%. ${variation === null ? "Não há mês anterior disponível para comparação." : `A variação contra o mês anterior foi de ${variation >= 0 ? "+" : ""}${brNumber(variation)} ponto(s) percentual(is).`}\n\n${topReasons.length ? `Principais motivos: ${topReasons.map((x) => `${x.motivo} (${brNumber(x.horas)} h)`).join(", ")}.` : "Não há ranking de motivos disponível."} ${topAreas.length ? `Maior concentração por área/centro: ${topAreas[0].area ?? "não informado"} (${brNumber(topAreas[0].horas)} h).` : ""}` + questionLine;
    }
    case "absenteismo_contribuidores": {
      if (!topPeople.length) return noData("os colaboradores que mais contribuíram");
      return `## Quem mais contribuiu\n${source}\n\nOs maiores volumes de horas improdutivas no período são: ${topPeople.map((x, index) => `${index + 1}. ${x.colaborador ?? "Não informado"} — ${brNumber(x.horas)} h`).join("; ")}.\n\nOs colaboradores listados concentram ${brNumber(totalPeopleHours)} h do ranking retornado; os recorrentes representam aproximadamente ${brNumber(recurringPct)}% desse total. Essa é uma concentração observada nos dados e não prova de causalidade.` + questionLine;
    }
    case "absenteismo_recorrencia": {
      const recurring = recurringRows(context);
      if (!recurring.length) return noData("recorrência");
      return `## Recorrência\n${source}\n\nForam identificados ${recurring.length} colaboradores recorrentes no contexto retornado. Os maiores volumes entre eles são: ${recurring.slice(0, 8).map((x) => `${x.colaborador ?? "Não informado"} (${brNumber(x.horas)} h em ${x.meses ?? "vários"} mês(es))`).join(", ")}.\n\nA soma das horas dos recorrentes é ${brNumber(recurringHours)} h, equivalente a aproximadamente ${brNumber(recurringPct)}% das horas do ranking de pessoas disponível. Não há dados suficientes neste contexto para atribuir causa individual.` + questionLine;
    }
    case "absenteismo_tendencia": {
      const months = (abs.mensal ?? []).slice().sort((a, b) => Number(a.mes) - Number(b.mes));
      if (months.length < 2) return noData("a tendência de Absenteísmo");
      const recent = months.slice(-Math.min(3, months.length));
      const trend = recent.map((x) => `${MONTHS[Math.max(0, Number(x.mes) - 1)]}: ${brNumber(x.indice_absenteismo)}%`).join("; ");
      return `## Tendência de Absenteísmo\n${source}\n\nEvolução disponível: ${trend}. ${number(recent.at(-1)?.indice_absenteismo) > number(recent[0]?.indice_absenteismo) ? "O índice aumentou no recorte apresentado." : number(recent.at(-1)?.indice_absenteismo) < number(recent[0]?.indice_absenteismo) ? "O índice reduziu no recorte apresentado." : "O índice permaneceu estável no recorte apresentado."} A comparação está limitada aos meses efetivamente retornados pelo Supabase.` + questionLine;
    }
    case "indicadores_abaixo_meta":
      return `## Indicadores abaixo da meta\n${source}\n\n${below.length ? `Foram encontrados ${below.length} indicador(es) abaixo da meta: ${below.map((x) => `${x.name} (${x.result === null ? "sem resultado" : brNumber(x.result)} contra ${brNumber(x.target)})`).join(", ")}.` : "Não foram encontrados indicadores abaixo da meta entre os resultados disponíveis."}` + questionLine;
    case "indicador_queda": {
      const rows = indicatorDeteriorations(context);
      const belowRows = indicators.filter((x) => x.status === "abaixo da meta");
      if (!rows.length) return `## Quedas e pioras\n${source}\n\nNão foram encontrados indicadores que pioraram quando comparados ao mês anterior disponível. ${belowRows.length ? `Ainda assim, estão abaixo da meta: ${belowRows.map((x) => x.name).join(", ")}.` : "Não há desvio de meta no recorte atual."}` + questionLine;
      return `## Quedas e pioras\n${source}\n\nOs indicadores que pioraram na comparação histórica são: ${rows.slice(0, 8).map((x) => `${x.indicador} (${brNumber(x.anterior)} → ${brNumber(x.atual)}; variação ${number(x.variacao) >= 0 ? "+" : ""}${brNumber(x.variacao)})`).join("; ")}. A comparação usa os dois últimos resultados disponíveis por indicador e não determina a causa da piora.` + questionLine;
    }
    case "ofensores":
      return topPeople.length ? `## Principais ofensores\n${source}\n\nOs maiores impactos identificados são: ${topPeople.map((x) => `${x.colaborador ?? "Não informado"} (${brNumber(x.horas)} h)`).join(", ")}. A área de maior concentração retornada é ${topAreas[0]?.area ?? "não informada"}. Os dados mostram concentração, mas não determinam causalidade.` + questionLine : noData("principais ofensores");
    case "acoes_atrasadas":
      return `## Planos de Ação\n${source}\n\nHá ${openActions.length} ação(ões) aberta(s) no escopo consultado e ${overdueActions.length} com prazo vencido. ${overdueActions.length ? `Ações vencidas: ${overdueActions.slice(0, 8).map((x) => `${x.acao ?? "ação sem descrição"} (responsável: ${x.responsavel ?? "não informado"}; prazo: ${brDate(x.data_fim)})`).join("; ")}.` : "Não há ações vencidas no contexto disponível."}` + questionLine;
    case "sla_neolog": {
      if (!(context.sla ?? []).length) return noData("SLA NEOLOG");
      const points = (context.sla ?? []).filter((x) => String(x.tipo ?? "PONTOS") === "PONTOS").reduce((sum, x) => sum + number(x.valor), 0);
      return `## SLA NEOLOG\n${source}\n\nHá ${context.sla?.length ?? 0} lançamento(s) de pontuação no ano selecionado, totalizando ${brNumber(points)} pontos nos registros disponíveis. A leitura não cria uma classificação contratual que não esteja cadastrada no sistema.` + questionLine;
    }
    case "operacao":
      return `## Operação autorizada\n${source}\n\nO contexto atual está vinculado a: ${operationLabel(context)}. A resposta respeita somente o escopo e as permissões do usuário autenticado.` + questionLine;
    case "executive_summary":
    case "screen":
    case "unknown":
    default: {
      const score = indicators.length ? `${indicators.filter((x) => x.status === "dentro da meta").length} de ${indicators.length} indicador(es) dentro da meta` : "não há indicadores com resultado";
      return `## Resumo direto\n${source}\n\n${score}. ${below.length ? `Pontos de atenção: ${below.slice(0, 5).map((x) => x.name).join(", ")}.` : "Não foram encontrados desvios de meta nos indicadores disponíveis."} ${current ? `O Absenteísmo do período está em ${brNumber(current.indice_absenteismo)}%.` : "Não há registro de Absenteísmo no período."} ${openActions.length ? `Existem ${openActions.length} ação(ões) aberta(s), sendo ${overdueActions.length} vencida(s).` : "Não há ações abertas retornadas."}` + questionLine;
    }
  }
}

async function modelAnalysis(question: string, context: Context, intent: Intent, conversation: ConversationTurn[]) {
  const apiKey = Deno.env.get("OPENAI_API_KEY") ?? Deno.env.get("ASSISTENTE_MODEL_API_KEY");
  const baseUrl = (Deno.env.get("OPENAI_API_BASE") ?? "https://api.openai.com/v1").replace(/\/$/, "");
  const model = Deno.env.get("ASSISTENTE_MODEL") ?? "gpt-4o-mini";
  if (!apiKey) return null;
  const system = `Você é o Assistente de Gestão do Plano de Sustentação Mundial Logistics. Responda diretamente à pergunta atual, sem gerar um relatório genérico. Use somente o JSON autorizado fornecido. Não invente dados, causas, metas ou pontuação. Se a informação não existir, diga que não há dados suficientes. Responda em português do Brasil, em texto curto e objetivo, podendo usar títulos simples. Intenção identificada: ${intent}. A conversa anterior é contexto, não fonte de fatos.`;
  const response = await fetch(`${baseUrl}/chat/completions`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${apiKey}` },
    body: JSON.stringify({
      model,
      temperature: 0.1,
      max_tokens: 900,
      messages: [
        { role: "system", content: system },
        { role: "user", content: JSON.stringify({ pergunta_atual: question, intencao: intent, conversa: conversation.slice(-8), contexto_autorizado: compactContext(context, intent) }) },
      ],
    }),
  });
  if (!response.ok) throw new Error(`Modelo indisponível (${response.status})`);
  const payload = await response.json();
  const text = payload?.choices?.[0]?.message?.content?.trim();
  return text || null;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Método não permitido" }, 405);
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const authorization = req.headers.get("Authorization");
  if (!supabaseUrl || !anonKey || !authorization) return json({ error: "Sessão inválida" }, 401);

  const userClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authorization } } });
  const token = authorization.replace(/^Bearer\s+/i, "").trim();
  const verified = await userClient.auth.getUser(token);
  if (verified.error || !verified.data.user) return json({ error: "Sessão inválida" }, 401);

  let body: {
    question?: string;
    mode?: string;
    operation_id?: number | null;
    year?: number;
    month?: number | null;
    module?: string | null;
    filters?: Record<string, unknown>;
    conversation?: ConversationTurn[];
  };
  try { body = await req.json(); } catch { return json({ error: "JSON inválido" }, 400); }
  const question = String(body.question ?? "").trim();
  const mode = ["ask", "screen", "monthly"].includes(String(body.mode)) ? String(body.mode) : "ask";
  if (question.length > 2000) return json({ error: "Pergunta muito longa" }, 400);
  const operationId = body.operation_id === null || body.operation_id === undefined ? null : Number(body.operation_id);
  const year = Number(body.year) || new Date().getFullYear();
  const month = body.month === null || body.month === undefined ? null : Number(body.month);
  const conversation = Array.isArray(body.conversation) ? body.conversation.filter((turn) => (turn?.role === "user" || turn?.role === "assistant") && String(turn.content ?? "").length <= 2000).slice(-10) : [];
  const historyQuestion = question || (mode === "monthly" ? "Gerar Análise Executiva do Mês" : "Analisar esta tela");
  const intentResult = inferIntent(historyQuestion, mode, conversation);

  const contextQuery = await userClient.rpc("assistente_obter_conversa_contexto", {
    p_operacao_id: operationId,
    p_ano: year,
    p_mes: month,
    p_modulo: body.module ?? null,
    p_filtros: body.filters ?? {},
  });
  if (contextQuery.error) return json({ error: "Não foi possível consultar o contexto autorizado.", code: contextQuery.error.code ?? "ASSISTANT_CONTEXT_ERROR" }, 403);
  const context = contextQuery.data as Context;
  if (!context?.permitido) return json({ error: "Você não possui permissão para consultar este contexto." }, 403);

  const history = await userClient.rpc("assistente_registrar_pergunta", {
    p_operacao_id: operationId ?? Number(context.operacoes?.[0]?.id),
    p_modulo: body.module ?? context.modulo ?? "",
    p_ano: context.ano ?? year,
    p_mes: context.mes ?? month,
    p_pergunta: historyQuestion,
    p_modo: mode,
  });
  if (history.error) console.warn("assistant history unavailable", history.error.message);

  const recordsUsed = recordsUsedForIntent(context, intentResult.intent);
  const sources = sourcesForIntent(context, intentResult.intent);
  const deterministic = answerForIntent(historyQuestion, context, intentResult.intent);
  let answer = deterministic;
  let engine = "analise_deterministica";
  try {
    const modelAnswer = await modelAnalysis(historyQuestion, context, intentResult.intent, conversation);
    if (modelAnswer) { answer = modelAnswer; engine = "modelo_backend"; }
  } catch (error) {
    console.warn("assistant model fallback", error instanceof Error ? error.message : error);
  }
  const suggestions = suggestionsForIntent(intentResult.intent, context, answer);
  const trace = { question: historyQuestion, intent: intentResult.intent, intent_label: intentResult.label, sources, records_used: recordsUsed, response: answer.slice(0, 1500) };
  console.info("[Assistente] pergunta → intenção → fontes → registros → resposta", trace);
  return json({
    ok: true,
    answer,
    engine,
    intent: intentResult.intent,
    intent_label: intentResult.label,
    intent_reason: intentResult.reason,
    suggestions,
    sources,
    records_used: recordsUsed,
    context: { header: contextHeader(context), operacoes: context.operacoes ?? [], ano: context.ano, mes: context.mes, modulo: context.modulo, acessos: context.acessos ?? {} },
    evidence: compactContext(context, intentResult.intent),
    generated_at: new Date().toISOString(),
  });
});
