import type { Page, Route } from "@playwright/test";

import type { components } from "../../src/lib/api/schema";

export const TEST_NOW = "2026-07-17T15:00:00.000Z";
export const TEST_API_SECRET = "rntv-v1-e2e-only-not-a-real-credential";

type SessionMode = "anonymous" | "authenticated" | "pending";

export interface CapturedRequest {
  body: unknown;
  headers: Record<string, string>;
  method: string;
  path: string;
}

// The generated OpenAPI client types are the single source of truth for every
// mocked payload below. Aliases keep the route table readable without letting
// the fixtures drift away from the committed contract.
type Schemas = components["schemas"];
type SecuritySummary = Schemas["SecuritySummaryResponse"];
type ApiKeyRecord = Schemas["APIKeyResponse"];
type ApiKeyGrant = Schemas["APIKeyGrantResponse"];

export interface ApiMockOptions {
  apiKeys?: ApiKeyRecord[];
  /** Mirrors the production `google_auth` feature flag, which is on. */
  googleAuth?: boolean;
  pendingInviteCount?: number;
  security?: SecuritySummary;
  session?: SessionMode;
}

export interface ApiMockState {
  apiKeys: ApiKeyRecord[];
  releaseSession: (mode?: Exclude<SessionMode, "pending">) => void;
  requests: CapturedRequest[];
  unexpectedRequests: string[];
}

export const authenticatedResponse: Schemas["SessionResponse"] = {
  bootstrap: {
    analytics: { events: [], gtm_container_id: "" },
    capabilities: {
      mfa_setup_required: false,
      scopes: [
        "profile:read",
        "organizations:read",
        "organizations:write",
        "organizations:members",
        "billings:read",
        "billings:write",
        "bills:read",
        "bills:write",
        "expenses:read",
        "expenses:write",
        "files:read",
        "files:write",
        "communications:read",
        "communications:send",
        "themes:read",
        "themes:write",
        "exports:create"
      ]
    },
    csrf_token: "csrf-e2e-token",
    feature_flags: {
      google_auth: false,
      turnstile: false,
      turnstile_site_key: ""
    },
    pending_invite_count: 1,
    user: { email: "ana@example.com", id: 42 }
  },
  status: "authenticated"
};

export const authConfig: Schemas["AuthConfigResponse"] = {
  analytics: { gtm_container_id: "" },
  feature_flags: {
    google_auth: false,
    turnstile: false,
    turnstile_site_key: ""
  }
};

export const defaultSecuritySummary: SecuritySummary = {
  mfa: { organization_enforced: false, setup_required: false },
  passkeys: [
    {
      created_at: "2026-01-12T13:00:00.000Z",
      last_used_at: "2026-07-16T18:30:00.000Z",
      name: "Notebook pessoal",
      uuid: "passkey-e2e"
    }
  ],
  profile: {
    email: "ana@example.com",
    pix_key: "ana@example.com",
    pix_merchant_city: "SAO PAULO",
    pix_merchant_name: "ANA SILVA"
  },
  totp: { enabled: true, recovery_codes_remaining: 6 }
};

export const apiKeyOptions: Schemas["APIKeyOptionsResponse"] = {
  default_expiration_days: 90,
  max_expiration_days: 365,
  organizations: [
    {
      name: "Acme Administração",
      resource_id: "11111111-1111-4111-8111-111111111111",
      resource_type: "organization"
    },
    {
      name: "Edifício Aurora",
      resource_id: "22222222-2222-4222-8222-222222222222",
      resource_type: "organization"
    }
  ],
  personal_workspace: { resource_id: "personal", resource_type: "user" },
  scopes: [
    "profile:read",
    "organizations:read",
    "billings:read",
    "billings:write",
    "expenses:read"
  ]
};

const recoveryCodes: Schemas["RecoveryCodesResponse"] = {
  recovery_codes: ["RECOVERY-ALPHA", "RECOVERY-BRAVO", "RECOVERY-CHARLIE"]
};

export const defaultApiKeys: ApiKeyRecord[] = [
  {
    created_at: "2026-05-20T12:00:00.000Z",
    expires_at: "2026-11-20T12:00:00.000Z",
    grants: [
      { available: true, resource_id: "personal", resource_type: "user" },
      {
        available: true,
        resource_id: "11111111-1111-4111-8111-111111111111",
        resource_type: "organization"
      }
    ],
    hint: "rntv-v1-abcd••••yz",
    last_used_at: "2026-07-15T10:30:00.000Z",
    name: "Painel financeiro",
    revoked_at: null,
    scopes: ["profile:read", "billings:read"],
    uuid: "api-key-e2e"
  }
];

