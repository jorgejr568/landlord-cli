import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

function source(relativePath: string): string {
  return readFileSync(new URL(relativePath, import.meta.url), "utf8");
}

describe("shared interface consistency contracts", () => {
  it("uses explicit accessible foreground, placeholder, radius, and shadow tokens", () => {
    const css = source("./custom.css");

    expect(css).toContain("--foreground-muted:");
    expect(css).toContain("--foreground-placeholder:");
    expect(css).toContain("--radius-control:");
    expect(css).toContain("--shadow-raised:");
    expect(css).toContain("color: var(--foreground-placeholder)");
  });

  it("retains mobile table headers in the accessibility tree", () => {
    const invites = source("../features/invites/InviteListPage.css");
    const organization = source("../features/organizations/OrganizationDetailPage.css");

    expect(invites).not.toMatch(/\.invite-ledger__table thead\s*{\s*display:\s*none;/);
    expect(invites).toContain("clip-path: inset(50%)");
    expect(organization).not.toMatch(/\.organization-billing-table thead\s*{\s*display:\s*none;/);
    expect(organization).toContain("clip-path: inset(50%)");
  });

  it("removes nested short-viewport composer scroll traps", () => {
    const css = source("../features/bills/CommunicationComposePage.css");

    expect(css).not.toContain("height: clamp(540px, calc(100dvh - 380px), 650px)");
    expect(css).not.toContain("min-height: 580px");
    expect(css).toContain(".communication-compose-form .wizard__content {\n  flex: 1;\n  overflow: visible;");
  });

  it("centers the wide communication workspace without transform-based viewport overflow", () => {
    const css = source("../features/bills/CommunicationComposePage.css");

    expect(css).not.toContain("margin-inline: 50%");
    expect(css).not.toContain("transform: translateX(-50%)");
    expect(css).toContain("calc((100% - min(1280px, calc(100vw - 3.5rem))) / 2)");
  });

  it("gives status-menu actions a visible keyboard focus indicator", () => {
    const css = source("./custom.css");
    const focusRule = /\.status-menu__item:focus-visible\s*{([^}]*)}/s.exec(css);

    expect(focusRule?.[1]).toMatch(/outline:\s*[2-9]px solid var\(--accent\)/);
    expect(focusRule?.[1]).toContain("outline-offset:");
  });

  it("keeps security table actions sticky and visible on narrow screens", () => {
    const css = source("../features/security/SecurityPage.css");
    const mobile = css.slice(css.indexOf("@media (max-width: 700px)"));

    expect(mobile).toMatch(/\.security-passkey-table th:last-child,[\s\S]*\.security-passkey-table td:last-child[^{]*{[^}]*position:\s*sticky;[^}]*right:\s*0;/);
    expect(mobile).toMatch(/\.api-key-table th:last-child,[\s\S]*\.api-key-table td:last-child[^{]*{[^}]*position:\s*sticky;[^}]*right:\s*0;/);
  });

  it("disables shared dialog and menu motion when reduced motion is requested", () => {
    const css = source("./custom.css");
    const reducedMotion = css.slice(css.lastIndexOf("@media (prefers-reduced-motion: reduce)"));

    expect(reducedMotion).toContain(".modal-overlay");
    expect(reducedMotion).toContain(".modal");
    expect(reducedMotion).toContain(".status-menu__panel");
    expect(reducedMotion).toContain("animation: none");
  });

  it("keeps shared monetary columns tabular and unbroken", () => {
    const css = source("./custom.css");

    expect(css).toMatch(/\.table \.num, \.data-table \.num \{[^}]*white-space: nowrap;/s);
  });
});
