import SwiftUI

struct APIKeyListView: View {
  @Environment(AppModel.self) private var app
  @State private var state: LoadState<[APIKeyMetadata]> = .idle
  @State private var showingCreate = false
  @State private var createdSecret: CreatedAPIKeySecret?
  @State private var editingKey: APIKeyMetadata?
  @State private var keyPendingRevoke: APIKeyMetadata?

  /// Demo "viewer mode" is a local demo/mock-backend concept only. Once the app is
  /// connected to the live API, the signed-in user owns their own account and this
  /// screen should be fully enabled regardless of the demo viewer-mode toggle.
  private var isDemoViewerLocked: Bool {
    !app.usesLiveAPI && app.demoSettings.viewerMode
  }

  var body: some View {
    let canCreate = !isDemoViewerLocked
    PageStateView(
      state: state,
      emptyTitle: "Nenhuma chave de integração",
      emptyMessage: "Crie uma chave de API para conectar integrações externas com escopos e acessos controlados.",
      emptySystemImage: "key.fill",
      emptyActionTitle: canCreate ? "Criar chave" : nil,
      emptyAction: canCreate ? { showingCreate = true } : nil
    ) { keys in
      ScrollView {
        LazyVStack(spacing: RentivoSpacing.large) {
          ForEach(keys) { key in
            APIKeyCard(
              key: key,
              showsActions: !isDemoViewerLocked && key.revokedAt == nil,
              onEdit: { editingKey = key },
              onRevoke: { keyPendingRevoke = key }
            )
          }
        }
        .padding(RentivoSpacing.page)
      }
    } retry: {
      await load()
    }
    .background(RentivoColors.paper)
    .navigationTitle("Chaves de integração")
    .toolbar {
      if !isDemoViewerLocked {
        Button {
          showingCreate = true
        } label: {
          Label("Criar chave", systemImage: "plus")
        }
        .accessibilityIdentifier("api-key.create")
      }
    }
    .rentivoFullScreenWizard(isPresented: $showingCreate) {
      APIKeyFormView { secret in
        createdSecret = secret
        await load()
      }
    }
    .fullScreenCover(item: $editingKey) { key in
      APIKeyFormView(key: key) { _ in await load() }
        .tint(RentivoColors.emerald)
    }
    .sheet(item: $createdSecret) { secret in
      APIKeySecretView(created: secret)
    }
    .task(id: app.dataRevision) { await load() }
    .refreshable { await load() }
    .confirmationDialog(
      "Revogar esta chave de integração?",
      isPresented: Binding(
        get: { keyPendingRevoke != nil },
        set: { if !$0 { keyPendingRevoke = nil } }
      ),
      presenting: keyPendingRevoke
    ) { key in
      Button("Revogar chave", role: .destructive) {
        Task { await revoke(key) }
      }
      .accessibilityIdentifier("api-key.revoke.confirm")
      Button("Cancelar", role: .cancel) {}
        .accessibilityIdentifier("api-key.revoke.cancel")
    } message: { key in
      Text("Qualquer integração usando \"\(key.name)\" perderá acesso imediatamente. Esta ação não pode ser desfeita.")
    }
  }

  private func load() async {
    state = .loading
    do {
      let keys = try await app.dependencies.apiKeys.listAPIKeys()
      state = keys.isEmpty ? .empty : .loaded(keys)
    } catch { state = .failed(DemoError(error)) }
  }

  private func revoke(_ key: APIKeyMetadata) async {
    do {
      try await app.dependencies.apiKeys.revokeAPIKey(id: key.id)
      await load()
      app.showNotice("Chave revogada.")
    } catch { app.showNotice(DemoError(error).message, kind: .warning) }
  }
}

private struct APIKeyCard: View {
  let key: APIKeyMetadata
  let showsActions: Bool
  let onEdit: () -> Void
  let onRevoke: () -> Void

