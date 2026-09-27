import Foundation

extension GoogleAccount {
    /// Reads the account out of the accessible label on Google's account
    /// button: "Google Account: Jane Appleseed (jane@example.com)" in English,
    /// "Google-Konto: …" in German, full-width brackets in Japanese.
    ///
    /// The wording is localized, so the parse leans only on shape: the email
    /// is whatever contains an "@" (preferably in trailing brackets), and the
    /// name is what sits between the first colon and the email. Nil when
    /// neither can be found.
    public init?(accountLabel: String) {
        let text = accountLabel.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !text.isEmpty else { return nil }

        let opening: Set<Character> = ["(", "（"]
        let closing: Set<Character> = [")", "）"]
        var email: String?
        var rest = text

        if let open = text.lastIndex(where: { opening.contains($0) }),
           let close = text[open...].firstIndex(where: { closing.contains($0) }) {
            let inner = text[text.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
            if inner.contains("@") {
                email = inner
                rest = String(text[..<open])
            }
        }
        if email == nil, let token = text.split(separator: " ").first(where: { $0.contains("@") }) {
            email = token.trimmingCharacters(in: CharacterSet(charactersIn: "()（）<>,;:"))
            rest = text.replacingOccurrences(of: String(token), with: "")
        }

        var name: String?
        if let colon = rest.firstIndex(where: { $0 == ":" || $0 == "：" }) {
            name = rest[rest.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        } else if email != nil {
            name = rest.trimmingCharacters(in: .whitespaces)
        }
        if name?.isEmpty == true { name = nil }
        if email?.isEmpty == true { email = nil }

        guard name != nil || email != nil else { return nil }
        self.init(name: name, email: email)
    }
}
