import RentivoCore
import SwiftUI

/// The trailing label — and the accessibility value — of a demo toggle row.
func demoScenarioStateLabel(enabled: Bool) -> String {
  enabled ? "Ativo" : "Inativo"
}

extension AppModel {
  /// Arms the next controlled failure and says so. This pairs the store mutation with its notice
  /// copy, which is what the "Falhar a próxima operação" row does; keeping it off the view makes
  /// the pairing testable without presenting a `Form`.
  func armNextDemoFailure() {
    failNextOperation()
    showNotice("A próxima operação falhará de forma controlada.", kind: .information)
  }

  /// Restores the canonical fixtures and confirms it — the demo screen's reset action, paired
  /// with its notice for the same reason as `armNextDemoFailure()`.
  func restoreDemoData() {
    resetDemo()
    showNotice("Demonstração restaurada.")
  }
}

struct DemoScenariosView: View {
  @Environment(AppModel.self) private var app
  @State private var confirmingReset = false

  var body: some View {
    Form {
      Section {
        Label(
          "Estas opções alteram apenas o repositório em memória e serão removidas da navegação de produção.",
          systemImage: "hammer.fill"
        )
        .font(RentivoTypography.caption)
      }
      RentivoSection("Estados de leitura") {
        settingButton(
          title: "Atraso de 350 ms",
          enabled: app.demoSettings.delayEnabled,
          identifier: "demo.delay-mode"
        ) {
          app.setDelayEnabled(!app.demoSettings.delayEnabled)
        }
        settingButton(
          title: "Conteúdo vazio",
          enabled: app.demoSettings.emptyMode,
          identifier: "demo.empty-mode"
        ) {
          app.setEmptyMode(!app.demoSettings.emptyMode)
        }
        settingButton(
          title: "Permissões de visualizador",
          enabled: app.demoSettings.viewerMode,
          identifier: "demo.viewer-mode"
        ) {
          app.setViewerMode(!app.demoSettings.viewerMode)
        }
      }
      RentivoSection("Falhas recuperáveis") {
        Button {
          app.armNextDemoFailure()
        } label: {
          Label(
            "Falhar a próxima operação", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
        }
        .accessibilityIdentifier("demo.fail-next")
      }
      RentivoSection("Dados canônicos") {
        Button("Restaurar toda a demonstração", role: .destructive) {
          confirmingReset = true
        }
        .accessibilityIdentifier("demo.reset")
      }
    }
    // Grouped is the macOS equivalent of the inset-grouped list iOS renders a `Form` as. The
    // scroll background is hidden so the screen keeps the app's paper backdrop instead of the
    // system's window chrome color.
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
    .background(RentivoColors.paper)
    .navigationTitle("Cenários")
    .confirmationDialog("Restaurar todos os dados?", isPresented: $confirmingReset) {
      Button("Restaurar", role: .destructive) { app.restoreDemoData() }
      Button("Cancelar", role: .cancel) {}
    } message: {
      Text("Cobranças, faturas, despesas, organizações e configurações voltarão ao estado inicial.")
    }
  }

  private func settingButton(
    title: String,
    enabled: Bool,
    identifier: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack {
        Text(title)
        Spacer()
        Label(
          demoScenarioStateLabel(enabled: enabled),
          systemImage: enabled ? "checkmark.circle.fill" : "circle"
        )
        .foregroundStyle(enabled ? RentivoColors.emerald : RentivoColors.secondaryInk)
      }
      // Without a plain style the row would render as a bordered macOS control and the `Spacer()`
      // would collapse; the explicit shape keeps the whole row — not just its labels — clickable.
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(RentivoColors.ink)
    .accessibilityIdentifier(identifier)
    .accessibilityValue(demoScenarioStateLabel(enabled: enabled))
  }
}
