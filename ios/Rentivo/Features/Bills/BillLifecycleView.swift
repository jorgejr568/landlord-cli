import SwiftUI
import UIKit

enum BillTimelineStageState: Equatable, Sendable {
  case completed
  case current
  case future
}

struct BillTimelineStage: Equatable, Sendable {
  let status: BillStatus
  let state: BillTimelineStageState

  var accessibilityLabel: String {
    let suffix = switch state {
    case .completed: "etapa concluída"
    case .current: "status atual"
    case .future: "próxima etapa"
    }
    return "\(status.label), \(suffix)"
  }
}

struct BillTimelinePresentation: Equatable, Sendable {
  let canonicalStages: [BillTimelineStage]
  let branch: BillTimelineStage?

  var accessibilityStages: [BillTimelineStage] {
    canonicalStages + (branch.map { [$0] } ?? [])
  }

  init(currentStatus: BillStatus) {
    let canonical: [BillStatus] = [.draft, .published, .sent, .paid]
    switch currentStatus {
    case .delayedPayment:
      canonicalStages = canonical.map { status in
        BillTimelineStage(status: status, state: status == .paid ? .future : .completed)
      }
      branch = BillTimelineStage(status: .delayedPayment, state: .current)
    case .cancelled:
      canonicalStages = canonical.map { BillTimelineStage(status: $0, state: .future) }
      branch = BillTimelineStage(status: .cancelled, state: .current)
    case .draft, .published, .sent, .paid:
      let currentIndex = canonical.firstIndex(of: currentStatus) ?? 0
      canonicalStages = canonical.enumerated().map { index, status in
        let state: BillTimelineStageState = if index < currentIndex {
          .completed
        } else if index == currentIndex {
          .current
        } else {
          .future
        }
        return BillTimelineStage(status: status, state: state)
      }
      branch = nil
    }
  }
}

enum BillLifecycleActionKind: Equatable, Sendable {
  case primary
  case forwardAlternative
  case rollback
  case destructiveCancellation
}

struct BillLifecyclePresentedAction: Equatable, Sendable {
  let action: BillTransition
  let kind: BillLifecycleActionKind

  var isDestructive: Bool { kind == .destructiveCancellation }
  var isRollback: Bool { kind == .rollback }

  var requiresConfirmation: Bool {
    action.requiresConfirmation || isRollback || isDestructive
  }

  var confirmationTitle: String? {
    guard requiresConfirmation else { return nil }
    return isDestructive ? "Cancelar esta fatura?" : action.label
  }

  var confirmationMessage: String? {
    guard requiresConfirmation else { return nil }
    switch kind {
    case .rollback:
      return "O status da fatura voltará para uma etapa anterior. Confirme para continuar."
    case .destructiveCancellation:
      return "A fatura sairá do ciclo de cobrança. Confirme para continuar."
    case .primary, .forwardAlternative:
      return "Confirme a alteração de status desta fatura."
    }
  }
}

struct BillLifecyclePresentation: Equatable, Sendable {
  let primaryAction: BillLifecyclePresentedAction?
  let menuActions: [BillLifecyclePresentedAction]
  let isTerminal: Bool
}

enum BillLifecyclePresentationPolicy {
  static func presentation(
    for currentStatus: BillStatus,
    actions: [BillTransition]
  ) -> BillLifecyclePresentation {
    let naturalTarget = naturalPrimaryTarget(for: currentStatus)
    let primaryIndex = naturalTarget.flatMap { target in
      actions.firstIndex { $0.target == target }
    }
    let primaryAction = primaryIndex.map {
      BillLifecyclePresentedAction(action: actions[$0], kind: .primary)
    }

    var forward: [BillLifecyclePresentedAction] = []
    var rollbacks: [BillLifecyclePresentedAction] = []
    var cancellations: [BillLifecyclePresentedAction] = []

    for (index, action) in actions.enumerated() where index != primaryIndex {
      let kind = menuKind(from: currentStatus, to: action.target)
      let presented = BillLifecyclePresentedAction(action: action, kind: kind)
      switch kind {
      case .forwardAlternative: forward.append(presented)
      case .rollback: rollbacks.append(presented)
      case .destructiveCancellation: cancellations.append(presented)
      case .primary: break
      }
    }

    return BillLifecyclePresentation(
      primaryAction: primaryAction,
      menuActions: forward + rollbacks + cancellations,
      isTerminal: actions.isEmpty
    )
  }

  private static func naturalPrimaryTarget(for status: BillStatus) -> BillStatus? {
    switch status {
    case .draft: .published
    case .published: .sent
    case .sent, .delayedPayment: .paid
    case .paid, .cancelled: nil
    }
  }

  private static func menuKind(
    from currentStatus: BillStatus,
    to target: BillStatus
  ) -> BillLifecycleActionKind {
    if target == .cancelled { return .destructiveCancellation }
    if isRollback(from: currentStatus, to: target) { return .rollback }
    return .forwardAlternative
  }

