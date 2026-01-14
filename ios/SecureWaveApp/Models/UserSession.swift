import Foundation
import Combine

final class UserSession: ObservableObject {
    @Published var accessToken: String? = nil

    var isAuthenticated: Bool {
        accessToken != nil
    }

    func updateToken(_ token: String) {
        accessToken = token
    }

    func logout() {
        accessToken = nil
    }
}
