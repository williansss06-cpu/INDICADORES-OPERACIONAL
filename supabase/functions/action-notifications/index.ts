import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const APP_URL = "https://williansss06-cpu.github.io/INDICADORES-OPERACIONAL/";
const BUCKET = "plano-acao-evidencias";
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, x-client-info, content-type, x-action-worker-key",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type AnyRecord = Record<string, unknown>;

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function env(name: string) {
  return Deno.env.get(name)?.trim() || "";
}

function randomToken() {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (value) => value.toString(16).padStart(2, "0")).join("");
}

function bytesToBase64(bytes: Uint8Array) {
  let text = "";
  for (const byte of bytes) text += String.fromCharCode(byte);
  return btoa(text);
}

function base64ToBytes(value: string) {
  const text = atob(value);
  return Uint8Array.from(text, (char) => char.charCodeAt(0));
}

async function sha256(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function deriveKey(workerKey: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(workerKey));
  return crypto.subtle.importKey("raw", digest, { name: "AES-GCM" }, false, ["encrypt", "decrypt"]);
}

async function encryptToken(token: string, workerKey: string) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const key = await deriveKey(workerKey);
  const encrypted = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, new TextEncoder().encode(token));
  return `${bytesToBase64(iv)}.${bytesToBase64(new Uint8Array(encrypted))}`;
}

async function decryptToken(value: string, workerKey: string) {
  const [ivText, cipherText] = String(value || "").split(".");
  if (!ivText || !cipherText) throw new Error("Token protegido inválido");
  const key = await deriveKey(workerKey);
  const plain = await crypto.subtle.decrypt({ name: "AES-GCM", iv: base64ToBytes(ivText) }, key, base64ToBytes(cipherText));
  return new TextDecoder().decode(plain);
}

async function readBody(req: Request): Promise<AnyRecord> {
  try {
    const value = await req.json();
    return value && typeof value === "object" ? value as AnyRecord : {};
  } catch {
    return {};
  }
}

function safeFileName(value: string) {
  return String(value || "evidencia").replace(/[^a-zA-Z0-9._-]+/g, "-").slice(0, 100) || "evidencia";
}

function isFinished(action: AnyRecord) {
  return action.concluido === true || String(action.status || "").toLowerCase().includes("conclu");
}

function daysFromDeadline(dateValue: unknown) {
  if (!dateValue) return null;
  const deadline = new Date(`${String(dateValue)}T00:00:00-03:00`);
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  return Math.floor((today.getTime() - deadline.getTime()) / 86400000);
}

async function getWorkerKey(adminClient: ReturnType<typeof createClient>) {
  const { data, error } = await adminClient.from("sustentacao_acao_worker_secrets").select("worker_key").eq("id", 1).maybeSingle();
  if (error || !data?.worker_key) throw new Error("Chave interna do worker não configurada");
  return String(data.worker_key);
}

async function isWorkerRequest(req: Request, adminClient: ReturnType<typeof createClient>) {
  const supplied = req.headers.get("x-action-worker-key") || "";
  if (!supplied) return false;
  const expected = await getWorkerKey(adminClient);
  return supplied === expected;
}

async function getAction(adminClient: ReturnType<typeof createClient>, actionId: number) {
  const { data: action, error } = await adminClient.from("sustentacao_plano_acao").select("*").eq("id", actionId).maybeSingle();
  if (error) throw error;
  if (!action) throw new Error("Ação não encontrada");
  const [{ data: operation }, { data: indicator }, { data: creator }] = await Promise.all([
    adminClient.from("sustentacao_operacoes").select("id,codigo,nome").eq("id", action.operacao_id).maybeSingle(),
    action.indicador_id ? adminClient.from("sustentacao_indicadores").select("id,nome").eq("id", action.indicador_id).maybeSingle() : Promise.resolve({ data: null }),
    action.criado_por_user_id ? adminClient.from("sustentacao_usuarios").select("user_id,nome,email").eq("user_id", action.criado_por_user_id).maybeSingle() : Promise.resolve({ data: null }),
  ]);
  return { action, operation, indicator, creator };
}

