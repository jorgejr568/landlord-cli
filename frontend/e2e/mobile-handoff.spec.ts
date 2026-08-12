import { expect, test } from "@playwright/test";

import { installApiMocks } from "./support/api-mocks";

const GOOGLE_BUTTON = { name: "Continuar com Google" } as const;

// App Store guideline 4.8 rejected Rentivo 1.0.1: the iOS app opens this page
// in ASWebAuthenticationSession, and it offered Google sign-in without an
// equivalent alternative. The website is unaffected — only the pages the app
// can reach must hide it.
test("the website keeps Google sign-in", async ({ page }) => {
  await installApiMocks(page, { googleAuth: true, session: "anonymous" });
  await page.goto("/login");

  await expect(page.getByRole("link", GOOGLE_BUTTON)).toBeVisible();
});

test("the iOS handoff offers no third-party login, including after navigating", async ({
  page
}) => {
  await installApiMocks(page, { googleAuth: true, session: "anonymous" });
  await page.goto("/login?mobile_state=native-state");

  await expect(page.getByLabel("E-mail")).toBeVisible();
  await expect(page.getByRole("link", GOOGLE_BUTTON)).toHaveCount(0);

  // Signup is one tap away and renders its own Google button on the website.
  await page.getByRole("link", { name: "Criar conta" }).click();

  await expect(page).toHaveURL(/\/signup\?mobile_state=native-state$/);
  await expect(page.getByRole("button", { name: "Criar Conta" })).toBeVisible();
  await expect(page.getByRole("link", GOOGLE_BUTTON)).toHaveCount(0);
});

// App Store guideline 2.1a rejected Rentivo: account creation started in the
// app's authentication sheet and ended on the web dashboard, so the user never
// got back to the app. Signing up must finish the mobile authorization.
test("creating an account inside the iOS handoff returns to the app", async ({ page }) => {
  await installApiMocks(page, { googleAuth: true, session: "anonymous" });
  await page.goto("/login?mobile_state=native-state");

  await page.getByRole("link", { name: "Criar conta" }).click();
  await expect(page).toHaveURL(/\/signup\?mobile_state=native-state$/);
  await expect(page.getByRole("button", { name: "Criar Conta" })).toBeVisible();

  await page.getByLabel("E-mail").fill("nova@example.com");
  await page.getByLabel("Senha", { exact: true }).fill("senha-correta");
  await page.getByLabel("Confirmar Senha").fill("senha-correta");
  await page.getByRole("button", { name: "Criar Conta" }).click();

  await expect(page).toHaveURL(/\/login\?mobile_state=native-state$/);
  await expect(page.getByRole("heading", { name: "Tudo pronto" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Voltar para o app agora" })).toBeVisible();
});

test("the gate survives a URL that lost the handoff parameter", async ({ page }) => {
  await installApiMocks(page, { googleAuth: true, session: "anonymous" });
  await page.goto("/login?mobile_state=native-state");
  await expect(page.getByLabel("E-mail")).toBeVisible();

  // Stands in for an untreaded link or an auth page added later: the marker,
  // not the URL, is what keeps Google hidden.
  await page.goto("/signup");

  await expect(page.getByRole("button", { name: "Criar Conta" })).toBeVisible();
  await expect(page.getByRole("link", GOOGLE_BUTTON)).toHaveCount(0);
});
