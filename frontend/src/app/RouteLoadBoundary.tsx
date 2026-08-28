import { Component, Suspense, type ErrorInfo, type ReactNode } from "react";
import { useLocation } from "react-router";

import { RouteSkeleton } from "./RouteSkeleton";

interface RouteLoadBoundaryProps {
  children: ReactNode;
}

type RouteChunkErrorBoundaryProps = RouteLoadBoundaryProps;

interface RouteChunkErrorBoundaryState {
  failed: boolean;
}

class RouteChunkErrorBoundary extends Component<
  RouteChunkErrorBoundaryProps,
  RouteChunkErrorBoundaryState
> {
  state: RouteChunkErrorBoundaryState = { failed: false };

  static getDerivedStateFromError(): RouteChunkErrorBoundaryState {
    return { failed: true };
  }

  componentDidCatch(error: unknown, info: ErrorInfo) {
    console.error("Failed to load route", error, info);
  }

  render() {
    if (this.state.failed) {
      return (
        <div className="empty-state">
          <p role="alert">Não foi possível carregar esta página.</p>
          <a className="btn btn--primary" href={window.location.href}>
            Recarregar página
          </a>
        </div>
      );
    }
    return this.props.children;
  }
}

export function RouteLoadBoundary({ children }: RouteLoadBoundaryProps) {
  const location = useLocation();

  return (
    <RouteChunkErrorBoundary key={location.pathname}>
      <Suspense fallback={<RouteSkeleton pathname={location.pathname} />}>
        {children}
      </Suspense>
    </RouteChunkErrorBoundary>
  );
}
