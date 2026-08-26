import { Check, ChevronLeft, ChevronRight } from "lucide-react";
import { useEffect, useRef, type ReactNode } from "react";

export interface WizardStep {
  description?: string;
  id: string;
  label: string;
}

interface FormWizardProps {
  activeStep: number;
  aside?: ReactNode;
  busy?: boolean;
  busyLabel?: string;
  cancelAction?: ReactNode;
  children: ReactNode;
  finalLabel: string;
  onBack: () => void;
  onNext: () => void;
  onStepChange: (step: number) => void;
  steps: WizardStep[];
  visitedStep: number;
}

function defaultBusyLabel(label: string): string {
  if (label.startsWith("Criar")) return "Criando…";
  if (label.startsWith("Gerar")) return "Gerando…";
  if (label.startsWith("Enviar")) return "Enviando…";
  if (label.startsWith("Salvar")) return "Salvando…";
  return "Processando…";
}

export function FormWizard({
  activeStep,
  aside,
  busy = false,
  busyLabel,
  cancelAction,
  children,
  finalLabel,
  onBack,
  onNext,
  onStepChange,
  steps,
  visitedStep
}: FormWizardProps) {
  const headingRef = useRef<HTMLHeadingElement>(null);
  const previousStep = useRef(activeStep);
  const isFinalStep = activeStep === steps.length - 1;
  const step = steps[activeStep];

  useEffect(() => {
    if (previousStep.current !== activeStep) headingRef.current?.focus({ preventScroll: true });
    previousStep.current = activeStep;
  }, [activeStep]);

  return (
    <div className={`wizard${aside ? " wizard--with-aside" : ""}`}>
      <nav aria-label="Etapas do formulário" className="wizard__rail">
        <div aria-live="polite" className="wizard-progress">
          <span>Etapa {activeStep + 1} de {steps.length}</span>
          <div aria-hidden="true" className="wizard-progress__track">
            {steps.map((item, index) => <i className={index <= activeStep ? "is-reached" : ""} key={item.id} />)}
          </div>
        </div>
        <ol className="wizard-steps">
          {steps.map((item, index) => {
            const state = index < activeStep ? "complete" : index === activeStep ? "current" : "future";
            const reached = index <= visitedStep;
            const content = (
              <>
                <span aria-hidden="true" className="wizard-step__mark">
                  {state === "complete" ? <Check size={15} strokeWidth={3} /> : index + 1}
                </span>
                <span className="wizard-step__copy">
                  <strong>{item.label}</strong>
                  {item.description ? <small>{item.description}</small> : null}
                </span>
              </>
            );
            return (
              <li className="wizard-step" data-state={state} key={item.id}>
                {reached ? (
                  <button
                    aria-current={index === activeStep ? "step" : undefined}
                    onClick={() => onStepChange(index)}
                    type="button"
                  >
                    {content}
                  </button>
                ) : <div>{content}</div>}
              </li>
            );
          })}
        </ol>
      </nav>

      <section className="wizard__stage" key={step.id}>
        <header className="wizard__stage-head">
          <span className="wizard__eyebrow">Etapa {activeStep + 1}</span>
          <h2 className="wizard__stage-title" ref={headingRef} tabIndex={-1}>{step.label}</h2>
          {step.description ? <p>{step.description}</p> : null}
        </header>
        <div className="wizard__content">{children}</div>
        <footer className="wizard__actions">
          <div>{activeStep === 0 ? cancelAction : (
            <button className="btn" disabled={busy} onClick={onBack} type="button">
              <ChevronLeft aria-hidden="true" size={16} /> Voltar
            </button>
          )}</div>
          {isFinalStep ? (
            <button className="btn btn--primary" disabled={busy} type="submit">
              {busy ? (busyLabel ?? defaultBusyLabel(finalLabel)) : finalLabel}
            </button>
          ) : (
            <button className="btn btn--primary" disabled={busy} onClick={onNext} type="button">
              Continuar <ChevronRight aria-hidden="true" size={16} />
            </button>
          )}
        </footer>
      </section>

      {aside ? <div className="wizard__aside">{aside}</div> : null}
    </div>
  );
}

interface WizardSummaryProps {
  children: ReactNode;
  title: string;
}

export function WizardSummary({ children, title }: WizardSummaryProps) {
  return (
    <aside aria-label={title} className="wizard-summary">
      <span className="wizard-summary__eyebrow">Acompanhe enquanto preenche</span>
      <h3>{title}</h3>
      <div className="wizard-summary__body">{children}</div>
    </aside>
  );
}

interface WizardReviewRowProps {
  label: string;
  onEdit?: () => void;
  value: ReactNode;
}

export function WizardReviewRow({ label, onEdit, value }: WizardReviewRowProps) {
  return (
    <div className="review-row">
      <div>
        <dt>{label}</dt>
        <dd>{value}</dd>
      </div>
      {onEdit ? <button className="review-row__edit" onClick={onEdit} type="button">Editar <span className="sr-only">{label}</span></button> : null}
    </div>
  );
}