export const emptyBillingList: Schemas["BillingListResponse"] = {
  items: [],
  stats: {
    active_count: 0,
    billed_count: 0,
    expected: 0,
    net_income: 0,
    overdue: 0,
    overdue_count: 0,
    paid_count: 0,
    pending: 0,
    pending_count: 0,
    received: 0,
    total_expenses: 0,
    year: 2026
  },
  user_pix_incomplete: true
};

export const defaultUserTheme: Schemas["ThemeResponse"] = {
  capabilities: { can_edit: true, can_reset: false },
  effective: {
    header_font: "Montserrat",
    primary: "#8A4C94",
    primary_light: "#EEE4F1",
    secondary: "#6EAFAE",
    secondary_dark: "#357B7C",
    text_color: "#282830",
    text_contrast: "#FFFFFF",
    text_font: "Montserrat"
  },
  effective_source: "default",
  owner_name: "Meu Tema",
  options: {
    fonts: [
      "Montserrat",
      "Roboto",
      "Lora",
      "Playfair Display",
      "Open Sans",
      "Source Sans 3",
      "Merriweather",
      "Raleway",
      "Oswald",
      "Nunito"
    ]
  },
  stored: null
};

function clone<T>(value: T): T {
  return structuredClone(value);
}

/** Mirrors the API filling in `default_expiration_days` for an omitted expiration. */
function defaultExpiration(): string {
  const expiration = new Date(TEST_NOW);
  expiration.setUTCDate(expiration.getUTCDate() + apiKeyOptions.default_expiration_days);
  return expiration.toISOString();
}

function grantResponse(grant: Schemas["APIKeyGrantRequest"]): ApiKeyGrant {
  return { ...grant, available: true };
}

function parseBody(value: string | null): unknown {
  if (!value) return null;
  try {
    return JSON.parse(value) as unknown;
  } catch {
    return value;
  }
}

async function fulfillJson(route: Route, body: unknown, status = 200) {
  await route.fulfill({
    body: JSON.stringify(body),
    contentType: "application/json; charset=utf-8",
    headers: { "X-Request-ID": "e2e-request-id" },
    status
  });
}

async function fulfillProblem(route: Route, problem: Schemas["Problem"]) {
  await route.fulfill({
    body: JSON.stringify(problem),
    contentType: "application/problem+json; charset=utf-8",
    status: problem.status
  });
}

async function fulfillAnonymous(route: Route) {
  await fulfillProblem(route, {
    code: "authentication_required",
    detail: "Autenticação necessária.",
    fields: {},
    request_id: "e2e-request-id",
    status: 401,
    title: "Não autenticado",
    type: "https://rentivo.com.br/problems/authentication_required"
  });
}

