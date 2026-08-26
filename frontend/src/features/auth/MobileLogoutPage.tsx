import {
  ArrowRight,
  Check,
  LogOut,
  RefreshCw,
  ShieldCheck,
  Smartphone,
  TriangleAlert,
  type LucideIcon
} from "lucide-react";
import { useCallback, useEffect, useRef, useState, type ReactNode } from "react";
import { useSearchParams } from "react-router";

import { ApiError, apiClient, apiRequest } from "../../lib/api/client";
import { useAuth } from "./AuthProvider";
import { openMobileAuthorizationCallback } from "./mobileAuthorization";
import "./MobileLogoutPage.css";

type LogoutPhase = "checking" | "complete" | "failed" | "logging-out";
type LogoutView = "checking" | "complete" | "invalid" | "logout-failed" | "session-failed";
type ProgressStep = "app" | "logout" | "session";
type StepState = "complete" | "current" | "error" | "upcoming";

const STEPS: { icon: LucideIcon; id: ProgressStep; label: string }[] = [
  { icon: ShieldCheck, id: "session", label: "Confirmar sessão" },
  { icon: LogOut, id: "logout", label: "Encerrar no navegador" },
  { icon: Smartphone, id: "app", label: "Voltar ao app" }
];

export function MobileLogoutPage() {
  const { retrySession, status } = useAuth();
  const [searchParams] = useSearchParams();
  const mobileState = searchParams.get("state");
  const [attempt, setAttempt] = useState(0);
  const [phase, setPhase] = useState<LogoutPhase>("checking");
  const startedAttempt = useRef(-1);

  const returnToApp = useCallback(() => {
    openMobileAuthorizationCallback(
      `rentivo://auth/logout?state=${encodeURIComponent(mobileState!)}`
    );
  }, [mobileState]);

  useEffect(() => {
    document.title = "Sair - Rentivo";
  }, []);

  useEffect(() => {
    if (!mobileState || status === "error" || status === "loading") {
      return;
    }
    // Logging out clears the session, so `status` changes while this flow runs. Each attempt
    // must run exactly once: re-entering would return to the app a second time.
    if (startedAttempt.current === attempt) {
      return;
    }
    startedAttempt.current = attempt;
    let active = true;
    setPhase("logging-out");
    void (async () => {
      if (status === "authenticated") {
        try {
          await apiRequest(apiClient.POST("/api/v1/auth/logout"));
        } catch (caught: unknown) {
          if (!(caught instanceof ApiError && caught.status === 401)) {
            if (active) {
              setPhase("failed");
            }
            return;
          }
        }
      }
      if (active) {
        setPhase("complete");
        returnToApp();
      }
    })();
    return () => {
      active = false;
    };
  }, [attempt, mobileState, returnToApp, status]);

  const view: LogoutView = !mobileState
    ? "invalid"
    : status === "error"
      ? "session-failed"
      : phase === "failed"
        ? "logout-failed"
        : phase === "complete"
          ? "complete"
          : "checking";
  const workingStep: ProgressStep = phase === "logging-out" ? "logout" : "session";

  if (view === "invalid") {
    return (
      <LogoutPanel
        icon={TriangleAlert}
        progressError="session"
        tone="danger"
        title="Link de saída inválido"
        view={view}
      >
        <p className="mobile-logout__message" role="alert">
          Volte ao app Rentivo e inicie a saída novamente.
        </p>
      </LogoutPanel>
    );
  }

  if (view === "session-failed") {
    return (
      <LogoutPanel
        icon={TriangleAlert}
        progressError="session"
        tone="danger"
        title="Não foi possível confirmar sua sessão"
        view={view}
      >
        <p className="mobile-logout__message" role="alert">
          Não foi possível verificar a sessão do site. Confira sua conexão e tente novamente.
        </p>
        <button className="btn btn--primary mobile-logout__action" onClick={retrySession} type="button">
          <RefreshCw aria-hidden="true" size={18} />
          Verificar novamente
        </button>
      </LogoutPanel>
    );
  }

  if (view === "logout-failed") {
    return (
      <LogoutPanel
        icon={TriangleAlert}
        progressError="logout"
        tone="danger"
        title="Não foi possível concluir a saída"
        view={view}
      >
        <p className="mobile-logout__message" role="alert">
          Sua sessão continua ativa neste navegador. Confira sua conexão e tente outra vez.
        </p>
        <button
          className="btn btn--primary mobile-logout__action"
          onClick={() => setAttempt((value) => value + 1)}
          type="button"
        >
          <RefreshCw aria-hidden="true" size={18} />
          Tentar sair novamente
        </button>
      </LogoutPanel>
    );
  }

  if (view === "complete") {
    return (
      <LogoutPanel icon={ShieldCheck} tone="success" title="Sessão encerrada" view={view}>
        <p className="mobile-logout__message" role="status">
          A sessão deste navegador foi encerrada com segurança. Você já pode continuar no app
          Rentivo.
        </p>
        <button
          className="btn btn--primary mobile-logout__action"
          onClick={returnToApp}
          type="button"
        >
          Voltar para o app agora
          <ArrowRight aria-hidden="true" size={18} />
        </button>
      </LogoutPanel>
    );
  }

  const checkingSession = status === "loading" || phase === "checking";
  return (
    <LogoutPanel
      icon={checkingSession ? ShieldCheck : LogOut}
      title="Saindo do Rentivo"
      view={view}
      workingStep={workingStep}
    >
      <p aria-live="polite" className="mobile-logout__message" role="status">
        {checkingSession
          ? "Confirmando sua sessão neste navegador…"
          : "Encerrando a sessão deste navegador…"}
      </p>
    </LogoutPanel>
  );
}

