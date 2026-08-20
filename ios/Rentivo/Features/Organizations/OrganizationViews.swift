import SwiftUI
import UIKit

private struct OrganizationListItem: Identifiable, Sendable {
  let organization: Organization
  let billingCount: Int
  var id: OrganizationID { organization.id }
}

enum OrganizationListRules {
  /// The "convites pendentes" banner lives inside the loaded-content closure, so routing an
  /// invitee with no organizations to the empty state would strand them: accepting a first
  /// invitation is the one action they can take, and it would be unreachable.
  static func showsEmptyState(organizationCount: Int, pendingInvitationCount: Int) -> Bool {
    organizationCount == 0 && pendingInvitationCount == 0
  }

  /// Shown in place of the organization cards when the list is empty but invitations are waiting,
  /// so the screen reads as a next step rather than as a failed load.
  static func emptyListHint(canCreateOrganization: Bool) -> String {
    canCreateOrganization
      ? "Aceite um convite pendente para entrar em uma organização, ou crie a sua para começar do zero."
      : "Aceite um convite pendente para entrar em uma organização."
  }
}

enum OrganizationMFAPolicyCopy {
  static func confirmationMessage(
    requiresMFA: Bool,
    currentUserHasMFA: Bool?
  ) -> String {
    let base = "A política será aplicada a todos os membros desta organização."
    guard !requiresMFA else { return base }
    if currentUserHasMFA == false {
      return "\(base) Você ainda não configurou a autenticação em duas etapas. Ao confirmar, será necessário configurá-la para continuar usando o Rentivo."
    }
    if currentUserHasMFA == nil {
      return "\(base) Membros sem autenticação em duas etapas precisarão configurá-la para continuar usando o Rentivo."
    }
    return base
  }
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
      emptyState: EmptyStateConfiguration(
        title: "Nenhuma organização ainda",
        message: canCreateOrganization
          ? "Organizações reúnem cobranças e membros sob papéis e permissões compartilhados. Crie uma para colaborar com sua equipe."
          : "As organizações das quais você participa aparecerão aqui.",
        systemImage: "building.2.fill",
        actionTitle: canCreateOrganization ? "Criar organização" : nil
      ),
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
          if organizations.isEmpty {
            RentivoCard {
              Text(OrganizationListRules.emptyListHint(canCreateOrganization: canCreateOrganization))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("organization.list.empty-hint")
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
      .rentivoTabContent()
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
    .noticeArea(.organizations)
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
      state =
        OrganizationListRules.showsEmptyState(
          organizationCount: values.count,
          pendingInvitationCount: pendingCount
        ) ? .empty : .loaded(values)
    } catch {
      switch state {
      case .loaded, .empty:
        app.showNotice(UserFacingError.message(for: error, operation: .loadOrganizations), kind: .warning)
      default:
        state = .failed(UserFacingError.presentation(for: error, operation: .loadOrganizations).demoError)
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

  private enum Field: Hashable {
    case name
    case pixKey
    case merchantName
    case city
  }

  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  let organization: Organization?
  let onSaved: () async -> Void
  @State private var name: String
  @State private var pixKeyType: PixKeyType
  @State private var pixKey: String
  @State private var preservesUnclassifiedLegacyPixKey: Bool
  @State private var merchantName: String
  @State private var city: String
  @State private var usesCustomPix: Bool
  @State private var pixValidationMessage: String?
  @State private var nameValidationMessage: String?
  @State private var submitFailure: UserFacingFailure?
  @State private var saving = false
  @State private var step: Step = .organization
  @State private var pendingPixKeyType: PixKeyType?
  @State private var confirmingPixKeyTypeChange = false
  @State private var isPixKeyRevealed = false
  @FocusState private var focusedField: Field?
  @AccessibilityFocusState private var accessibilityFocusedField: Field?
  private let initialDraftState: NativeOrganizationDraftState

  init(organization: Organization? = nil, onSaved: @escaping () async -> Void) {
    self.organization = organization
    self.onSaved = onSaved
    let name = organization?.name ?? ""
    let pixInput = PixKeyInput(persistedKey: organization?.pix?.key ?? "")
    let pixKey = pixInput.value
    let merchantName = organization?.pix?.merchantName ?? ""
    let city = organization?.pix?.merchantCity ?? ""
    let usesCustomPix = organization?.pix != nil
    initialDraftState = NativeOrganizationDraftState(
      name: name, pixKey: pixKey, merchantName: merchantName, city: city,
      usesCustomPix: usesCustomPix
    )
    _name = State(initialValue: name)
    _pixKeyType = State(initialValue: pixInput.type)
    _pixKey = State(initialValue: pixKey)
    _preservesUnclassifiedLegacyPixKey = State(
      initialValue: pixInput.preservesUnclassifiedLegacyValue
    )
    _merchantName = State(initialValue: merchantName)
    _city = State(initialValue: city)
    _usesCustomPix = State(initialValue: usesCustomPix)
  }

  var body: some View {
    RentivoFormWizard(
      title: organization == nil ? "Nova organização" : "Editar organização",
      descriptors: descriptors,
      selectedStep: $step,
      isBusy: saving,
      finalActionTitle: organization == nil ? "Criar organização" : "Salvar organização",
      onValidateAndAdvance: validateCurrentStep,
      onCommit: { Task { await save() } }
    ) { selectedStep in
      stepContent(selectedStep)
    }
    .interactiveDismissDisabled(hasUnsavedChanges || saving)
    .onChange(of: step) { _, _ in isPixKeyRevealed = false }
    .confirmationDialog(
      "Alterar tipo de chave?",
      isPresented: $confirmingPixKeyTypeChange,
      titleVisibility: .visible
    ) {
      Button("Alterar e apagar", role: .destructive) {
        guard let pendingPixKeyType else { return }
        pixKeyType = pendingPixKeyType
        pixKey = ""
        preservesUnclassifiedLegacyPixKey = false
        self.pendingPixKeyType = nil
        scheduleFocus(.pixKey)
      }
      Button("Cancelar", role: .cancel) { pendingPixKeyType = nil }
    } message: {
      Text("A chave digitada será apagada para evitar que seja interpretada no formato errado.")
    }
  }

  private var descriptors: [RentivoWizardStepDescriptor<Step>] {
    [
      .init(id: .organization, title: "Organização"),
      .init(id: .pix, title: "Recebimento PIX"),
      .init(id: .review, title: "Revisão"),
    ]
  }

  private var hasUnsavedChanges: Bool {
    NativeOrganizationDraftState(
      name: name,
      pixKey: pixKey,
      merchantName: merchantName,
      city: city,
      usesCustomPix: usesCustomPix
    ).hasChanges(from: initialDraftState)
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
        RentivoTextFormField(
          label: "Nome",
          text: $name,
          errorMessage: nameValidationMessage,
          accessibilityIdentifier: "organization.form.name"
        )
          .focused($focusedField, equals: .name)
          .accessibilityFocused($accessibilityFocusedField, equals: .name)
          .onChange(of: name) {
            if nameValidationMessage != nil {
              nameValidationMessage = OrganizationDraft.nameValidationMessage(name)
            }
          }
      }
    case .pix:
      RentivoWizardSection(
        "Recebimento PIX",
        subtitle: "Escolha se a organização terá dados PIX próprios."
      ) {
        Toggle("Usar PIX da organização", isOn: $usesCustomPix)
          .accessibilityIdentifier("organization.form.pix.enabled")
        if usesCustomPix {
          RentivoFormField(label: "Tipo de chave") {
            Picker("", selection: pixKeyTypeBinding) {
              ForEach(PixKeyType.allCases, id: \.self) { type in Text(type.label).tag(type) }
            }
            .labelsHidden()
            .accessibilityLabel("Tipo de chave")
            .accessibilityIdentifier("organization.form.pix.key-type")
          }
          RentivoTextFormField(
            label: "Chave",
            text: pixKeyBinding,
            hint: pixKeyType.hint,
            errorMessage: pixKeyError,
            accessibilityIdentifier: "organization.form.pix.key"
          )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(pixKeyboardType)
            .focused($focusedField, equals: .pixKey)
            .accessibilityFocused($accessibilityFocusedField, equals: .pixKey)
          RentivoTextFormField(
            label: "Nome do recebedor",
            text: $merchantName,
            errorMessage: pixMerchantNameError,
            accessibilityIdentifier: "organization.form.pix.merchant-name"
          )
            .focused($focusedField, equals: .merchantName)
            .accessibilityFocused($accessibilityFocusedField, equals: .merchantName)
          RentivoTextFormField(
            label: "Cidade",
            text: $city,
            errorMessage: pixCityError,
            accessibilityIdentifier: "organization.form.pix.city"
          )
            .textInputAutocapitalization(.characters)
            .focused($focusedField, equals: .city)
            .accessibilityFocused($accessibilityFocusedField, equals: .city)
        } else {
          Text("Sem PIX próprio. Cobranças podem usar o PIX pessoal do responsável.")
            .font(.footnote)
            .foregroundStyle(RentivoColors.secondaryInk)
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
        if usesCustomPix {
          RentivoPixKeyReview(
            input: currentPixKeyInput,
            isRevealed: $isPixKeyRevealed,
            accessibilityIdentifier: "organization.form.pix.review.reveal"
          )
          RentivoWizardReviewRow(
            label: "Recebedor",
            value: merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
          )
          RentivoWizardReviewRow(
            label: "Cidade", value: city.trimmingCharacters(in: .whitespacesAndNewlines)
          )
        }
      }
      if let submitFailure {
        RentivoWizardSection("Não foi possível salvar") {
          UserFacingFailureView(failure: submitFailure) { openAuthenticatorSetup() }
            .accessibilityIdentifier("organization.form.submit-error")
        }
      }
    }
  }

  private var pixSummary: String {
    usesCustomPix ? "PIX configurado" : "Sem PIX próprio"
  }

  private func openAuthenticatorSetup() {
    dismiss()
    Task { @MainActor in app.navigateToAuthenticatorSetup() }
  }

  private func validationLabel(_ message: String) -> some View {
    Label(message, systemImage: "exclamationmark.circle.fill")
      .font(.footnote)
      .foregroundStyle(RentivoColors.coral)
      .accessibilityIdentifier("organization.form.validation")
  }

  private func validateCurrentStep() -> Bool {
    submitFailure = nil
    switch step {
    case .organization:
      nameValidationMessage = OrganizationDraft.nameValidationMessage(name)
      if nameValidationMessage != nil { scheduleFocus(.name) }
      return nameValidationMessage == nil
    case .pix:
      guard usesCustomPix else {
        pixValidationMessage = nil
        return true
      }
      if case .invalid(let message) = PixFormRules.result(
        type: pixKeyType,
        key: pixKey,
        merchantName: merchantName,
        merchantCity: city,
        preservesUnclassifiedLegacyValue: preservesUnclassifiedLegacyPixKey
      ) {
        pixValidationMessage = message
      } else {
        pixValidationMessage = nil
      }
      if pixValidationMessage != nil { scheduleFocus(firstInvalidPixField) }
      return pixValidationMessage == nil
    case .review:
      return true
    }
  }

  private var firstInvalidPixField: Field {
    let normalizedName = merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
    if currentPixKeyInput.validationMessage != nil {
      return .pixKey
    }
    if normalizedName.isEmpty || normalizedName.unicodeScalars.count > 25 { return .merchantName }
    if normalizedCity.isEmpty || normalizedCity.unicodeScalars.count > 15 { return .city }
    return .pixKey
  }

  private func save() async {
    guard !saving else { return }
    submitFailure = nil
    let result = usesCustomPix
      ? PixFormRules.result(
        type: pixKeyType,
        key: pixKey,
        merchantName: merchantName,
        merchantCity: city,
        preservesUnclassifiedLegacyValue: preservesUnclassifiedLegacyPixKey
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

    guard pixValidationMessage == nil else {
      step = .pix
      scheduleFocus(firstInvalidPixField)
      return
    }

    let draft = OrganizationDraft(
      name: name.trimmingCharacters(in: .whitespacesAndNewlines), pix: pix
    )
    guard draft.isValid else {
      nameValidationMessage = OrganizationDraft.nameValidationMessage(name)
      step = .organization
      scheduleFocus(.name)
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
    } catch {
      submitFailure = UserFacingError.presentation(for: error, operation: .saveOrganization)
    }
  }

  private func scheduleFocus(_ field: Field) {
    Task { @MainActor in
      focusedField = field
      accessibilityFocusedField = field
    }
  }

  private var pixKeyBinding: Binding<String> {
    Binding(
      get: { pixKey },
      set: {
        pixKey = PixKeyInput.formatted($0, as: pixKeyType)
        preservesUnclassifiedLegacyPixKey = false
      }
    )
  }

  private var pixKeyTypeBinding: Binding<PixKeyType> {
    Binding(
      get: { pixKeyType },
      set: { newType in
        guard newType != pixKeyType else { return }
        if currentPixKeyInput.requiresConfirmation(to: newType) {
          pendingPixKeyType = newType
          confirmingPixKeyTypeChange = true
        } else {
          pixKeyType = newType
          preservesUnclassifiedLegacyPixKey = false
        }
      }
    )
  }

  private var pixKeyboardType: UIKeyboardType {
    switch pixKeyType {
    case .cpf, .cnpj: .numberPad
    case .email: .emailAddress
    case .phone: .phonePad
    case .random: .asciiCapable
    }
  }

  private var pixKeyError: String? {
    guard pixValidationMessage != nil else { return nil }
    return currentPixKeyInput.validationMessage
  }

  private var currentPixKeyInput: PixKeyInput {
    PixKeyInput(
      type: pixKeyType,
      value: pixKey,
      preservesUnclassifiedLegacyValue: preservesUnclassifiedLegacyPixKey
    )
  }

  private var pixMerchantNameError: String? {
    guard pixValidationMessage != nil, pixKeyError == nil else { return nil }
    let value = merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.isEmpty { return "Informe o nome do recebedor." }
    if value.unicodeScalars.count > 25 {
      return "O nome do recebedor deve ter até 25 caracteres."
    }
    return nil
  }

  private var pixCityError: String? {
    guard pixValidationMessage != nil, pixKeyError == nil, pixMerchantNameError == nil else {
      return nil
    }
    let value = city.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.isEmpty { return "Informe a cidade do recebedor." }
    if value.unicodeScalars.count > 15 {
      return "A cidade do recebedor deve ter até 15 caracteres."
    }
    return nil
  }
}

private enum OrganizationDetailAction: Equatable {
  case member(Int)
  case policy
  case transfer(BillingID)
  case delete
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
  @State private var activeAction: OrganizationDetailAction?
  @State private var currentUserHasMFA: Bool?

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
      state.value?.requiresMFA == true
        ? "Tornar a autenticação em duas etapas opcional?"
        : "Exigir autenticação em duas etapas?",
      isPresented: $confirmingMFA
    ) {
      Button("Confirmar") { Task { await toggleMFA() } }.disabled(activeAction != nil)
      Button("Cancelar", role: .cancel) {}
    } message: {
      Text(mfaConfirmationMessage)
    }
    .confirmationDialog("Excluir organização?", isPresented: $confirmingDelete) {
      Button("Excluir", role: .destructive) { Task { await deleteOrganization() } }
        .disabled(activeAction != nil)
      Button("Cancelar", role: .cancel) {}
    } message: {
      Text("Primeiro transfira todas as cobranças vinculadas.")
    }
    .task(id: app.dataRevision) { await load() }
    .noticeArea(.organizations)
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
        .buttonStyle(RentivoSecondaryButtonStyle())
        .accessibilityIdentifier("organization.theme")

        if organization.capabilities.canManage {
          Button(role: .destructive) {
            confirmingDelete = true
          } label: {
            Label("Excluir organização", systemImage: "trash").frame(maxWidth: .infinity)
          }
          .buttonStyle(RentivoDestructiveButtonStyle())
          .disabled(activeAction != nil)
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
    .rentivoTabContent()
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
            if member.isCurrentUser {
              memberRow(member, organization: organization)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                  "\(member.email), \(member.role.label), Você, usuário atual"
                    + (member.role == .admin ? ", Dono da organização" : "")
                )
            } else {
              memberRow(member, organization: organization)
            }
          }
        }
      }
    }
  }

  private func memberRow(
    _ member: OrganizationMember,
    organization: Organization
  ) -> some View {
    HStack {
      VStack(alignment: .leading) {
        HStack(spacing: RentivoSpacing.tiny) {
          Text(member.email).font(.subheadline.weight(.semibold))
          if member.isCurrentUser {
            Text("você")
              .font(.caption2.weight(.bold))
              .foregroundStyle(AppChromeSemanticPresentation.currentUserIdentityTone.color)
              .padding(.horizontal, 7)
              .padding(.vertical, 3)
              .background(
                AppChromeSemanticPresentation.currentUserIdentityTone.color.opacity(0.14)
              )
              .clipShape(Capsule())
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
        .foregroundStyle(member.role == .admin ? RentivoColors.amber : RentivoColors.emerald)
        .accessibilityLabel(
          member.role == .admin ? "Dono da organização" : "Usuário atual"
        )
      } else if organization.capabilities.canManage {
        Menu {
          ForEach(OrganizationRole.allCases, id: \.self) { role in
            Button {
              guard role != member.role else { return }
              Task { await changeRole(member, to: role) }
            } label: {
              if role == member.role {
                Label(role.label, systemImage: "checkmark")
              } else {
                Text(role.label)
              }
            }
            .disabled(role == member.role)
          }
          Divider()
          Button("Remover", role: .destructive) { Task { await remove(member) } }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
        .disabled(activeAction != nil)
        .accessibilityLabel("Alterar nível de acesso de \(member.email)")
        .accessibilityIdentifier("organization.member.\(member.userID).role-menu")
      } else if member.role == .admin {
        Image(systemName: "crown.fill")
          .foregroundStyle(RentivoColors.amber)
          .accessibilityLabel("Dono da organização")
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
          .disabled(!organization.capabilities.canManage || activeAction != nil)
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
        .disabled(activeAction != nil)
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
      let security = try? await app.dependencies.security.securitySummary()
      billings = loadedBillings
      currentUserHasMFA = security.map { $0.totpEnabled || !$0.passkeys.isEmpty }
      state = .loaded(loadedOrganization)
    } catch {
      switch state {
      case .loaded, .empty:
        app.showNotice(UserFacingError.message(for: error, operation: .loadOrganization), kind: .warning)
      default:
        state = .failed(UserFacingError.presentation(for: error, operation: .loadOrganization).demoError)
      }
    }
  }

  private func refreshAll() async {
    await load()
    await onMutation()
  }

  private func changeRole(_ member: OrganizationMember, to role: OrganizationRole) async {
    guard activeAction == nil, role != member.role else { return }
    activeAction = .member(member.userID)
    defer { activeAction = nil }
    do {
      try await app.dependencies.organizations.updateMemberRole(
        organizationID: organizationID,
        userID: member.userID,
        role: role
      )
      await refreshAll()
    } catch {
      app.showNotice(UserFacingError.message(for: error, operation: .updateMember), kind: .warning)
    }
  }

  private func remove(_ member: OrganizationMember) async {
    guard activeAction == nil else { return }
    activeAction = .member(member.userID)
    defer { activeAction = nil }
    do {
      try await app.dependencies.organizations.removeMember(
        organizationID: organizationID, userID: member.userID)
      await refreshAll()
    } catch {
      app.showNotice(UserFacingError.message(for: error, operation: .updateMember), kind: .warning)
    }
  }

  private func toggleMFA() async {
    guard activeAction == nil, let organization = state.value else { return }
    activeAction = .policy
    defer { activeAction = nil }
    do {
      let policy = try await app.dependencies.organizations.setOrganizationMFA(
        organizationID: organizationID,
        required: !organization.requiresMFA
      )
      await refreshAll()
      if policy.mfaSetupRequired {
        app.navigateToAuthenticatorSetup()
        app.showNotice(
          "A verificação em duas etapas agora é obrigatória. Em Conta, abra Segurança para configurar.",
          kind: .information,
          owner: .security
        )
      }
    } catch {
      app.showNotice(
        UserFacingError.message(for: error, operation: .changeOrganizationSecurity), kind: .warning)
    }
  }

  private var mfaConfirmationMessage: String {
    OrganizationMFAPolicyCopy.confirmationMessage(
      requiresMFA: state.value?.requiresMFA == true,
      currentUserHasMFA: currentUserHasMFA
    )
  }

  private func transfer(_ billing: Billing, to organization: Organization) async {
    guard activeAction == nil else { return }
    activeAction = .transfer(billing.id)
    defer { activeAction = nil }
    do {
      try await app.dependencies.organizations.transferBilling(
        billingID: billing.id,
        toOrganizationID: organization.id
      )
      await refreshAll()
    } catch {
      app.showNotice(UserFacingError.message(for: error, operation: .transferBilling), kind: .warning)
    }
  }

  private func deleteOrganization() async {
    guard activeAction == nil else { return }
    activeAction = .delete
    defer { activeAction = nil }
    do {
      try await app.dependencies.organizations.deleteOrganization(id: organizationID)
      await onMutation()
      dismiss()
    } catch {
      app.showNotice(UserFacingError.message(for: error, operation: .deleteOrganization), kind: .warning)
    }
  }
}
