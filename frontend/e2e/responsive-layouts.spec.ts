import { readFileSync } from "node:fs";

import { expect, test, type Page } from "@playwright/test";

import { installApiMocks } from "./support/api-mocks";

async function mockJson(page: Page, path: string, body: unknown) {
  await page.route(`**/api/v1${path}`, async (route) => {
    await route.fulfill({
      body: JSON.stringify(body),
      contentType: "application/json; charset=utf-8",
      status: 200
    });
  });
}

async function expectSingleColumn(page: Page, selector: string) {
  const grid = page.locator(selector);
  await expect(grid).toBeVisible();
  await expect.poll(() => grid.evaluate((element) => getComputedStyle(element).gridTemplateColumns.split(" ").length)).toBe(1);
}

test("wide communication workspace breaks out safely at desktop and tablet widths", async ({ page }) => {
  const css = readFileSync(new URL("../src/features/bills/CommunicationComposePage.css", import.meta.url), "utf8");

  for (const width of [1440, 820]) {
    await page.setViewportSize({ height: 900, width });
    await page.setContent(`
      <style>
        * { box-sizing: border-box; }
        html, body { margin: 0; }
        .test-shell { width: min(960px, calc(100% - 3rem)); margin-inline: auto; }
        ${css}
      </style>
      <main class="test-shell"><article class="communication-workspace">Composer</article></main>
    `);

    const dimensions = await page.evaluate(() => {
      const shell = document.querySelector<HTMLElement>(".test-shell")!.getBoundingClientRect();
      const workspace = document.querySelector<HTMLElement>(".communication-workspace")!.getBoundingClientRect();
      return {
        bodyWidth: document.body.scrollWidth,
        clientWidth: document.documentElement.clientWidth,
        shellCenter: shell.left + shell.width / 2,
        shellWidth: shell.width,
        workspaceCenter: workspace.left + workspace.width / 2,
        workspaceWidth: workspace.width
      };
    });

    expect(dimensions.bodyWidth).toBeLessThanOrEqual(dimensions.clientWidth);
    expect(Math.abs(dimensions.workspaceCenter - dimensions.shellCenter)).toBeLessThanOrEqual(1);
    if (width === 1440) expect(dimensions.workspaceWidth).toBeGreaterThan(dimensions.shellWidth);
  }
});

test("status menu items retain a visible keyboard focus ring", async ({ page }) => {
  const css = readFileSync(new URL("../src/styles/custom.css", import.meta.url), "utf8");
  await page.setContent(`<style>${css}</style><button class="status-menu__item">Alterar status</button>`);

  await page.keyboard.press("Tab");
  await expect(page.getByRole("button", { name: "Alterar status" })).toBeFocused();
  const focusStyle = await page.getByRole("button", { name: "Alterar status" }).evaluate((element) => {
    const style = getComputedStyle(element);
    return { outlineStyle: style.outlineStyle, outlineWidth: style.outlineWidth };
  });
  expect(focusStyle.outlineStyle).not.toBe("none");
  expect(Number.parseFloat(focusStyle.outlineWidth)).toBeGreaterThanOrEqual(2);
});

test("security keeps passkey and API-key actions in view on mobile", async ({ isMobile, page }) => {
  test.skip(!isMobile, "Mobile layout regression");
  await installApiMocks(page);
  await page.goto("/security");

  const actions = [
    page.getByRole("button", { name: "Remover Notebook pessoal" }),
    page.getByRole("button", { name: /Editar / }).first(),
    page.getByRole("button", { name: /Revogar / }).first()
  ];
  for (const action of actions) {
    await expect(action).toBeVisible();
    const box = await action.boundingBox();
    expect(box).not.toBeNull();
    expect(box!.x).toBeGreaterThanOrEqual(0);
    expect(box!.x + box!.width).toBeLessThanOrEqual(390);
  }
});

test("populated detail and theme grids collapse to one column on mobile", async ({ isMobile, page }) => {
  test.skip(!isMobile, "Mobile layout regression");
  await installApiMocks(page, { pendingInviteCount: 0 });
  await mockJson(page, "/billings/billing-responsive", {
    capabilities: {
      can_create_bills: true,
      can_create_exports: true,
      can_delete: false,
      can_edit: false,
      can_manage_bills: false,
      can_manage_theme: false,
      can_read_attachments: false,
      can_read_bills: false,
      can_read_expenses: false,
      can_read_theme: false,
      can_transfer: false,
      can_upload_bill_receipts: false,
      can_write_attachments: false,
      can_write_expenses: false
    },
    communication_templates: [],
    created_at: "2026-07-17T15:00:00Z",
    description: "Cobrança responsiva",
    items: [{ amount: 100000, description: "Aluguel", item_type: "fixed", uuid: "item-responsive" }],
    name: "Apartamento responsivo",
    owner: { name: null, type: "user", uuid: null },
    pix_key: "ana@example.com",
    pix_merchant_city: "SAO PAULO",
    pix_merchant_name: "ANA SILVA",
    pix_needs_setup: true,
    recipients: [],
    reply_to: [],
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
    updated_at: "2026-07-17T15:00:00Z",
    uuid: "billing-responsive"
  });
  await mockJson(page, "/organizations/org-responsive", {
    capabilities: {
      can_create_billing: true,
      can_invite: true,
      can_manage: true,
      can_view_billing_stats: false
    },
    created_at: "2026-07-17T15:00:00Z",
    current_role: "admin",
    enforce_mfa: false,
    invites: [],
    members: [{ created_at: null, email: "ana@example.com", is_current_user: true, role: "admin", user_id: 42 }],
    name: "Organização responsiva",
    settings: { pix_key: "ana@example.com", pix_merchant_city: "SAO PAULO", pix_merchant_name: "ANA SILVA" },
    stats: null,
    updated_at: "2026-07-17T15:00:00Z",
    uuid: "org-responsive"
  });

  await page.goto("/billings/billing-responsive");
  await expect(page.getByRole("heading", { name: "Itens da cobrança" })).toBeVisible();
  await expectSingleColumn(page, ".billing-workspace__body");
  const identityBox = await page.locator(".bill-workspace__identity").boundingBox();
  const toolbarBox = await page.locator(".bill-workspace__toolbar").boundingBox();
  expect(identityBox).not.toBeNull();
  expect(toolbarBox).not.toBeNull();
  expect(toolbarBox!.y).toBeGreaterThanOrEqual(identityBox!.y + identityBox!.height - 1);

  await page.goto("/organizations/org-responsive");
  await page.getByRole("tab", { name: "Equipe 1" }).click();
  await expect(page.getByRole("heading", { name: "Pessoas e convites" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Membros" })).toBeVisible();
  await expectSingleColumn(page, ".organization-team__body--managed");

  await page.goto("/themes/user");
  await expect(page.getByRole("heading", { name: "Paleta" })).toBeVisible();
  await expectSingleColumn(page, ".theme-color-list");
});
