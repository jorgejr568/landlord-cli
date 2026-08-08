import { expect, it } from "vitest";

import { multipartBodySerializer } from "./billSupport";

it("serializes all multipart value shapes", () => {
  expect(Array.from((multipartBodySerializer(null) as FormData).entries())).toEqual([]);
  expect(Array.from((multipartBodySerializer("text") as FormData).entries())).toEqual([]);
  const file = new File(["pdf"], "a.pdf", { type: "application/pdf" });
  const form = multipartBodySerializer({ files: [file, "tail"], ignored: undefined, nil: null, payload: "{}" }) as FormData;
  expect(form.getAll("files")).toEqual([file, "tail"]);
  expect(form.get("payload")).toBe("{}");
  expect(form.has("ignored")).toBe(false);
});
