import { readFileSync } from "node:fs";
import path from "node:path";

import { expect, test } from "@playwright/test";

import { defaultSecuritySummary, installApiMocks } from "./support/api-mocks";

test("updates PIX and password, then reveals regenerated recovery codes once", async ({ page }) => {
  const api = await installApiMocks(page);
  await page.goto("/security");
  await expect(page.getByRole("heading", { name: "Segurança" })).toBeVisible();

  await page.getByLabel("Chave PIX").fill("financeiro@example.com");
  await page.getByLabel("Nome do recebedor").fill("FINANCEIRO ACME");
  await page.getByLabel("Cidade do recebedor").fill("CAMPINAS");
  await page.getByRole("button", { name: "Salvar Dados PIX" }).click();
  await expect(page.getByRole("status")).toContainText("Dados do PIX atualizados.");

  await page.getByLabel("Senha atual").fill("current-password-e2e");
  await page.getByLabel("Nova senha", { exact: true }).fill("new-password-e2e");
  await page.getByLabel("Confirmar nova senha").fill("new-password-e2e");
  await page.getByRole("button", { name: "Alterar Senha" }).click();
  await expect(page.getByRole("status")).toContainText("Senha alterada com sucesso!");
  await expect(page.getByLabel("Senha atual")).toHaveValue("");

  await page.getByRole("button", { name: "Regenerar Códigos de Recuperação" }).click();
  await expect(page).toHaveURL(/\/security\/recovery-codes$/);
  await expect(
    page.getByRole("heading", { exact: true, name: "Códigos de Recuperação" })
  ).toBeVisible();
  await expect(page.getByText("RECOVERY-ALPHA")).toBeVisible();

  const pix = api.requests.find((request) => request.path === "/security/pix");
  expect(pix?.body).toEqual({
    pix_key: "financeiro@example.com",
    pix_merchant_city: "CAMPINAS",
    pix_merchant_name: "FINANCEIRO ACME"
  });
  expect(api.requests.some((request) => request.path === "/security/change-password")).toBe(true);
  expect(api.unexpectedRequests).toEqual([]);
});

test("completes TOTP setup and registers a passkey through browser credentials", async ({ page }) => {
  const security = {
    ...defaultSecuritySummary,
    passkeys: [],
    totp: { enabled: false, recovery_codes_remaining: 0 }
  };
  const api = await installApiMocks(page, { security });
  await page.goto("/security");

  await page.getByRole("link", { name: "Configurar TOTP" }).click();
  await expect(page.getByRole("img", { name: "QR Code TOTP" })).toBeVisible();
  await page.getByLabel("Código de verificação").fill("123456");
  await page.getByRole("button", { name: "Confirmar e Ativar" }).click();
  await expect(page.getByText("RECOVERY-BRAVO")).toBeVisible();

  await page.getByRole("button", { name: "Continuar" }).click();
  await page.getByLabel("Nome da passkey").fill("Celular E2E");
  await page.getByRole("button", { name: "Adicionar Passkey" }).click();
  await expect(page.getByRole("status")).toContainText("Passkey cadastrada.");
  await expect(page.getByText("Celular E2E")).toBeVisible();

  const registration = api.requests.find(
    (request) => request.path === "/security/passkeys/register/complete"
  );
  expect(registration?.body).toMatchObject({
    challenge_id: "passkey-challenge-e2e",
    name: "Celular E2E"
  });
  expect(api.unexpectedRequests).toEqual([]);
});

test("deletes the account and returns to the login screen", async ({ page }) => {
  const api = await installApiMocks(page);
  await page.goto("/security");
  await expect(page.getByRole("heading", { name: "Segurança" })).toBeVisible();

  await page.getByRole("button", { name: "Excluir conta" }).click();
  await page.getByLabel("Confirme sua senha para excluir a conta").fill("current-password-e2e");
  await page.getByRole("button", { name: "Excluir minha conta permanentemente" }).click();

  await expect(page).toHaveURL(/\/login$/);

  const deletion = api.requests.find((request) => request.path === "/security/delete-account");
  expect(deletion?.body).toEqual({ password: "current-password-e2e" });
  expect(api.requests.some((request) => request.path === "/auth/logout")).toBe(true);
  expect(api.unexpectedRequests).toEqual([]);
});

