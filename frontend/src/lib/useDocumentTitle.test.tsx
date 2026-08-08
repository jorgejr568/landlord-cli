import { render } from "@testing-library/react";
import { afterEach, expect, it } from "vitest";

import { useDocumentTitle } from "./useDocumentTitle";

afterEach(() => {
  document.title = "";
});

function TitleProbe({ title }: { title: string }) {
  useDocumentTitle(title);
  return null;
}

it("updates and restores the page title across rerenders", () => {
  document.title = "Anterior";
  const view = render(<TitleProbe title="Primeiro" />);
  expect(document.title).toBe("Primeiro");
  view.rerender(<TitleProbe title="Segundo" />);
  expect(document.title).toBe("Segundo");
  view.unmount();
  expect(document.title).toBe("Anterior");
});

it("skips the title restore when no previous title could be captured", () => {
  const written: string[] = [];
  Object.defineProperty(document, "title", {
    configurable: true,
    get: () => null as unknown as string,
    set: (value: string) => { written.push(value); }
  });
  try {
    const view = render(<TitleProbe title="Primeiro" />);
    expect(written).toEqual(["Primeiro"]);
    view.unmount();
    expect(written).toEqual(["Primeiro"]);
  } finally {
    Reflect.deleteProperty(document, "title");
  }
});
