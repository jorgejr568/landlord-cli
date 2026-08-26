import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter, Route, Routes, useLocation } from "react-router";
import { afterEach, expect, it, vi } from "vitest";

import { AUTH_CONFIG, AUTHENTICATED_RESPONSE, jsonResponse } from "../../test/auth";
import { AuthProvider } from "../auth/AuthProvider";
import { RecoveryCodesPage } from "./RecoveryCodesPage";

function LocationProbe() {
  return <span>{useLocation().pathname}</span>;
}

function renderRecovery(
  recoveryCodes?: string[],
  options: { failRefresh?: boolean } = {}
) {
  let sessionRequests = 0;
  vi.stubGlobal("fetch", vi.fn(async (input: RequestInfo | URL) => {
    const url = String(input);
    if (url === "/api/v1/auth/config") return jsonResponse(AUTH_CONFIG);
    if (url === "/api/v1/auth/session") {
      sessionRequests += 1;
      if (options.failRefresh && sessionRequests > 1) throw new Error("offline");
      return jsonResponse(AUTHENTICATED_RESPONSE);
    }
    throw new Error(`Unexpected request: ${url}`);
  }));
  const entry = recoveryCodes
    ? { pathname: "/security/recovery-codes", state: { recoveryCodes } }
    : "/security/recovery-codes";
  return render(
    <MemoryRouter initialEntries={[entry]}>
      <AuthProvider>
        <Routes>
          <Route element={<RecoveryCodesPage />} path="/security/recovery-codes" />
          <Route element={<LocationProbe />} path="/security" />
        </Routes>
      </AuthProvider>
    </MemoryRouter>
  );
}

afterEach(() => vi.unstubAllGlobals());

it("presents one-time codes as a focused storage workspace", () => {
  renderRecovery(["one", "two"]);

  expect(screen.getByRole("heading", { level: 1, name: "Códigos de Recuperação" })).toBeVisible();
  expect(screen.getByText("Visíveis somente agora")).toBeVisible();
  expect(screen.getByRole("list", { name: "Códigos de recuperação" })).toBeVisible();
  expect(screen.getByText("one")).toHaveAttribute("translate", "no");
  expect(screen.getByText("two")).toHaveAttribute("translate", "no");
  expect(screen.getByRole("group", { name: "Opções para guardar os códigos" })).toBeVisible();
  expect(screen.getByRole("button", { name: "Copiar códigos" })).toBeVisible();
  expect(screen.getByRole("button", { name: "Baixar arquivo" })).toBeVisible();
  expect(screen.getByRole("button", { name: "Imprimir códigos" })).toBeVisible();
  expect(screen.getByRole("button", { name: "Concluir e ir para Segurança" })).toBeVisible();
});

it("uses a singular count for one recovery code", () => {
  renderRecovery(["one"]);

  expect(screen.getByText("1 código")).toBeVisible();
});

it("copies one-time recovery codes and announces the result", async () => {
  const user = userEvent.setup();
  const writeText = vi.spyOn(navigator.clipboard, "writeText").mockResolvedValue(undefined);
  renderRecovery(["one", "two"]);

  expect(screen.getByText("one")).toBeVisible();
  await user.click(screen.getByRole("button", { name: "Copiar códigos" }));
  expect(writeText).toHaveBeenCalledWith("one\ntwo");
  expect(screen.getByRole("status")).toHaveTextContent("Códigos copiados. Guarde a cópia em um local seguro.");
  expect(screen.getByRole("button", { name: "Copiar códigos" })).toBeVisible();
});

it("downloads the codes in a private text file", async () => {
  const user = userEvent.setup();
  const createObjectURL = vi.fn((blob: Blob) => {
    void blob;
    return "blob:recovery-codes";
  });
  const revokeObjectURL = vi.fn();
  const click = vi.spyOn(HTMLAnchorElement.prototype, "click").mockImplementation(() => undefined);
  vi.stubGlobal("URL", { ...URL, createObjectURL, revokeObjectURL });
  renderRecovery(["one", "two"]);

  await user.click(screen.getByRole("button", { name: "Baixar arquivo" }));

  expect(createObjectURL).toHaveBeenCalledOnce();
  const blob = createObjectURL.mock.calls[0]?.[0] as Blob;
  expect(blob.type).toBe("text/plain;charset=utf-8");
  expect(click).toHaveBeenCalledOnce();
  expect(revokeObjectURL).toHaveBeenCalledWith("blob:recovery-codes");
  expect(screen.getByRole("status")).toHaveTextContent("Arquivo baixado. Guarde-o em um local protegido.");
});

it("opens the browser print dialog for an offline copy", async () => {
  const user = userEvent.setup();
  const print = vi.spyOn(window, "print").mockImplementation(() => undefined);
  renderRecovery(["one"]);

  await user.click(screen.getByRole("button", { name: "Imprimir códigos" }));

  expect(print).toHaveBeenCalledOnce();
});

it("keeps the codes available when the download cannot start", async () => {
  const user = userEvent.setup();
  const createObjectURL = vi.fn((blob: Blob) => {
    void blob;
    throw new Error("blocked");
  });
  vi.stubGlobal("URL", { ...URL, createObjectURL });
  renderRecovery(["one"]);

  await user.click(screen.getByRole("button", { name: "Baixar arquivo" }));

  expect(await screen.findByRole("alert")).toHaveTextContent(
    "Não foi possível baixar. Copie os códigos ou tente imprimir."
  );
  expect(screen.getByText("one")).toBeVisible();
});

it("returns to security when codes are absent", () => {
  renderRecovery();
  expect(screen.getByText("/security")).toBeVisible();
});

it("warns before a browser reload can discard the one-time codes", () => {
  renderRecovery(["one"]);
  const event = new Event("beforeunload", { cancelable: true });

  window.dispatchEvent(event);

  expect(event.defaultPrevented).toBe(true);
});

it("reports clipboard failures", async () => {
  const user = userEvent.setup();
  vi.spyOn(navigator.clipboard, "writeText").mockRejectedValue(new Error("denied"));
  renderRecovery(["one"]);
  await user.click(screen.getByRole("button", { name: "Copiar códigos" }));
  expect(await screen.findByRole("alert")).toHaveTextContent(
    "Não foi possível copiar. Selecione os códigos ou baixe o arquivo."
  );
});

it("refreshes the session before leaving the one-time screen", async () => {
  const user = userEvent.setup();
  renderRecovery(["one"]);

  await user.click(screen.getByRole("button", { name: "Concluir e ir para Segurança" }));

  await waitFor(() => expect(screen.getByText("/security")).toBeVisible());
});

it("keeps the codes visible and focuses recovery guidance when refresh fails", async () => {
  const user = userEvent.setup();
  renderRecovery(["one"], { failRefresh: true });

  await user.click(screen.getByRole("button", { name: "Concluir e ir para Segurança" }));

  const alert = await screen.findByRole("alert");
  expect(alert).toHaveTextContent("Não foi possível atualizar sua sessão. Seus códigos continuam nesta tela.");
  expect(alert).toHaveFocus();
  expect(screen.getByText("one")).toBeVisible();
  expect(screen.getByRole("button", { name: "Tentar novamente" })).toBeVisible();
});
