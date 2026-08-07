import { createContext, useContext, useMemo, type ReactNode } from "react";
import { useSearchParams } from "react-router";

const HANDOFF_STORAGE_KEY = "rentivo.auth.mobile_handoff";

export interface MobileHandoff {
  /**
   * Whether the current page is being displayed inside the iOS app's
   * authentication sheet. Sticky for the lifetime of the tab: it stays true
   * once `mobile_state` has been seen, even after navigating to a page whose
   * URL no longer carries the parameter.
   *
   * Only ever used to hide UI. App Store guideline 4.8 forbids offering a
   * third-party login service without an equivalent alternative, so the
   * dangerous failure is showing Google when it should be hidden. Reading a
   * sticky marker makes an untreaded link or a future auth page fail safe.
   */
  isHandoff: boolean;
  /**
   * Appends `mobile_state` to `path` when the *current URL* carries it.
   *
   * Deliberately does not fall back to the stored value. A stale state
   * threaded onto a link would make LoginPage request a mobile authorization
   * the app is no longer waiting on, which surfaces a misleading success
   * screen. Losing link threading is cosmetic; threading a stale state is not.
   */
  withHandoff: (path: string) => string;
}

const NO_HANDOFF: MobileHandoff = {
  isHandoff: false,
  withHandoff: (path) => path
};

const MobileHandoffContext = createContext<MobileHandoff>(NO_HANDOFF);

function readStoredHandoff(): boolean {
  try {
    return sessionStorage.getItem(HANDOFF_STORAGE_KEY) !== null;
  } catch {
    return false;
  }
}

function storeHandoff() {
  try {
    sessionStorage.setItem(HANDOFF_STORAGE_KEY, "1");
  } catch {
    // A storage-less browser still gets URL-based detection. Degrading the
    // gate is acceptable; breaking the auth page is not.
  }
}

export function MobileHandoffProvider({ children }: { children: ReactNode }) {
  const [searchParams] = useSearchParams();
  const mobileState = searchParams.get("mobile_state");

  const value = useMemo<MobileHandoff>(() => {
    if (mobileState) {
      storeHandoff();
    }
    return {
      isHandoff: Boolean(mobileState) || readStoredHandoff(),
      withHandoff: (path: string) => {
        if (!mobileState) {
          return path;
        }
        const separator = path.includes("?") ? "&" : "?";
        return `${path}${separator}mobile_state=${encodeURIComponent(mobileState)}`;
      }
    };
  }, [mobileState]);

  return (
    <MobileHandoffContext.Provider value={value}>{children}</MobileHandoffContext.Provider>
  );
}

// eslint-disable-next-line react-refresh/only-export-components
export function useMobileHandoff(): MobileHandoff {
  return useContext(MobileHandoffContext);
}
