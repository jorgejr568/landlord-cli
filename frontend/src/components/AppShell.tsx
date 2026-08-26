import type { ReactNode } from "react";
import { Outlet } from "react-router";

import { ToastRegion, type Toast } from "./ToastRegion";
import { Topbar } from "./Topbar";

export interface AppShellProps {
  children?: ReactNode;
  currentPath?: string;
  currentUser?: { email: string };
  onLogout?: () => void;
  pendingInviteCount?: number;
  toasts?: Toast[];
}

export function AppShell({
  children,
  currentPath,
  currentUser,
  onLogout,
  pendingInviteCount = 0,
  toasts = []
}: AppShellProps) {
  return (
    <>
      <a className="skip-link" href="#main-content">Pular para o conteúdo principal</a>
      {currentUser ? (
        <Topbar
          currentPath={currentPath}
          currentUser={currentUser}
          onLogout={onLogout}
          pendingInviteCount={pendingInviteCount}
        />
      ) : null}
      <main className="wrapper main-content" id="main-content" tabIndex={-1}>
        <ToastRegion toasts={toasts} />
        {children ?? <Outlet />}
      </main>
    </>
  );
}
