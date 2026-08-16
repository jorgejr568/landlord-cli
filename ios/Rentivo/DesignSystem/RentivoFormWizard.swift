import SwiftUI

enum RentivoAsyncDraftLoadRules {
  static func shouldApply<Draft: Equatable>(
    requestDraft: Draft,
    currentDraft: Draft,
    requestRevision: Int,
    currentRevision: Int
  ) -> Bool {
    requestRevision == currentRevision && requestDraft == currentDraft
  }

  static func isPrimaryEnabled(hasLoadedBaseline: Bool) -> Bool {
    hasLoadedBaseline
  }
}

struct RentivoWizardStepDescriptor<Step: Hashable>: Identifiable {
  let id: Step
  let title: String
}

struct RentivoWizardFlow<Step: Hashable> {
  let steps: [Step]
  private(set) var currentIndex = 0

  init(steps: [Step]) {
    precondition(!steps.isEmpty, "A wizard needs at least one step.")
    self.steps = steps
  }

  var current: Step { steps[currentIndex] }
  var progressLabel: String { "Etapa \(currentIndex + 1) de \(steps.count)" }
  var isFirst: Bool { currentIndex == 0 }
  var isLast: Bool { currentIndex == steps.count - 1 }

  @discardableResult
  mutating func advance() -> Bool {
    guard !isLast else { return false }
    currentIndex += 1
    return true
  }

  @discardableResult
  mutating func retreat() -> Bool {
    guard !isFirst else { return false }
    currentIndex -= 1
    return true
  }
}

enum RentivoWizardNavigationPolicy {
  static func primaryTitle(isLast: Bool, finalActionTitle: String) -> String {
    isLast ? finalActionTitle : "Continuar"
  }

  static func closeRequiresConfirmation(isFirst: Bool) -> Bool { !isFirst }
}

struct RentivoFormWizard<Step: Hashable, Content: View>: View {
  let title: String
  let descriptors: [RentivoWizardStepDescriptor<Step>]
  @Binding var selectedStep: Step
  let isDirty: Bool
  let isBusy: Bool
  let isPrimaryEnabled: Bool
  let primaryTitle: String
  let onValidateAndAdvance: () -> Bool
  let onCommit: () -> Void
  private let content: (Step) -> Content

  @Environment(\.dismiss) private var dismiss
  @State private var confirmingDiscard = false

