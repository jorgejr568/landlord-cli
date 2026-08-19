import RentivoCore
import SwiftUI

private struct OrganizationListItem: Identifiable, Sendable {
  let organization: Organization
  let billingCount: Int
  var id: OrganizationID { organization.id }
}

/// Pure form rules shared by the organization sheet and its tests, so the PT-BR validation copy
/// can be exercised without standing up SwiftUI.
enum OrganizationFormValidation {
  /// Mirrors BillingFormView's PIX validation: a blank key means no PIX at all, but once a key
  /// is present the recipient name/city are required, and must respect the server's column
  /// limits (`OrganizationUpdateRequest.pix_merchant_name` maxLength 25, `pix_merchant_city`
  /// maxLength 15) so the follow-up PATCH in `createOrganization`/`updateOrganization` can't
  /// 422 on data the form already accepted. Returns `nil` when the section is valid.
  static func pixMessage(key: String, merchantName: String, city: String) -> String? {
    OrganizationDraft.pixValidationMessage(
      key: key, merchantName: merchantName, city: city
    )
  }

  static func pixResult(
    editor: MacOSPixKeyEditor, merchantName: String, city: String
  ) -> PixFormResult {
    editor.result(merchantName: merchantName, merchantCity: city)
  }
}

/// Indexes an account's cobranças by the workspace that owns them.
///
/// Both organization screens need a per-organization slice of the same `listBillings()` result.
/// Filtering the whole portfolio once per organization costs `organizations × billings` on the
/// list screen, and the detail screen paid its two filters again on every `body` evaluation —
/// every hover, every sheet toggle, every keystroke in a presented form. Grouping once per load
/// turns both into a dictionary lookup.
enum OrganizationBillingIndex {
  /// The workspace key a cobrança owned by `organization` is filed under.
  ///
  /// `BillingOwner.workspaceID` reuses the organization's raw identifier for organization-owned
  /// cobranças, so this is the one key both sides of the lookup agree on.
  static func workspaceID(of organization: OrganizationID) -> WorkspaceID {
    WorkspaceID(rawValue: organization.rawValue)
  }

  static func byWorkspace(_ billings: [Billing]) -> [WorkspaceID: [Billing]] {
    Dictionary(grouping: billings, by: \.owner.workspaceID)
  }

  /// The cobranças that belong to no organization — the transfer menu's candidates.
  static func personal(_ billings: [Billing]) -> [Billing] {
    billings.filter(\.canTransferToOrganization)
  }
}

/// The roles an administrator may assign to another member from the member row's menu.
enum OrganizationMemberActions {
  static func assignableRoles(excluding currentRole: OrganizationRole) -> [OrganizationRole] {
    OrganizationRole.allCases.filter { $0 != currentRole }
  }
}

