import { cleanup, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router";
import { afterEach, expect, it, vi } from "vitest";

import type { components } from "../../lib/api/schema";
import { AttachmentManager } from "./AttachmentManager";

vi.mock("../../components/ConfirmDialog", () => ({
  ConfirmDialog: ({ onConfirm, title }: { onConfirm: () => void; title: string }) => (
    <button onClick={onConfirm} type="button">{`confirm ${title}`}</button>
  )
}));

type Attachment = components["schemas"]["AttachmentResponse"];
const attachment: Attachment = {
  content_type: "application/pdf", created_at: "2026-07-18T12:00:00Z", file_size: 1536,
  filename: "contrato.pdf", name: "Contrato", sort_order: 0, uuid: "attachment-public"
};

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

it("ignores a stray dialog confirmation when no attachment deletion is pending", async () => {
  const user = userEvent.setup();
  const fetchMock = vi.fn();
  vi.stubGlobal("fetch", fetchMock);
  const onChanged = vi.fn();
  const onError = vi.fn();
  render(<MemoryRouter><AttachmentManager attachments={[attachment]} billingUuid="billing-public" canEdit mode="edit" onChanged={onChanged} onError={onError} /></MemoryRouter>);

  await user.click(screen.getByRole("button", { name: "confirm Remover documento?" }));

  expect(fetchMock).not.toHaveBeenCalled();
  expect(onChanged).not.toHaveBeenCalled();
  expect(onError).not.toHaveBeenCalled();
});
