import {
  ArrowLeft,
  Check,
  KeyRound,
  LockKeyhole,
  RotateCcw,
  ShieldCheck,
  TriangleAlert
} from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { Link, useNavigate, useSearchParams } from "react-router";

import { apiClient, apiRequest } from "../../lib/api/client";
import { postLoginPath, useAuth } from "./AuthProvider";
import { saveMfaChallenge } from "./authStorage";
import "./GoogleCallbackPage.css";
import { useMobileHandoff } from "./mobileHandoff";

type CallbackPhase = "invalid" | "processing" | "success";

function parseCallback(queryString: string) {
  const query = new URLSearchParams(queryString);
  const code = query.get("code")?.trim() ?? "";
  const error = query.get("error")?.trim() ?? "";
  const state = query.get("state")?.trim() ?? "";
  const hasSingleResult = Boolean(code) !== Boolean(error);

  return { code, error, isValid: Boolean(state) && hasSingleResult, state };
}

function requestCallback(queryString: string) {
  const callback = parseCallback(queryString);
  return apiRequest(
    apiClient.GET("/api/v1/auth/google/callback", {
      params: {
        query: {
          code: callback.code || undefined,
          error: callback.error || undefined,
          state: callback.state
        }
      }
    })
  );
}

export function GoogleCallbackPage() {
  const auth = useAuth();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const callbackQuery = searchParams.toString();
  const callback = parseCallback(callbackQuery);
  const [phase, setPhase] = useState<CallbackPhase>(
    callback.isValid ? "processing" : "invalid"
  );
  const callbackRequest = useRef<{
    promise: ReturnType<typeof requestCallback>;
    query: string;
  } | null>(null);
  const errorRef = useRef<HTMLDivElement>(null);
  const redirectTimer = useRef<number | null>(null);
  const { isHandoff, withHandoff } = useMobileHandoff();

  useEffect(() => {
    document.title =
      phase === "success"
        ? "Acesso confirmado - Rentivo"
        : phase === "invalid"
          ? "Retorno inválido - Rentivo"
          : "Validando acesso - Rentivo";
  }, [phase]);

  useEffect(() => {
    if (phase === "invalid") {
      errorRef.current?.focus();
    }
  }, [phase]);

  useEffect(() => {
    if (!callback.isValid) {
      return;
    }

    if (!callbackRequest.current || callbackRequest.current.query !== callbackQuery) {
      callbackRequest.current = {
        promise: requestCallback(callbackQuery),
        query: callbackQuery
      };
    }

    let cancelled = false;
    const request = callbackRequest.current.promise;
    void request
      .then(({ data }) => {
        if (cancelled) {
          return;
        }
        setPhase("success");
        redirectTimer.current = window.setTimeout(() => {
          if (data.status === "mfa_required") {
            saveMfaChallenge({ challengeId: data.challenge_id, methods: data.methods });
            navigate(`/mfa-verify?challenge=${encodeURIComponent(data.challenge_id)}`, {
              replace: true
            });
            return;
          }
          auth.authenticate(data);
          navigate(postLoginPath(data.bootstrap), { replace: true });
        }, 480);
      })
      .catch(() => {
        if (!cancelled) {
          navigate("/login?error=google_auth_failed", { replace: true });
        }
      });

    return () => {
      cancelled = true;
      if (redirectTimer.current !== null) {
        window.clearTimeout(redirectTimer.current);
      }
    };
  }, [auth, callback.isValid, callbackQuery, navigate]);

  const stepState =
    phase === "success" ? "complete" : phase === "invalid" ? "error" : "active";
  const returnPath = withHandoff("/login?error=google_auth_failed");

  return (
    <div className="google-callback">
      <div className="google-callback__brand" translate="no">
        <span aria-hidden="true" className="google-callback__brand-mark">
          R
        </span>
        <span>
          rent<em>ivo</em>
        </span>
      </div>

      <section
        aria-busy={phase === "processing"}
        aria-labelledby="google-callback-title"
        className={`google-callback__shell google-callback__shell--${phase}`}
      >
        <aside className="google-callback__context">
          <div aria-hidden="true" className="google-callback__context-icon">
            <LockKeyhole size={24} strokeWidth={2.2} />
          </div>
          <div>
            <span className="google-callback__eyebrow">Conexão protegida</span>
            <p className="google-callback__context-title">
              Google e Rentivo, com uma verificação entre eles.
            </p>
            <p>O código de acesso desta página é conferido uma única vez e não expõe sua senha.</p>
          </div>
          <p className="google-callback__privacy">
            <ShieldCheck aria-hidden="true" size={18} strokeWidth={2.2} />
            Seus dados de cobrança continuam protegidos pela sua conta Rentivo.
          </p>
        </aside>

        <div className="google-callback__content">
          {phase === "processing" ? (
            <div aria-atomic="true" aria-live="polite" role="status">
              <div aria-hidden="true" className="google-callback__state-icon is-processing">
                <KeyRound size={27} strokeWidth={2.2} />
              </div>
              <span className="google-callback__phase-label">Retorno recebido</span>
              <h1 id="google-callback-title">Confirmando seu acesso</h1>
              <p>Validando o retorno do Google antes de abrir sua conta.</p>
            </div>
          ) : null}

          {phase === "success" ? (
            <div aria-atomic="true" aria-live="polite" role="status">
              <div aria-hidden="true" className="google-callback__state-icon is-success">
                <Check size={29} strokeWidth={2.5} />
              </div>
              <span className="google-callback__phase-label">Acesso validado</span>
              <h1 id="google-callback-title">Acesso confirmado</h1>
              <p>Tudo certo. Abrindo suas cobranças…</p>
            </div>
          ) : null}

          {phase === "invalid" ? (
            <div ref={errorRef} role="alert" tabIndex={-1}>
              <div aria-hidden="true" className="google-callback__state-icon is-error">
                <TriangleAlert size={27} strokeWidth={2.2} />
              </div>
              <span className="google-callback__phase-label">Retorno incompleto</span>
              <h1 id="google-callback-title">Este retorno não é válido</h1>
              <p>Inicie o acesso com Google novamente para criar uma conexão segura.</p>
              <div className="google-callback__actions">
                {!isHandoff ? (
                  <a className="btn btn--primary" href="/api/v1/auth/google/start">
                    <RotateCcw aria-hidden="true" size={17} strokeWidth={2.2} />
                    Tentar com Google novamente
                  </a>
                ) : null}
                <Link className="google-callback__return" to={returnPath}>
                  <ArrowLeft aria-hidden="true" size={17} strokeWidth={2.2} />
                  Voltar para entrar
                </Link>
              </div>
            </div>
          ) : null}

          <ol aria-label="Progresso do acesso" className="google-callback__steps">
            <li aria-label="Google, concluído" className="is-complete">
              <span aria-hidden="true" className="google-callback__step-mark">
                <Check size={14} strokeWidth={2.6} />
              </span>
              <strong>Google</strong>
            </li>
            <li
              aria-label={`Verificação, ${stepState === "complete" ? "concluída" : stepState === "error" ? "interrompida" : "em andamento"}`}
              className={`is-${stepState}`}
            >
              <span aria-hidden="true" className="google-callback__step-mark">
                {stepState === "complete" ? (
                  <Check size={14} strokeWidth={2.6} />
                ) : stepState === "error" ? (
                  <TriangleAlert size={14} strokeWidth={2.4} />
                ) : (
                  <KeyRound size={14} strokeWidth={2.4} />
                )}
              </span>
              <strong>Verificação</strong>
            </li>
            <li
              aria-label={`Rentivo, ${stepState === "complete" ? "concluído" : "aguardando"}`}
              className={stepState === "complete" ? "is-complete" : "is-pending"}
            >
              <span aria-hidden="true" className="google-callback__step-mark">
                {stepState === "complete" ? <Check size={14} strokeWidth={2.6} /> : null}
              </span>
              <strong>Rentivo</strong>
            </li>
          </ol>
        </div>
      </section>
    </div>
  );
}