async function ensurePortalToken(adminClient: ReturnType<typeof createClient>, action: AnyRecord, workerKey: string, issuedByUserId?: string | null) {
  const { data: active } = await adminClient.from("sustentacao_acao_portal_tokens").select("id,token_ciphertext,expires_at,revoked_at").eq("action_id", action.id).is("revoked_at", null).order("created_at", { ascending: false }).limit(1).maybeSingle();
  if (active && (!active.expires_at || new Date(active.expires_at).getTime() > Date.now())) {
    const token = await decryptToken(String(active.token_ciphertext), workerKey);
    return { id: active.id, token, link: `${APP_URL}?action-token=${encodeURIComponent(token)}` };
  }
  const token = randomToken();
  const tokenHash = await sha256(token);
  const tokenCiphertext = await encryptToken(token, workerKey);
  await adminClient.from("sustentacao_acao_portal_tokens").update({ revoked_at: new Date().toISOString(), updated_at: new Date().toISOString() }).eq("action_id", action.id).is("revoked_at", null);
  const { data, error } = await adminClient.from("sustentacao_acao_portal_tokens").insert({ action_id: action.id, token_hash: tokenHash, token_ciphertext: tokenCiphertext, issued_by_user_id: issuedByUserId || null, expires_at: action.concluido ? new Date(Date.now() + 30 * 86400000).toISOString() : null }).select("id").single();
  if (error) throw error;
  return { id: data.id, token, link: `${APP_URL}?action-token=${encodeURIComponent(token)}` };
}

function emailLayout(title: string, body: string, actionLink: string, buttonLabel: string) {
  return `<!doctype html><html lang="pt-BR"><body style="margin:0;background:#eef3f7;font-family:Arial,sans-serif;color:#173957"><div style="max-width:640px;margin:24px auto;background:#fff;border-radius:12px;overflow:hidden;border:1px solid #d7e0e8"><div style="background:#092b4d;color:#fff;padding:22px 26px;border-bottom:4px solid #ff5a00"><div style="font-size:13px;letter-spacing:.08em;font-weight:800">MUNDIAL LOGISTICS</div><div style="font-size:24px;font-weight:900;margin-top:7px">PLANO DE AÇÃO</div></div><div style="padding:26px">${body}<p style="margin:25px 0"><a href="${actionLink}" style="display:inline-block;background:#ff5a00;color:#fff;text-decoration:none;padding:12px 18px;border-radius:7px;font-weight:800">${buttonLabel}</a></p><p style="font-size:11px;color:#718598">Se o botão não abrir diretamente, acesse a aplicação pelo mesmo endereço e conclua o login.</p></div></div></body></html>`;
}

function actionBody(details: AnyRecord, heading: string, external: boolean) {
  const action = details.action as AnyRecord;
  const operation = details.operation as AnyRecord | null;
  const indicator = details.indicator as AnyRecord | null;
  const creator = details.creator as AnyRecord | null;
  const overdue = daysFromDeadline(action.data_fim);
  const overdueBlock = !isFinished(action) && overdue !== null && overdue > 0 ? `<div style="background:#fee2e2;color:#991b1b;padding:12px;border-radius:7px;font-weight:900;margin:14px 0">AÇÃO VENCIDA — ${overdue} ${overdue === 1 ? "dia" : "dias"} de atraso</div>` : "";
  return `<h2 style="margin:0 0 8px;color:#092b4d">${heading}</h2><p>Você recebeu uma ação do Plano de Sustentação Mundial.</p>${overdueBlock}<table style="width:100%;border-collapse:collapse;font-size:13px"><tr><td style="padding:7px 0;color:#718598">Operação</td><td style="padding:7px 0;font-weight:800">${operation?.nome || "—"}</td></tr><tr><td style="padding:7px 0;color:#718598">Indicador</td><td style="padding:7px 0;font-weight:800">${indicator?.nome || "Não vinculado"}</td></tr><tr><td style="padding:7px 0;color:#718598">Ação</td><td style="padding:7px 0;font-weight:800">${action.acao || "—"}</td></tr><tr><td style="padding:7px 0;color:#718598">Prazo</td><td style="padding:7px 0;font-weight:800">${action.data_fim || "Não informado"}</td></tr><tr><td style="padding:7px 0;color:#718598">Prioridade</td><td style="padding:7px 0;font-weight:800">${action.prioridade || "Não informada"}</td></tr><tr><td style="padding:7px 0;color:#718598">Atribuída por</td><td style="padding:7px 0;font-weight:800">${creator?.nome || creator?.email || "Administrador"}</td></tr><tr><td style="padding:7px 0;color:#718598">Status</td><td style="padding:7px 0;font-weight:800">${action.concluido ? "Concluído" : action.status || "Pendente"}</td></tr></table>${external ? "<p style=\"margin-top:18px\">Este link abre somente o portal individual desta ação. Ele não libera acesso ao dashboard da empresa.</p>" : "<p style=\"margin-top:18px\">Após autenticar, a aplicação abrirá diretamente esta ação.</p>"}`;
}

