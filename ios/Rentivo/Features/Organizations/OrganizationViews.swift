import SwiftUI

private struct OrganizationListItem: Identifiable, Sendable {
  let organization: Organization
  let billingCount: Int
  var id: OrganizationID { organization.id }
}

struct OrganizationListView: View {
  @Environment(AppModel.self) private var app
  @State private var state: LoadState<[OrganizationListItem]> = .idle
  @State private var pendingCount = 0
  @State private var showingCreate = false
  @State private var showingInvitations = false

  // `viewerMode` is a demo-mode-only concept: `LiveDemoRepository.setViewerMode`
  // just flips a local flag with zero effect on the live server, so gating a
  // real affordance on it while connected live would hide a working action
  // for no server-backed reason. Organization creation has no per-payload
  // capability to check (it isn't scoped to an existing organization), so we
  // only respect the demo toggle when actually running against the mock store.
  private var canCreateOrganization: Bool {
    app.usesLiveAPI || !app.demoSettings.viewerMode
  }

  var body: some View {
    PageStateView(
      state: state,
      emptyTitle: "Nenhuma organização ainda",
      emptyMessage:
        "Organizações reúnem cobranças e membros sob papéis e permissões compartilhados. Crie uma para colaborar com sua equipe.",
      emptySystemImage: "building.2.fill",
      emptyActionTitle: canCreateOrganization ? "Criar organização" : nil,
      emptyAction: canCreateOrganization ? { showingCreate = true } : nil
    ) { organizations in
      ScrollView {
        LazyVStack(spacing: RentivoSpacing.large) {
          if pendingCount > 0 {
            Button {
              showingInvitations = true
            } label: {
              RentivoCard {
                HStack {
                  Label(
                    ptBRCount(pendingCount, singular: "convite pendente", plural: "convites pendentes"),
                    systemImage: "envelope.badge.fill"
                  )
                  .font(.headline)
                  Spacer()
                  Image(systemName: "chevron.right")
                }
              }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("organization.invitations.open")
          }
          ForEach(organizations) { item in
            NavigationLink {
              OrganizationDetailView(organizationID: item.id) { await load() }
            } label: {
              OrganizationCard(item: item)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(RentivoSpacing.page)
      }
    } retry: {
      await load()
    }
    .background(RentivoColors.paper)
    .navigationTitle("Organizações")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        if canCreateOrganization {
          Button {
            showingCreate = true
          } label: {
            Label("Criar", systemImage: "plus")
          }
          .accessibilityIdentifier("organization.create")
        }
      }
    }
    .rentivoFullScreenWizard(isPresented: $showingCreate) {
      OrganizationFormView { await load() }
    }
    .sheet(isPresented: $showingInvitations) {
      NavigationStack {
        InvitationListView { await load() }
      }
    }
    .task(id: app.dataRevision) { await load() }
    .refreshable { await load() }
  }

  private func load() async {
    // Only show the loading spinner when nothing is on screen yet; pull-to-
    // refresh and every tab revisit (`.task(id: app.dataRevision)`) otherwise
    // refresh in place instead of tearing down the list.
    switch state {
    case .idle, .failed:
      state = .loading
    case .loading, .loaded, .empty:
      break
    }
    do {
      let organizations = try await app.dependencies.organizations.listOrganizations()
      let billings = try await app.dependencies.billings.listBillings()
      let values = organizations.map { organization in
        OrganizationListItem(
          organization: organization,
          billingCount: billings.filter { $0.owner.workspaceID.rawValue == organization.id.rawValue }.count
        )
      }
      pendingCount = try await app.dependencies.invitations.listPendingInvitations().count
      state = values.isEmpty ? .empty : .loaded(values)
    } catch {
      switch state {
      case .loaded, .empty:
        app.showNotice(DemoError(error).message, kind: .warning)
      default:
        state = .failed(DemoError(error))
      }
    }
  }
}

private struct OrganizationCard: View {
  let item: OrganizationListItem

  var body: some View {
    RentivoCard {
      VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
        HStack(alignment: .top) {
          Image(systemName: "building.2.fill")
            .font(.title2)
            .foregroundStyle(RentivoColors.emerald)
          VStack(alignment: .leading, spacing: RentivoSpacing.tiny) {
            Text(item.organization.name)
              .font(RentivoTypography.cardTitle)
              .foregroundStyle(RentivoColors.ink)
            Text(item.organization.currentUserRole.label)
              .font(.caption.weight(.semibold))
              .foregroundStyle(RentivoColors.secondaryInk)
          }
          Spacer()
          Image(systemName: "chevron.right")
            .foregroundStyle(RentivoColors.secondaryInk)
        }
        HStack {
          Label(
            ptBRCount(item.organization.members.count, singular: "membro", plural: "membros"),
            systemImage: "person.2.fill"
          )
          Spacer()
          Label(
            ptBRCount(item.billingCount, singular: "cobrança", plural: "cobranças"),
            systemImage: "house.fill"
          )
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(RentivoColors.secondaryInk)
        Label(
          item.organization.requiresMFA ? "MFA obrigatório" : "MFA opcional",
          systemImage: item.organization.requiresMFA ? "lock.shield.fill" : "lock.open"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(
          item.organization.requiresMFA ? RentivoColors.emerald : RentivoColors.secondaryInk
        )
      }
    }
  }
}

struct OrganizationFormView: View {
  private enum Step: CaseIterable {
    case organization
    case pix
    case review
  }

  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  let organization: Organization?
  let onSaved: () async -> Void
  @State private var name: String
  @State private var pixKey: String
  @State private var merchantName: String
  @State private var city: String
  @State private var pixValidationMessage: String?
  @State private var nameValidationMessage: String?
  @State private var submitErrorMessage: String?
  @State private var saving = false
  @State private var step: Step = .organization
  private let initialName: String
  private let initialPixKey: String
  private let initialMerchantName: String
  private let initialCity: String

  init(organization: Organization? = nil, onSaved: @escaping () async -> Void) {
    self.organization = organization
    self.onSaved = onSaved
    initialName = organization?.name ?? ""
    initialPixKey = organization?.pix?.key ?? ""
    initialMerchantName = organization?.pix?.merchantName ?? ""
    initialCity = organization?.pix?.merchantCity ?? ""
    _name = State(initialValue: initialName)
    _pixKey = State(initialValue: initialPixKey)
    _merchantName = State(initialValue: initialMerchantName)
    _city = State(initialValue: initialCity)
  }

  var body: some View {
    RentivoFormWizard(
      title: organization == nil ? "Nova organização" : "Editar organização",
      descriptors: descriptors,
      selectedStep: $step,
      isDirty: isDirty,
      isBusy: saving,
      primaryTitle: step == .review ? (organization == nil ? "Criar" : "Salvar") : "Continuar",
      onValidateAndAdvance: validateCurrentStep,
      onCommit: { Task { await save() } }
    ) { selectedStep in
      stepContent(selectedStep)
    }
    .interactiveDismissDisabled(isDirty || saving)
  }

  private var descriptors: [RentivoWizardStepDescriptor<Step>] {
    [
      .init(id: .organization, title: "Organização"),
      .init(id: .pix, title: "Recebimento PIX"),
      .init(id: .review, title: "Revisão"),
    ]
  }

  private var isDirty: Bool {
    name != initialName || pixKey != initialPixKey || merchantName != initialMerchantName
      || city != initialCity
  }

  @ViewBuilder
  private func stepContent(_ step: Step) -> some View {
    switch step {
    case .organization:
      RentivoWizardSection(
        "Identidade da organização",
        subtitle: organization == nil
          ? "Dê um nome claro para o espaço compartilhado."
          : "Atualize o nome exibido para membros e cobranças."
      ) {
        TextField("Nome", text: $name)
        if let nameValidationMessage {
          validationLabel(nameValidationMessage)
        }
      }
    case .pix:
      RentivoWizardSection(
        "Recebimento PIX",
        subtitle: "Deixe todos os campos vazios para manter a organização sem PIX."
      ) {
        TextField("Chave", text: $pixKey)
          .textInputAutocapitalization(.never)
        TextField("Nome do recebedor", text: $merchantName)
        TextField("Cidade", text: $city)
          .textInputAutocapitalization(.characters)
        if let pixValidationMessage {
          validationLabel(pixValidationMessage)
        }
      }
    case .review:
      RentivoWizardSection("Organização") {
        RentivoWizardReviewRow(
          label: "Nome",
          value: name.trimmingCharacters(in: .whitespacesAndNewlines)
        )
      }
      RentivoWizardSection("PIX") {
        RentivoWizardReviewRow(label: "Configuração", value: pixSummary)
        if !pixKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          RentivoWizardReviewRow(
            label: "Recebedor",
            value: merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
          )
          RentivoWizardReviewRow(
            label: "Cidade", value: city.trimmingCharacters(in: .whitespacesAndNewlines)
          )
        }
      }
      if let submitErrorMessage {
        RentivoWizardSection("Não foi possível salvar") {
          validationLabel(submitErrorMessage)
        }
      }
    }
  }

  private var pixSummary: String {
    pixKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? "Sem PIX configurado" : "PIX configurado"
  }

  private func validationLabel(_ message: String) -> some View {
    Label(message, systemImage: "exclamationmark.circle.fill")
      .font(.footnote)
      .foregroundStyle(RentivoColors.coral)
      .accessibilityIdentifier("organization.form.validation")
  }

  private func validateCurrentStep() -> Bool {
    submitErrorMessage = nil
    switch step {
    case .organization:
      nameValidationMessage = OrganizationDraft.nameValidationMessage(name)
      return nameValidationMessage == nil
    case .pix:
      pixValidationMessage = OrganizationDraft.pixValidationMessage(
        key: pixKey, merchantName: merchantName, city: city
      )
      return pixValidationMessage == nil
    case .review:
      return true
    }
  }

  private func save() async {
    guard !saving else { return }
    submitErrorMessage = nil
    let trimmedKey = pixKey.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedMerchantName = merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
    // Mirrors BillingFormView's PIX validation: a blank key means no PIX at all, but once a key
    // is present the recipient name/city are required, and must respect the server's column
    // limits (`OrganizationUpdateRequest.pix_merchant_name` maxLength 25, `pix_merchant_city`
    // maxLength 15) so the follow-up PATCH in `createOrganization`/`updateOrganization` can't
    // 422 on data the form already accepted.
    pixValidationMessage = OrganizationDraft.pixValidationMessage(
      key: trimmedKey, merchantName: trimmedMerchantName, city: trimmedCity
    )
    guard pixValidationMessage == nil else { return }
    let pix: PixConfiguration? =
      trimmedKey.isEmpty
      ? nil
      : PixConfiguration(key: trimmedKey, merchantName: trimmedMerchantName, merchantCity: trimmedCity)
    let draft = OrganizationDraft(name: name, pix: pix)
    guard draft.isValid else {
      nameValidationMessage = OrganizationDraft.nameValidationMessage(name)
      submitErrorMessage = nameValidationMessage
      step = nameValidationMessage == nil ? .pix : .organization
      return
    }
    saving = true
    defer { saving = false }
    do {
      if let organization {
        _ = try await app.dependencies.organizations.updateOrganization(
          id: organization.id, draft: draft)
      } else {
        _ = try await app.dependencies.organizations.createOrganization(draft)
      }
      await onSaved()
      dismiss()
      app.showNotice(organization == nil ? "Organização criada." : "Organização atualizada.")
    } catch { submitErrorMessage = DemoError(error).message }
  }
}

struct OrganizationDetailView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  let organizationID: OrganizationID
  let onMutation: () async -> Void
  @State private var state: LoadState<Organization> = .idle
  @State private var billings: [Billing] = []
  @State private var showingEdit = false
  @State private var showingInvite = false
  @State private var showingTheme = false
  @State private var confirmingMFA = false
  @State private var confirmingDelete = false

  var body: some View {
    PageStateView(state: state) { organization in
      content(organization)
    } retry: {
      await load()
    }
    .background(RentivoColors.paper)
    .navigationTitle("Organização")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if state.value?.capabilities.canManage == true {
        Button("Editar") { showingEdit = true }
      }
    }
    .rentivoFullScreenWizard(isPresented: $showingEdit) {
      if let organization = state.value {
        OrganizationFormView(organization: organization) { await refreshAll() }
      }
    }
    .rentivoFullScreenWizard(isPresented: $showingInvite) {
      if let organization = state.value {
        InviteMemberView(organization: organization) { await refreshAll() }
      }
    }
    .rentivoFullScreenWizard(isPresented: $showingTheme) {
      ThemeEditorView(target: .organization(organizationID))
    }
    .confirmationDialog(
      state.value?.requiresMFA == true ? "Tornar MFA opcional?" : "Exigir MFA?",
      isPresented: $confirmingMFA
    ) {
      Button("Confirmar") { Task { await toggleMFA() } }
      Button("Cancelar", role: .cancel) {}
    } message: {
      Text("A política será aplicada a todos os membros desta organização.")
    }
    .confirmationDialog("Excluir organização?", isPresented: $confirmingDelete) {
      Button("Excluir", role: .destructive) { Task { await deleteOrganization() } }
      Button("Cancelar", role: .cancel) {}
    } message: {
      Text("Primeiro transfira todas as cobranças vinculadas.")
    }
    .task(id: app.dataRevision) { await load() }
  }

