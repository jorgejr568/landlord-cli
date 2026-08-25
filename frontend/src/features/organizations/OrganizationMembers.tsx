import { Trash2 } from "lucide-react";
import type { RefObject } from "react";

import type { components } from "../../lib/api/schema";

type Member = components["schemas"]["OrganizationMemberResponse"];
type Role = Member["role"];

interface OrganizationMembersProps {
  canManageMembers: boolean;
  disabled: boolean;
  headingRef: RefObject<HTMLHeadingElement | null>;
  members: Member[];
  onRemove: (member: Member) => void;
  onRoleChange: (member: Member, role: Role, control: HTMLSelectElement) => void;
}

const ROLE_META: Record<Role, { className: string; label: string }> = {
  admin: { className: "tag--fixed", label: "Admin" },
  manager: { className: "tag--variable", label: "Gerente" },
  viewer: { className: "tag--draft", label: "Visualizador" }
};

export function OrganizationMembers({
  canManageMembers,
  disabled,
  headingRef,
  members,
  onRemove,
  onRoleChange
}: OrganizationMembersProps) {
  return (
    <section aria-labelledby="organization-members-heading" className="organization-members">
      <div className="organization-team__subheading"><h3 id="organization-members-heading" ref={headingRef} tabIndex={-1}>Membros</h3><span>{members.length}</span></div>
      <div className="organization-members__list">
        {members.map((member) => {
          const role = ROLE_META[member.role];
          return (
            <div className="organization-member-row" data-member-id={member.user_id} key={member.user_id}>
              <div className="member">
                <span className={`avatar${member.is_current_user ? " avatar--accent" : ""}`}>{member.email.slice(0, 2).toLocaleUpperCase("pt-BR")}</span>
                <div>
                  <div className="member__name">{member.email.split("@")[0]} {member.is_current_user ? <span className="you-chip">você</span> : null}</div>
                  <div className="member__email">{member.email}</div>
                </div>
              </div>
              <div className="organization-member-row__role">
                {canManageMembers && !member.is_current_user ? (
                  <select
                    aria-label={`Papel de ${member.email}`}
                    className="select"
                    data-member-control
                    disabled={disabled}
                    name={`member-role-${member.user_id}`}
                    onChange={(event) => onRoleChange(member, event.target.value as Role, event.currentTarget)}
                    value={member.role}
                  >
                    {Object.entries(ROLE_META).map(([value, meta]) => <option key={value} value={value}>{meta.label}</option>)}
                  </select>
                ) : <span className={`tag ${role.className}`}>{role.label}</span>}
              </div>
              {canManageMembers ? member.is_current_user ? <span className="organization-member-row__current">Conta atual</span> : (
                <button aria-label={`Remover ${member.email}`} className="icon-btn" data-member-control disabled={disabled} onClick={() => onRemove(member)} title="Remover" type="button">
                  <Trash2 aria-hidden="true" size={16} />
                </button>
              ) : null}
            </div>
          );
        })}
      </div>
    </section>
  );
}
