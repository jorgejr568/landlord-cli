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