  private func content(_ organization: Organization) -> some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: RentivoSpacing.section) {
        RentivoCard {
          VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
            Text(organization.name).font(RentivoTypography.title)
            Label(organization.currentUserRole.label, systemImage: "person.badge.shield.checkmark")
            Label(
              organization.pix?.isComplete == true ? "PIX configurado" : "PIX pendente",
              systemImage: "qrcode"
            )
          }
        }

        memberSection(organization)
        policySection(organization)
        billingSection(organization)

        Button {
          showingTheme = true
        } label: {
          Label("Aparência da organização", systemImage: "paintpalette.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(RentivoButtonStyle(color: RentivoColors.blue))
        .accessibilityIdentifier("organization.theme")

        if organization.capabilities.canManage {
          Button(role: .destructive) {
            confirmingDelete = true
          } label: {
            Label("Excluir organização", systemImage: "trash").frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
        } else {
          Label(
            "Seu papel permite consultar esta organização, sem alterar sua configuração.",
            systemImage: "eye.fill"
          )
          .font(.footnote.weight(.semibold))
          .foregroundStyle(RentivoColors.secondaryInk)
        }
      }
      .padding(RentivoSpacing.page)
    }
  }

  private func memberSection(_ organization: Organization) -> some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
      HStack {
        SectionTitle(title: "Membros", symbol: "person.2.fill")
        Spacer()
        if organization.capabilities.canInvite {
          Button {
            showingInvite = true
          } label: {
            Image(systemName: "person.badge.plus")
          }
          .accessibilityLabel("Convidar membro")
        }
      }
      RentivoCard {
        VStack(spacing: RentivoSpacing.medium) {
          ForEach(organization.members) { member in
            HStack {
              VStack(alignment: .leading) {
                HStack(spacing: RentivoSpacing.tiny) {
                  Text(member.email).font(.subheadline.weight(.semibold))
                  if member.isCurrentUser {
                    Text("você").font(.caption2.weight(.bold)).foregroundStyle(RentivoColors.blue)
                  }
                }
                Text(member.role.label)
                  .font(.caption)
                  .foregroundStyle(RentivoColors.secondaryInk)
              }
              Spacer()
              if member.isCurrentUser {
                Image(
                  systemName: member.role == .admin
                    ? "crown.fill" : "person.crop.circle.badge.checkmark"
                )
                .foregroundStyle(member.role == .admin ? RentivoColors.amber : RentivoColors.blue)
              } else if organization.capabilities.canManage {
                Menu {
                  ForEach(
                    OrganizationRole.allCases.filter { $0 != member.role },
                    id: \.self
                  ) { role in
                    Button(role.label) { Task { await changeRole(member, to: role) } }
                  }
                  Divider()
                  Button("Remover", role: .destructive) { Task { await remove(member) } }
                } label: {
                  Image(systemName: "ellipsis.circle")
                }
              } else if member.role == .admin {
                Image(systemName: "crown.fill").foregroundStyle(RentivoColors.amber)
              }
            }
          }
        }
      }
    }
  }

  private func policySection(_ organization: Organization) -> some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
      SectionTitle(title: "Política de segurança", symbol: "lock.shield.fill")
      RentivoCard {
        HStack {
          VStack(alignment: .leading) {
            Text("Autenticação em duas etapas").font(.headline)
            Text(organization.requiresMFA ? "Obrigatória para membros" : "Opcional")
              .font(.caption)
              .foregroundStyle(RentivoColors.secondaryInk)
          }
          Spacer()
          // A real `Toggle` (not a hit-test-disabled decoration behind an
          // `onTapGesture`) so VoiceOver can focus and activate it directly.
          // The binding never applies the tap's intended value: it only
          // opens the confirmation dialog. The switch's visual position stays
          // driven entirely by `organization.requiresMFA`, so it only moves
          // once `toggleMFA()` actually persists the change and reloads —
          // if the user cancels the dialog, nothing changes and the toggle
          // silently reverts to its true state.
          Toggle(
            "Autenticação em duas etapas obrigatória",
            isOn: Binding(
              get: { organization.requiresMFA },
              set: { _ in confirmingMFA = true }
            )
          )
          .labelsHidden()
          .disabled(!organization.capabilities.canManage)
          .accessibilityIdentifier("organization.mfa.toggle")
        }
      }
    }
  }

  private func billingSection(_ organization: Organization) -> some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
      SectionTitle(title: "Cobranças", symbol: "house.fill")
      let owned = billings.filter { $0.owner.workspaceID.rawValue == organization.id.rawValue }
      if owned.isEmpty {
        Text("Nenhuma cobrança pertence a esta organização.")
          .foregroundStyle(RentivoColors.secondaryInk)
      } else {
        ForEach(owned) { billing in
          RentivoCard {
            HStack {
              Text(billing.name).font(.subheadline.weight(.semibold))
              Spacer()
            }
          }
        }
      }
      let personal = billings.filter(\.canTransferToOrganization)
      if !personal.isEmpty && organization.capabilities.canCreateBilling {
        Menu {
          ForEach(personal) { billing in
            Button(billing.name) { Task { await transfer(billing, to: organization) } }
          }
        } label: {
          Label("Transferir cobrança para cá", systemImage: "arrow.right.square.fill")
        }
        .buttonStyle(.bordered)
      }
    }
  }

  private func load() async {
    // Same "don't blank on refresh" rule as the organization list: every
    // member/role/MFA/billing mutation calls `refreshAll()` -> `load()`, and
    // `.task(id: app.dataRevision)` reruns on demo-state changes too, so
    // resetting to `.loading` unconditionally would flash a spinner over an
    // already-visible organization on every one of those actions.
    switch state {
    case .idle, .failed:
      state = .loading
    case .loading, .loaded, .empty:
      break
    }
    do {
      let loadedOrganization = try await app.dependencies.organizations.organization(
        id: organizationID
      )
      let loadedBillings = try await app.dependencies.billings.listBillings()
      billings = loadedBillings
      state = .loaded(loadedOrganization)
    } catch {
      switch state {
      case .loaded, .empty:
        app.showNotice(DemoError(error).message, kind: .warning)
      default:
        state = .failed(DemoError(error))
      }
    }
  }

  private func refreshAll() async {
    await load()
    await onMutation()
  }

  private func changeRole(_ member: OrganizationMember, to role: OrganizationRole) async {
    do {
      try await app.dependencies.organizations.updateMemberRole(
        organizationID: organizationID,
        userID: member.userID,
        role: role
      )
      await refreshAll()
    } catch { app.showNotice(DemoError(error).message, kind: .warning) }
  }

  private func remove(_ member: OrganizationMember) async {
    do {
      try await app.dependencies.organizations.removeMember(
        organizationID: organizationID, userID: member.userID)
      await refreshAll()
    } catch { app.showNotice(DemoError(error).message, kind: .warning) }
  }

  private func toggleMFA() async {
    guard let organization = state.value else { return }
    do {
      let policy = try await app.dependencies.organizations.setOrganizationMFA(
        organizationID: organizationID,
        required: !organization.requiresMFA
      )
      await refreshAll()
      if policy.mfaSetupRequired {
        app.selectedTab = .account
        app.showNotice(
          "MFA passou a ser obrigatório. Abra Segurança para cadastrar um método.",
          kind: .information
        )
      }
    } catch { app.showNotice(DemoError(error).message, kind: .warning) }
  }

  private func transfer(_ billing: Billing, to organization: Organization) async {
    do {
      try await app.dependencies.organizations.transferBilling(
        billingID: billing.id,
        toOrganizationID: organization.id
      )
      await refreshAll()
    } catch { app.showNotice(DemoError(error).message, kind: .warning) }
  }

  private func deleteOrganization() async {
    do {
      try await app.dependencies.organizations.deleteOrganization(id: organizationID)
      await onMutation()
      dismiss()
    } catch { app.showNotice(DemoError(error).message, kind: .warning) }
  }
}
