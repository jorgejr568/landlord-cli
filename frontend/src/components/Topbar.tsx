import { CircleUserRound, Menu } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { Link, useLocation } from "react-router";

export interface TopbarProps {
  currentPath?: string;
  currentUser: { email: string };
  onLogout?: () => void;
  pendingInviteCount: number;
}

export function Topbar({ currentPath, currentUser, onLogout, pendingInviteCount }: TopbarProps) {
  const [isAccountMenuOpen, setIsAccountMenuOpen] = useState(false);
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false);
  const accountMenuRef = useRef<HTMLDivElement>(null);
  const accountTriggerRef = useRef<HTMLButtonElement>(null);
  const location = useLocation();
  const resolvedCurrentPath = currentPath ?? location.pathname;
  const billingsActive = resolvedCurrentPath.startsWith("/billings");
  const organizationsActive = resolvedCurrentPath.startsWith("/organizations");

  useEffect(() => {
    setIsAccountMenuOpen(false);
    setIsMobileMenuOpen(false);
  }, [location.pathname]);

  useEffect(() => {
    if (!isAccountMenuOpen) {
      return;
    }

    const closeFromOutside = (event: MouseEvent) => {
      if (!accountMenuRef.current?.contains(event.target as Node)) {
        setIsAccountMenuOpen(false);
      }
    };
    const closeFromEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setIsAccountMenuOpen(false);
        accountTriggerRef.current?.focus();
      }
    };

    document.addEventListener("mousedown", closeFromOutside);
    document.addEventListener("keydown", closeFromEscape);

    return () => {
      document.removeEventListener("mousedown", closeFromOutside);
      document.removeEventListener("keydown", closeFromEscape);
    };
  }, [isAccountMenuOpen]);

  return (
    <nav className="topbar">
      <div className="wrapper">
        <Link className="topbar-brand" to="/">
          <span className="brand__mark">R</span>
          <span>
            rent<em>ivo</em>
          </span>
        </Link>
        <button
          aria-expanded={isMobileMenuOpen}
          aria-label="Menu"
          className="topbar-toggle"
          onClick={() => setIsMobileMenuOpen((isOpen) => !isOpen)}
          type="button"
        >
          <Menu aria-hidden="true" size={20} />
        </button>
        <div className={`topbar-menu${isMobileMenuOpen ? " open" : ""}`}>
          <Link
            aria-current={billingsActive ? "page" : undefined}
            className={`topbar-link${billingsActive ? " is-active" : ""}`}
            to="/billings/"
          >
            Minhas Cobranças
          </Link>
          <Link
            aria-current={organizationsActive ? "page" : undefined}
            className={`topbar-link${organizationsActive ? " is-active" : ""}`}
            to="/organizations/"
          >
            Organizações
          </Link>
          <div className={`topbar-dropdown${isAccountMenuOpen ? " open" : ""}`} ref={accountMenuRef}>
            <button
              aria-expanded={isAccountMenuOpen}
              className="topbar-link topbar-dropdown-toggle"
              onClick={() => setIsAccountMenuOpen((isOpen) => !isOpen)}
              ref={accountTriggerRef}
              type="button"
            >
              <CircleUserRound aria-hidden="true" className="topbar-icon" size={18} />
              <span className="topbar-user-email" title={currentUser.email}>{currentUser.email}</span>
            </button>
            <div className="topbar-dropdown-menu">
              <Link aria-current={resolvedCurrentPath.startsWith("/invites") ? "page" : undefined} className="topbar-dropdown-item" to="/invites/">
                Convites
                {pendingInviteCount > 0 ? <span className="topbar-badge">{pendingInviteCount}</span> : null}
              </Link>
              <Link aria-current={resolvedCurrentPath.startsWith("/themes") ? "page" : undefined} className="topbar-dropdown-item" to="/themes/user">Tema</Link>
              <Link aria-current={resolvedCurrentPath.startsWith("/security") ? "page" : undefined} className="topbar-dropdown-item" to="/security">Segurança</Link>
              <div className="topbar-dropdown-divider" />
              <button className="topbar-dropdown-item topbar-dropdown-item--danger" onClick={onLogout} type="button">
                Sair
              </button>
            </div>
          </div>
        </div>
      </div>
    </nav>
  );
}