struct OrganizationListView: View {
  @Environment(AppModel.self) private var app
  @State private var state: LoadState<[OrganizationListItem]> = .idle
  @State private var pendingCount = 0
  @State private var showingCreate = false
  @State private var showingInvitations = false
  @State private var refresh = RefreshActivity()

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
                  .font(RentivoTypography.cardTitle)
                  Spacer()
                  Image(systemName: "chevron.right")
                }
              }
            }
            .buttonStyle(.plain)
            .rentivoHoverLift()
            .accessibilityIdentifier("organization.invitations.open")
          }
          ForEach(organizations) { item in
            NavigationLink {
              OrganizationDetailView(organizationID: item.id)
            } label: {
              OrganizationCard(item: item)
            }
            .buttonStyle(.plain)
            .rentivoHoverLift()
            .accessibilityIdentifier("organization.card.\(item.id.rawValue)")
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
      ToolbarItem(placement: .primaryAction) {
        RefreshToolbarButton(
          activity: refresh,
          help: "Atualizar as organizações",
          accessibilityIdentifier: "organization.refresh"
        ) {
          await load()
        }
      }
      if canCreateOrganization {
        ToolbarItem(placement: .primaryAction) {
          Button {
            showingCreate = true
          } label: {
            Label("Criar", systemImage: "plus")
          }
        }
      }
    }
    .sheet(isPresented: $showingCreate) {
      NavigationStack {
        OrganizationFormView { await load() }
      }
      .rentivoSheetFrame()
    }
    .sheet(isPresented: $showingInvitations) {
      NavigationStack {
        InvitationListView { await load() }
      }
      .rentivoSheetFrame()
    }
    .task(id: app.dataRevision) { await load() }
  }

  private func load() async {
    state.prepareForRefresh()
    do {
      // The organizations, the portfolio, and the pending invitations are three independent
      // requests: run them together so the screen costs the slowest one instead of all three end
      // to end. `RepositoryBox` is what carries a main-actor repository into the child tasks.
      let organizationsRepository = RepositoryBox(app.dependencies.organizations)
      let billingsRepository = RepositoryBox(app.dependencies.billings)
      let invitationsRepository = RepositoryBox(app.dependencies.invitations)
      async let organizationsRequest = organizationsRepository.repository.listOrganizations()
      async let billingsRequest = billingsRepository.repository.listBillings()
      async let invitationsRequest = invitationsRepository.repository.listPendingInvitations()
      let (organizations, billings, invitations) = try await (
        organizationsRequest, billingsRequest, invitationsRequest
      )
      let billingsByWorkspace = OrganizationBillingIndex.byWorkspace(billings)
      let values = organizations.map { organization in
        OrganizationListItem(
          organization: organization,
          billingCount: billingsByWorkspace[
            OrganizationBillingIndex.workspaceID(of: organization.id)
          ]?.count ?? 0
        )
      }
      pendingCount = invitations.count
      state = values.isEmpty ? .empty : .loaded(values)
    } catch {
      state.settleFailure(error, reportingTo: app)
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
            .font(RentivoTypography.icon)
            .foregroundStyle(RentivoColors.emerald)
          VStack(alignment: .leading, spacing: RentivoSpacing.tiny) {
            Text(item.organization.name)
              .font(RentivoTypography.cardTitle)
              .foregroundStyle(RentivoColors.ink)
            Text(item.organization.currentUserRole.label)
              .font(RentivoTypography.metadata)
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
        .font(RentivoTypography.metadata)
        .foregroundStyle(RentivoColors.secondaryInk)
        Label(
          item.organization.requiresMFA ? "MFA obrigatório" : "MFA opcional",
          systemImage: item.organization.requiresMFA ? "lock.shield.fill" : "lock.open"
        )
        .font(RentivoTypography.metadata)
        .foregroundStyle(
          item.organization.requiresMFA ? RentivoColors.emerald : RentivoColors.secondaryInk
        )
      }
    }
  }
}