  var body: some View {
    RentivoCard {
      VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
        VStack(alignment: .leading, spacing: RentivoSpacing.tiny) {
          HStack(alignment: .firstTextBaseline, spacing: RentivoSpacing.small) {
            Text(key.name)
              .font(RentivoTypography.cardTitle)
              .foregroundStyle(RentivoColors.ink)
              .multilineTextAlignment(.leading)
            if key.revokedAt != nil {
              Text("Revogada")
                .font(.caption.weight(.semibold))
                .foregroundStyle(RentivoColors.coral)
                .accessibilityIdentifier("api-key.revoked")
            }
          }
          Label(key.hint, systemImage: "key.fill")
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(RentivoColors.secondaryInk)
        }
        // Scopes are never truncated: this is the only place outside the edit sheet that
        // shows what an integration is allowed to do, so the card grows instead.
        Text(key.scopes.map(\.label).sorted().joined(separator: " · "))
          .font(.subheadline)
          .foregroundStyle(RentivoColors.secondaryInk)
        HStack(alignment: .top) {
          dateColumn("Criada em", value: key.createdAt, alignment: .leading)
          Spacer()
          dateColumn("Expira em", value: key.expiresAt, alignment: .trailing)
        }
        Label(
          ptBRCount(key.grants.count, singular: "acesso", plural: "acessos"),
          systemImage: "person.2.fill"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(RentivoColors.secondaryInk)
        if showsActions {
          // `RentivoButtonStyle` already expands to the available width, so the HStack
          // splits the footer 50/50.
          HStack(spacing: RentivoSpacing.medium) {
            Button("Editar", action: onEdit)
              .buttonStyle(RentivoButtonStyle(color: RentivoColors.blue))
              .accessibilityIdentifier("api-key.edit")
            Button("Revogar", action: onRevoke)
              .buttonStyle(RentivoButtonStyle(color: RentivoColors.coral))
              .accessibilityIdentifier("api-key.revoke")
          }
        }
      }
    }
  }

  private func dateColumn(
    _ title: String,
    value: Date,
    alignment: HorizontalAlignment
  ) -> some View {
    VStack(alignment: alignment, spacing: RentivoSpacing.tiny) {
      Text(title)
        .font(.caption)
        .foregroundStyle(RentivoColors.secondaryInk)
      Text(value.formattedPTBR())
        .font(RentivoTypography.metadata)
        .foregroundStyle(RentivoColors.ink)
    }
  }
}

private struct APIKeyFormView: View {
  private enum Step: CaseIterable {
    case identification
    case scopes
    case access
    case expiration
    case review
  }

  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  let key: APIKeyMetadata?
  let onSaved: (CreatedAPIKeySecret?) async -> Void
  @State private var name: String
  @State private var scopes: Set<APIKeyScope>
  @State private var grantIDs: Set<WorkspaceID>
  @State private var expiresAt: Date
  @State private var options: LoadState<APIKeyOptions> = .idle
  @State private var step: Step = .identification
  @State private var validationMessage: String?
  @State private var submitErrorMessage: String?
  @State private var saving = false
  @State private var baselineScopes: Set<APIKeyScope>
  @State private var baselineExpiresAt: Date?
  private let originalGrants: [WorkspaceID: APIKeyGrant]
  private let originalGrantIDs: Set<WorkspaceID>
  private let initialName: String

  init(
    key: APIKeyMetadata? = nil,
    onSaved: @escaping (CreatedAPIKeySecret?) async -> Void
  ) {
    self.key = key
    self.onSaved = onSaved
    let grants = key?.grants ?? [APIKeyGrant(resourceType: .user, resourceID: .personal)]
    originalGrants = Dictionary(uniqueKeysWithValues: grants.map { ($0.resourceID, $0) })
    originalGrantIDs = Set(grants.filter(\.available).map(\.resourceID))
    initialName = key?.name ?? "Nova integração"
    let initialScopes = key?.scopes ?? [.profileRead, .billingsRead]
    _name = State(initialValue: initialName)
    _scopes = State(initialValue: initialScopes)
    _baselineScopes = State(initialValue: initialScopes)
    _grantIDs = State(initialValue: originalGrantIDs)
    _expiresAt = State(initialValue: key?.expiresAt ?? Date())
    _baselineExpiresAt = State(initialValue: key?.expiresAt)
  }

