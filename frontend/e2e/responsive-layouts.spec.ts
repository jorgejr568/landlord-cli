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

test("theme contrast icon remains centered inside its status circle", async ({ page }) => {
  const css = readFileSync(new URL("../src/features/themes/ThemePage.css", import.meta.url), "utf8");
  await page.setContent(`
    <style>${css}</style>
    <div class="theme-contrast">
      <span class="theme-contrast__icon">
        <svg viewBox="0 0 24 24" width="15" height="15" aria-hidden="true">
          <path d="m5 12 4 4L19 6"></path>
        </svg>
      </span>
      <div class="theme-contrast__copy">
        <strong>Contraste aprovado</strong><span>5,2:1 entre a cor primária e o texto.</span>
      </div>
    </div>
  `);

  const alignment = await page.locator(".theme-contrast__icon").evaluate((element) => {
    const circle = element.getBoundingClientRect();
    const icon = element.querySelector("svg")!.getBoundingClientRect();
    return {
      x: icon.x + icon.width / 2 - (circle.x + circle.width / 2),
      y: icon.y + icon.height / 2 - (circle.y + circle.height / 2)
    };
  });

  expect(Math.abs(alignment.x)).toBeLessThanOrEqual(0.5);
  expect(Math.abs(alignment.y)).toBeLessThanOrEqual(0.5);
});

test("organization wizard rail stays connected to its stage at every breakpoint", async ({ isMobile, page }) => {
  const css = readFileSync(new URL("../src/features/organizations/OrganizationCreatePage.css", import.meta.url), "utf8");
  await page.setContent(`
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <style>
      * { box-sizing: border-box; }
      html, body { margin: 0; }
      .wizard { display: grid; align-items: start; }
      ${css}
    </style>
    <form class="organization-create-form">
      <div class="wizard">
        <nav class="wizard__rail">
          <div class="wizard-progress">Etapa 1 de 3</div>
          <ol class="wizard-steps"><li>Identidade</li><li>Recebimento PIX</li><li>Revisão</li></ol>
        </nav>
        <section class="wizard__stage">
          <header class="wizard__stage-head">Identidade</header>
          <div class="wizard__content">Nome da organização</div>
          <footer class="wizard__actions">Continuar</footer>
        </section>
      </div>
    </form>
  `);

  const edges = await page.locator(".wizard").evaluate((wizard) => {
    const rail = wizard.querySelector(".wizard__rail")!.getBoundingClientRect();
    const stage = wizard.querySelector(".wizard__stage")!.getBoundingClientRect();
    return {
      railBottom: rail.bottom,
      railLeft: rail.left,
      railRight: rail.right,
      stageBottom: stage.bottom,
      stageLeft: stage.left,
      stageRight: stage.right,
      stageTop: stage.top
    };
  });

  if (isMobile) {
    expect(Math.abs(edges.railLeft - edges.stageLeft)).toBeLessThanOrEqual(1);
    expect(Math.abs(edges.railRight - edges.stageRight)).toBeLessThanOrEqual(1);
    expect(edges.railBottom).toBeLessThanOrEqual(edges.stageTop + 1);
  } else {
    expect(Math.abs(edges.railBottom - edges.stageBottom)).toBeLessThanOrEqual(1);
  }
});

test("communication wizard columns reach the same connected bottom edge", async ({ page }) => {
  const sharedCss = readFileSync(new URL("../src/styles/custom.css", import.meta.url), "utf8");
  const pageCss = readFileSync(new URL("../src/features/bills/CommunicationComposePage.css", import.meta.url), "utf8");
  await page.setViewportSize({ height: 900, width: 1440 });
  await page.setContent(`
    <style>* { box-sizing: border-box; } html, body { margin: 0; } ${sharedCss} ${pageCss}</style>
    <form class="communication-compose-form" style="width: 1180px;">
      <div class="wizard wizard--with-aside">
        <nav class="wizard__rail"><div class="wizard-progress">Etapa 1 de 3</div></nav>
        <section class="wizard__stage">
          <header class="wizard__stage-head">Destinatários</header>
          <div class="wizard__content" style="min-height: 420px;">Selecione quem receberá o documento.</div>
          <footer class="wizard__actions">Continuar</footer>
        </section>
        <aside class="wizard__aside"><section class="wizard-summary">Prévia da mensagem</section></aside>
      </div>
    </form>
  `);

  const edges = await page.locator(".communication-compose-form .wizard").evaluate((wizard) => {
    const rail = wizard.querySelector(".wizard__rail")!.getBoundingClientRect();
    const stage = wizard.querySelector(".wizard__stage")!.getBoundingClientRect();
    const preview = wizard.querySelector(".wizard__aside")!.getBoundingClientRect();
    return { previewBottom: preview.bottom, railBottom: rail.bottom, stageBottom: stage.bottom };
  });

  expect(Math.abs(edges.railBottom - edges.stageBottom)).toBeLessThanOrEqual(1);
  expect(Math.abs(edges.previewBottom - edges.stageBottom)).toBeLessThanOrEqual(1);
});

