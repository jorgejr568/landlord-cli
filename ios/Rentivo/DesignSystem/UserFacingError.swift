import Foundation
import SwiftUI

enum UserFacingOperation: Equatable, Sendable {
  case loadBillings
  case loadBilling
  case saveBilling
  case deleteBilling
  case transferBilling
  case loadBill
  case saveBill
  case deleteBill
  case changeBillStatus
  case regenerateDocument
  case openDocument
  case loadExpenses
  case addExpense
  case deleteExpense
  case loadAttachments
  case addAttachment
  case deleteAttachment
  case openAttachment
  case addReceipt
  case deleteReceipt
  case reorderReceipts
  case sendCommunication
  case requestExport
  case loadOrganizations
  case loadOrganization
  case saveOrganization
  case deleteOrganization
  case updateMember
  case changeOrganizationSecurity
  case loadInvitations
  case sendInvitation
  case respondToInvitation
  case loadAPIKeys
  case loadAPIKeyOptions
  case saveAPIKey
  case revokeAPIKey

  fileprivate var fallback: String {
    switch self {
    case .loadBillings:
      "Não foi possível carregar as cobranças. Verifique sua conexão e tente novamente."
    case .loadBilling:
      "Não foi possível carregar esta cobrança. Verifique sua conexão e tente novamente."
    case .saveBilling:
      "Não foi possível salvar a cobrança. Revise os dados e tente novamente."
    case .deleteBilling:
      "Não foi possível excluir a cobrança. Atualize a tela e tente novamente."
    case .transferBilling:
      "Não foi possível concluir a alteração. Atualize a organização e tente novamente."
    case .loadBill:
      "Não foi possível carregar esta fatura. Verifique sua conexão e tente novamente."
    case .saveBill:
      "Não foi possível salvar a fatura. Revise os dados e tente novamente."
    case .deleteBill:
      "Não foi possível excluir a fatura. Atualize a tela e tente novamente."
    case .changeBillStatus:
      "Não foi possível alterar o status da fatura. Atualize a tela e tente novamente."
    case .regenerateDocument:
      "Não foi possível solicitar um novo documento. Tente novamente em alguns instantes."
    case .openDocument, .openAttachment:
      "Não foi possível abrir o arquivo. Verifique sua conexão e tente novamente."
    case .loadExpenses:
      "Não foi possível carregar as despesas. Verifique sua conexão e tente novamente."
    case .addExpense:
      "Não foi possível salvar a despesa. Revise os dados e tente novamente."
    case .deleteExpense:
      "Não foi possível excluir a despesa. Atualize a tela e tente novamente."
    case .loadAttachments:
      "Não foi possível carregar os arquivos. Verifique sua conexão e tente novamente."
    case .addAttachment:
      "Não foi possível adicionar o arquivo. Escolha outro e tente novamente."
    case .deleteAttachment:
      "Não foi possível excluir o arquivo. Atualize a tela e tente novamente."
    case .addReceipt:
      "Não foi possível adicionar o comprovante. Escolha outro e tente novamente."
    case .deleteReceipt, .reorderReceipts:
      "Não foi possível concluir a alteração. Atualize a fatura e tente novamente."
    case .sendCommunication:
      "Não foi possível iniciar o envio. Revise os dados e tente novamente."
    case .requestExport:
      "Não foi possível preparar a exportação. Tente novamente em alguns instantes."
    case .loadOrganizations:
      "Não foi possível carregar as organizações. Verifique sua conexão e tente novamente."
    case .loadOrganization:
      "Não foi possível carregar esta organização. Verifique sua conexão e tente novamente."
    case .saveOrganization:
      "Não foi possível salvar a organização. Revise os dados e tente novamente."
    case .deleteOrganization:
      "Não foi possível excluir a organização. Atualize a tela e tente novamente."
    case .updateMember, .changeOrganizationSecurity:
      "Não foi possível concluir a alteração. Atualize a organização e tente novamente."
    case .loadInvitations:
      "Não foi possível carregar os convites. Verifique sua conexão e tente novamente."
    case .sendInvitation:
      "Não foi possível enviar o convite. Confira o e-mail e tente novamente."
    case .respondToInvitation:
      "Não foi possível responder ao convite. Atualize a lista e tente novamente."
    case .loadAPIKeys:
      "Não foi possível carregar as chaves de integração. Verifique sua conexão e tente novamente."
    case .loadAPIKeyOptions:
      "Não foi possível carregar as opções da chave de integração. Verifique sua conexão e tente novamente."
    case .saveAPIKey:
      "Não foi possível salvar a chave de integração. Revise os dados e tente novamente."
    case .revokeAPIKey:
      "Não foi possível revogar a chave. Atualize a lista e tente novamente."
    }
  }

  fileprivate var temporaryFailureFallback: String {
    if fallback.hasSuffix("Tente novamente em alguns instantes.") { return fallback }
    guard let sentenceEnd = fallback.range(of: ". ") else {
      return "\(fallback) Tente novamente em alguns instantes."
    }
    return "\(fallback[..<sentenceEnd.lowerBound]). Tente novamente em alguns instantes."
  }
}

struct UserFacingFailure: Equatable, Sendable {
  enum Recovery: Equatable, Sendable {
    case retry
    case configureAuthenticator
    case none
  }

