import Foundation

func extractUserId(token: String) -> String {
    let parts = token.split(separator: ".")
    guard parts.count >= 2,
          let data = Data(base64Encoded: String(parts[1]).base64Padded()),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let sub = json["sub"] as? String else {
        return UUID().uuidString.prefix(8).lowercased()
    }
    return sub
}

extension String {
    func base64Padded() -> String {
        var padded = self
        let remainder = self.count % 4
        if remainder > 0 {
            padded = self.padding(toLength: self.count + 4 - remainder, withPad: "=", startingAt: 0)
        }
        return padded
    }
}