struct OrganizationFormView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  let organization: Organization?
  let onSaved: () async -> Void
  @State private var name: String
  @State private var pixEditor: MacOSPixKeyEditor
  @State private var merchantName: String
  @State private var city: String
  @State private var usesCustomPix: Bool
  @State private var pixValidationMessage: String?
  @State private var submitFailureMessage: String?
  @State private var saving = false
  @State private var confirmingDiscard = false
  private let initialDraftState: NativeOrganizationDraftState

  init(organization: Organization? = nil, onSaved: @escaping () async -> Void) {
    self.organization = organization
    self.onSaved = onSaved
    let name = organization?.name ?? ""
    let pixEditor = MacOSPixKeyEditor(persistedKey: organization?.pix?.key ?? "")
    let merchantName = organization?.pix?.merchantName ?? ""
    let city = organization?.pix?.merchantCity ?? ""
    let usesCustomPix = organization?.pix != nil
    initialDraftState = NativeOrganizationDraftState(
      name: name, pixKey: pixEditor.key, merchantName: merchantName, city: city,
      usesCustomPix: usesCustomPix
    )
    _name = State(initialValue: name)
    _pixEditor = State(initialValue: pixEditor)
    _merchantName = State(initialValue: merchantName)
    _city = State(initialValue: city)
    _usesCustomPix = State(initialValue: usesCustomPix)
  }

  var body: some View {
    Form {
      RentivoSection("Organização") {
        TextField("Nome", text: $name)
        if !name.isEmpty, let message = OrganizationDraft.nameValidationMessage(name) {
          Text(message).foregroundStyle(RentivoColors.coral)
        }
      }
      RentivoSection("PIX") {
        Toggle("Usar PIX da organização", isOn: $usesCustomPix)
        if usesCustomPix {
          Picker("Tipo de chave", selection: pixKeyTypeBinding) {
            ForEach(PixKeyType.allCases, id: \.self) { type in
              Text(type.label).tag(type)
            }
          }
          .accessibilityIdentifier("organization.form.pix.key-type")
          TextField("Chave", text: pixKeyBinding)
            .autocorrectionDisabled()
            .accessibilityIdentifier("organization.form.pix.key")
          TextField("Nome do recebedor", text: $merchantName)
          TextField("Cidade", text: $city)
        } else {
          Text("Sem PIX próprio. Cobranças podem usar o PIX pessoal do responsável.")
            .font(RentivoTypography.caption)
            .foregroundStyle(RentivoColors.secondaryInk)
        }
      }

      if let pixValidationMessage {
        RentivoSection("Revise os campos") {
          Label(pixValidationMessage, systemImage: "exclamationmark.circle.fill")
            .foregroundStyle(RentivoColors.coral)
            .accessibilityIdentifier("organization.form.validation")
        }
      }

      if let submitFailureMessage {
        RentivoSection("Não foi possível salvar") {
          Label(submitFailureMessage, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(RentivoColors.coral)
            .accessibilityIdentifier("organization.form.error")
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle(organization == nil ? "Nova organização" : "Editar organização")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancelar") {
          if hasUnsavedChanges { confirmingDiscard = true } else { dismiss() }
        }.disabled(saving)
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Salvar") { Task { await save() } }
          .disabled(saving || !OrganizationDraft(name: name, pix: nil).isValid)
          .accessibilityIdentifier("organization.form.save")
      }
    }
    .interactiveDismissDisabled(saving || hasUnsavedChanges)
    .confirmationDialog(
      "Descartar as alterações?", isPresented: $confirmingDiscard, titleVisibility: .visible
    ) {
      Button("Descartar", role: .destructive) { dismiss() }
      Button("Continuar editando", role: .cancel) {}
    }
  }

  private var hasUnsavedChanges: Bool {
    NativeOrganizationDraftState(
      name: name, pixKey: pixEditor.key, merchantName: merchantName, city: city,
      usesCustomPix: usesCustomPix
    ).hasChanges(from: initialDraftState)
  }

  private func save() async {
    // Without this the sheet stays interactive across the round trip and a double-click creates
    // two organizations.
    guard !saving else { return }
    let result = usesCustomPix
      ? OrganizationFormValidation.pixResult(
        editor: pixEditor, merchantName: merchantName, city: city
      )
      : .inherit
    let pix: PixConfiguration?
    switch result {
    case .inherit:
      pix = nil
      pixValidationMessage = nil
    case .custom(let configuration):
      pix = configuration
      pixValidationMessage = nil
    case .invalid(let message):
      pix = nil
      pixValidationMessage = message
    }
    guard pixValidationMessage == nil else { return }
    let draft = OrganizationDraft(
      name: name.trimmingCharacters(in: .whitespacesAndNewlines), pix: pix
    )
    guard OrganizationDraft.nameValidationMessage(draft.name) == nil else {
      submitFailureMessage = OrganizationDraft.nameValidationMessage(name)
      return
    }
    submitFailureMessage = nil
    saving = true
    defer { saving = false }
    do {
      if let organization {
        _ = try await app.dependencies.organizations.updateOrganization(
          id: organization.id, draft: draft)
      } else {
        _ = try await app.dependencies.organizations.createOrganization(draft)
      }
      // The notice outlives the sheet — `app.notice` holds it until the banner is dismissed — so
      // setting it just before `dismiss()` still leaves it visible once the sheet is gone.
      app.showNotice(organization == nil ? "Organização criada." : "Organização atualizada.")
      await onSaved()
      dismiss()
    } catch {
      // The global banner renders behind this sheet, so a failure reported there would read as
      // Salvar doing nothing at all. Keep it inline, where the user is looking.
      submitFailureMessage = DemoError(error).message
    }
  }

  private var pixKeyBinding: Binding<String> {
    Binding(
      get: { pixEditor.key },
      set: { pixEditor.updateKey($0) }
    )
  }

  private var pixKeyTypeBinding: Binding<PixKeyType> {
    Binding(
      get: { pixEditor.keyType },
      set: { pixEditor.selectType($0) }
    )
  }
}