  private static func isRollback(from currentStatus: BillStatus, to target: BillStatus) -> Bool {
    if currentStatus == .cancelled { return target != .cancelled }
    guard let currentRank = lifecycleRank[currentStatus], let targetRank = lifecycleRank[target]
    else { return false }
    return targetRank < currentRank
  }

  private static let lifecycleRank: [BillStatus: Int] = [
    .draft: 0,
    .published: 1,
    .sent: 2,
    .delayedPayment: 3,
    .paid: 4,
  ]
}

struct BillLifecycleView: View {
  let currentStatus: BillStatus
  let actions: [BillTransition]
  let statusUpdatedAt: Date?
  let transitioningAction: BillLifecyclePresentedAction?
  let allowsActions: Bool
  let onAction: (BillLifecyclePresentedAction) -> Void

  private var presentation: BillLifecyclePresentation {
    BillLifecyclePresentationPolicy.presentation(for: currentStatus, actions: actions)
  }

  private var isTransitioning: Bool { transitioningAction != nil }

  private var isMenuTransitioning: Bool {
    guard let transitioningAction else { return false }
    return transitioningAction.kind != .primary
  }

  var body: some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
      SectionTitle(title: "Ciclo da fatura", symbol: "arrow.triangle.2.circlepath")
      BillStatusTimeline(currentStatus: currentStatus)

      if !allowsActions {
        Label(
          "Ciclo disponível somente para quem pode gerenciar faturas.",
          systemImage: "eye"
        )
        .font(.footnote)
        .foregroundStyle(RentivoColors.secondaryInk)
      } else if presentation.isTerminal {
        Label("Esta fatura está em um estado final.", systemImage: "checkmark.circle")
          .foregroundStyle(RentivoColors.secondaryInk)
      } else {
        if let primaryAction = presentation.primaryAction {
          Button {
            onAction(primaryAction)
          } label: {
            Label(
              primaryAction.action.label,
              systemImage: BillStatusPresentation(status: primaryAction.action.target).symbol
            )
          }
          .buttonStyle(
            RentivoButtonStyle(
              isBusy: transitioningAction?.action.target == primaryAction.action.target
                && transitioningAction?.kind == .primary
            )
          )
          .disabled(isTransitioning)
          .accessibilityIdentifier("bill.transition.\(primaryAction.action.target.rawValue)")
        }

        if !presentation.menuActions.isEmpty {
          lifecycleMenu
        }
      }

      if let statusUpdatedAt {
        Text("Status atualizado em \(statusUpdatedAt.formattedPTBR(time: .shortened)).")
          .font(.caption)
          .foregroundStyle(RentivoColors.secondaryInk)
      }
    }
  }

  private var lifecycleMenu: some View {
    Menu {
      ForEach(nonCancellationActions, id: \.action.target) { action in
        Button {
          onAction(action)
        } label: {
          Label(
            action.action.label,
            systemImage: BillStatusPresentation(status: action.action.target).symbol
          )
        }
        .accessibilityIdentifier("bill.transition.\(action.action.target.rawValue)")
      }

      if let cancellationAction {
        if !nonCancellationActions.isEmpty { Divider() }
        Button(role: .destructive) {
          onAction(cancellationAction)
        } label: {
          Label(
            cancellationAction.action.label,
            systemImage: BillStatusPresentation(status: .cancelled).symbol
          )
        }
        .accessibilityIdentifier("bill.transition.\(cancellationAction.action.target.rawValue)")
      }
    } label: {
      Label(
        isMenuTransitioning ? "Atualizando status…" : "Mais ações",
        systemImage: "ellipsis.circle"
      )
      .frame(maxWidth: .infinity)
    }
    .buttonStyle(RentivoSecondaryButtonStyle(isBusy: isMenuTransitioning))
    .disabled(isTransitioning)
    .accessibilityLabel(
      isMenuTransitioning ? "Atualizando status…" : "Mais ações do ciclo da fatura"
    )
    .accessibilityHint(isMenuTransitioning ? "" : "Mostra outras mudanças de status")
    .accessibilityIdentifier("bill.lifecycle.more-actions")
    .onChange(of: isMenuTransitioning) { _, isUpdating in
      guard isUpdating, UIAccessibility.isVoiceOverRunning else { return }
      UIAccessibility.post(notification: .announcement, argument: "Atualizando status…")
    }
  }

  private var nonCancellationActions: [BillLifecyclePresentedAction] {
    presentation.menuActions.filter { $0.kind != .destructiveCancellation }
  }

  private var cancellationAction: BillLifecyclePresentedAction? {
    presentation.menuActions.first { $0.kind == .destructiveCancellation }
  }
}

