import RentivoCore
import SwiftUI

/// Pure draft rules shared by the API key sheet and its tests.
enum APIKeyFormRules {
  /// Resolves the toggled workspace IDs back into grants, reusing the grant the key already had
  /// for a resource (which carries the server's `available` flag) and synthesizing one only for
  /// resources the key didn't cover before. Sorted so the payload is stable across saves.
  static func grants(
    for resourceIDs: Set<WorkspaceID>,
    original: [WorkspaceID: APIKeyGrant]
  ) -> [APIKeyGrant] {
    resourceIDs
      .sorted { $0.rawValue < $1.rawValue }
      .map { resourceID in
        original[resourceID]
          ?? APIKeyGrant(
            resourceType: resourceID == .personal ? .user : .organization,
            resourceID: resourceID
          )
      }
  }

  /// A key needs a name, at least one scope, and at least one resource to act on; anything less
  /// is a key that either can't be identified later or can't do anything.
  static func isSavable(name: String, scopes: Set<APIKeyScope>, resourceIDs: Set<WorkspaceID>) -> Bool {
    !name.isEmpty && !scopes.isEmpty && !resourceIDs.isEmpty
  }
}

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
              showsActions: !isDemoViewerLocked,
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
      // macOS has no pull-to-refresh, so the reload iOS gets from `.refreshable` is an explicit
      // toolbar command here.
      ToolbarItem(placement: .primaryAction) {
        Button {
          Task { await load() }
        } label: {
          Label("Atualizar", systemImage: "arrow.clockwise")
        }
      }
      if !isDemoViewerLocked {
        ToolbarItem(placement: .primaryAction) {
          Button {
            showingCreate = true
          } label: {
            Label("Criar chave", systemImage: "plus")
          }
          .accessibilityIdentifier("api-key.create")
        }
      }
    }
    .sheet(isPresented: $showingCreate) {
      NavigationStack {
        APIKeyFormView { secret in
          createdSecret = secret
          await load()
        }
      }
      .frame(minWidth: 640, idealWidth: 720, minHeight: 520)
    }
    .sheet(item: $editingKey) { key in
      NavigationStack {
        APIKeyFormView(key: key) { _ in await load() }
      }
      .frame(minWidth: 640, idealWidth: 720, minHeight: 520)
    }
    .sheet(item: $createdSecret) { secret in
      APIKeySecretView(created: secret)
    }
    .task(id: app.dataRevision) { await load() }
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
          Text(key.name)
            .font(RentivoTypography.cardTitle)
            .foregroundStyle(RentivoColors.ink)
            .multilineTextAlignment(.leading)
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
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  let key: APIKeyMetadata?
  let onSaved: (CreatedAPIKeySecret?) async -> Void
  @State private var name: String
  @State private var scopes: Set<APIKeyScope>
  @State private var grantIDs: Set<WorkspaceID>
  @State private var expiresAt: Date
  @State private var organizations: [Organization] = []
  private let originalGrants: [WorkspaceID: APIKeyGrant]

  init(
    key: APIKeyMetadata? = nil,
    onSaved: @escaping (CreatedAPIKeySecret?) async -> Void
  ) {
    self.key = key
    self.onSaved = onSaved
    let grants = key?.grants ?? [APIKeyGrant(resourceType: .user, resourceID: .personal)]
    originalGrants = Dictionary(uniqueKeysWithValues: grants.map { ($0.resourceID, $0) })
    _name = State(initialValue: key?.name ?? "Nova integração")
    _scopes = State(initialValue: key?.scopes ?? [.profileRead, .billingsRead])
    _grantIDs = State(initialValue: Set(grants.map(\.resourceID)))
    _expiresAt = State(initialValue: key?.expiresAt ?? Date(timeIntervalSinceNow: 31_536_000))
  }

  var body: some View {
    Form {
      Section("Identificação") { TextField("Nome", text: $name) }
      Section("Escopos seguros") {
        ForEach(APIKeyScope.integrationCases, id: \.self) { scope in
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
      }
      Section("Acesso") {
        resourceToggle("Conta pessoal", id: .personal)
        ForEach(organizations) { organization in
          resourceToggle(organization.name, id: WorkspaceID(rawValue: organization.id.rawValue))
        }
      }
      Section("Validade") {
        DatePicker("Expira em", selection: $expiresAt, displayedComponents: .date)
      }
    }
    .formStyle(.grouped)
    .navigationTitle(key == nil ? "Nova chave" : "Editar chave")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
      ToolbarItem(placement: .confirmationAction) {
        Button(key == nil ? "Criar" : "Salvar") { Task { await save() } }
          .disabled(!APIKeyFormRules.isSavable(name: name, scopes: scopes, resourceIDs: grantIDs))
      }
    }
    .task {
      organizations = (try? await app.dependencies.organizations.listOrganizations()) ?? []
    }
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
    let draft = APIKeyDraft(
      name: name,
      scopes: scopes,
      grants: APIKeyFormRules.grants(for: grantIDs, original: originalGrants),
      expiresAt: expiresAt
    )
    do {
      if let key {
        _ = try await app.dependencies.apiKeys.updateAPIKey(id: key.id, draft: draft)
        dismiss()
        await onSaved(nil)
        app.showNotice("Metadados da chave atualizados.")
      } else {
        let secret = try await app.dependencies.apiKeys.createAPIKey(draft)
        dismiss()
        await onSaved(secret)
      }
    } catch { app.showNotice(DemoError(error).message, kind: .warning) }
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
        ClipboardCopyButton(value: created.secret, title: "Copiar segredo")
        Spacer()
        Button("Já copiei") { dismiss() }
          .buttonStyle(RentivoButtonStyle())
      }
      .rentivoSheetIntro()
      .padding(RentivoSpacing.page)
      .rentivoPage()
      .navigationTitle("Segredo da chave")
    }
    .frame(minWidth: 640, idealWidth: 720, minHeight: 520)
  }
}

extension CreatedAPIKeySecret: @retroactive Identifiable {
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
