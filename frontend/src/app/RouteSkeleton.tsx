type RouteSkeletonVariant = "auth" | "collection" | "detail" | "landing";

interface SkeletonBlockProps {
  className: string;
}

function SkeletonBlock({ className }: SkeletonBlockProps) {
  return <span aria-hidden="true" className={`route-skeleton__block ${className}`} />;
}

function routeSkeletonVariant(pathname: string): RouteSkeletonVariant {
  if (pathname === "/") return "landing";
  if (
    /^\/(?:auth\/google\/callback|forgot-password|login|mfa-verify|reset-password|signup)\/?$/.test(
      pathname
    )
  ) {
    return "auth";
  }
  if (/^\/(?:billings|invites|organizations)\/?$/.test(pathname)) return "collection";
  return "detail";
}

function LandingSkeleton() {
  return (
    <div aria-hidden="true" className="route-skeleton__landing">
      <div className="route-skeleton__landing-copy">
        <SkeletonBlock className="route-skeleton__eyebrow" />
        <SkeletonBlock className="route-skeleton__title route-skeleton__title--wide" />
        <SkeletonBlock className="route-skeleton__title route-skeleton__title--medium" />
        <SkeletonBlock className="route-skeleton__line route-skeleton__line--wide" />
        <SkeletonBlock className="route-skeleton__line route-skeleton__line--medium" />
        <SkeletonBlock className="route-skeleton__button" />
      </div>
      <div className="route-skeleton__preview">
        <SkeletonBlock className="route-skeleton__preview-head" />
        <SkeletonBlock className="route-skeleton__preview-card" />
        <SkeletonBlock className="route-skeleton__preview-card" />
        <SkeletonBlock className="route-skeleton__preview-row" />
      </div>
    </div>
  );
}

function AuthSkeleton() {
  return (
    <div aria-hidden="true" className="route-skeleton__auth-card">
      <SkeletonBlock className="route-skeleton__eyebrow" />
      <SkeletonBlock className="route-skeleton__title route-skeleton__title--medium" />
      <SkeletonBlock className="route-skeleton__line route-skeleton__line--wide" />
      <div className="route-skeleton__fields">
        <SkeletonBlock className="route-skeleton__field" />
        <SkeletonBlock className="route-skeleton__field" />
      </div>
      <SkeletonBlock className="route-skeleton__button route-skeleton__button--full" />
    </div>
  );
}

function CollectionSkeleton() {
  return (
    <div aria-hidden="true" className="route-skeleton__collection">
      <div className="route-skeleton__head">
        <div>
          <SkeletonBlock className="route-skeleton__eyebrow" />
          <SkeletonBlock className="route-skeleton__title route-skeleton__title--medium" />
        </div>
        <SkeletonBlock className="route-skeleton__button" />
      </div>
      <div className="route-skeleton__metrics">
        <SkeletonBlock className="route-skeleton__metric" />
        <SkeletonBlock className="route-skeleton__metric" />
        <SkeletonBlock className="route-skeleton__metric" />
      </div>
      <div className="route-skeleton__rows">
        <SkeletonBlock className="route-skeleton__row" />
        <SkeletonBlock className="route-skeleton__row" />
        <SkeletonBlock className="route-skeleton__row" />
        <SkeletonBlock className="route-skeleton__row" />
      </div>
    </div>
  );
}

function DetailSkeleton() {
  return (
    <div aria-hidden="true" className="route-skeleton__detail">
      <SkeletonBlock className="route-skeleton__breadcrumb" />
      <div className="route-skeleton__head">
        <div>
          <SkeletonBlock className="route-skeleton__title route-skeleton__title--wide" />
          <SkeletonBlock className="route-skeleton__line route-skeleton__line--medium" />
        </div>
        <SkeletonBlock className="route-skeleton__button" />
      </div>
      <div className="route-skeleton__detail-grid">
        <div className="route-skeleton__panel">
          <SkeletonBlock className="route-skeleton__panel-title" />
          <SkeletonBlock className="route-skeleton__row" />
          <SkeletonBlock className="route-skeleton__row" />
          <SkeletonBlock className="route-skeleton__row" />
        </div>
        <div className="route-skeleton__panel route-skeleton__panel--aside">
          <SkeletonBlock className="route-skeleton__panel-title" />
          <SkeletonBlock className="route-skeleton__line route-skeleton__line--wide" />
          <SkeletonBlock className="route-skeleton__line route-skeleton__line--medium" />
        </div>
      </div>
    </div>
  );
}

const skeletons: Record<RouteSkeletonVariant, React.JSX.Element> = {
  auth: <AuthSkeleton />,
  collection: <CollectionSkeleton />,
  detail: <DetailSkeleton />,
  landing: <LandingSkeleton />
};

export function RouteSkeleton({ pathname }: { pathname: string }) {
  const variant = routeSkeletonVariant(pathname);
  return (
    <div
      aria-busy="true"
      aria-live="polite"
      className={`route-skeleton route-skeleton--${variant}`}
      role="status"
    >
      <span className="sr-only">Carregando página...</span>
      {skeletons[variant]}
    </div>
  );
}