  var body: some View {
    RentivoFormWizard(
      title: key == nil ? "Nova chave" : "Editar chave",
      descriptors: descriptors,
      selectedStep: $step,
      isDirty: isDirty,
      isBusy: saving,
      primaryTitle: step == .review ? (key == nil ? "Criar" : "Salvar") : "Continuar",
      onValidateAndAdvance: validateCurrentStep,
      onCommit: { Task { await save() } }
    ) { selectedStep in
      stepContent(selectedStep)
    }
    .interactiveDismissDisabled(isDirty || saving)
    .task { await loadOptions() }
  }

  private var descriptors: [RentivoWizardStepDescriptor<Step>] {
    [
      .init(id: .identification, title: "Identificação"),
      .init(id: .scopes, title: "Escopos"),
      .init(id: .access, title: "Acessos"),
      .init(id: .expiration, title: "Expiração"),
      .init(id: .review, title: "Revisão"),
    ]
  }

  private var isDirty: Bool {
    name != initialName || scopes != baselineScopes || grantIDs != originalGrantIDs
      || (key == nil && baselineExpiresAt.map { expiresAt != $0 } == true)
  }

  @ViewBuilder
  private func stepContent(_ step: Step) -> some View {
    switch step {
    case .identification:
      RentivoWizardSection(
        "Identifique a integração",
        subtitle: "Use um nome que deixe claro onde esta chave será usada."
      ) {
        TextField("Nome", text: $name)
        if let validationMessage { errorLabel(validationMessage) }
      }
    case .scopes:
      RentivoWizardSection(
        "Escopos seguros",
        subtitle: "Conceda somente as operações necessárias para a integração."
      ) {
        switch options {
        case .loaded(let options):
          ForEach(options.scopes, id: \.self) { scope in scopeToggle(scope) }
        case .idle, .loading:
          ProgressView("Carregando opções…")
        case .empty:
          Text("Nenhum escopo de integração está disponível.")
            .foregroundStyle(RentivoColors.secondaryInk)
        case .failed(let error):
          optionsFailure(error)
        }
        if let validationMessage { errorLabel(validationMessage) }
      }
    case .access:
      RentivoWizardSection(
        "Espaços de trabalho",
        subtitle: "Escolha em quais contas e organizações a chave poderá atuar."
      ) {
        switch options {
        case .loaded(let options):
          resourceToggle(options.personalWorkspace.name, id: options.personalWorkspace.resourceID)
          ForEach(options.organizations) { workspace in
            resourceToggle(workspace.name, id: workspace.resourceID)
          }
          ForEach(preservedUnavailableGrants, id: \.resourceID) { grant in
            HStack {
              Label("Acesso original indisponível", systemImage: "lock.fill")
              Spacer()
              Text("Mantido")
                .font(.caption.weight(.semibold))
                .foregroundStyle(RentivoColors.secondaryInk)
            }
            .accessibilityElement(children: .combine)
          }
        case .idle, .loading:
          ProgressView("Carregando espaços de trabalho…")
        case .empty:
          Text("Nenhum acesso está disponível.")
            .foregroundStyle(RentivoColors.secondaryInk)
        case .failed(let error):
          optionsFailure(error)
        }
        if let validationMessage { errorLabel(validationMessage) }
      }
    case .expiration:
      RentivoWizardSection(
        "Validade da chave",
        subtitle: key == nil
          ? "A chave deixa de funcionar automaticamente depois desta data."
          : "A validade de uma chave existente não pode ser alterada."
      ) {
        if key == nil, let options = options.value {
          DatePicker(
            "Expira em",
            selection: $expiresAt,
            in: Date().addingTimeInterval(60)...options.maximumExpiration(),
            displayedComponents: .date
          )
        } else if let key {
          RentivoWizardReviewRow(label: "Expira em", value: key.expiresAt.formattedPTBR())
        } else {
          optionsStateView(loadingMessage: "Carregando validade…")
        }
        if let validationMessage { errorLabel(validationMessage) }
      }
    case .review:
      RentivoWizardSection("Chave de integração") {
        RentivoWizardReviewRow(
          label: "Nome", value: name.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        RentivoWizardReviewRow(label: "Escopos", value: "\(scopes.count)")
        RentivoWizardReviewRow(label: "Acessos", value: "\(allDraftGrants.count)")
        RentivoWizardReviewRow(
          label: "Expira em", value: (key?.expiresAt ?? expiresAt).formattedPTBR()
        )
      }
      if let submitErrorMessage {
        RentivoWizardSection("Não foi possível salvar") {
          errorLabel(submitErrorMessage)
        }
      }
    }
  }

  private var preservedUnavailableGrants: [APIKeyGrant] {
    originalGrants.values
      .filter { !$0.available }
      .sorted { $0.resourceID.rawValue < $1.resourceID.rawValue }
  }

  private var allDraftGrants: [APIKeyGrant] {
    let available = grantIDs.map { resourceID in
      originalGrants[resourceID]
        ?? APIKeyGrant(
          resourceType: resourceID == .personal ? .user : .organization,
          resourceID: resourceID
        )
    }
    return (available + preservedUnavailableGrants)
      .sorted { $0.resourceID.rawValue < $1.resourceID.rawValue }
  }

  @ViewBuilder
  private func optionsStateView(loadingMessage: String) -> some View {
    switch options {
    case .idle, .loading:
      ProgressView(loadingMessage)
    case .failed(let error):
      optionsFailure(error)
    case .empty:
      Text("As opções da chave estão indisponíveis.")
        .foregroundStyle(RentivoColors.secondaryInk)
    case .loaded:
      EmptyView()
    }
  }

  private func errorLabel(_ message: String) -> some View {
    Label(message, systemImage: "exclamationmark.circle.fill")
      .font(.footnote)
      .foregroundStyle(RentivoColors.coral)
      .accessibilityIdentifier("api-key.form.error")
  }

  private func validateCurrentStep() -> Bool {
    submitErrorMessage = nil
    validationMessage = nil
    switch step {
    case .identification:
      guard APIKeyValidation.isValidName(name) else {
        validationMessage = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? "Informe o nome da chave."
          : "O nome da chave deve ter até 255 caracteres."
        return false
      }
    case .scopes:
      guard options.value != nil else {
        validationMessage = "Aguarde o carregamento das opções antes de continuar."
        return false
      }
      guard !scopes.isEmpty else {
        validationMessage = "Selecione ao menos um escopo."
        return false
      }
    case .access:
      guard options.value != nil else {
        validationMessage = "Aguarde o carregamento dos acessos antes de continuar."
        return false
      }
      guard !allDraftGrants.isEmpty else {
        validationMessage = "Selecione ao menos um acesso."
        return false
      }
    case .expiration:
      guard options.value != nil else {
        validationMessage = "Aguarde o carregamento da validade antes de continuar."
        return false
      }
    case .review:
      break
    }
    return true
  }

  private func loadOptions() async {
    options = .loading
    do {
      let loaded = try await app.dependencies.apiKeys.apiKeyOptions()
      options = loaded.scopes.isEmpty ? .empty : .loaded(loaded)
      if key == nil {
        scopes.formIntersection(Set(loaded.scopes))
        baselineScopes = scopes
        expiresAt = loaded.defaultExpiration()
        baselineExpiresAt = expiresAt
      }
    } catch { options = .failed(DemoError(error)) }
  }

  private func optionsFailure(_ error: DemoError) -> some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.small) {
      Label(error.message, systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(RentivoColors.coral)
      Button("Tentar novamente") { Task { await loadOptions() } }
    }
  }

