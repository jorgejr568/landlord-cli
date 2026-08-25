import type { components } from "../../lib/api/schema";

type Transition = components["schemas"]["AvailableTransitionResponse"];

export interface LifecycleStage {
  id: string;
  label: string;
  state: "complete" | "current" | "future";
}

export interface LifecycleModel {
  branch?: LifecycleStage;
  stages: LifecycleStage[];
}

const STAGES = [
  { id: "draft", label: "Rascunho" },
  { id: "published", label: "Publicado" },
  { id: "sent", label: "Enviado" },
  { id: "paid", label: "Pago" }
] as const;

const NEXT_TARGET: Record<string, string | undefined> = {
  cancelled: "draft",
  delayed_payment: "paid",
  draft: "published",
  published: "sent",
  sent: "paid"
};

export function groupBillTransitions(status: string, transitions: Transition[]) {
  const destructive = transitions.filter((transition) => transition.target === "cancelled" || transition.style === "danger");
  const safe = transitions.filter((transition) => !destructive.includes(transition));
  const primary = safe.find((transition) => transition.target === NEXT_TARGET[status]);
  return {
    destructive,
    primary,
    secondary: safe.filter((transition) => transition !== primary)
  };
}

export function modelBillLifecycle(status: string): LifecycleModel {
  if (status === "cancelled") {
    return { branch: { id: "cancelled", label: "Cancelado", state: "current" }, stages: [] };
  }

  const canonicalStatus = status === "delayed_payment" ? "sent" : status;
  const currentIndex = STAGES.findIndex((stage) => stage.id === canonicalStatus);
  const stages: LifecycleStage[] = STAGES.map((stage, index) => ({
    ...stage,
    state: currentIndex < 0 ? "future" : index < currentIndex ? "complete" : index === currentIndex ? "current" : "future"
  }));
  if (status === "delayed_payment") {
    stages[2] = { ...stages[2], state: "complete" };
    return {
      branch: { id: "delayed_payment", label: "Pagamento atrasado", state: "current" },
      stages
    };
  }
  if (currentIndex < 0) {
    return { branch: { id: status, label: status, state: "current" }, stages };
  }
  return { stages };
}
