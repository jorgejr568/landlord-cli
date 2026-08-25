import { cleanup, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, expect, it, vi } from "vitest";

import { FormWizard, WizardReviewRow, WizardSummary } from "./FormWizard";

afterEach(cleanup);

const steps = [
  { description: "Identifique a cobrança", id: "details", label: "Essenciais" },
  { description: "Defina os valores", id: "items", label: "Itens" },
  { description: "Confira antes de salvar", id: "review", label: "Revisão" }
];

it("exposes current progress and only lets users revisit reached steps", async () => {
  const user = userEvent.setup();
  const onStepChange = vi.fn();

  render(
    <FormWizard
      activeStep={1}
      finalLabel="Criar cobrança"
      onBack={vi.fn()}
      onNext={vi.fn()}
      onStepChange={onStepChange}
      steps={steps}
      visitedStep={1}
    >
      <p>Campos dos itens</p>
    </FormWizard>
  );

  expect(screen.getByText("Etapa 2 de 3")).toBeVisible();
  expect(screen.getByRole("button", { name: /Essenciais/ })).toBeEnabled();
  expect(screen.getByRole("button", { name: /Itens/ })).toHaveAttribute("aria-current", "step");
  expect(screen.queryByRole("button", { name: /Revisão/ })).not.toBeInTheDocument();
  expect(screen.getByText("Revisão").closest("li")).toHaveAttribute("data-state", "future");

  await user.click(screen.getByRole("button", { name: /Essenciais/ }));
  expect(onStepChange).toHaveBeenCalledWith(0);
});

it("uses back, continue, and final actions without submitting intermediate steps", async () => {
  const user = userEvent.setup();
  const onBack = vi.fn();
  const onNext = vi.fn();
  const onSubmit = vi.fn((event: React.FormEvent) => event.preventDefault());
  const view = render(
    <form onSubmit={onSubmit}>
      <FormWizard
        activeStep={1}
        busy={false}
        cancelAction={<a href="/cancel">Cancelar</a>}
        finalLabel="Criar cobrança"
        onBack={onBack}
        onNext={onNext}
        onStepChange={vi.fn()}
        steps={steps}
        visitedStep={1}
      >
        <p>Campos</p>
      </FormWizard>
    </form>
  );

  await user.click(screen.getByRole("button", { name: "Voltar" }));
  await user.click(screen.getByRole("button", { name: "Continuar" }));
  expect(onBack).toHaveBeenCalledOnce();
  expect(onNext).toHaveBeenCalledOnce();
  expect(onSubmit).not.toHaveBeenCalled();
  expect(screen.queryByRole("link", { name: "Cancelar" })).not.toBeInTheDocument();

  view.rerender(
    <form onSubmit={onSubmit}>
      <FormWizard
        activeStep={2}
        busy
        finalLabel="Criar cobrança"
        onBack={onBack}
        onNext={onNext}
        onStepChange={vi.fn()}
        steps={steps}
        visitedStep={2}
      >
        <p>Revisão</p>
      </FormWizard>
    </form>
  );
  expect(screen.getByRole("button", { name: "Criando..." })).toBeDisabled();

  view.rerender(
    <form onSubmit={onSubmit}>
      <FormWizard
        activeStep={2}
        finalLabel="Criar cobrança"
        onBack={onBack}
        onNext={onNext}
        onStepChange={vi.fn()}
        steps={steps}
        visitedStep={2}
      >
        <p>Revisão</p>
      </FormWizard>
    </form>
  );
  await user.click(screen.getByRole("button", { name: "Criar cobrança" }));
  expect(onSubmit).toHaveBeenCalledOnce();
});

it("focuses the active step heading after progression and renders contextual summaries", () => {
  const { rerender } = render(
    <FormWizard
      activeStep={0}
      aside={<WizardSummary title="Resumo"><span>Total R$ 1.000,00</span></WizardSummary>}
      finalLabel="Salvar"
      onBack={vi.fn()}
      onNext={vi.fn()}
      onStepChange={vi.fn()}
      steps={steps}
      visitedStep={0}
    >
      <p>Detalhes</p>
    </FormWizard>
  );

  rerender(
    <FormWizard
      activeStep={1}
      aside={<WizardSummary title="Resumo"><span>Total R$ 1.000,00</span></WizardSummary>}
      finalLabel="Salvar"
      onBack={vi.fn()}
      onNext={vi.fn()}
      onStepChange={vi.fn()}
      steps={steps}
      visitedStep={1}
    >
      <WizardReviewRow label="Imóvel" onEdit={vi.fn()} value="Apartamento 302" />
    </FormWizard>
  );

  expect(screen.getByRole("heading", { name: "Itens" })).toHaveFocus();
  expect(screen.getByRole("complementary", { name: "Resumo" })).toHaveTextContent("Total R$ 1.000,00");
  expect(screen.getByText("Apartamento 302")).toBeVisible();
  expect(screen.getByRole("button", { name: "Editar Imóvel" })).toBeVisible();
});