/// The one mutation the detail screen has in flight, so the control that started it can show the
/// wait and refuse a second click for the length of the round trip.
///
/// A single slot rather than one flag per control: these actions all end in `refreshAll()`, so
/// letting two run at once would race two reloads against each other for no gain.
private enum OrganizationDetailAction: Equatable {
  /// A role change or a removal, keyed by the member the row belongs to.
  case member(Int)
  case policy
  case transfer(BillingID)
  case delete
}

struct OrganizationDetailView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  let organizationID: OrganizationID
  @State private var state: LoadState<Organization> = .idle
  @State private var billingsByWorkspace: [WorkspaceID: [Billing]] = [:]
  @State private var personalBillings: [Billing] = []
  @State private var showingEdit = false
  @State private var showingInvite = false
  @State private var confirmingMFA = false
  @State private var confirmingDelete = false
  @State private var runningAction: OrganizationDetailAction?

  private var isTransferring: Bool {
    if case .transfer = runningAction { return true }
    return false
  }

  var body: some View {
    PageStateView(state: state) { organization in
      content(organization)
    } retry: {
      await load()
    }
    .background(RentivoColors.paper)
    .navigationTitle("Organização")
    .toolbar {
      if state.value?.capabilities.canManage == true {
        ToolbarItem(placement: .primaryAction) {
          Button("Editar") { showingEdit = true }
        }
      }
    }
    .sheet(isPresented: $showingEdit) {
      if let organization = state.value {
        NavigationStack {
          OrganizationFormView(organization: organization) { refreshAll() }
        }
        .rentivoSheetFrame()
      }
    }
    .sheet(isPresented: $showingInvite) {
      if let organization = state.value {
        NavigationStack {
          InviteMemberView(organization: organization) { refreshAll() }
        }
        .rentivoSheetFrame()
      }
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
        .accessibilityIdentifier("organization.detail")

        memberSection(organization)
        policySection(organization)
        billingSection(organization)

        NavigationLink {
          ThemeEditorView(target: .organization(organizationID))
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
            if runningAction == .delete {
              HStack(spacing: RentivoSpacing.small) {
                ProgressView().controlSize(.small)
                Text("Excluindo…")
              }
              .frame(maxWidth: .infinity)
            } else {
              Label("Excluir organização", systemImage: "trash").frame(maxWidth: .infinity)
            }
          }
          .buttonStyle(.bordered)
          .disabled(runningAction != nil)
        } else {
          Label(
            "Seu papel permite consultar esta organização, sem alterar sua configuração.",
            systemImage: "eye.fill"
          )
          .font(RentivoTypography.captionStrong)
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
        VStack(spacing: RentivoSpacing.small) {
          ForEach(organization.members) { member in
            MemberRow(
              member: member,
              canManage: organization.capabilities.canManage,
              isBusy: runningAction == .member(member.userID),
              isLocked: runningAction != nil,
              changeRole: { role in await changeRole(member, to: role) },
              remove: { await remove(member) }
            )
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
            Text("Autenticação em duas etapas").font(RentivoTypography.cardTitle)
            Text(organization.requiresMFA ? "Obrigatória para membros" : "Opcional")
              .font(RentivoTypography.caption)
              .foregroundStyle(RentivoColors.secondaryInk)
          }
          Spacer()
          if runningAction == .policy {
            ProgressView().controlSize(.small)
          }
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
          .toggleStyle(.switch)
          .labelsHidden()
          .disabled(!organization.capabilities.canManage || runningAction != nil)
          .accessibilityIdentifier("organization.mfa.toggle")
        }
      }
    }
  }

  private func billingSection(_ organization: Organization) -> some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
      SectionTitle(title: "Cobranças", symbol: "house.fill")
      // Both slices come from the dictionary `load()` built, rather than from two filters over the
      // whole portfolio that SwiftUI would re-run on every `body` evaluation.
      let owned =
        billingsByWorkspace[OrganizationBillingIndex.workspaceID(of: organization.id)] ?? []
      if owned.isEmpty {
        Text("Nenhuma cobrança pertence a esta organização.")
          .foregroundStyle(RentivoColors.secondaryInk)
      } else {
        ForEach(owned) { billing in
          RentivoCard {
            HStack {
              Text(billing.name).font(RentivoTypography.bodyStrong)
              Spacer()
            }
          }
        }
      }
      if !personalBillings.isEmpty && organization.capabilities.canCreateBilling {
        Menu {
          ForEach(personalBillings) { billing in
            Button(billing.name) { Task { await transfer(billing, to: organization) } }
          }
        } label: {
          if isTransferring {
            HStack(spacing: RentivoSpacing.small) {
              ProgressView().controlSize(.small)
              Text("Transferindo…")
            }
          } else {
            Label("Transferir cobrança para cá", systemImage: "arrow.right.square.fill")
          }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(runningAction != nil)
      }
    }
  }

  private func load() async {
    // Every member/role/MFA/billing mutation on this screen calls `refreshAll()` -> `load()`, so
    // `prepareForRefresh()` is what keeps the organization on screen through all of them.
    state.prepareForRefresh()
    do {
      // The record and the portfolio are independent requests, so the screen costs the slower of
      // the two rather than their sum. `RepositoryBox` is what carries a main-actor repository
      // into the child tasks.
      let organizationsRepository = RepositoryBox(app.dependencies.organizations)
      let billingsRepository = RepositoryBox(app.dependencies.billings)
      async let organizationRequest = organizationsRepository.repository.organization(
        id: organizationID
      )
      async let billingsRequest = billingsRepository.repository.listBillings()
      let (loadedOrganization, loadedBillings) = try await (organizationRequest, billingsRequest)
      billingsByWorkspace = OrganizationBillingIndex.byWorkspace(loadedBillings)
      personalBillings = OrganizationBillingIndex.personal(loadedBillings)
      state = .loaded(loadedOrganization)
    } catch {
      state.settleFailure(error, reportingTo: app)
    }
  }

  private func refreshAll() {
    app.invalidateData()
  }

  // Each mutation below claims `runningAction` for the length of its round trip and the reload
  // that follows it, which is what lets the control that started it show the wait. Failures still
  // report to the global banner: this screen is pushed, not presented, so the banner is visible.

  private func changeRole(_ member: OrganizationMember, to role: OrganizationRole) async {
    guard runningAction == nil else { return }
    runningAction = .member(member.userID)
    defer { runningAction = nil }
    do {
      try await app.dependencies.organizations.updateMemberRole(
        organizationID: organizationID,
        userID: member.userID,
        role: role
      )
      refreshAll()
    } catch { app.reportFailure(error) }
  }

  private func remove(_ member: OrganizationMember) async {
    guard runningAction == nil else { return }
    runningAction = .member(member.userID)
    defer { runningAction = nil }
    do {
      try await app.dependencies.organizations.removeMember(
        organizationID: organizationID, userID: member.userID)
      refreshAll()
    } catch { app.reportFailure(error) }
  }

  private func toggleMFA() async {
    guard let organization = state.value, runningAction == nil else { return }
    runningAction = .policy
    defer { runningAction = nil }
    do {
      let policy = try await app.dependencies.organizations.setOrganizationMFA(
        organizationID: organizationID,
        required: !organization.requiresMFA
      )
      refreshAll()
      if policy.mfaSetupRequired {
        app.selectedTab = .account
        app.showNotice(
          "MFA passou a ser obrigatório. Abra Segurança para cadastrar um método.",
          kind: .information
        )
      }
    } catch { app.reportFailure(error) }
  }

  private func transfer(_ billing: Billing, to organization: Organization) async {
    guard runningAction == nil else { return }
    runningAction = .transfer(billing.id)
    defer { runningAction = nil }
    do {
      try await app.dependencies.organizations.transferBilling(
        billingID: billing.id,
        toOrganizationID: organization.id
      )
      refreshAll()
    } catch { app.reportFailure(error) }
  }

  private func deleteOrganization() async {
    guard runningAction == nil else { return }
    runningAction = .delete
    defer { runningAction = nil }
    do {
      try await app.dependencies.organizations.deleteOrganization(id: organizationID)
      app.invalidateData()
      dismiss()
    } catch { app.reportFailure(error) }
  }
}

