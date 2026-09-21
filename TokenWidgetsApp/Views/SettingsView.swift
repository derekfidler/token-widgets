import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var scheduler: RefreshScheduler

    @State private var claudeMode: AccountMode = AppSettings.claudeAccountMode
        ?? (CredentialStore.has(.claudeAnalyticsApiKey) ? .enterprise : .personal)
    @State private var chatgptMode: AccountMode = AppSettings.chatgptAccountMode
        ?? (CredentialStore.has(.openaiAdminApiKey) ? .enterprise : .personal)

    @State private var claudeSessionCookie = CredentialStore.get(.claudeSessionCookie) ?? ""
    @State private var claudeOrgId = CredentialStore.get(.claudeOrgId) ?? ""
    @State private var claudeUsageEndpointOverride = CredentialStore.get(.claudeUsageEndpointOverride) ?? ""
    @State private var claudeAnalyticsApiKey = CredentialStore.get(.claudeAnalyticsApiKey) ?? ""

    @State private var chatgptSessionCookie = CredentialStore.get(.chatgptSessionCookie) ?? ""
    @State private var openaiAdminApiKey = CredentialStore.get(.openaiAdminApiKey) ?? ""

    @State private var refreshIntervalMinutes: Double = RefreshScheduler.shared.intervalMinutes
    @State private var launchAtLogin = LoginItemManager.isEnabled
    @State private var launchAtLoginError: String?
    @State private var loginSheet: LoginProduct?

    var body: some View {
        TabView {
            claudeTab.tabItem { Text("Claude") }
            chatgptTab.tabItem { Text("ChatGPT / Codex") }
            generalTab.tabItem { Text("General") }
        }
        .padding()
        .frame(width: 480, height: 440)
        .sheet(item: $loginSheet) { product in
            LoginCaptureSheet(product: product) { cookieValue in
                switch product {
                case .claude:
                    claudeSessionCookie = cookieValue
                    CredentialStore.set(cookieValue, for: .claudeSessionCookie)
                case .chatgpt:
                    chatgptSessionCookie = cookieValue
                    CredentialStore.set(cookieValue, for: .chatgptSessionCookie)
                }
                Task { await scheduler.refresh() }
            }
        }
    }

    private var claudeTab: some View {
        Form {
            Picker("Plan type", selection: $claudeMode) {
                Text("Personal (Pro/Max)").tag(AccountMode.personal)
                Text("Enterprise").tag(AccountMode.enterprise)
            }
            .pickerStyle(.segmented)
            .onChange(of: claudeMode) { _, _ in applyClaudeMode() }

            if claudeMode == .personal {
                Section("Session") {
                    Button("Log in to claude.ai…") { loginSheet = .claude }
                    LabeledContent("Status") {
                        Text(claudeSessionCookie.isEmpty ? "Not connected" : "Connected")
                            .foregroundStyle(claudeSessionCookie.isEmpty ? Color.secondary : Color.green)
                    }
                    SecureField("Session cookie (manual paste)", text: $claudeSessionCookie)
                        .onSubmit { CredentialStore.set(claudeSessionCookie, for: .claudeSessionCookie) }
                    TextField("Organization ID (optional override)", text: $claudeOrgId)
                        .onSubmit { CredentialStore.set(claudeOrgId, for: .claudeOrgId) }
                    TextField("Usage endpoint override (advanced)", text: $claudeUsageEndpointOverride)
                        .onSubmit { CredentialStore.set(claudeUsageEndpointOverride, for: .claudeUsageEndpointOverride) }
                    Text("If usage stops loading, open claude.ai/settings/usage in a browser, check the Network tab for the request returning five_hour/seven_day limits, and paste its path (e.g. /api/organizations/…/usage) here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let error = scheduler.snapshot.claude.errorMessage {
                    Section("Last error") {
                        ScrollView {
                            Text(error)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 90)
                    }
                }
            } else {
                Section("Analytics API") {
                    SecureField("Analytics API key", text: $claudeAnalyticsApiKey)
                        .onSubmit { CredentialStore.set(claudeAnalyticsApiKey, for: .claudeAnalyticsApiKey) }
                    Text("Create one in Claude Console → Settings → Analytics API keys (Claude Enterprise only).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onDisappear(perform: persistClaude)
    }

    private var chatgptTab: some View {
        Form {
            Picker("Plan type", selection: $chatgptMode) {
                Text("Personal (Plus/Pro)").tag(AccountMode.personal)
                Text("Enterprise").tag(AccountMode.enterprise)
            }
            .pickerStyle(.segmented)
            .onChange(of: chatgptMode) { _, _ in applyChatGPTMode() }

            if chatgptMode == .personal {
                Section("Session") {
                    Button("Log in to chatgpt.com…") { loginSheet = .chatgpt }
                    LabeledContent("Status") {
                        Text(chatgptSessionCookie.isEmpty ? "Not connected" : "Connected")
                            .foregroundStyle(chatgptSessionCookie.isEmpty ? Color.secondary : Color.green)
                    }
                    SecureField("Session cookie (manual paste)", text: $chatgptSessionCookie)
                        .onSubmit { CredentialStore.set(chatgptSessionCookie, for: .chatgptSessionCookie) }
                }
                if let error = scheduler.snapshot.chatgpt.errorMessage {
                    Section("Last error") {
                        ScrollView {
                            Text(error)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 90)
                    }
                }
            } else {
                Section("Usage API") {
                    SecureField("Admin API key", text: $openaiAdminApiKey)
                        .onSubmit { CredentialStore.set(openaiAdminApiKey, for: .openaiAdminApiKey) }
                    Text("Create one at platform.openai.com → Organization → Admin keys.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onDisappear(perform: persistChatGPT)
    }

    private var generalTab: some View {
        Form {
            Toggle("Launch Token Widgets at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    do {
                        try LoginItemManager.setEnabled(enabled)
                        launchAtLoginError = nil
                    } catch {
                        launchAtLoginError = error.localizedDescription
                        launchAtLogin = LoginItemManager.isEnabled
                    }
                }

            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Slider(value: $refreshIntervalMinutes, in: 5...60, step: 5) {
                Text("Refresh every \(Int(refreshIntervalMinutes)) minutes")
            }
            .onChange(of: refreshIntervalMinutes) { _, newValue in
                scheduler.intervalMinutes = newValue
            }

            Button {
                Task { await scheduler.refresh() }
            } label: {
                Text("Refresh Now")
            }
        }
    }

    private func applyClaudeMode() {
        AppSettings.claudeAccountMode = claudeMode
        Task { await scheduler.refresh() }
    }

    private func applyChatGPTMode() {
        AppSettings.chatgptAccountMode = chatgptMode
        Task { await scheduler.refresh() }
    }

    private func persistClaude() {
        CredentialStore.set(claudeSessionCookie, for: .claudeSessionCookie)
        CredentialStore.set(claudeOrgId, for: .claudeOrgId)
        CredentialStore.set(claudeUsageEndpointOverride, for: .claudeUsageEndpointOverride)
        CredentialStore.set(claudeAnalyticsApiKey, for: .claudeAnalyticsApiKey)
    }

    private func persistChatGPT() {
        CredentialStore.set(chatgptSessionCookie, for: .chatgptSessionCookie)
        CredentialStore.set(openaiAdminApiKey, for: .openaiAdminApiKey)
    }
}
