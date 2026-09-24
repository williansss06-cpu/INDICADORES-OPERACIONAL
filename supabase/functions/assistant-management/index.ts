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
  sla?: Array<Record<string, unknown>>;
  absenteismo?: {
    permitido?: boolean;
    mensal?: Array<Record<string, unknown>>;
    motivos?: Array<Record<string, unknown>>;
    areas?: Array<Record<string, unknown>>;
    pessoas?: Array<Record<string, unknown>>;
    recorrentes?: Array<Record<string, unknown>>;
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

function deterministicAnalysis(question: string, context: Context, mode: string) {
  const period = `${MONTHS[Math.max(0, number(context.mes) - 1)] ?? "mês"}/${context.ano ?? "ano"}`;
  const abs = context.absenteismo ?? {};
  const monthly = (abs.mensal ?? []).find((x) => Number(x.mes) === Number(context.mes)) ?? (abs.mensal ?? []).at(-1);
  const previous = (abs.mensal ?? []).find((x) => Number(x.mes) === Math.max(1, number(context.mes) - 1));
  const indicators = summarizeIndicators(context);
  const below = indicators.filter((x) => x.status === "abaixo da meta");
  const topPeople = (abs.pessoas ?? []).slice(0, 10);
  const topReasons = (abs.motivos ?? []).slice(0, 3);
  const topAreas = (abs.areas ?? []).slice(0, 3);
  const recurring = abs.recorrentes ?? [];
  const totalHours = number(monthly?.horas_improdutivas);
  const recurringHours = recurring.reduce((sum, x) => sum + number(x.horas), 0);
  const previousAbs = number(previous?.indice_absenteismo);
  const currentAbs = number(monthly?.indice_absenteismo);
  const openActions = context.acoes ?? [];
  const now = Date.now();
  const overdueActions = openActions.filter((x) => x.data_fim && new Date(String(x.data_fim)).getTime() < now);
  const slaPoints = (context.sla ?? []).filter((x) => String(x.tipo ?? "PONTOS") === "PONTOS").reduce((sum, x) => sum + number(x.valor), 0);
  const damages = (context.sla ?? []).filter((x) => String(x.tipo ?? "") === "MOEDA").reduce((sum, x) => sum + number(x.valor), 0);

  const lines: string[] = [];
  lines.push(`## Resumo executivo\n${contextHeader(context)}\n\nA leitura solicitada para ${period} considera exclusivamente os dados liberados para o usuário e o contexto atual da tela.`);
  if (indicators.length) {
    lines.push(`\n## Evidências\n${indicators.length} indicador(es) no contexto; ${below.length} abaixo da meta. ${below.length ? `Os pontos fora da meta são: ${below.slice(0, 6).map((x) => `${x.name} (${x.result === null ? "sem resultado" : brNumber(x.result)} contra ${brNumber(x.target)})`).join(", ")}.` : "Os indicadores com resultado disponível estão dentro das metas cadastradas."}`);
  }
  if (monthly) {
    const variation = previous ? currentAbs - previousAbs : null;
    lines.push(`\n## Absenteísmo\n${brNumber(totalHours)} h improdutivas sobre ${brNumber(monthly.horas_disponiveis)} h disponíveis, índice de ${brNumber(currentAbs)}%. ${variation === null ? "Não há mês anterior comparável no contexto." : `A variação contra o período anterior foi de ${variation >= 0 ? "+" : ""}${brNumber(variation)} ponto(s) percentual(is).`}`);
  } else if (context.acessos?.absenteismo) {
    lines.push("\n## Absenteísmo\nNão há registros de Absenteísmo no período selecionado para a operação autorizada.");
  }
  if (topPeople.length || topReasons.length || topAreas.length) {
    const concentration = totalHours > 0 ? (recurringHours / totalHours) * 100 : 0;
    lines.push(`\n## Principais ofensores\n${topPeople.length ? `Colaboradores com maior concentração de horas: ${topPeople.slice(0, 5).map((x) => `${x.colaborador} (${brNumber(x.horas)} h)`).join(", ")}.` : "Não há ranking de colaboradores disponível."} ${topAreas.length ? `Área/centro de custo de maior impacto no contexto: ${String(topAreas[0].area ?? "não informado")} (${brNumber(topAreas[0].horas)} h).` : ""} ${topReasons.length ? `Motivos mais representativos: ${topReasons.map((x) => `${x.motivo} (${brNumber(x.horas)} h)`).join(", ")}.` : ""} ${recurring.length ? `Os recorrentes representam aproximadamente ${brNumber(concentration)}% das horas listadas no período; isso é concentração, não prova de causalidade.` : ""}`);
  }
  if (context.sla?.length) {
    lines.push(`\n## SLA / Pontuação Neolog\nHá ${context.sla.length} lançamento(s) disponíveis no contexto, totalizando ${brNumber(slaPoints)} pontos registrados${damages ? ` e ${brNumber(damages)} em valores monetários` : ""}. A pontuação acumulada deve ser interpretada junto dos indicadores e das regras de pontuação cadastradas; este relatório não cria uma classificação contratual que não esteja configurada.`);
  }
  lines.push(`\n## Tendência\n${previous ? (currentAbs > previousAbs ? "O absenteísmo aumentou" : currentAbs < previousAbs ? "O absenteísmo reduziu" : "O absenteísmo permaneceu estável") + " em relação ao período anterior disponível." : "A comparação com período anterior não está disponível no recorte atual."} ${below.length ? "Os desvios de indicadores merecem priorização." : "Não foram identificados desvios de meta nos resultados disponíveis."}`);
  lines.push(`\n## Plano de ação\nExistem ${openActions.length} ação(ões) aberta(s) no escopo consultado; ${overdueActions.length} está(ão) com prazo vencido. ${openActions.length ? `A primeira verificação deve considerar: ${openActions.slice(0, 3).map((x) => `${x.acao} (${x.status || "sem status"}; prazo ${brDate(x.data_fim)})`).join("; ")}.` : "Não há ação aberta retornada para este contexto."}`);
  lines.push(`\n## Pontos para decisão\n1. Priorizar ${below[0]?.name ?? topAreas[0]?.area ?? "o principal desvio identificado"}.\n2. Validar com a gestão a concentração observada nos ofensores e motivos; os dados identificam concentração, mas não são suficientes para determinar a causa.\n3. ${overdueActions.length ? "Revisar responsáveis e prazos das ações vencidas." : "Confirmar o próximo ciclo de acompanhamento e manter o histórico atualizado."}`);
  if (mode === "screen") lines.push("\n## Contexto da tela\nA análise foi gerada automaticamente a partir da operação, módulo, ano, mês e filtros ativos informados pela aplicação.");
  if (question) lines.push(`\n**Pergunta analisada:** ${question}`);
  return lines.join("\n");
}

function compactContext(context: Context) {
  return {
    header: contextHeader(context),
    indicators: summarizeIndicators(context),
    absenteismo: {
      mensal: context.absenteismo?.mensal ?? [],
      motivos: (context.absenteismo?.motivos ?? []).slice(0, 10),
      areas: (context.absenteismo?.areas ?? []).slice(0, 10),
      pessoas: (context.absenteismo?.pessoas ?? []).slice(0, 10),
      recorrentes: (context.absenteismo?.recorrentes ?? []).slice(0, 10),
    },
    sla: (context.sla ?? []).slice(0, 100),
    acoes: (context.acoes ?? []).slice(0, 100),
    access: context.acessos ?? {},
  };
}

async function modelAnalysis(question: string, context: Context, mode: string) {
  const apiKey = Deno.env.get("OPENAI_API_KEY") ?? Deno.env.get("ASSISTENTE_MODEL_API_KEY");
  const baseUrl = (Deno.env.get("OPENAI_API_BASE") ?? "https://api.openai.com/v1").replace(/\/$/, "");
  const model = Deno.env.get("ASSISTENTE_MODEL") ?? "gpt-4o-mini";
  if (!apiKey) return null;
  const system = `Você é o Assistente de Gestão do Plano de Sustentação Mundial Logistics. Analise somente o JSON fornecido. Não invente causas, metas, pontuação contratual ou dados que não estejam no contexto. Se houver concentração sem causalidade, diga explicitamente que os dados não determinam a causa. Responda em português do Brasil, com as seções: Resumo executivo, Evidências, Principais ofensores, Tendência, Plano de ação e Pontos para decisão. Sempre preserve a linha de fonte/período/atualização. Não proponha alterações automáticas no banco. Modo: ${mode}.`;
  const response = await fetch(`${baseUrl}/chat/completions`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${apiKey}` },
    body: JSON.stringify({
      model,
      temperature: 0.1,
      max_tokens: 1400,
      messages: [
        { role: "system", content: system },
        { role: "user", content: JSON.stringify({ pergunta: question, contexto: compactContext(context) }) },
      ],
    }),
  });
  if (!response.ok) throw new Error(`Modelo indisponível (${response.status})`);
  const payload = await response.json();
  return payload?.choices?.[0]?.message?.content?.trim() || null;
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

  let body: { question?: string; mode?: string; operation_id?: number | null; year?: number; month?: number | null; module?: string | null; filters?: Record<string, unknown> };
  try { body = await req.json(); } catch { return json({ error: "JSON inválido" }, 400); }
  const question = String(body.question ?? "").trim();
  const mode = ["ask", "screen", "monthly"].includes(String(body.mode)) ? String(body.mode) : "ask";
  if (question.length > 2000) return json({ error: "Pergunta muito longa" }, 400);
  const operationId = body.operation_id === null || body.operation_id === undefined ? null : Number(body.operation_id);
  const year = Number(body.year) || new Date().getFullYear();
  const month = body.month === null || body.month === undefined ? null : Number(body.month);

  const contextQuery = await userClient.rpc("assistente_obter_contexto_v2", {
    p_operacao_id: operationId,
    p_ano: year,
    p_mes: month,
    p_modulo: body.module ?? null,
    p_filtros: body.filters ?? {},
  });
  if (contextQuery.error) return json({ error: "Não foi possível consultar o contexto autorizado.", code: contextQuery.error.code ?? "ASSISTANT_CONTEXT_ERROR" }, 403);
  const context = contextQuery.data as Context;
  if (!context?.permitido) return json({ error: "Você não possui permissão para consultar este contexto." }, 403);

  const historyQuestion = question || (mode === "monthly" ? "Gerar Análise Executiva do Mês" : "Analisar esta tela");
  const history = await userClient.rpc("assistente_registrar_pergunta", {
    p_operacao_id: operationId ?? Number(context.operacoes?.[0]?.id),
    p_modulo: body.module ?? context.modulo ?? "",
    p_ano: context.ano ?? year,
    p_mes: context.mes ?? month,
    p_pergunta: historyQuestion,
    p_modo: mode,
  });
  if (history.error) console.warn("assistant history unavailable", history.error.message);

  let answer: string | null = null;
  let engine = "analise_deterministica";
  try {
    answer = await modelAnalysis(historyQuestion, context, mode);
    if (answer) engine = "modelo_backend";
  } catch (error) {
    console.warn("assistant model fallback", error instanceof Error ? error.message : error);
  }
  if (!answer) answer = deterministicAnalysis(historyQuestion, context, mode);

  return json({ ok: true, answer, engine, context: { header: contextHeader(context), operacoes: context.operacoes ?? [], ano: context.ano, mes: context.mes, modulo: context.modulo, acessos: context.acessos ?? {} }, evidence: compactContext(context), generated_at: new Date().toISOString() });
});
