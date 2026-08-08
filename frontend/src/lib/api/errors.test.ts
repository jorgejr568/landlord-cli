import { expect, it } from "vitest";

import { ApiError } from "./client";
import { errorMessage, firstFieldError, normalizedFieldErrors } from "./errors";

it("normalizes API errors while retaining safe fallbacks", () => {
  const error = new ApiError(new Response(null, { status: 422 }), {
    code: "validation_error",
    detail: "Confira os campos.",
    fields: { "body.subject": "Obrigatório.", plain: "Inválido." }
  });
  expect(errorMessage(error, "fallback")).toBe("Confira os campos.");
  expect(errorMessage(new Error("offline"), "fallback")).toBe("fallback");
  expect(normalizedFieldErrors(error)).toEqual({ plain: "Inválido.", subject: "Obrigatório." });
  expect(normalizedFieldErrors(new Error("offline"))).toEqual({});
  expect(firstFieldError({ body: "x", subject: "x" }, ["subject"])).toBe("subject");
  expect(firstFieldError({ body: "x" }, ["subject"])).toBe("body");
  expect(firstFieldError({}, ["subject"])).toBeUndefined();
});