async function sendResend(to: string, subject: string, html: string) {
  const apiKey = env("RESEND_API_KEY");
  const from = env("ACTION_EMAIL_FROM");
  if (!apiKey || !from) throw new Error("Resend ainda não configurado: defina RESEND_API_KEY e ACTION_EMAIL_FROM nos Secrets.");
  const response = await fetch("https://api.resend.com/emails", { method: "POST", headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" }, body: JSON.stringify({ from, to: [to], subject, html }) });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(String((payload as AnyRecord)?.message || `Resend HTTP ${response.status}`));
  return String((payload as AnyRecord)?.id || "");
}

async function processDue(adminClient: ReturnType<typeof createClient>, workerKey: string) {
  const now = new Date().toISOString();
  const { data: dueActions } = await adminClient.from("sustentacao_plano_acao").select("id,operacao_id,responsavel_email,responsavel_user_id,responsavel_tipo,concluido,proximo_lembrete_em").eq("concluido", false).not("responsavel_email", "is", null).lte("proximo_lembrete_em", now).limit(100);
  for (const action of dueActions || []) {
    const dedupe = `reminder:${action.id}:${String(action.proximo_lembrete_em || now).slice(0, 10)}`;
    await adminClient.from("sustentacao_acao_notificacoes").upsert({ action_id: action.id, operacao_id: action.operacao_id, tipo: "LEMBRETE", destinatario_tipo: action.responsavel_user_id ? "PLATAFORMA" : (action.responsavel_tipo || "EXTERNO"), destinatario_user_id: action.responsavel_user_id || null, destinatario_email: action.responsavel_email, dedupe_key: dedupe, scheduled_at: now, payload: { action_id: action.id } }, { onConflict: "dedupe_key", ignoreDuplicates: true });
    await adminClient.from("sustentacao_plano_acao").update({ proximo_lembrete_em: new Date(Date.now() + 7 * 86400000).toISOString(), ultimo_lembrete_em: now }).eq("id", action.id).eq("concluido", false);
  }

  const { data: claimed, error } = await adminClient.rpc("claim_sustentacao_acao_notificacoes", { p_limit: 25 });
  if (error) throw error;
  const resendConfigured = Boolean(env("RESEND_API_KEY") && env("ACTION_EMAIL_FROM"));
  const results: AnyRecord[] = [];
  for (const notification of claimed || []) {
    const { data: freshAction } = await adminClient.from("sustentacao_plano_acao").select("id,concluido").eq("id", notification.action_id).maybeSingle();
    if (!freshAction || freshAction.concluido) {
      await adminClient.rpc("mark_sustentacao_acao_notification", { p_id: notification.id, p_status: "CANCELADO", p_error: "Ação concluída ou removida antes do envio." });
      continue;
    }
    if (!resendConfigured) {
      await adminClient.from("sustentacao_acao_notificacoes").update({ status: "PENDENTE", attempts: Math.max(0, Number(notification.attempts || 1) - 1), next_attempt_at: new Date(Date.now() + 3600000).toISOString(), last_error: "Resend ainda não configurado; aguardando chave do provedor.", updated_at: now }).eq("id", notification.id);
      results.push({ id: notification.id, status: "PENDENTE", reason: "RESEND_NOT_CONFIGURED" });
      continue;
    }
    try {
      const details = await getAction(adminClient, Number(notification.action_id));
      let actionLink = `${APP_URL}?action-id=${notification.action_id}`;
      const external = notification.destinatario_tipo === "EXTERNO";
      if (external) actionLink = (await ensurePortalToken(adminClient, details.action, workerKey)).link;
      const subject = notification.tipo === "LEMBRETE" ? "Lembrete: você possui uma ação pendente" : "Uma nova ação foi atribuída a você";
      const html = emailLayout(subject, actionBody(details, subject, external), actionLink, external ? "RESPONDER AÇÃO" : "ACESSAR AÇÃO");
      const providerId = await sendResend(String(notification.destinatario_email), subject, html);
      await adminClient.rpc("mark_sustentacao_acao_notification", { p_id: notification.id, p_status: "ENVIADO", p_provider_message_id: providerId, p_error: null });
      await adminClient.from("sustentacao_acao_eventos").insert({ action_id: notification.action_id, operacao_id: notification.operacao_id, tipo: notification.tipo === "LEMBRETE" ? "LEMBRETE_ENVIADO" : "EMAIL_ENVIADO", actor_type: "SISTEMA", actor_email: notification.destinatario_email, metadata: { notification_id: notification.id, provider_message_id: providerId } });
      results.push({ id: notification.id, status: "ENVIADO" });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      const next = new Date(Date.now() + Math.min(86400000, Math.max(900000, Number(notification.attempts || 1) * 900000))).toISOString();
      await adminClient.rpc("mark_sustentacao_acao_notification", { p_id: notification.id, p_status: "FALHA", p_error: message.slice(0, 500), p_next_attempt_at: next });
      await adminClient.from("sustentacao_acao_eventos").insert({ action_id: notification.action_id, operacao_id: notification.operacao_id, tipo: "EMAIL_FALHA", actor_type: "SISTEMA", actor_email: notification.destinatario_email, metadata: { notification_id: notification.id, error: message.slice(0, 500) } });
      results.push({ id: notification.id, status: "FALHA" });
    }
  }
  return { processed: results.length, results };
}

async function portalRecord(adminClient: ReturnType<typeof createClient>, token: string) {
  const tokenHash = await sha256(token);
  const { data: tokenRow, error } = await adminClient.from("sustentacao_acao_portal_tokens").select("id,action_id,expires_at,revoked_at,completed_read_until").eq("token_hash", tokenHash).maybeSingle();
  if (error || !tokenRow) throw new Error("Link inválido ou expirado");
  const now = Date.now();
  if (tokenRow.revoked_at || (tokenRow.expires_at && new Date(tokenRow.expires_at).getTime() < now)) throw new Error("Este link foi revogado ou expirou");
  const details = await getAction(adminClient, Number(tokenRow.action_id));
  if (isFinished(details.action) && tokenRow.completed_read_until && new Date(tokenRow.completed_read_until).getTime() < now) throw new Error("O acesso de leitura desta ação expirou");
  await adminClient.from("sustentacao_acao_portal_tokens").update({ last_accessed_at: new Date().toISOString(), updated_at: new Date().toISOString() }).eq("id", tokenRow.id);
  await adminClient.from("sustentacao_acao_eventos").insert({ action_id: details.action.id, operacao_id: details.action.operacao_id, tipo: "PORTAL_ACESSADO", actor_type: "EXTERNO", actor_email: details.action.responsavel_email, metadata: { token_id: tokenRow.id } });
  return { tokenRow, details };
}

function publicAction(details: AnyRecord, readOnly: boolean) {
  const action = details.action as AnyRecord;
  return { id: action.id, operacao: (details.operation as AnyRecord | null)?.nome || "—", indicador: (details.indicator as AnyRecord | null)?.nome || "Não vinculado", acao: action.acao, responsavel: action.responsavel, data_inicio: action.data_inicio, data_fim: action.data_fim, status: action.concluido ? "Concluído" : action.status || "Pendente", observacao: action.observacao, andamento: action.andamento, prioridade: action.prioridade, concluido: action.concluido === true, readOnly };
}

async function verifyInternal(adminClient: ReturnType<typeof createClient>, req: Request, actionId: number, mode: "view" | "manage") {
  const authorization = req.headers.get("Authorization") || "";
  const token = authorization.replace(/^Bearer\s+/i, "").trim();
  if (!token) throw new Error("Sessão inválida");
  const { data: authData, error: authError } = await adminClient.auth.getUser(token);
  if (authError || !authData.user) throw new Error("Sessão inválida");
  const { data: profile } = await adminClient.from("sustentacao_usuarios").select("user_id,perfil,ativo").eq("user_id", authData.user.id).maybeSingle();
  if (!profile?.ativo) throw new Error("Usuário operacional inativo");
  const details = await getAction(adminClient, actionId);
  const superProfile = ["admin", "super_admin"].includes(String(profile.perfil));
  const adminProfile = ["gestor", "administrador_operacao"].includes(String(profile.perfil));
  if (!superProfile && !adminProfile) throw new Error("Sem permissão para administrar esta ação");
  if (!superProfile) {
    const { data: link } = await adminClient.from("sustentacao_usuario_operacoes").select("operacao_id").eq("user_id", authData.user.id).eq("operacao_id", details.action.operacao_id).eq("ativo", true).maybeSingle();
    if (!link) throw new Error("Ação fora do escopo da operação");
  }
  if (mode === "manage" && !superProfile && !adminProfile) throw new Error("Sem permissão de gerenciamento");
  return { details, userId: authData.user.id };
}

async function handle(req: Request) {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Método não permitido" }, 405);
  const supabaseUrl = env("SUPABASE_URL");
  const serviceRoleKey = env("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) return json({ error: "Configuração do backend incompleta" }, 500);
  const adminClient = createClient(supabaseUrl, serviceRoleKey);
  const body = await readBody(req);
  const mode = String(body.mode || "");

  if (mode === "process_due") {
    try {
      if (!(await isWorkerRequest(req, adminClient))) return json({ error: "Worker não autorizado" }, 401);
      const workerKey = await getWorkerKey(adminClient);
      return json({ ok: true, ...(await processDue(adminClient, workerKey)) });
    } catch (error) {
      return json({ error: error instanceof Error ? error.message : "Falha no worker" }, 500);
    }
  }

  if (mode === "portal_get" || mode === "portal_update" || mode === "portal_upload_url") {
    const token = String(body.token || "").trim();
    if (!token) return json({ error: "Link inválido" }, 400);
    try {
      const portal = await portalRecord(adminClient, token);
      const action = portal.details.action as AnyRecord;
      if (mode === "portal_get") return json({ ok: true, action: publicAction(portal.details, isFinished(action)) });
      if (isFinished(action)) return json({ error: "Esta ação está concluída e o portal está disponível somente para leitura." }, 409);
      if (mode === "portal_upload_url") {
        const fileName = safeFileName(String(body.file_name || "evidencia"));
        const mime = String(body.mime_type || "");
        const size = Number(body.size || 0);
        if (!(mime.startsWith("image/") || mime === "application/pdf") || size <= 0 || size > 10485760) return json({ error: "Arquivo inválido. Envie imagem ou PDF de até 10 MB." }, 400);
        const path = `${action.id}/${crypto.randomUUID()}-${fileName}`;
        const { data, error } = await adminClient.storage.from(BUCKET).createSignedUploadUrl(path);
        if (error) throw error;
        return json({ ok: true, path, token: data.token });
      }
      const status = String(body.status || "Em andamento");
      if (!["Em andamento", "Concluído"].includes(status)) return json({ error: "Status inválido" }, 400);
      const evidencePath = body.evidence_path ? String(body.evidence_path) : null;
      if (evidencePath && !evidencePath.startsWith(`${action.id}/`)) return json({ error: "Evidência inválida para esta ação" }, 400);
      const concluded = status === "Concluído";
      const update = { status, concluido: concluded, andamento: String(body.response || "").trim() || null, observacao: String(body.observation || "").trim() || null };
      const { error: updateError } = await adminClient.from("sustentacao_plano_acao").update(update).eq("id", action.id).eq("concluido", false);
      if (updateError) throw updateError;
      await adminClient.from("sustentacao_acao_eventos").insert([{ action_id: action.id, operacao_id: action.operacao_id, tipo: "PORTAL_STATUS_ALTERADO", actor_type: "EXTERNO", actor_email: action.responsavel_email, metadata: { status } }, { action_id: action.id, operacao_id: action.operacao_id, tipo: "PORTAL_RESPOSTA_REGISTRADA", actor_type: "EXTERNO", actor_email: action.responsavel_email, metadata: { evidence_path: evidencePath } }]);
      if (evidencePath) await adminClient.from("sustentacao_acao_eventos").insert({ action_id: action.id, operacao_id: action.operacao_id, tipo: "EVIDENCIA_ANEXADA", actor_type: "EXTERNO", actor_email: action.responsavel_email, metadata: { path: evidencePath } });
      return json({ ok: true, action: publicAction({ ...portal.details, action: { ...action, ...update } }, concluded) });
    } catch (error) {
      return json({ error: error instanceof Error ? error.message : "Não foi possível acessar esta ação" }, 403);
    }
  }

  const actionId = Number(body.action_id || 0);
  if (!actionId) return json({ error: "Ação não informada" }, 400);
  try {
    const internal = await verifyInternal(adminClient, req, actionId, mode === "history" ? "view" : "manage");
    const workerKey = await getWorkerKey(adminClient);
    if (mode === "history") {
      const { data, error } = await adminClient.from("sustentacao_acao_eventos").select("id,tipo,actor_user_id,actor_type,actor_email,metadata,created_at").eq("action_id", actionId).order("created_at", { ascending: false }).limit(200);
      if (error) throw error;
      return json({ ok: true, events: data || [] });
    }
    if (mode === "revoke") {
      await adminClient.from("sustentacao_acao_portal_tokens").update({ revoked_at: new Date().toISOString(), updated_at: new Date().toISOString() }).eq("action_id", actionId).is("revoked_at", null);
      await adminClient.from("sustentacao_acao_eventos").insert({ action_id: actionId, operacao_id: internal.details.action.operacao_id, tipo: "PORTAL_REVOGADO", actor_user_id: internal.userId, actor_type: "PLATAFORMA", metadata: {} });
      return json({ ok: true, message: "Acesso externo revogado." });
    }
    if (mode === "regenerate") {
      const portal = await ensurePortalToken(adminClient, internal.details.action, workerKey, internal.userId);
      await adminClient.from("sustentacao_acao_eventos").insert({ action_id: actionId, operacao_id: internal.details.action.operacao_id, tipo: "PORTAL_REGENERADO", actor_user_id: internal.userId, actor_type: "PLATAFORMA", metadata: {} });
      return json({ ok: true, link: portal.link });
    }
    if (mode === "resend") {
      const action = internal.details.action as AnyRecord;
      if (!action.responsavel_email) return json({ error: "A ação não possui e-mail de responsável." }, 400);
      await adminClient.from("sustentacao_acao_notificacoes").insert({ action_id: actionId, operacao_id: action.operacao_id, tipo: "REENVIO", destinatario_tipo: action.responsavel_tipo || (action.responsavel_user_id ? "PLATAFORMA" : "EXTERNO"), destinatario_user_id: action.responsavel_user_id || null, destinatario_email: action.responsavel_email, dedupe_key: `resend:${actionId}:${crypto.randomUUID()}`, scheduled_at: new Date().toISOString(), payload: { action_id: actionId } });
      return json({ ok: true, message: "Reenvio colocado na fila." });
    }
    return json({ error: "Operação desconhecida" }, 400);
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Não foi possível concluir a operação" }, 403);
  }
}

Deno.serve(handle);
