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

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Método não permitido" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const authorization = req.headers.get("Authorization");
  if (!supabaseUrl || !serviceRoleKey || !authorization) return json({ error: "Configuração de autenticação incompleta" }, 500);

  const adminClient = createClient(supabaseUrl, serviceRoleKey);
  const userClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY") ?? "", {
    global: { headers: { Authorization: authorization } },
  });

  const token = authorization.replace(/^Bearer\s+/i, "").trim();
  if (!token) return json({ error: "Sessão inválida" }, 401);
  const { data: caller, error: callerError } = await adminClient.auth.getUser(token);
  if (callerError || !caller.user) return json({ error: "Sessão inválida" }, 401);

  const { data: callerProfile, error: profileError } = await adminClient
    .from("sustentacao_usuarios")
    .select("perfil,ativo")
    .eq("user_id", caller.user.id)
    .maybeSingle();
  if (profileError || callerProfile?.ativo !== true || callerProfile.perfil !== "admin") {
    return json({ error: "Apenas Administrador pode cadastrar usuários" }, 403);
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
  if (!email || !email.includes("@")) return json({ error: "Informe um e-mail válido" }, 400);
  if (!["admin", "gestor", "usuario"].includes(perfil)) return json({ error: "Perfil inválido" }, 400);

  const { data: usersPage, error: listError } = await adminClient.auth.admin.listUsers({ page: 1, perPage: 1000 });
  if (listError) return json({ error: listError.message }, 400);
  const existing = usersPage.users.find((u) => (u.email ?? "").toLowerCase() === email);
  let authUserId = existing?.id;
  let invited = false;

  if (!authUserId) {
    const { data, error } = await adminClient.auth.admin.inviteUserByEmail(email, {
      data: { nome, perfil },
    });
    if (error || !data.user) return json({ error: error?.message ?? "Não foi possível enviar o convite" }, 400);
    authUserId = data.user.id;
    invited = true;
  }

  const { error: rpcError } = await userClient.rpc("admin_save_user_access", {
    p_user_id: authUserId,
    p_email: email,
    p_nome: nome,
    p_perfil: perfil,
    p_ativo: ativo,
    p_operation_ids: Array.isArray(body.operation_ids) ? body.operation_ids : [],
    p_module_permissions: Array.isArray(body.module_permissions) ? body.module_permissions : [],
    p_indicator_permissions: Array.isArray(body.indicator_permissions) ? body.indicator_permissions : [],
    p_action_permissions: Array.isArray(body.action_permissions) ? body.action_permissions : [],
  });
  if (rpcError) return json({ error: rpcError.message, user_id: authUserId }, 400);
  return json({ ok: true, user_id: authUserId, invited, existing: Boolean(existing) });
});
