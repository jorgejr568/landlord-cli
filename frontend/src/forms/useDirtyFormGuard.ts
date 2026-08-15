import { createElement, useContext, useEffect } from "react";
import { UNSAFE_DataRouterContext, useBeforeUnload, useBlocker } from "react-router";

const message = "Você tem alterações não salvas. Deseja sair sem salvar?";

function DataRouterBlocker({ isDirty }: { isDirty: boolean }) {
  const blocker = useBlocker(isDirty);

  useEffect(() => {
    if (blocker.state !== "blocked") return;
    if (window.confirm(message)) blocker.proceed();
    else blocker.reset();
  }, [blocker]);

  return null;
}

/** Warn before discarding unsaved parent-form edits; immediate file actions stay outside this draft. */
export function DirtyFormGuard({ isDirty }: { isDirty: boolean }) {
  const dataRouter = useContext(UNSAFE_DataRouterContext);

  useBeforeUnload((event) => {
    if (!isDirty) return;
    event.preventDefault();
    event.returnValue = "";
  });

  return dataRouter ? createElement(DataRouterBlocker, { isDirty }) : null;
}