  let message: String
  let recovery: Recovery

  var demoError: DemoError { DemoError(message: message) }
}

enum UserFacingError {
  static func presentation(
    for error: Error,
    operation: UserFacingOperation
  ) -> UserFacingFailure {
    if case LiveAPIError.sessionExpired = error {
      return UserFacingFailure(
        message: "Sua sessão expirou. Entre novamente para continuar.", recovery: .none)
    }

    let apiError = error as? LiveAPIError
    let code = apiError?.problemCode
    let status = apiError?.statusCode

    if code == SecurityViewRules.mfaSetupRequiredCode {
      return UserFacingFailure(
        message: "Sua organização exige autenticação em duas etapas. Configure um autenticador para continuar.",
        recovery: .configureAuthenticator
      )
    }
    if let override = problemOverride(code: code, operation: operation) {
      return UserFacingFailure(message: override, recovery: .retry)
    }
    if code == "not_found" || status == 404 {
      return UserFacingFailure(
        message: "Este conteúdo não está mais disponível. Volte e atualize a lista.",
        recovery: .retry
      )
    }
    if status == 403 || code == "missing_scope" || code == "insufficient_role" {
      return UserFacingFailure(
        message: "Você não tem permissão para fazer esta alteração. Peça ajuda a um administrador da organização.",
        recovery: .none
      )
    }
    if status == 429 {
      return UserFacingFailure(
        message: "Muitas tentativas em pouco tempo. Aguarde alguns minutos e tente novamente.",
        recovery: .retry
      )
    }

    if status.map({ $0 >= 500 }) == true || apiError == .invalidResponse {
      return UserFacingFailure(
        message: operation.temporaryFailureFallback,
        recovery: .retry
      )
    }

    if let demoError = error as? DemoError {
      if demoError == .staleBillStatus {
        return UserFacingFailure(message: DemoError.staleBillStatus.message, recovery: .retry)
      }
      if demoError == .resourceNotFound {
        return UserFacingFailure(
          message: "Este conteúdo não está mais disponível. Volte e atualize a lista.",
          recovery: .retry
        )
      }
      if demoError == .permissionDenied {
        return UserFacingFailure(
          message: "Você não tem permissão para fazer esta alteração. Peça ajuda a um administrador da organização.",
          recovery: .none
        )
      }
    }

    return UserFacingFailure(message: operation.fallback, recovery: .retry)
  }

  static func message(for error: Error, operation: UserFacingOperation) -> String {
    presentation(for: error, operation: operation).message
  }

  private static func problemOverride(
    code: String?, operation: UserFacingOperation
  ) -> String? {
    if operation == .saveBilling,
      ["validation_error", "invalid_billing", "invalid_billing_item"].contains(code)
    {
      return "Não foi possível salvar a cobrança. Revise os campos e tente novamente."
    }
    switch code {
    case "pix_setup_required":
      return "Não foi possível gerar a fatura. Configure os dados do PIX da cobrança e tente novamente."
    case "invalid_variable_amounts", "invalid_total_amount":
      return "Não foi possível salvar a fatura. Revise os valores dos itens e tente novamente."
    case "stale_bill_status":
      return "O status da fatura foi alterado. Atualize a página e tente novamente."
    case "invalid_status_transition":
      return "Essa alteração de status não está mais disponível. Atualize a fatura e escolha outra ação."
    case "stale_bill_delete":
      return "Esta fatura já foi excluída. Volte para a cobrança e atualize a lista."
    case "invoice_not_ready", "recibo_not_ready":
      return "O documento ainda está sendo preparado. Aguarde e tente novamente."
    case "invoice_unavailable":
      return "O PDF da fatura ainda não está disponível. Gere o documento e tente novamente."
    case "receipt_unavailable", "recibo_unavailable":
      return "O recibo fica disponível depois que a fatura é marcada como paga."
    case "invalid_recipients":
      return "Um destinatário não está mais disponível. Atualize os destinatários da cobrança e tente novamente."
    case "communication_blocked":
      return "A mensagem contém conteúdo que não pode ser enviado. Revise o texto e tente novamente."
    case "billing_transfer_conflict":
      return "Não foi possível transferir a cobrança porque os dados mudaram. Atualize e tente novamente."
    case "organization_has_billings":
      return "Esta organização ainda possui cobranças. Transfira ou exclua essas cobranças e tente novamente."
    case "membership_conflict":
      return "Os dados deste membro mudaram. Atualize a organização e tente novamente."
    case "invite_conflict":
      return "Não foi possível enviar o convite. Confira se a pessoa já é membro ou tem um convite pendente."
    default:
      return nil
    }
  }
}

struct UserFacingFailureView: View {
  let failure: UserFacingFailure
  let configureAuthenticator: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.small) {
      Label(failure.message, systemImage: "exclamationmark.circle.fill")
        .foregroundStyle(RentivoColors.coral)
      if failure.recovery == .configureAuthenticator {
        Button("Configurar autenticador", action: configureAuthenticator)
          .buttonStyle(.borderedProminent)
          .accessibilityIdentifier("error.configure-authenticator")
      }
    }
    .accessibilityElement(children: .contain)
  }
}