  private func scopeToggle(_ scope: APIKeyScope) -> some View {
    Toggle(
      scope.label,
      isOn: Binding(
        get: { scopes.contains(scope) },
        set: { enabled in
          if enabled { scopes.insert(scope) } else { scopes.remove(scope) }
        }
      )
    )
  }

  private func resourceToggle(_ label: String, id: WorkspaceID) -> some View {
    Toggle(
      label,
      isOn: Binding(
        get: { grantIDs.contains(id) },
        set: { enabled in
          if enabled { grantIDs.insert(id) } else { grantIDs.remove(id) }
        }
      )
    )
  }

  private func save() async {
    guard !saving, let options = options.value else { return }
    submitErrorMessage = nil
    guard APIKeyValidation.isValidName(name), !scopes.isEmpty, !allDraftGrants.isEmpty else {
      step = !APIKeyValidation.isValidName(name) ? .identification : (scopes.isEmpty ? .scopes : .access)
      _ = validateCurrentStep()
      return
    }
    let draft = APIKeyDraft(
      name: name.trimmingCharacters(in: .whitespacesAndNewlines),
      scopes: scopes,
      grants: allDraftGrants,
      expiresAt: key?.expiresAt ?? options.clampedExpiration(expiresAt)
    )
    saving = true
    defer { saving = false }
    do {
      if let key {
        _ = try await app.dependencies.apiKeys.updateAPIKey(
          id: key.id,
          draft: draft,
          updateGrants: grantIDs != originalGrantIDs
        )
        dismiss()
        await onSaved(nil)
        app.showNotice("Metadados da chave atualizados.")
      } else {
        let secret = try await app.dependencies.apiKeys.createAPIKey(draft)
        dismiss()
        await onSaved(secret)
      }
    } catch { submitErrorMessage = DemoError(error).message }
  }
}