  init(
    title: String,
    descriptors: [RentivoWizardStepDescriptor<Step>],
    selectedStep: Binding<Step>,
    isDirty: Bool,
    isBusy: Bool,
    isPrimaryEnabled: Bool = true,
    primaryTitle: String,
    onValidateAndAdvance: @escaping () -> Bool,
    onCommit: @escaping () -> Void,
    @ViewBuilder content: @escaping (Step) -> Content
  ) {
    precondition(!descriptors.isEmpty, "A wizard needs at least one step.")
    precondition(Set(descriptors.map(\.id)).count == descriptors.count, "Wizard step IDs must be unique.")

    self.title = title
    self.descriptors = descriptors
    _selectedStep = selectedStep
    self.isDirty = isDirty
    self.isBusy = isBusy
    self.isPrimaryEnabled = isPrimaryEnabled
    self.primaryTitle = primaryTitle
    self.onValidateAndAdvance = onValidateAndAdvance
    self.onCommit = onCommit
    self.content = content
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: RentivoSpacing.section) {
          progress
          content(selectedStep)
        }
        .padding(RentivoSpacing.page)
      }
      .background(RentivoColors.paper)
      .safeAreaInset(edge: .bottom) {
        actions
      }
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(action: close) {
            Image(systemName: "xmark")
          }
          .disabled(isBusy)
          .accessibilityLabel("Fechar")
          .accessibilityIdentifier("wizard.close")
        }
      }
      .confirmationDialog(
        "Descartar alterações?",
        isPresented: $confirmingDiscard,
        titleVisibility: .visible
      ) {
        Button("Descartar", role: .destructive) { dismiss() }
        Button("Continuar editando", role: .cancel) {}
      } message: {
        Text("As alterações não salvas serão perdidas.")
      }
    }
  }

  private var selectedIndex: Int {
    descriptors.firstIndex { $0.id == selectedStep } ?? 0
  }

  private var isFirst: Bool { selectedIndex == 0 }
  private var isLast: Bool { selectedIndex == descriptors.count - 1 }
  private var progressLabel: String { "Etapa \(selectedIndex + 1) de \(descriptors.count)" }

  private var progress: some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.small) {
      Text(progressLabel)
        .font(RentivoTypography.metadata)
        .foregroundStyle(RentivoColors.secondaryInk)
        .accessibilityValue(progressLabel)

      HStack(spacing: RentivoSpacing.tiny) {
        ForEach(descriptors.indices, id: \.self) { index in
          Capsule()
            .fill(index <= selectedIndex ? RentivoColors.emerald : RentivoColors.secondaryInk.opacity(0.2))
            .frame(maxWidth: .infinity, minHeight: 6)
        }
      }
      .accessibilityHidden(true)

      Text(descriptors[selectedIndex].title)
        .font(RentivoTypography.title)
        .foregroundStyle(RentivoColors.ink)
    }
  }

  private var actions: some View {
    HStack(spacing: RentivoSpacing.medium) {
      if !isFirst {
        Button("Voltar", action: retreat)
          .buttonStyle(RentivoSecondaryButtonStyle())
          .disabled(isBusy)
          .accessibilityIdentifier("wizard.back")
      }

      Button(action: advanceOrCommit) {
        HStack(spacing: RentivoSpacing.small) {
          if isBusy {
            ProgressView()
              .tint(.white)
          }
          Text(
            RentivoWizardNavigationPolicy.primaryTitle(
              isLast: isLast,
              finalActionTitle: primaryTitle
            )
          )
        }
      }
      .buttonStyle(RentivoButtonStyle())
      .disabled(isBusy || !isPrimaryEnabled)
      .accessibilityIdentifier(isLast ? "wizard.commit" : "wizard.continue")
    }
    .padding(.horizontal, RentivoSpacing.page)
    .padding(.vertical, RentivoSpacing.medium)
    .background(RentivoColors.surface)
    .overlay(alignment: .top) {
      Rectangle()
        .fill(RentivoColors.ink.opacity(0.15))
        .frame(height: 1)
    }
  }

  private func advanceOrCommit() {
    guard !isBusy && isPrimaryEnabled else { return }
    if isLast {
      onCommit()
    } else {
      guard onValidateAndAdvance() else { return }
      selectedStep = descriptors[selectedIndex + 1].id
    }
  }

  private func retreat() {
    guard !isFirst else { return }
    selectedStep = descriptors[selectedIndex - 1].id
  }

  private func close() {
    if RentivoWizardNavigationPolicy.closeRequiresConfirmation(isFirst: isFirst) {
      confirmingDiscard = true
    } else {
      dismiss()
    }
  }
}

struct RentivoWizardSection<Content: View>: View {
  let title: String
  let subtitle: String?
  private let content: Content

  init(
    title: String,
    subtitle: String? = nil,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.subtitle = subtitle
    self.content = content()
  }

  init(
    _ title: String,
    subtitle: String? = nil,
    @ViewBuilder content: () -> Content
  ) {
    self.init(title: title, subtitle: subtitle, content: content)
  }

  var body: some View {
    RentivoCard {
      VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
        Text(title)
          .font(RentivoTypography.cardTitle)
          .foregroundStyle(RentivoColors.ink)
        if let subtitle {
          Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(RentivoColors.secondaryInk)
        }
        content
      }
    }
  }
}

struct RentivoWizardReviewRow: View {
  let label: String
  let value: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: RentivoSpacing.medium) {
      Text(label)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(RentivoColors.secondaryInk)
      Spacer(minLength: RentivoSpacing.medium)
      Text(value)
        .multilineTextAlignment(.trailing)
        .foregroundStyle(RentivoColors.ink)
    }
    .accessibilityElement(children: .combine)
  }
}

extension View {
  func rentivoFullScreenWizard<Content: View>(
    isPresented: Binding<Bool>,
    @ViewBuilder content: @escaping () -> Content
  ) -> some View {
    fullScreenCover(isPresented: isPresented) {
      content()
        .tint(RentivoColors.emerald)
    }
  }
}