test("bill action menu escapes the invoice shell without leaving the viewport", async ({ page }) => {
  const css = readFileSync(new URL("../src/styles/custom.css", import.meta.url), "utf8");
  await page.setViewportSize({ height: 710, width: 1120 });
  await page.setContent(`
    <style>* { box-sizing: border-box; } html, body { margin: 0; } ${css}</style>
    <main style="padding: 42px 24px; width: 100%;">
      <article class="bill-workspace bill-workspace--menu-open" style="height: 560px;">
        <section class="bill-workspace__control-strip">
          <div></div><div></div>
          <div class="bill-workspace__toolbar">
            <div class="btn-dropdown bill-action-menu open">
              <button class="btn btn--sm btn-dropdown-toggle">Ações</button>
              <div class="btn-dropdown-menu">
                ${Array.from({ length: 13 }, (_, index) => `<button class="status-menu__item">Ação ${index + 1}</button>`).join("")}
              </div>
            </div>
          </div>
        </section>
      </article>
    </main>
  `);

  const layout = await page.locator(".bill-action-menu .btn-dropdown-menu").evaluate((menu) => {
    const box = menu.getBoundingClientRect();
    const workspace = menu.closest(".bill-workspace")!;
    const style = getComputedStyle(menu);
    return {
      bottom: box.bottom,
      menuOverflowY: style.overflowY,
      viewportHeight: document.documentElement.clientHeight,
      workspaceOverflow: getComputedStyle(workspace).overflow
    };
  });
  expect(layout.workspaceOverflow).toBe("visible");
  expect(layout.menuOverflowY).toBe("auto");
  expect(layout.bottom).toBeLessThanOrEqual(layout.viewportHeight);
});

test("bill action menu can flip above a trigger near the bottom edge", async ({ page }) => {
  const css = readFileSync(new URL("../src/styles/custom.css", import.meta.url), "utf8");
  await page.setViewportSize({ height: 420, width: 1120 });
  await page.setContent(`
    <style>* { box-sizing: border-box; } html, body { margin: 0; } ${css}</style>
    <div class="btn-dropdown bill-action-menu open" style="position: fixed; right: 24px; bottom: 12px;">
      <button class="btn btn--sm btn-dropdown-toggle">Ações</button>
      <div class="btn-dropdown-menu" data-placement="top" style="--bill-action-menu-space: 330px;">
        ${Array.from({ length: 8 }, (_, index) => `<button class="status-menu__item">Ação ${index + 1}</button>`).join("")}
      </div>
    </div>
  `);

  const trigger = await page.getByRole("button", { name: "Ações" }).boundingBox();
  const menu = await page.locator(".bill-action-menu .btn-dropdown-menu").boundingBox();
  expect(trigger).not.toBeNull();
  expect(menu).not.toBeNull();
  expect(menu!.y + menu!.height).toBeLessThanOrEqual(trigger!.y);
  expect(menu!.y).toBeGreaterThanOrEqual(0);
});

test("receipt rail uses a compact list without horizontal scrolling", async ({ page }) => {
  const css = readFileSync(new URL("../src/styles/custom.css", import.meta.url), "utf8");
  await page.setViewportSize({ height: 710, width: 390 });
  await page.setContent(`
    <style>* { box-sizing: border-box; } html, body { margin: 0; } ${css}</style>
    <section class="receipt-manager" style="width: 342px; padding: 16px;">
      <div class="table-wrap receipt-list">
        <table class="table data-table"><thead><tr><th></th><th>Arquivo</th><th class="num">Tamanho</th><th></th></tr></thead>
          <tbody><tr class="receipt-row">
            <td class="receipt-row__handle"><button class="drag-handle">::</button></td>
            <td class="table__primary receipt-row__file">Nubank_2026-08-03_comprovante-muito-longo.pdf</td>
            <td class="num receipt-row__size">39.6 KB</td>
            <td class="receipt-row__actions"><a class="btn btn--sm">Ver</a><button class="btn btn--sm btn--danger">Remover</button></td>
          </tr></tbody>
        </table>
      </div>
      <form class="receipt-upload-form"><button class="btn btn--sm btn--primary receipt-upload-submit">Enviar comprovantes</button></form>
      <div class="receipt-feedback toast toast--success">1 comprovante anexado.</div>
    </section>
  `);

  for (const width of [342, 453]) {
    await page.locator(".receipt-manager").evaluate((manager, nextWidth) => {
      (manager as HTMLElement).style.width = `${nextWidth}px`;
    }, width);
    const layout = await page.locator(".receipt-manager").evaluate((manager) => {
      const row = manager.querySelector(".receipt-row")!;
      const actions = manager.querySelector(".receipt-row__actions")!.getBoundingClientRect();
      const managerBox = manager.getBoundingClientRect();
      const submit = manager.querySelector(".receipt-upload-submit")!.getBoundingClientRect();
      const feedback = manager.querySelector(".receipt-feedback")!.getBoundingClientRect();
      return {
        actionsRight: actions.right,
        feedbackGap: feedback.top - submit.bottom,
        managerRight: managerBox.right,
        managerScrollWidth: manager.scrollWidth,
        managerWidth: manager.clientWidth,
        rowDisplay: getComputedStyle(row).display
      };
    });
    expect(layout.managerScrollWidth).toBeLessThanOrEqual(layout.managerWidth);
    expect(layout.actionsRight).toBeLessThanOrEqual(layout.managerRight);
    expect(layout.feedbackGap).toBeGreaterThanOrEqual(12);
    expect(layout.rowDisplay).toBe("grid");
  }
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
