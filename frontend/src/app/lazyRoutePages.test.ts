import { expect, it } from "vitest";

import { routePageLoaders as ROUTE_PAGE_LOADERS } from "./routePageLoaders";

it("resolves every code-split route to a renderable page component", async () => {
  const loadedPages = await Promise.all(
    Object.entries(ROUTE_PAGE_LOADERS).map(async ([name, load]) => ({
      module: await load(),
      name
    }))
  );

  expect(loadedPages.length).toBeGreaterThan(20);
  for (const { module, name } of loadedPages) {
    expect(module.default, `${name} must expose a default route component`).toBeTypeOf("function");
    expect(module.default.name, `${name} must resolve its matching named export`).toBe(name);
  }
});
