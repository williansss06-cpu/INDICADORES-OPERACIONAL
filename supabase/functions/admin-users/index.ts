import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const LEGACY_SUPER = new Set(["admin", "super_admin"]);
const OPERATION_ADMIN = new Set(["gestor", "administrador_operacao"]);
const ALLOWED_PROFILES = new Set([
  "admin",
  "super_admin",
  "gestor",
  "administrador_operacao",
  "coordenador",
  "usuario",
]);

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
  if (!LEGACY_SUPER.has(String(callerProfile.perfil))) {
    const { data: centralAccess, error: accessError } = await userClient.rpc(
      "tem_acesso_central_administrativa",
    );
    if (accessError || centralAccess !== true) {
      return json({ error: "Sem permissão para administrar usuários" }, 403);
    }
  }

  let body: {
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

  const email = String(body.email ?? "").trim().toLowerCase();
  const nome = String(body.nome ?? "").trim();
  const perfil = String(body.perfil ?? "usuario").trim().toLowerCase();
  const ativo = body.ativo !== false;
  const operationIds = Array.isArray(body.operation_ids)
    ? body.operation_ids.map(Number).filter(Number.isInteger)
    : [];
  if (!email || !email.includes("@")) return json({ error: "Informe um e-mail válido" }, 400);
  if (!ALLOWED_PROFILES.has(perfil)) return json({ error: "Perfil inválido" }, 400);

  const isSuper = LEGACY_SUPER.has(String(callerProfile.perfil));
  if (!isSuper && (LEGACY_SUPER.has(perfil) || OPERATION_ADMIN.has(perfil))) {
    return json({ error: "Administrador da operação só pode cadastrar coordenadores e usuários" }, 403);
  }

  // A função SQL é a autoridade final: ela compara o ator, a operação e cada permissão.
  // O navegador nunca consegue ampliar seu escopo apenas alterando operation_ids.
  const { data: usersPage, error: listError } = await adminClient.auth.admin.listUsers({
    page: 1,
    perPage: 1000,
  });
  if (listError) return json({ error: listError.message }, 400);
  const existing = usersPage.users.find((u) => (u.email ?? "").toLowerCase() === email);
  let authUserId = existing?.id;
  let invited = false;

  if (!authUserId) {
    const { data, error } = await adminClient.auth.admin.inviteUserByEmail(email, {
      data: { nome, perfil },
    });
    if (error || !data.user) {
      return json({ error: error?.message ?? "Não foi possível enviar o convite" }, 400);
    }
    authUserId = data.user.id;
    invited = true;
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
    return json({ error: rpcError.message, user_id: authUserId }, 400);
  }

  return json({ ok: true, user_id: authUserId, invited, existing: Boolean(existing) });
});
