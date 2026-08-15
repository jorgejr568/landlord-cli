import SwiftUI
import UIKit

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
    .sheet(isPresented: $showingCreate) {
      NavigationStack {
        APIKeyFormView { secret in
          createdSecret = secret
          await load()
        }
      }
    }
    .sheet(item: $editingKey) { key in
      NavigationStack {
        APIKeyFormView(key: key) { _ in await load() }
      }
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
          ptBRCount(
            key.grants.count + key.unavailableGrantCount,
            singular: "acesso", plural: "acessos"
          ),
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
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  let key: APIKeyMetadata?
  let onSaved: (CreatedAPIKeySecret?) async -> Void
  @State private var name: String
  @State private var scopes: Set<APIKeyScope>
  @State private var grantIDs: Set<WorkspaceID>
  @State private var expiresAt: Date
  @State private var options: LoadState<APIKeyOptions> = .idle
  /// Server-side rejection (e.g. a 422) for the last submit. This form is presented in a sheet
  /// and the global notice banner renders behind it, so the message has to stay inline.
  @State private var submitErrorMessage: String?
  @State private var saving = false
  @State private var confirmingDiscard = false
  @State private var expiresAtEdited = false
  private let originalGrants: [WorkspaceID: APIKeyGrant]
  private let originalGrantIDs: Set<WorkspaceID>
  private let initialDraftState: NativeAPIKeyDraftState

  init(
    key: APIKeyMetadata? = nil,
    onSaved: @escaping (CreatedAPIKeySecret?) async -> Void
  ) {
    self.key = key
    self.onSaved = onSaved
    let grants = key?.grants ?? [APIKeyGrant(resourceType: .user, resourceID: .personal)]
    let name = key?.name ?? "Nova integração"
    let scopes = key?.scopes ?? [.profileRead, .billingsRead]
    let grantIDs = Set(grants.filter(\.available).map(\.resourceID))
    originalGrants = Dictionary(uniqueKeysWithValues: grants.map { ($0.resourceID, $0) })
    originalGrantIDs = grantIDs
    initialDraftState = NativeAPIKeyDraftState(
      name: name, scopes: scopes, resourceIDs: grantIDs
    )
    _name = State(initialValue: name)
    _scopes = State(initialValue: scopes)
    _grantIDs = State(initialValue: originalGrantIDs)
    _expiresAt = State(initialValue: key?.expiresAt ?? Date())
  }

  var body: some View {
    Form {
      Section("Identificação") { TextField("Nome", text: $name) }
      Section("Escopos seguros") {
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
        if let key, key.unsupportedScopeCount > 0 {
          Text("Alguns escopos desta chave exigem uma versão mais nova do app e serão preservados.")
            .foregroundStyle(RentivoColors.secondaryInk)
        }
      }
      Section("Acesso") {
        switch options {
        case .loaded(let options):
          resourceToggle(options.personalWorkspace.name, id: options.personalWorkspace.resourceID)
          ForEach(options.organizations) { workspace in
            resourceToggle(workspace.name, id: workspace.resourceID)
          }
        case .idle, .loading:
          ProgressView("Carregando espaços de trabalho…")
        case .empty:
          EmptyView()
        case .failed(let error):
          optionsFailure(error)
        }
        if let key, key.unavailableGrantCount > 0 {
          Text("Alguns acessos protegidos não podem ser editados neste dispositivo e serão preservados.")
            .foregroundStyle(RentivoColors.secondaryInk)
        }
      }
      if key == nil, let options = options.value {
        Section("Validade") {
          DatePicker(
            "Expira em",
            selection: expiresAtBinding,
            in: Date().addingTimeInterval(60)...options.maximumExpiration(),
            displayedComponents: .date
          )
        }
      }
      if let submitErrorMessage {
        Section {
          Label(submitErrorMessage, systemImage: "exclamationmark.circle.fill")
            .foregroundStyle(RentivoColors.coral)
            .accessibilityIdentifier("api-key.form.error")
        }
      }
    }
    .navigationTitle(key == nil ? "Nova chave" : "Editar chave")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancelar") {
          if hasUnsavedChanges { confirmingDiscard = true } else { dismiss() }
        }
        .disabled(saving)
      }
      ToolbarItem(placement: .confirmationAction) {
        // The spinner is the only sign the request is still in flight: everything else this form
        // does while saving is a disable, which on a stalled request reads as a frozen sheet.
        Button {
          Task { await save() }
        } label: {
          HStack(spacing: RentivoSpacing.small) {
            if saving { ProgressView() }
            Text(key == nil ? "Criar" : "Salvar")
          }
        }
        .disabled(
          saving || options.value == nil || !APIKeyValidation.isValidName(name)
            || scopes.isEmpty || grantIDs.isEmpty
        )
      }
    }
    .interactiveDismissDisabled(saving || hasUnsavedChanges)
    .confirmationDialog(
      "Descartar as alterações?", isPresented: $confirmingDiscard, titleVisibility: .visible
    ) {
      Button("Descartar", role: .destructive) { dismiss() }
      Button("Continuar editando", role: .cancel) {}
    }
    .task { await loadOptions() }
  }

  private var hasUnsavedChanges: Bool {
    NativeAPIKeyDraftState(name: name, scopes: scopes, resourceIDs: grantIDs)
      .hasChanges(from: initialDraftState, expirationEdited: expiresAtEdited)
  }

  private var expiresAtBinding: Binding<Date> {
    Binding(
      get: { expiresAt },
      set: { value in
        expiresAt = value
        expiresAtEdited = true
      }
    )
  }

  private func loadOptions() async {
    options = .loading
    do {
      let loaded = try await app.dependencies.apiKeys.apiKeyOptions()
      options = loaded.scopes.isEmpty ? .empty : .loaded(loaded)
      if key == nil {
        scopes.formIntersection(Set(loaded.scopes))
        expiresAt = loaded.defaultExpiration()
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
    .disabled((key?.unsupportedScopeCount ?? 0) > 0)
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
    .disabled((key?.unavailableGrantCount ?? 0) > 0)
  }

  private func save() async {
    guard !saving, let options = options.value else { return }
    submitErrorMessage = nil
    let grants =
      grantIDs
      .sorted { $0.rawValue < $1.rawValue }
      .map { resourceID in
        originalGrants[resourceID]
          ?? APIKeyGrant(
            resourceType: resourceID == .personal ? .user : .organization,
            resourceID: resourceID
          )
      }
    let draft = APIKeyDraft(
      name: name.trimmingCharacters(in: .whitespacesAndNewlines),
      scopes: scopes,
      grants: grants,
      expiresAt: key?.expiresAt ?? options.clampedExpiration(expiresAt),
      shouldUpdateGrants: key == nil
        || ((key?.unavailableGrantCount ?? 0) == 0 && grantIDs != originalGrantIDs),
      shouldUpdateScopes: key == nil
        || ((key?.unsupportedScopeCount ?? 0) == 0 && scopes != key?.scopes)
    )
    saving = true
    defer { saving = false }
    do {
      if let key {
        _ = try await app.dependencies.apiKeys.updateAPIKey(
          id: key.id,
          draft: draft,
          updateGrants: draft.shouldUpdateGrants
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
        HStack {
          Button {
            UIPasteboard.general.string = created.secret
          } label: {
            Label("Copiar segredo", systemImage: "doc.on.doc")
          }
          ShareLink(item: created.secret) {
            Label("Compartilhar", systemImage: "square.and.arrow.up")
          }
        }
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