// The default Playwright projects run against the Vite dev server, which never
// serves the production nginx headers. These tests lock the committed nginx
// source instead; frontend/e2e/production-stack.spec.ts asserts the live
// headers against the real image.

const SECURITY_HEADERS_INCLUDE = "include /etc/nginx/rentivo-security-headers.conf;";

const ENFORCED_CSP = "base-uri 'none'; object-src 'none'; frame-ancestors 'none'; form-action 'self'";

const REPORT_ONLY_CSP_DIRECTIVES = [
  "default-src 'self'",
  "base-uri 'none'",
  "object-src 'none'",
  "frame-ancestors 'none'",
  "form-action 'self'",
  "script-src 'self' https://www.googletagmanager.com https://challenges.cloudflare.com",
  "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
  "font-src 'self' https://fonts.gstatic.com",
  "img-src 'self' data: https://www.googletagmanager.com https://*.google-analytics.com",
  "connect-src 'self' https://www.googletagmanager.com https://challenges.cloudflare.com https://*.google-analytics.com https://*.analytics.google.com https://stats.g.doubleclick.net",
  "frame-src 'self' blob: https://challenges.cloudflare.com"
];

function readNginxFile(name: string): string {
  const frontendRoot = path.resolve(path.dirname(test.info().file), "..");
  return readFileSync(path.join(frontendRoot, "nginx", name), "utf8");
}

function withoutComments(config: string): string {
  return config
    .split("\n")
    .filter((line) => !line.trimStart().startsWith("#"))
    .join("\n");
}

function locationBlocks(config: string): string[] {
  const blocks: string[] = [];
  let start = config.indexOf("location ");
  while (start >= 0) {
    let depth = 0;
    for (let cursor = config.indexOf("{", start); cursor < config.length; cursor += 1) {
      if (config[cursor] === "{") depth += 1;
      if (config[cursor] === "}") {
        depth -= 1;
        if (depth === 0) {
          blocks.push(config.slice(start, cursor + 1));
          break;
        }
      }
    }
    start = config.indexOf("location ", start + 1);
  }
  return blocks;
}

test("declares the baseline security headers unconditionally", () => {
  const snippet = readNginxFile("security-headers.conf");

  expect(snippet).toContain(`add_header Content-Security-Policy "${ENFORCED_CSP}" always;`);
  expect(snippet).toContain('add_header X-Content-Type-Options "nosniff" always;');
  expect(snippet).toContain('add_header X-Frame-Options "DENY" always;');
  expect(snippet).toContain('add_header Referrer-Policy "strict-origin-when-cross-origin" always;');

  const reportOnly = /add_header Content-Security-Policy-Report-Only "([^"]+)" always;/.exec(snippet);
  expect(reportOnly, "The report-only policy must stay on one quoted line.").not.toBeNull();
  REPORT_ONLY_CSP_DIRECTIVES.forEach((directive) => {
    expect(reportOnly![1]).toContain(directive);
  });

  // "always" keeps every header on error responses, such as the /assets/ 404.
  const headerLines = snippet
    .split("\n")
    .filter((line) => line.trimStart().startsWith("add_header"));
  expect(headerLines).toHaveLength(5);
  headerLines.forEach((line) => expect(line.trimEnd().endsWith("always;")).toBe(true));
});

test("repeats the security-header include in every nginx block that answers a request", () => {
  const config = withoutComments(readNginxFile("default.conf"));

  // Nginx discards the whole inherited add_header set as soon as a block
  // declares an add_header of its own, so a server-level include is not
  // enough: "location /assets/" and "location = /index.html" both set
  // Cache-Control and would otherwise drop every security header. The
  // try_files fallback in "location /" internally redirects to /index.html,
  // so the exact-match block serves every client-side route.
  const blocks = locationBlocks(config);
  expect(blocks).toHaveLength(3);
  blocks.forEach((block) => expect(block).toContain(SECURITY_HEADERS_INCLUDE));

  expect(config.slice(0, config.indexOf("location "))).toContain(SECURITY_HEADERS_INCLUDE);
  expect(config.split(SECURITY_HEADERS_INCLUDE).length - 1).toBe(4);
});
