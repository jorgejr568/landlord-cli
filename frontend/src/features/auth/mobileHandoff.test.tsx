import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { afterEach, describe, expect, it, vi } from "vitest";

import { MobileHandoffProvider, useMobileHandoff } from "./mobileHandoff";

function Probe() {
  const { isHandoff, withHandoff } = useMobileHandoff();
  return (
    <>
      <output data-testid="handoff">{String(isHandoff)}</output>
      <output data-testid="plain">{withHandoff("/signup")}</output>
      <output data-testid="query">{withHandoff("/signup?next=1")}</output>
    </>
  );
}

function renderProbe(path: string) {
  return render(
    <MemoryRouter initialEntries={[path]}>
      <MobileHandoffProvider>
        <Probe />
      </MobileHandoffProvider>
    </MemoryRouter>
  );
}

afterEach(() => {
  sessionStorage.clear();
  vi.restoreAllMocks();
});

describe("mobile handoff", () => {
  it("stays inactive for ordinary browser visits", () => {
    renderProbe("/login");

    expect(screen.getByTestId("handoff")).toHaveTextContent("false");
    expect(screen.getByTestId("plain")).toHaveTextContent("/signup");
  });

  it("activates from the URL and threads the state onto links", () => {
    renderProbe("/login?mobile_state=native%2Fstate");

    expect(screen.getByTestId("handoff")).toHaveTextContent("true");
    expect(screen.getByTestId("plain")).toHaveTextContent("/signup?mobile_state=native%2Fstate");
    expect(screen.getByTestId("query")).toHaveTextContent(
      "/signup?next=1&mobile_state=native%2Fstate"
    );
  });

  it("stays active after navigating to a URL without the parameter", () => {
    renderProbe("/login?mobile_state=native-state").unmount();

    // A page the app can reach whose link was never threaded: the gate must
    // still hide Google, because guideline 4.8 is about what the app offers.
    renderProbe("/signup");

    expect(screen.getByTestId("handoff")).toHaveTextContent("true");
    // The parameter is gone, so there is nothing to thread. Threading a stale
    // state would be worse than not threading at all.
    expect(screen.getByTestId("plain")).toHaveTextContent("/signup");
  });

  it("degrades to URL-only detection when session storage cannot be read", () => {
    vi.spyOn(Storage.prototype, "getItem").mockImplementation(() => {
      throw new Error("storage disabled");
    });

    renderProbe("/login");

    expect(screen.getByTestId("handoff")).toHaveTextContent("false");
  });

  it("still activates from the URL when session storage cannot be written", () => {
    vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
      throw new Error("storage disabled");
    });

    renderProbe("/login?mobile_state=native-state");

    expect(screen.getByTestId("handoff")).toHaveTextContent("true");
  });

  it("defaults to inactive when no provider is mounted", () => {
    render(
      <MemoryRouter initialEntries={["/login?mobile_state=native-state"]}>
        <Probe />
      </MemoryRouter>
    );

    expect(screen.getByTestId("handoff")).toHaveTextContent("false");
    expect(screen.getByTestId("plain")).toHaveTextContent("/signup");
  });
});
