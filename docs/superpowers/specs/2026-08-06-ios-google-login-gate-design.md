# Hiding Google sign-in from the iOS authentication handoff

## Background

App Review rejected Rentivo 1.0.1 (submission `4704506a-a030-44e9-ad93-167ce3fd12ce`,
reviewed 2026-08-05) under guideline 4.8, Login Services:

> The app uses a third-party login service, but does not appear to offer as an
> equivalent login option another login service with all of the following
> features.

The iOS app has no login form of its own. `LoginView` shows a single "Entrar"
button that opens `ASWebAuthenticationSession` against
`https://rentivo.com.br/login?mobile_state=<state>`, and the resulting web page
renders a "Continuar com Google" button whenever the `google_auth` feature flag
is on. Production returns `google_auth: true`, so the reviewer saw a
third-party login service inside the app.

Guideline 4.8 applies only to apps that offer a third-party login service. An
app that uses exclusively the developer's own account system is exempt.
Removing every Google affordance from the pages reachable inside the
authentication sheet therefore resolves the rejection without adding Sign in
with Apple.

## Goals

- No Google affordance is reachable from inside the iOS authentication sheet,
  on any page, now or after future changes to the auth flow.
- The website keeps Google sign-in unchanged for browser users, including
  mobile browsers.
- No backend, OpenAPI, or iOS changes.

## Non-goals

- Native email/password login in the app. The backend already supports it
  (`credential_transport: "body"` on `/auth/login`, body-transport MFA
  challenges), but replacing the web handoff is a larger change and is not
  required to clear 4.8.
- Sign in with Apple. Not needed once no third-party login service is offered.
- Special handling for Google-provisioned users. They are created with
  `password_hash=""` by `UserService.register_google_user`, so email/password
  login fails for them with the existing generic invalid-credentials error.
  This is accepted for now.

## Design

### Handoff context

A new module `frontend/src/features/auth/mobileHandoff.tsx` exports
`MobileHandoffProvider` and `useMobileHandoff()`.

The provider reads `mobile_state` from the URL on mount. When present it
records a sticky marker in `sessionStorage` under `rentivo.auth.mobile_handoff`,
matching the existing `rentivo.auth.*` keys in `authStorage.ts`. The hook
returns:

- `isHandoff: boolean` — true when the current URL carries `mobile_state` or
  the sticky marker is set.
- `withHandoff(path: string): string` — appends `mobile_state` to `path` when
  the **current URL** carries it.

The provider mounts in `PublicAuthLayout` (`frontend/src/app/router.tsx`),
which already wraps every anonymous route: login, signup, MFA verify, forgot
and reset password, mobile logout, privacy, terms, and support. One mount point
covers the entire surface reachable inside the sheet, including routes added
later.

`useMobileHandoff()` returns a non-handoff default when no provider is mounted,
so component tests that render a page in isolation keep working.

### Why the marker is sticky but the parameter is not

`isHandoff` is sticky because its only job is to hide UI, and the dangerous
failure is showing Google when it should be hidden. Reading it from
`sessionStorage` means a page that loses `mobile_state` — a refresh, a link
that was not threaded, a route added in future work — still hides Google.
The gate fails safe.

`withHandoff` deliberately does **not** fall back to the stored value. It
appends only what the current URL carries. A stale `mobile_state` threaded onto
a link would drive `LoginPage` to call `/auth/mobile/authorize` for an
authorization the app is no longer waiting on. The app validates the state in
`MobileWebAuthenticationFlow.authorizationCode`, so a stale code is rejected
rather than honoured, but the user would still see a misleading "Tudo pronto"
screen. Losing link threading is a cosmetic degradation; threading a stale
state is a broken flow.

For the same reason `LoginPage` keeps reading `mobile_state` from
`useSearchParams()` for the authorization flow itself. The sticky marker gates
presentation only and never feeds the authorization request.

### The gate

`LoginPage` and `SignupPage` currently duplicate the same markup: an inline
"ou" divider followed by `<GoogleAuthLink />`, both wrapped in a
`config.feature_flags.google_auth` check. Nulling out only the link would leave
an orphaned divider above nothing.

A new `GoogleAuthOption` component in `AuthComponents.tsx` owns the divider and
the link together and gates itself on both inputs:

```tsx
export function GoogleAuthOption({ enabled }: { enabled: boolean }) {
  const { isHandoff } = useMobileHandoff();
  if (!enabled || isHandoff) {
    return null;
  }
  // divider + <GoogleAuthLink />
}
```

The `enabled` prop carries `config.feature_flags.google_auth`, matching how
`<Turnstile enabled={...} />` already receives its flag. Both pages render
`<GoogleAuthOption enabled={config.feature_flags.google_auth} />` with no
surrounding conditional, which removes the duplicated divider markup.

Putting the handoff check inside the component is what makes the gate fail
safe: there is no call site left to forget. `GoogleAuthLink` stays exported as
the presentational button so its existing tests keep their subject.

### Link threading

`withHandoff` is applied to the links that currently drop the parameter:

| Page | Link |
| --- | --- |
| `LoginPage` | `/signup`, `/forgot-password` |
| `SignupPage` | `/login` |
| `ForgotPasswordPage` | `/login` |

The login-to-MFA hop already threads `mobile_state` and is left alone.

### Error handling

`sessionStorage` access is wrapped so a throwing implementation (Safari private
browsing in some configurations) degrades to URL-only detection instead of
breaking the login screen. A degraded gate is acceptable; a crashing auth page
is not.

## Testing

- Unit tests for the provider and hook: sticky marker set from the URL,
  `isHandoff` true after the parameter is gone, non-handoff default with no
  provider, `withHandoff` appending and omitting, and the `sessionStorage`
  failure path.
- Unit tests for `GoogleAuthOption`: renders divider and link when enabled and
  not in handoff; renders nothing when the flag is off; renders nothing in
  handoff mode even with the flag on.
- A route-walking regression test that renders every anonymous auth route in
  handoff mode and asserts no element with
  `href="/api/v1/auth/google/start"` exists. The route group carries an
  exported `PUBLIC_AUTH_ROUTE_ID`, so the test discovers its paths from the
  route table rather than a hand-written list and a new auth page is covered
  automatically. It runs with `google_auth: true`, matching production, and
  asserts alongside that the website itself still shows Google. A companion
  assertion fails if the route group is renamed or emptied, so the sweep
  cannot silently pass with nothing to check. This test, not the gate itself,
  is what prevents a repeat rejection.
- A mocked Playwright spec for the handoff flow, covering the website keeping
  Google, the handoff hiding it across a navigation, and the sticky marker
  holding on a URL that lost the parameter. `frontend/e2e/` has no
  `mobile_state` coverage today. The mock harness gains a `googleAuth` option,
  since it currently hardcodes the flag off and could not exercise the gate.

The repository's 100 percent frontend coverage gate applies to all new code.

## App Review response

Shipping the change is not sufficient on its own. Apple asked for a written
reply identifying the qualifying login service. The reply states that the app
uses only Rentivo's own email and password account system, that no third-party
login service is reachable from within the app, and that the app therefore
falls under the guideline 4.8 exemption for apps using exclusively the
developer's own account setup.

## Out of scope, tracked separately

The same rejection raised guideline 2.3.3 for the 6.5-inch iPhone screenshots.
That is App Store Connect metadata with no code component and is handled as
separate work.