/// One row of the member list. macOS has no swipe actions and no row selection here, so the
/// pointer is the affordance: the row tints on hover to show it carries an action menu.
private struct MemberRow: View {
  let member: OrganizationMember
  let canManage: Bool
  /// This row's own role change or removal is in flight.
  let isBusy: Bool
  /// Some mutation on the screen is in flight — this row's or another's.
  let isLocked: Bool
  let changeRole: (OrganizationRole) async -> Void
  let remove: () async -> Void

  var body: some View {
    HStack {
      VStack(alignment: .leading) {
        HStack(spacing: RentivoSpacing.tiny) {
          Text(member.email).font(RentivoTypography.bodyStrong)
          if member.isCurrentUser {
            Text("você").font(RentivoTypography.captionStrong).foregroundStyle(RentivoColors.blue)
          }
        }
        Text(member.role.label)
          .font(RentivoTypography.caption)
          .foregroundStyle(RentivoColors.secondaryInk)
      }
      Spacer()
      if member.isCurrentUser {
        Image(
          systemName: member.role == .admin
            ? "crown.fill" : "person.crop.circle.badge.checkmark"
        )
        .foregroundStyle(member.role == .admin ? RentivoColors.amber : RentivoColors.blue)
      } else if canManage {
        if isBusy {
          // The menu is replaced rather than merely dimmed, so the wait reads on the row the
          // change belongs to instead of on a control that looks unavailable for no reason.
          ProgressView().controlSize(.small)
        } else {
          Menu {
            ForEach(OrganizationMemberActions.assignableRoles(excluding: member.role), id: \.self) { role in
              Button(role.label) { Task { await changeRole(role) } }
            }
            Divider()
            Button("Remover", role: .destructive) { Task { await remove() } }
          } label: {
            Image(systemName: "ellipsis.circle")
          }
          .menuStyle(.borderlessButton)
          .menuIndicator(.hidden)
          .fixedSize()
          .disabled(isLocked)
        }
      } else if member.role == .admin {
        Image(systemName: "crown.fill").foregroundStyle(RentivoColors.amber)
      }
    }
    .padding(.horizontal, RentivoSpacing.small)
    .padding(.vertical, RentivoSpacing.small)
    .rentivoHoverTint()
  }
}