private struct APIKeySecretView: View {
  @Environment(\.dismiss) private var dismiss
  let created: CreatedAPIKeySecret

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: RentivoSpacing.large) {
        Label("Copie agora", systemImage: "exclamationmark.shield.fill")
          .font(RentivoTypography.title)
          .foregroundStyle(RentivoColors.amber)
        Text("Este segredo não será exibido novamente.")
        Text(created.secret)
          .font(.system(.body, design: .monospaced, weight: .bold))
          .textSelection(.enabled)
          .padding()
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(RentivoColors.surface)
          .clipShape(RoundedRectangle(cornerRadius: 12))
        Spacer()
        Button("Já copiei") { dismiss() }
          .buttonStyle(RentivoButtonStyle())
      }
      .padding(RentivoSpacing.page)
      .background(RentivoColors.paper)
      .navigationTitle("Segredo da chave")
    }
  }
}

extension CreatedAPIKeySecret: Identifiable {
  public var id: APIKeyID { metadata.id }
}

extension APIKeyScope {
  fileprivate var label: String {
    switch self {
    case .profileRead: "Ler perfil"
    case .accountWrite: "Alterar conta"
    case .securityManage: "Gerenciar segurança"
    case .apiKeysManage: "Gerenciar chaves de API"
    case .organizationsRead: "Ler organizações"
    case .organizationsWrite: "Alterar organizações"
    case .organizationsMembers: "Gerenciar membros"
    case .billingsRead: "Ler cobranças"
    case .billingsWrite: "Alterar cobranças"
    case .billsRead: "Ler faturas"
    case .billsWrite: "Alterar faturas"
    case .expensesRead: "Ler despesas"
    case .expensesWrite: "Alterar despesas"
    case .filesRead: "Ler arquivos"
    case .filesWrite: "Alterar arquivos"
    case .communicationsRead: "Ler comunicações"
    case .communicationsSend: "Enviar comunicações"
    case .themesRead: "Ler temas"
    case .themesWrite: "Alterar temas"
    case .exportsCreate: "Criar exportações"
    }
  }
}
