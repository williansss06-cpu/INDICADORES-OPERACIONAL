import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const APP_REDIRECT_URL = "https://williansss06-cpu.github.io/INDICADORES-OPERACIONAL/";
const LEGACY_AUTH_CUTOFF = "2026-09-23T17:48:36.000Z";
const FRIENDLY_RATE_LIMIT = "Não foi possível enviar o convite neste momento. O limite temporário de envio de e-mails foi atingido. Tente novamente mais tarde ou verifique a configuração de e-mail.";
const SUPER_PROFILES = new Set(["admin", "super_admin"]);
const OPERATION_ADMIN_PROFILES = new Set(["gestor", "administrador_operacao"]);
const ALLOWED_PROFILES = new Set([
  "admin",
  "super_admin",
  "gestor",
  "administrador_operacao",
  "coordenador",
  "usuario",
]);

type AdminAction = "save" | "resend" | "list";

type AuthUser = {
  id: string;
  email?: string;
  invited_at?: string | null;
  confirmation_sent_at?: string | null;
  email_confirmed_at?: string | null;
  confirmed_at?: string | null;
  last_sign_in_at?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
  user_metadata?: Record<string, unknown>;
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function isEmailRateLimit(error: unknown) {
  const value = error as { code?: string; message?: string } | null;
  const text = `${value?.code ?? ""} ${value?.message ?? ""}`.toLowerCase();
  return text.includes("over_email_send_rate_limit") || text.includes("email rate limit") || text.includes("too many");
}

function authError(error: unknown, userId?: string) {
  const value = error as { message?: string } | null;
  if (isEmailRateLimit(error)) {
    return json({ error: FRIENDLY_RATE_LIMIT, code: "EMAIL_RATE_LIMIT", user_id: userId ?? null }, 429);
  }
  return json({ error: value?.message ?? "Não foi possível enviar o convite.", code: "AUTH_INVITE_ERROR", user_id: userId ?? null }, 400);
}

async function listAllAuthUsers(adminClient: ReturnType<typeof createClient>): Promise<AuthUser[]> {
  const users: AuthUser[] = [];
  for (let page = 1; page <= 20; page += 1) {
    const { data, error } = await adminClient.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) throw error;
    const batch = (data.users ?? []) as AuthUser[];
    users.push(...batch);
    if (batch.length < 1000) break;
  }
  return users;
}

async function findAuthUser(adminClient: ReturnType<typeof createClient>, email: string) {
  const users = await listAllAuthUsers(adminClient);
  return users.find((user) => (user.email ?? "").toLowerCase() === email) ?? null;
}