struct BillStatusTimeline: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let currentStatus: BillStatus

  private var presentation: BillTimelinePresentation {
    BillTimelinePresentation(currentStatus: currentStatus)
  }

  var body: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        verticalTimeline
      } else {
        ViewThatFits(in: .horizontal) {
          horizontalTimeline.fixedSize(horizontal: true, vertical: false)
          verticalTimeline
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityIdentifier("bill.lifecycle.timeline")
  }

  private var horizontalTimeline: some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
      HStack(spacing: RentivoSpacing.small) {
        ForEach(Array(presentation.canonicalStages.enumerated()), id: \.element.status) {
          index, stage in
          if index > 0 { horizontalConnector }
          horizontalStage(stage)
        }
      }
      if let branch = presentation.branch {
        if branch.status == .delayedPayment {
          delayedHorizontalBranch(branch)
        } else {
          isolatedHorizontalBranch(branch)
        }
      }
    }
  }

  private var verticalTimeline: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(presentation.canonicalStages.enumerated()), id: \.element.status) {
        index, stage in
        if index > 0 { verticalConnector }
        verticalStage(stage)
      }
      if let branch = presentation.branch {
        if branch.status == .delayedPayment {
          delayedVerticalBranch(branch)
        } else {
          isolatedVerticalBranch(branch)
        }
      }
    }
  }

  private func horizontalStage(_ stage: BillTimelineStage) -> some View {
    VStack(spacing: RentivoSpacing.tiny) {
      Image(systemName: symbol(for: stage))
        .font(.body.weight(.bold))
      Text(stage.status.label)
        .font(.caption.weight(stage.state == .current ? .bold : .semibold))
        .fixedSize(horizontal: true, vertical: false)
    }
    .foregroundStyle(color(for: stage))
    .opacity(stage.state == .future ? 0.65 : 1)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(stage.accessibilityLabel)
  }

  private func verticalStage(_ stage: BillTimelineStage) -> some View {
    HStack(spacing: RentivoSpacing.small) {
      Image(systemName: symbol(for: stage))
        .font(.body.weight(.bold))
        .frame(width: 24)
      Text(stage.status.label)
        .font(.subheadline.weight(stage.state == .current ? .bold : .semibold))
        .fixedSize(horizontal: false, vertical: true)
    }
    .foregroundStyle(color(for: stage))
    .opacity(stage.state == .future ? 0.65 : 1)
    .frame(minHeight: 44)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(stage.accessibilityLabel)
  }

  private var horizontalConnector: some View {
    Image(systemName: "chevron.right")
      .font(.caption.weight(.bold))
      .foregroundStyle(RentivoColors.secondaryInk)
      .accessibilityHidden(true)
  }

  private var verticalConnector: some View {
    Rectangle()
      .fill(RentivoColors.secondaryInk.opacity(0.5))
      .frame(width: 2, height: 12)
      .padding(.leading, 11)
      .accessibilityHidden(true)
  }

  private func isolatedHorizontalBranch(_ stage: BillTimelineStage) -> some View {
    HStack(spacing: RentivoSpacing.small) {
      Image(systemName: "arrow.right")
        .foregroundStyle(RentivoColors.secondaryInk)
        .accessibilityHidden(true)
      horizontalStage(stage)
    }
  }

  private func isolatedVerticalBranch(_ stage: BillTimelineStage) -> some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.small) {
      Divider().accessibilityHidden(true)
      verticalStage(stage)
    }
  }

  private func delayedHorizontalBranch(_ stage: BillTimelineStage) -> some View {
    HStack(spacing: RentivoSpacing.small) {
      horizontalStage(BillTimelineStage(status: .sent, state: .completed))
        .accessibilityHidden(true)
      Image(systemName: "arrow.turn.down.right")
        .foregroundStyle(RentivoColors.secondaryInk)
        .accessibilityHidden(true)
      horizontalStage(stage)
      horizontalConnector
      horizontalStage(BillTimelineStage(status: .paid, state: .future))
        .accessibilityHidden(true)
    }
  }

  private func delayedVerticalBranch(_ stage: BillTimelineStage) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      verticalStage(BillTimelineStage(status: .sent, state: .completed))
        .accessibilityHidden(true)
      Image(systemName: "arrow.turn.down.right")
        .foregroundStyle(RentivoColors.secondaryInk)
        .frame(width: 24, height: 24)
        .padding(.leading, 11)
        .accessibilityHidden(true)
      verticalStage(stage)
      verticalConnector
      verticalStage(BillTimelineStage(status: .paid, state: .future))
        .accessibilityHidden(true)
    }
    .padding(.leading, RentivoSpacing.large)
  }

  private func symbol(for stage: BillTimelineStage) -> String {
    switch stage.state {
    case .completed: "checkmark.circle.fill"
    case .current: BillStatusPresentation(status: stage.status).symbol
    case .future: "circle"
    }
  }

  private func color(for stage: BillTimelineStage) -> Color {
    switch stage.state {
    case .completed: RentivoColors.emerald
    case .current: BillStatusPresentation(status: stage.status).color
    case .future: RentivoColors.secondaryInk
    }
  }
}
