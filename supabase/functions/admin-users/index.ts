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

type AdminAction = "save" | "resend" | "list" | "replicate" | "provision" | "temporary_password";

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

type AdminProfile = {
  user_id: string;
  email?: string | null;
  nome?: string | null;
  perfil?: string | null;
  ativo?: boolean | null;
};

type OperationLink = {
  user_id: string;
  operacao_id: number;
  ativo: boolean;
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
  const value = error as { code?: string; message?: string } | null;
  const text = `${value?.code ?? ""} ${value?.message ?? ""}`.toLowerCase();
  if (isEmailRateLimit(error)) return json({ error: FRIENDLY_RATE_LIMIT, code: "EMAIL_RATE_LIMIT", user_id: userId ?? null }, 429);
  if (text.includes("email_exists") || text.includes("already registered") || text.includes("already exists")) return json({ error: "Já existe uma conta com esse e-mail. Selecione o cadastro existente ou use Criar / Recuperar Senha; nada foi substituído.", code: "AUTH_USER_ALREADY_EXISTS", user_id: userId ?? null }, 409);
  return json({ error: "Não foi possível concluir o cadastro ou a atualização da senha.", code: "AUTH_ADMIN_ACTION_ERROR", user_id: userId ?? null }, 400);
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

function generateTemporaryPassword() {
  const upper = "ABCDEFGHJKLMNPQRSTUVWXYZ";
  const lower = "abcdefghijkmnopqrstuvwxyz";
  const digits = "23456789";
  const symbols = "!@#%^*-_=+";
  const alphabet = upper + lower + digits + symbols;
  const bytes = new Uint8Array(24);
  crypto.getRandomValues(bytes);
  const chars = [upper[bytes[0] % upper.length], lower[bytes[1] % lower.length], digits[bytes[2] % digits.length], symbols[bytes[3] % symbols.length]];
  for (let i = 4; i < bytes.length; i += 1) chars.push(alphabet[bytes[i] % alphabet.length]);
  for (let i = chars.length - 1; i > 0; i -= 1) {
    const random = new Uint32Array(1);
    crypto.getRandomValues(random);
    const j = random[0] % (i + 1);
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  return chars.join("");
}

async function listAdminUsers(adminClient: ReturnType<typeof createClient>, callerId: string, callerProfile: { perfil: string }) {
  const [authUsers, profilesQuery, linksQuery] = await Promise.all([
    listAllAuthUsers(adminClient),
    adminClient.from("sustentacao_usuarios").select("id,user_id,email,nome,perfil,ativo"),
    adminClient.from("sustentacao_usuario_operacoes").select("user_id,operacao_id,ativo"),
  ]);
  if (profilesQuery.error) throw profilesQuery.error;
  if (linksQuery.error) throw linksQuery.error;

  const profiles = (profilesQuery.data ?? []) as AdminProfile[];
  const links = (linksQuery.data ?? []) as OperationLink[];
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
        require_password_change: metadata.require_password_change === true,
        temporary_password_issued_at: metadata.temporary_password_issued_at ?? null,
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
    assistant_permissions?: unknown[];
    source_user_id?: string;
    target_user_id?: string;
    copy_profile?: boolean;
    replication_mode?: "REPLACE" | "MERGE";
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: "JSON inválido" }, 400);
  }

  const action: AdminAction = body.action === "list"
    ? "list"
    : body.action === "resend"
      ? "resend"
      : body.action === "replicate"
        ? "replicate"
        : body.action === "provision"
          ? "provision"
          : body.action === "temporary_password"
            ? "temporary_password"
            : "save";
  if (action === "list") {
    try {
      return json({ ok: true, users: await listAdminUsers(adminClient, caller.user.id, callerProfile) });
    } catch {
      return json({ error: "Não foi possível consultar os usuários do Auth." }, 400);
    }
  }

  if (action === "replicate") {
    const sourceUserId = String(body.source_user_id ?? "").trim();
    const targetUserId = String(body.target_user_id ?? "").trim();
    if (!sourceUserId || !targetUserId || sourceUserId === targetUserId) {
      return json({ error: "Selecione usuários de origem e destino diferentes.", code: "REPLICATION_INPUT_ERROR" }, 400);
    }
    const { data, error } = await userClient.rpc("admin_replicate_user_permissions", {
      p_source_user_id: sourceUserId,
      p_target_user_id: targetUserId,
      p_copy_profile: body.copy_profile !== false,
      p_mode: body.replication_mode === "MERGE" ? "MERGE" : "REPLACE",
    });
    if (error) {
      console.error("admin_replicate_user_permissions failed", {
        source_user_id: sourceUserId,
        target_user_id: targetUserId,
        code: error.code ?? null,
        message: error.message ?? null,
      });
      return json({ error: "Não foi possível replicar as permissões. Verifique o escopo dos usuários e tente novamente.", code: "REPLICATION_ERROR" }, 400);
    }
    return json({ ok: true, ...(data ?? {}), message: "Cadastro e permissões replicados com sucesso." });
  }

  if (action === "temporary_password") {
    const targetUserId = String(body.target_user_id ?? "").trim();
    if (!targetUserId) return json({ error: "Selecione um usuário vinculado para gerar uma senha temporária.", code: "TARGET_USER_REQUIRED" }, 400);
    if (!isSuper) {
      if (!OPERATION_ADMIN_PROFILES.has(String(callerProfile.perfil))) return json({ error: "Somente administradores podem gerar credenciais de usuários.", code: "USER_OUT_OF_SCOPE" }, 403);
      const [callerLinks, targetLinks] = await Promise.all([
        adminClient.from("sustentacao_usuario_operacoes").select("operacao_id").eq("user_id", caller.user.id).eq("ativo", true),
        adminClient.from("sustentacao_usuario_operacoes").select("operacao_id").eq("user_id", targetUserId).eq("ativo", true),
      ]);
      if (callerLinks.error || targetLinks.error) return json({ error: "Não foi possível validar o escopo operacional deste usuário.", code: "USER_SCOPE_CHECK_ERROR" }, 500);
      const callerOperationIds = new Set((callerLinks.data ?? []).map((link) => Number(link.operacao_id)));
      const targetInScope = (targetLinks.data ?? []).some((link) => callerOperationIds.has(Number(link.operacao_id)));
      if (!targetInScope) return json({ error: "Você não possui permissão para gerar credenciais deste usuário.", code: "USER_OUT_OF_SCOPE" }, 403);
    }
    const { data: targetProfile, error: targetProfileError } = await adminClient.from("sustentacao_usuarios").select("user_id,ativo").eq("user_id", targetUserId).maybeSingle();
    if (targetProfileError) return json({ error: "Não foi possível validar o vínculo do usuário.", code: "TARGET_PROFILE_ERROR" }, 500);
    if (!targetProfile || targetProfile.ativo !== true) return json({ error: "Somente usuários vinculados e ativos podem receber uma senha temporária.", code: "TARGET_NOT_ACTIVE" }, 409);
    const { data: targetAuth, error: targetAuthError } = await adminClient.auth.admin.getUserById(targetUserId);
    if (targetAuthError || !targetAuth.user) return json({ error: "Usuário não encontrado no Auth.", code: "AUTH_USER_NOT_FOUND" }, 404);
    const targetMetadata = targetAuth.user.user_metadata ?? {};
    const legacyActive = Boolean(targetAuth.user.created_at && targetAuth.user.created_at < LEGACY_AUTH_CUTOFF && targetMetadata.require_password_change !== true);
    if (targetMetadata.first_access_completed === true || legacyActive) return json({ error: "Este usuário já concluiu o primeiro acesso. Use o fluxo Criar / Recuperar Senha para não substituir uma senha ativa.", code: "FIRST_ACCESS_ALREADY_COMPLETED" }, 409);
    const temporaryPassword = generateTemporaryPassword();
    const issuedAt = new Date().toISOString();
    const metadata = {
      ...(targetAuth.user.user_metadata ?? {}),
      first_access_completed: false,
      first_access_completed_at: null,
      require_password_change: true,
      temporary_password_issued_at: issuedAt,
    };
    const { error: updateError } = await adminClient.auth.admin.updateUserById(targetUserId, {
      password: temporaryPassword,
      email_confirm: true,
      user_metadata: metadata,
    });
    if (updateError) return authError(updateError, targetUserId);
    return json({ ok: true, user_id: targetUserId, invite_state: "password_pending", temporary_password: temporaryPassword, message: "Senha temporária criada. O usuário deverá defini-la novamente no primeiro acesso." });
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
  let inviteState: "new" | "pending" | "confirmed" | "password_pending" = existing
    ? (existing.email_confirmed_at || existing.confirmed_at ? "confirmed" : "pending")
    : "new";
  let inviteError: unknown = null;
  let temporaryPassword: string | null = null;

  if (action === "provision") {
    if (existing) return json({ error: "Já existe uma conta Auth para este e-mail. Nenhuma senha ou permissão foi alterada; selecione o usuário existente ou use a recuperação de senha.", code: "AUTH_USER_ALREADY_EXISTS", user_id: existing.id }, 409);
    temporaryPassword = generateTemporaryPassword();
    const { data, error } = await adminClient.auth.admin.createUser({
      email,
      password: temporaryPassword,
      email_confirm: true,
      user_metadata: {
        nome,
        perfil,
        first_access_completed: false,
        require_password_change: true,
        first_access_created_at: new Date().toISOString(),
        temporary_password_issued_at: new Date().toISOString(),
      },
    });
    if (error || !data?.user?.id) {
      inviteError = error ?? new Error("Não foi possível criar a identidade no Auth.");
      temporaryPassword = null;
    } else {
      authUserId = data.user.id;
      inviteState = "password_pending";
    }
  } else {
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
  }

  if (!authUserId) {
    if (action === "provision" && isEmailRateLimit(inviteError)) {
      return json({ error: "Não foi possível provisionar a conta neste momento. Aguarde alguns minutos e tente novamente.", code: "AUTH_PROVISION_ERROR" }, 429);
    }
    return authError(inviteError ?? new Error("Não foi possível criar o usuário no Auth."));
  }

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
    console.error("admin_save_user_access failed", {
      user_id: authUserId,
      email,
      code: rpcError.code ?? null,
      message: rpcError.message ?? null,
      details: rpcError.details ?? null,
      hint: rpcError.hint ?? null,
    });
    return json({ error: "Não foi possível concluir o vínculo e as permissões do usuário. O usuário Auth foi preservado; salve novamente para concluir sem criar outro cadastro.", code: "ACCESS_SAVE_ERROR", user_id: authUserId }, 400);
  }

  const { error: assistantError } = await userClient.rpc("admin_save_assistant_access", {
    p_user_id: authUserId,
    p_permissions: Array.isArray(body.assistant_permissions) ? body.assistant_permissions : [],
  });
  if (assistantError) {
    console.error("admin_save_assistant_access failed", {
      user_id: authUserId,
      code: assistantError.code ?? null,
      message: assistantError.message ?? null,
      details: assistantError.details ?? null,
      hint: assistantError.hint ?? null,
    });
    return json({ error: "O usuário e as permissões operacionais foram preservados, mas não foi possível salvar as permissões do Assistente. Tente novamente.", code: "ASSISTANT_ACCESS_SAVE_ERROR", user_id: authUserId }, 400);
  }

  if (inviteError) return authError(inviteError, authUserId);

  return json({
    ok: true,
    user_id: authUserId,
    invited,
    existing: Boolean(existing),
    invite_state: inviteState,
    temporary_password: temporaryPassword,
    message: temporaryPassword
      ? "Conta Auth confirmada e permissões salvas. Compartilhe a senha temporária por canal seguro; ela deverá ser trocada no primeiro acesso."
      : inviteState === "confirmed" ? "Usuário e permissões salvos." : "Usuário e permissões salvos; o convite permanece pendente.",
  });
});
