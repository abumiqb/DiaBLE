import Foundation


extension Data {
    var hex: String {
        self.reduce("", { $0 + String(format: "%02x", $1)})
    }
}


extension String {
    var base64: String? { self.data(using: .utf8)?.base64EncodedString() }
    var base64Data: Data? { Data(base64Encoded: self) }
}
