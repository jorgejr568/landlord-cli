import "@testing-library/jest-dom/vitest";

const NativeRequest = globalThis.Request;

class CompatibleNavigationRequest extends NativeRequest {
  constructor(input: RequestInfo | URL, init?: RequestInit) {
    const compatibleInit = { ...init };
    delete compatibleInit.signal;
    super(input, compatibleInit);
  }
}

globalThis.Request = CompatibleNavigationRequest;

// jsdom does not implement the pointer/scroll APIs used by Radix overlays.
if (typeof HTMLElement !== "undefined") {
  Object.defineProperties(HTMLElement.prototype, {
    hasPointerCapture: { configurable: true, value: () => false },
    releasePointerCapture: { configurable: true, value: () => undefined },
    scrollIntoView: { configurable: true, value: () => undefined },
    setPointerCapture: { configurable: true, value: () => undefined }
  });
}