export async function installApiMocks(
  page: Page,
  options: ApiMockOptions = {}
): Promise<ApiMockState> {
  await page.clock.setFixedTime(new Date(TEST_NOW));
  await page.addInitScript(() => {
    const bytes = Uint8Array.from([1, 2, 3, 4]).buffer;
    const credential = {
      authenticatorAttachment: "platform",
      getClientExtensionResults: () => ({}),
      id: "e2e-passkey-credential",
      rawId: bytes,
      response: {
        attestationObject: bytes,
        clientDataJSON: bytes,
        getTransports: () => ["internal"]
      },
      type: "public-key"
    };
    Object.defineProperty(navigator, "credentials", {
      configurable: true,
      value: {
        create: async () => credential,
        get: async () => credential
      }
    });
  });

  let sessionMode: SessionMode = options.session ?? "authenticated";
  const sessionResponse: Schemas["SessionResponse"] = {
    ...authenticatedResponse,
    bootstrap: {
      ...authenticatedResponse.bootstrap,
      pending_invite_count: options.pendingInviteCount ?? authenticatedResponse.bootstrap.pending_invite_count
    }
  };
  // `POST /auth/login` and `POST /auth/signup` answer with
  // `AuthenticatedResponse`, which carries the `credential_transport`
  // discriminator that `GET /auth/session` does not.
  const loginResponse: Schemas["CookieAuthenticatedResponse"] = {
    ...sessionResponse,
    credential_transport: "cookie"
  };
  let releasePendingSession: (() => void) | undefined;
  const pendingSession = new Promise<void>((resolve) => {
    releasePendingSession = resolve;
  });
  const state: ApiMockState = {
    apiKeys: clone(options.apiKeys ?? defaultApiKeys),
    releaseSession: (mode = "authenticated") => {
      sessionMode = mode;
      releasePendingSession?.();
    },
    requests: [],
    unexpectedRequests: []
  };
  let security = clone(options.security ?? defaultSecuritySummary);

  await page.route("**/api/v1/**", async (route) => {
    const request = route.request();
    const url = new URL(request.url());
    const path = url.pathname.replace(/^\/api\/v1/, "") + url.search;
    const method = request.method();
    const body = parseBody(request.postData());
    state.requests.push({ body, headers: request.headers(), method, path });

    if (path === "/auth/config" && method === "GET") {
      const config: Schemas["AuthConfigResponse"] = {
        ...authConfig,
        feature_flags: {
          ...authConfig.feature_flags,
          google_auth: options.googleAuth ?? authConfig.feature_flags.google_auth
        }
      };
      await fulfillJson(route, config);
      return;
    }
    if (path === "/auth/session" && method === "GET") {
      if (sessionMode === "pending") await pendingSession;
      if (sessionMode === "anonymous") await fulfillAnonymous(route);
      else await fulfillJson(route, sessionResponse);
      return;
    }
    if (path === "/auth/login" && method === "POST") {
      await fulfillJson(route, loginResponse);
      return;
    }
    if (path === "/auth/signup" && method === "POST") {
      await fulfillJson(route, loginResponse);
      return;
    }
    if (path === "/auth/mobile/authorize" && method === "POST") {
      const authorize = body as Schemas["MobileAuthorizationRequest"];
      const authorization: Schemas["MobileAuthorizationResponse"] = {
        authorization_code: "mobile-authorization-code-e2e",
        state: authorize.state
      };
      await fulfillJson(route, authorization, 201);
      return;
    }
    if (path === "/auth/logout" && method === "POST") {
      await route.fulfill({ status: 204 });
      return;
    }
    if (path === "/billings" && method === "GET") {
      await fulfillJson(route, emptyBillingList);
      return;
    }
    if (path === "/organizations" && method === "GET") {
      const organizations: Schemas["OrganizationListResponse"] = { items: [] };
      await fulfillJson(route, organizations);
      return;
    }
    if (path === "/invites" && method === "GET") {
      const invites: Schemas["PendingInviteLoginListResponse"] = { items: [] };
      await fulfillJson(route, invites);
      return;
    }
    if (path === "/themes/user" && method === "GET") {
      await fulfillJson(route, defaultUserTheme);
      return;
    }
    if (path === "/themes/preview" && method === "POST") {
      await route.fulfill({ body: "%PDF-1.4\n%%EOF", contentType: "application/pdf" });
      return;
    }
    if (path === "/security" && method === "GET") {
      await fulfillJson(route, security);
      return;
    }
    if (path === "/security/account-deletion-readiness" && method === "GET") {
      const readiness: Schemas["AccountDeletionReadinessResponse"] = {
        can_delete: true,
        reason: null,
      };
      await fulfillJson(route, readiness);
      return;
    }
    if (path === "/security/pix" && method === "POST") {
      const update = body as Schemas["PixUpdateRequest"];
      security = {
        ...security,
        profile: {
          ...security.profile,
          pix_key: update.pix_key ?? "",
          pix_merchant_name: update.pix_merchant_name ?? "",
          pix_merchant_city: update.pix_merchant_city ?? "",
        },
      };
      const pixUpdate: Schemas["PixUpdateResponse"] = { profile: security.profile };
      await fulfillJson(route, pixUpdate);
      return;
    }
    if (path === "/security/change-password" && method === "POST") {
      await route.fulfill({ status: 204 });
      return;
    }
    if (path === "/security/delete-account" && method === "POST") {
      await route.fulfill({ status: 204 });
      return;
    }
    if (path === "/security/recovery-codes/regenerate" && method === "POST") {
      await fulfillJson(route, recoveryCodes);
      return;
    }
    if (path === "/security/totp/setup" && method === "POST") {
      const setup: Schemas["TOTPSetupResponse"] = {
        provisioning_uri: "otpauth://totp/Rentivo:ana@example.com?issuer=Rentivo",
        qr_code_base64:
          "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=",
        secret: "E2EONLYTOTPSEED"
      };
      await fulfillJson(route, setup);
      return;
    }
    if (path === "/security/totp/confirm" && method === "POST") {
      await fulfillJson(route, recoveryCodes);
      return;
    }
    if (path === "/security/totp/disable" && method === "POST") {
      await route.fulfill({ status: 204 });
      return;
    }
    if (path === "/security/passkeys/register/begin" && method === "POST") {
      const begin: Schemas["PasskeyRegistrationBeginResponse"] = {
        challenge_id: "passkey-challenge-e2e",
        options: {
          challenge: "AQIDBA",
          excludeCredentials: [],
          hints: [],
          pubKeyCredParams: [{ alg: -7, type: "public-key" }],
          rp: { id: "127.0.0.1", name: "Rentivo" },
          user: { displayName: "Ana", id: "AQIDBA", name: "ana@example.com" }
        }
      };
      await fulfillJson(route, begin);
      return;
    }
    if (path === "/security/passkeys/register/complete" && method === "POST") {
      const registration = body as Partial<Schemas["PasskeyRegistrationCompleteRequest"]>;
      const passkey: Schemas["PasskeyResponse"] = {
        created_at: TEST_NOW,
        last_used_at: null,
        name: registration.name ?? "Passkey E2E",
        uuid: "new-passkey-e2e"
      };
      security.passkeys.push(passkey);
      await fulfillJson(route, passkey);
      return;
    }
    if (/^\/security\/passkeys\/[^/]+$/.test(path) && method === "DELETE") {
      await route.fulfill({ status: 204 });
      return;
    }
    if (path === "/api-keys/options" && method === "GET") {
      await fulfillJson(route, apiKeyOptions);
      return;
    }
    if (path === "/api-keys" && method === "GET") {
      const list: Schemas["APIKeyListResponse"] = { items: state.apiKeys };
      await fulfillJson(route, list);
      return;
    }
    if (path === "/api-keys" && method === "POST") {
      const create = body as Schemas["APIKeyCreateRequest"];
      const created: ApiKeyRecord = {
        created_at: TEST_NOW,
        // The client omits `expires_at` when the default expiration is kept,
        // and the API still answers with a concrete expiration.
        expires_at: create.expires_at ?? defaultExpiration(),
        grants: create.grants.map(grantResponse),
        hint: "rntv-v1-e2e0••••ly",
        last_used_at: null,
        name: create.name,
        revoked_at: null,
        scopes: create.scopes,
        uuid: "created-api-key-e2e"
      };
      state.apiKeys.unshift(created);
      const issued: Schemas["APIKeyCreateResponse"] = { ...created, secret: TEST_API_SECRET };
      await fulfillJson(route, issued, 201);
      return;
    }
    const keyMatch = path.match(/^\/api-keys\/([^/?]+)$/);
    if (keyMatch && method === "PATCH") {
      // Every field of `APIKeyUpdateRequest` is optional, and its grants are
      // request grants without the `available` flag the response carries.
      const update = body as Schemas["APIKeyUpdateRequest"];
      const index = state.apiKeys.findIndex((key) => key.uuid === keyMatch[1]);
      if (index === -1) {
        await fulfillProblem(route, {
          code: "not_found",
          detail: "Chave de API não encontrada.",
          fields: {},
          request_id: "e2e-request-id",
          status: 404,
          title: "Não encontrado",
          type: "https://rentivo.com.br/problems/not_found"
        });
        return;
      }
      const current = state.apiKeys[index];
      const updated: ApiKeyRecord = {
        ...current,
        grants: update.grants ? update.grants.map(grantResponse) : current.grants,
        name: update.name ?? current.name,
        scopes: update.scopes ?? current.scopes
      };
      state.apiKeys[index] = updated;
      await fulfillJson(route, updated);
      return;
    }
    if (keyMatch && method === "DELETE") {
      const key = state.apiKeys.find((item) => item.uuid === keyMatch[1]);
      if (key) key.revoked_at = TEST_NOW;
      await route.fulfill({ status: 204 });
      return;
    }

    state.unexpectedRequests.push(`${method} ${path}`);
    await fulfillProblem(route, {
      code: "not_implemented",
      detail: `Unexpected E2E API request: ${method} ${path}`,
      fields: {},
      request_id: "e2e-request-id",
      status: 501,
      title: "Não implementado",
      type: "https://rentivo.com.br/problems/not_implemented"
    });
  });

  return state;
}

export async function settleVisualPage(page: Page) {
  await page.mouse.move(-1, -1);
  await page.addStyleTag({
    content: `
      *, *::before, *::after {
        animation-delay: 0s !important;
        animation-duration: 0s !important;
        caret-color: transparent !important;
        transition-delay: 0s !important;
        transition-duration: 0s !important;
      }
    `
  });
  await page.evaluate(async () => {
    await document.fonts.ready;
    window.scrollTo(0, 0);
  });
}