async function listAdminUsers(adminClient: ReturnType<typeof createClient>, callerId: string, callerProfile: { perfil: string }) {
  const [authUsers, profilesQuery, linksQuery] = await Promise.all([
    listAllAuthUsers(adminClient),
    adminClient.from("sustentacao_usuarios").select("id,user_id,email,nome,perfil,ativo"),
    adminClient.from("sustentacao_usuario_operacoes").select("user_id,operacao_id,ativo"),
  ]);
  if (profilesQuery.error) throw profilesQuery.error;
  if (linksQuery.error) throw linksQuery.error;

  const profiles = profilesQuery.data ?? [];
  const links = linksQuery.data ?? [];
  const isSuper = SUPER_PROFILES.has(String(callerProfile.perfil));
  let visibleUserIds: Set<string> | null = null;
  if (!isSuper) {
    const callerLinks = links.filter((link) => link.user_id === callerId && link.ativo);
    const allowedOperations = new Set(callerLinks.map((link) => Number(link.operacao_id)));
    visibleUserIds = new Set(
      links
        .filter((link) => link.ativo && allowedOperations.has(Number(link.operacao_id)))
        .map((link) => link.user_id),
    );
  }

  const profileById = new Map(profiles.map((profile) => [profile.user_id, profile]));
  const linksByUser = new Map<string, number[]>();
  for (const link of links) {
    if (!link.ativo) continue;
    const list = linksByUser.get(link.user_id) ?? [];
    list.push(Number(link.operacao_id));
    linksByUser.set(link.user_id, list);
  }

  return authUsers
    .filter((authUser) => isSuper || visibleUserIds?.has(authUser.id))
    .map((authUser) => {
      const profile = profileById.get(authUser.id);
      const metadata = authUser.user_metadata ?? {};
      return {
        user_id: authUser.id,
        email: authUser.email ?? profile?.email ?? "",
        nome: profile?.nome || metadata.nome || metadata.full_name || "",
        perfil: profile?.perfil || metadata.perfil || "usuario",
        ativo: profile ? profile.ativo !== false : true,
        linked: Boolean(profile),
        operation_ids: linksByUser.get(authUser.id) ?? [],
        invited_at: authUser.invited_at ?? null,
        confirmation_sent_at: authUser.confirmation_sent_at ?? null,
        email_confirmed_at: authUser.email_confirmed_at ?? null,
        confirmed_at: authUser.confirmed_at ?? null,
        last_sign_in_at: authUser.last_sign_in_at ?? null,
        created_at: authUser.created_at ?? null,
        updated_at: authUser.updated_at ?? null,
        first_access_completed: metadata.first_access_completed === true,
        first_access_completed_at: metadata.first_access_completed_at ?? null,
        legacy_compatible_active: Boolean(profile && authUser.created_at && authUser.created_at < LEGACY_AUTH_CUTOFF),
      };
    });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Método não permitido" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const authorization = req.headers.get("Authorization");
  if (!supabaseUrl || !serviceRoleKey || !anonKey || !authorization) {
    return json({ error: "Configuração de autenticação incompleta" }, 500);
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey);
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
  });

  const token = authorization.replace(/^Bearer\s+/i, "").trim();
  if (!token) return json({ error: "Sessão inválida" }, 401);
  const { data: caller, error: callerError } = await adminClient.auth.getUser(token);
  if (callerError || !caller.user) return json({ error: "Sessão inválida" }, 401);

  const { data: callerProfile, error: profileError } = await adminClient
    .from("sustentacao_usuarios")
    .select("user_id,perfil,ativo")
    .eq("user_id", caller.user.id)
    .maybeSingle();
  if (profileError) return json({ error: profileError.message }, 500);
  if (!callerProfile?.ativo) return json({ error: "Usuário operacional inativo" }, 403);

  const isSuper = SUPER_PROFILES.has(String(callerProfile.perfil));
  if (!isSuper) {
    const { data: centralAccess, error: accessError } = await userClient.rpc("tem_acesso_central_administrativa");
    if (accessError || centralAccess !== true) return json({ error: "Sem permissão para administrar usuários" }, 403);
  }

  let body: {
    action?: AdminAction;
    email?: string;
    nome?: string;
    perfil?: string;
    ativo?: boolean;
    operation_ids?: number[];
    module_permissions?: unknown[];
    indicator_permissions?: unknown[];
    action_permissions?: unknown[];
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: "JSON inválido" }, 400);
  }

  const action: AdminAction = body.action === "list" ? "list" : body.action === "resend" ? "resend" : "save";
  if (action === "list") {
    try {
      return json({ ok: true, users: await listAdminUsers(adminClient, caller.user.id, callerProfile) });
    } catch {
      return json({ error: "Não foi possível consultar os usuários do Auth." }, 400);
    }
  }

  const email = String(body.email ?? "").trim().toLowerCase();
  const nome = String(body.nome ?? "").trim();
  const perfil = String(body.perfil ?? "usuario").trim().toLowerCase();
  const ativo = body.ativo !== false;
  const operationIds = Array.isArray(body.operation_ids)
    ? body.operation_ids.map(Number).filter(Number.isInteger)
    : [];
  if (!email || !email.includes("@")) return json({ error: "Informe um e-mail válido" }, 400);
  if (!ALLOWED_PROFILES.has(perfil)) return json({ error: "Perfil inválido" }, 400);

  if (!isSuper && (SUPER_PROFILES.has(perfil) || OPERATION_ADMIN_PROFILES.has(perfil))) {
    return json({ error: "Administrador da operação só pode cadastrar coordenadores e usuários" }, 403);
  }

  let existing;
  try {
    existing = await findAuthUser(adminClient, email);
  } catch {
    return json({ error: "Não foi possível consultar o usuário no Auth." }, 400);
  }

  if (action === "resend" && !existing) {
    return json({ error: "Usuário não encontrado no Auth. Salve o usuário antes de reenviar o convite.", code: "AUTH_USER_NOT_FOUND" }, 404);
  }

  let authUserId = existing?.id;
  let invited = false;
  let inviteState: "new" | "pending" | "confirmed" = existing
    ? (existing.email_confirmed_at || existing.confirmed_at ? "confirmed" : "pending")
    : "new";
  let inviteError: unknown = null;

  const shouldSendInvite = action === "resend"
    ? Boolean(existing && !existing.email_confirmed_at && !existing.confirmed_at)
    : !existing;

  if (shouldSendInvite) {
    const { data, error } = await adminClient.auth.admin.inviteUserByEmail(email, {
      data: { nome, perfil },
      redirectTo: APP_REDIRECT_URL,
    });
    authUserId = data?.user?.id ?? authUserId;
    if (error || !authUserId) {
      inviteError = error ?? new Error("Não foi possível criar o usuário no Auth.");
      try {
        const afterError = await findAuthUser(adminClient, email);
        authUserId = afterError?.id ?? authUserId;
      } catch {
        // Preserva o erro original do Auth para a resposta amigável ao administrador.
      }
    } else {
      invited = true;
      inviteState = "pending";
    }
  } else if (action === "resend" && existing?.email_confirmed_at) {
    return json({ ok: true, user_id: existing.id, existing: true, invited: false, invite_state: "confirmed", message: "Este usuário já confirmou o e-mail." });
  }

  if (!authUserId) return authError(inviteError ?? new Error("Não foi possível criar o usuário no Auth."));

  const { error: rpcError } = await userClient.rpc("admin_save_user_access", {
    p_user_id: authUserId,
    p_email: email,
    p_nome: nome,
    p_perfil: perfil,
    p_ativo: ativo,
    p_operation_ids: operationIds,
    p_module_permissions: Array.isArray(body.module_permissions) ? body.module_permissions : [],
    p_indicator_permissions: Array.isArray(body.indicator_permissions) ? body.indicator_permissions : [],
    p_action_permissions: Array.isArray(body.action_permissions) ? body.action_permissions : [],
  });
  if (rpcError) {
    return json({ error: "Não foi possível salvar o vínculo e as permissões do usuário.", code: "ACCESS_SAVE_ERROR", user_id: authUserId }, 400);
  }

  if (inviteError) return authError(inviteError, authUserId);

  return json({
    ok: true,
    user_id: authUserId,
    invited,
    existing: Boolean(existing),
    invite_state: inviteState,
    message: inviteState === "confirmed" ? "Usuário e permissões salvos." : "Usuário e permissões salvos; o convite permanece pendente.",
  });
});
