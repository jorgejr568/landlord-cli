import { expect, it } from "vitest";

import { receiptFileError } from "./receiptFiles";

it("validates every receipt file constraint before upload", () => {
  expect(receiptFileError([new File(["x"], "nota.txt", { type: "text/plain" })]))
    .toBe("O arquivo nota.txt deve ser PDF, JPEG ou PNG.");
  expect(receiptFileError([new File([], "vazio.pdf", { type: "application/pdf" })]))
    .toBe("O arquivo vazio.pdf está vazio.");
  expect(receiptFileError([new File([new Uint8Array(10 * 1024 * 1024 + 1)], "grande.pdf", { type: "application/pdf" })]))
    .toBe("O arquivo grande.pdf excede o limite de 10 MB.");
  expect(receiptFileError([new File(["x"], "nota.pdf", { type: "application/pdf" })])).toBeNull();
});
