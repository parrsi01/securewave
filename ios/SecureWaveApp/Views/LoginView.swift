import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: UserSession
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Log in")
                .font(.title2)
                .fontWeight(.semibold)

            TextField("Email", text: $email)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .textFieldStyle(.roundedBorder)

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            Button(isLoading ? "Signing in..." : "Login") {
                Task { await login() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)
        }
        .padding()
        .navigationTitle("SecureWave")
    }

    private func login() async {
        errorMessage = nil
        isLoading = true
        do {
            let token = try await APIClient.shared.login(email: email, password: password)
            await MainActor.run {
                session.updateToken(token)
            }
        } catch {
            await MainActor.run {
                errorMessage = "Login failed. Check your credentials."
            }
        }
        await MainActor.run {
            isLoading = false
        }
    }
}
