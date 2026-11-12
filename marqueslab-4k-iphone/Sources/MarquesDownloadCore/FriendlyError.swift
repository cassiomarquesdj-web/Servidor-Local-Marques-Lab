import Foundation

/// Turns a raw failure into something the user can act on. A bare
/// "HTTP 403" says nothing about the provider having changed its delivery.
public enum FriendlyError {
    static let table: [(needle: String, message: String)] = [
        ("403", "A fonte recusou a entrega da mídia (HTTP 403). Normalmente significa que o site mudou a forma de servir o vídeo e o extrator embarcado ficou desatualizado."),
        ("404", "A fonte respondeu que esta mídia não existe mais."),
        ("login", "A fonte exige uma sessão autenticada. Publicações privadas e stories não ficam acessíveis sem login."),
        ("private", "Esta mídia é privada. O aplicativo não faz login nem contorna restrição de acesso."),
        ("rate", "A fonte aplicou limite de requisições. Espere alguns minutos e tente de novo."),
        ("unsupported", "Este site não é reconhecido pelo extrator embarcado."),
        ("offline", "Sem conexão com a internet."),
        ("timed out", "A fonte parou de responder. Tente novamente."),
        ("network connection was lost", "A conexão caiu durante a transferência."),
    ]

    public static func describe(_ error: Error) -> String {
        let raw = error.localizedDescription
        let lowered = raw.lowercased()
        for entry in table where lowered.contains(entry.needle) {
            return "\(entry.message)\n\nDetalhe técnico: \(raw)"
        }
        return raw
    }
}
