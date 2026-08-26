import { Check, CircleAlert } from "lucide-react";

import { modelBillLifecycle } from "./billLifecycle";

export function BillLifecycle({ status }: { status: string }) {
  const lifecycle = modelBillLifecycle(status);

  return (
    <section aria-label="Progresso da fatura" className="bill-lifecycle">
      {lifecycle.stages.length > 0 ? (
        <ol className="bill-lifecycle__track">
          {lifecycle.stages.map((stage, index) => (
            <li data-state={stage.state} key={stage.id}>
              <span aria-hidden="true" className="bill-lifecycle__mark">
                {stage.state === "complete" ? <Check size={15} strokeWidth={3} /> : index + 1}
              </span>
              <span>{stage.label}</span>
            </li>
          ))}
        </ol>
      ) : null}
      {lifecycle.branch ? (
        <div className={`bill-lifecycle__branch bill-lifecycle__branch--${lifecycle.branch.id}`} data-state={lifecycle.branch.state}>
          <CircleAlert aria-hidden="true" size={17} />
          <span>{lifecycle.branch.label}</span>
        </div>
      ) : null}
    </section>
  );
}