function LogoutPanel({
  children,
  icon: StateIcon,
  progressError,
  title,
  tone = "working",
  view,
  workingStep = "session"
}: {
  children: ReactNode;
  icon: LucideIcon;
  progressError?: ProgressStep;
  title: string;
  tone?: "danger" | "success" | "working";
  view: LogoutView;
  workingStep?: ProgressStep;
}) {
  const headingRef = useRef<HTMLHeadingElement>(null);
  const isBusy = view === "checking";

  useEffect(() => {
    if (!isBusy) {
      headingRef.current?.focus();
    }
  }, [isBusy, view]);

  return (
    <section
      aria-busy={isBusy}
      aria-label="Saída segura"
      className="mobile-logout"
      role="region"
    >
      <div className="mobile-logout__shell">
        <header className="mobile-logout__header">
          <div className="mobile-logout__brand" translate="no">
            <span aria-hidden="true" className="mobile-logout__brand-mark">R</span>
            <span>rent<em>ivo</em></span>
          </div>
          <span className="mobile-logout__context">
            <ShieldCheck aria-hidden="true" size={16} />
            Saída segura
          </span>
        </header>

        <LogoutProgress errorStep={progressError} view={view} workingStep={workingStep} />

        <div className="mobile-logout__body">
          <span aria-hidden="true" className={`mobile-logout__state mobile-logout__state--${tone}`}>
            <StateIcon size={28} strokeWidth={2.25} />
          </span>
          <h1 id="mobile-logout-title" ref={headingRef} tabIndex={-1}>
            {title}
          </h1>
          {children}
        </div>

        <footer className="mobile-logout__footer">
          <ShieldCheck aria-hidden="true" size={17} />
          <span>O retorno usa o vínculo seguro iniciado pelo app.</span>
        </footer>
      </div>
    </section>
  );
}

function LogoutProgress({
  errorStep,
  view,
  workingStep
}: {
  errorStep?: ProgressStep;
  view: LogoutView;
  workingStep: ProgressStep;
}) {
  const currentStep: ProgressStep = view === "complete" ? "app" : workingStep;
  const currentIndex = STEPS.findIndex(({ id }) => id === currentStep);

  function stateFor(step: ProgressStep, index: number): StepState {
    if (step === errorStep) {
      return "error";
    }
    if (index < currentIndex) {
      return "complete";
    }
    return index === currentIndex ? "current" : "upcoming";
  }

  return (
    <ol aria-label="Progresso da saída" className="mobile-logout__progress">
      {STEPS.map(({ icon: StepIcon, id, label }, index) => {
        const stepState = stateFor(id, index);
        return (
          <li
            aria-current={stepState === "current" || stepState === "error" ? "step" : undefined}
            data-state={stepState}
            key={id}
          >
            <span aria-hidden="true" className="mobile-logout__step-icon">
              {stepState === "complete" ? <Check size={16} /> : <StepIcon size={16} />}
            </span>
            <span>{label}</span>
          </li>
        );
      })}
    </ol>
  );
}
