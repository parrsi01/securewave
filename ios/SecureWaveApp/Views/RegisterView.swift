import SwiftUI

struct RegisterView: View {
    @EnvironmentObject private var session: UserSession
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Create account")
                .font(.title2)
                .fontWeight(.semibold)

            TextField("Email", text: $email)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .textFieldStyle(.roundedBorder)

            SecureField("Password (min 8 chars)", text: $password)
                .textFieldStyle(.roundedBorder)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            Button(isLoading ? "Creating..." : "Create Account") {
                Task { await register() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)
        }
        .padding()
        .navigationTitle("SecureWave")
    }

    private func register() async {
        errorMessage = nil
        isLoading = true
        do {
            let token = try await APIClient.shared.register(email: email, password: password)
            await MainActor.run {
                session.updateToken(token)
            }
        } catch {
            await MainActor.run {
                errorMessage = "Registration failed. Try another email."
            }
        }
        await MainActor.run {
            isLoading = false
        }
    }
}
