import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: UserSession

    var body: some View {
        Group {
            if session.isAuthenticated {
                MainTabView()
            } else {
                AuthLandingView()
            }
        }
    }
}

struct AuthLandingView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Text("SecureWave VPN")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Sign in to manage your VPN and connect instantly.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                NavigationLink("Login", destination: LoginView())
                    .buttonStyle(.borderedProminent)

                NavigationLink("Create Account", destination: RegisterView())
                    .buttonStyle(.bordered)
            }
            .padding()
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("VPN", systemImage: "lock.shield")
                }
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
            AccountView()
                .tabItem {
                    Label("Account", systemImage: "person.crop.circle")
                }
        }
    }
}

struct AccountView: View {
    @EnvironmentObject private var session: UserSession

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Subscription")) {
                    NavigationLink("Upgrade Plan", destination: UpgradeView())
                }
                Section(header: Text("Session")) {
                    Button("Log out") {
                        session.logout()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Account")
        }
    }
}

struct UpgradeView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Upgrade SecureWave")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Upgrade inside the app or continue in the web billing portal.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Link("Open Billing Portal", destination: URL(string: "https://securewave.example.com/subscription.html")!)
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
