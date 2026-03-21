//
//  AuthWebView.swift
//  JustaUsageBar
//
//  Browser-based authentication with automatic session extraction
//

import SwiftUI
import WebKit

struct AuthWindowView: View {
    @Environment(\.dismiss) private var dismiss
    let onAuthenticated: (String, String) -> Void

    @State private var showManualEntry = false
    @State private var sessionKey: String = ""
    @State private var organizationId: String = ""
    @State private var authStatus: AuthStatus = .waiting
    @State private var statusMessage: String = "Sign in to Claude"

    private let anthropicOrange = Color(red: 0.83, green: 0.53, blue: 0.30)

    enum AuthStatus {
        case waiting
        case authenticating
        case extracting
        case success
        case failed
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 4) {
                    Text("✳︎")
                        .foregroundColor(anthropicOrange)
                    Text("Sign in to Claude")
                        .font(.system(size: 13, weight: .medium))
                }
                Spacer()
                Button("×") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .font(.system(size: 16))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            // Status bar
            HStack(spacing: 6) {
                switch authStatus {
                case .waiting:
                    Circle().fill(Color.gray).frame(width: 6, height: 6)
                case .authenticating:
                    ProgressView().scaleEffect(0.5)
                case .extracting:
                    ProgressView().scaleEffect(0.5)
                case .success:
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                case .failed:
                    Circle().fill(Color.red).frame(width: 6, height: 6)
                }
                Text(statusMessage)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()

                Button(showManualEntry ? "Browser" : "Manual") {
                    showManualEntry.toggle()
                }
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))

            if showManualEntry {
                // Manual entry form
                manualEntryView
            } else {
                // Embedded browser
                ClaudeWebView(
                    onSessionExtracted: { session, org in
                        sessionKey = session
                        organizationId = org
                        authStatus = .success
                        statusMessage = "Authenticated!"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            onAuthenticated(session, org)
                            dismiss()
                        }
                    },
                    onOrgIdOnly: { org in
                        // Got org ID but not session key - switch to manual with org pre-filled
                        organizationId = org
                        authStatus = .failed
                        statusMessage = "Got org ID! Just need session key."
                        showManualEntry = true
                    },
                    onStatusChange: { status in
                        statusMessage = status
                        if status.contains("Extracting") {
                            authStatus = .extracting
                        } else if status.contains("Signed in") || status.contains("Detected") {
                            authStatus = .authenticating
                        }
                    }
                )
            }
        }
        .frame(width: 480, height: 600)
    }

    private var manualEntryView: some View {
        VStack(spacing: 16) {
            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                if !organizationId.isEmpty {
                    // Org ID was auto-extracted
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Organization ID auto-detected!")
                            .font(.system(size: 11, weight: .medium))
                    }

                    Text("Just paste your session key below:")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                } else {
                    Text("Manual Credential Entry")
                        .font(.system(size: 12, weight: .medium))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Session Key")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("In Safari DevTools: Application → Cookies → sessionKey")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary.opacity(0.7))
                    SecureField("sk-ant-sid01-...", text: $sessionKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                }

                if organizationId.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Organization ID")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        TextField("UUID from URL", text: $organizationId)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Organization ID (auto-detected)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(organizationId)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Button("Save & Connect") {
                    onAuthenticated(sessionKey, organizationId)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(anthropicOrange)
                .disabled(sessionKey.isEmpty || organizationId.isEmpty)
            }
            .padding(20)
            .frame(maxWidth: 300)

            Spacer()
        }
    }
}

// MARK: - WKWebView Wrapper

struct ClaudeWebView: NSViewRepresentable {
    let onSessionExtracted: (String, String) -> Void
    let onOrgIdOnly: (String) -> Void
    let onStatusChange: (String) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent() // Fresh session each time

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

        // Load Claude login page
        if let url = URL(string: "https://claude.ai/login") {
            webView.load(URLRequest(url: url))
        }

        // Start periodic check for login state (Claude uses client-side routing)
        context.coordinator.startPeriodicCheck(webView: webView)

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onSessionExtracted: onSessionExtracted, onOrgIdOnly: onOrgIdOnly, onStatusChange: onStatusChange)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let onSessionExtracted: (String, String) -> Void
        let onOrgIdOnly: (String) -> Void
        let onStatusChange: (String) -> Void
        private var hasExtracted = false
        private var extractionAttempts = 0
        private let maxAttempts = 15  // More attempts since we redirect
        private var checkTimer: Timer?
        private weak var webViewRef: WKWebView?
        private var extractedOrgId: String?
        private var hasRedirectedToUsage = false

        init(onSessionExtracted: @escaping (String, String) -> Void, onOrgIdOnly: @escaping (String) -> Void, onStatusChange: @escaping (String) -> Void) {
            self.onSessionExtracted = onSessionExtracted
            self.onOrgIdOnly = onOrgIdOnly
            self.onStatusChange = onStatusChange
        }

        func startPeriodicCheck(webView: WKWebView) {
            webViewRef = webView
            // Check every 2 seconds if user has logged in
            checkTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.checkLoginState()
            }
        }

        private func checkLoginState() {
            guard let webView = webViewRef, !hasExtracted else {
                checkTimer?.invalidate()
                return
            }

            guard let url = webView.url else { return }
            let urlString = url.absoluteString

            // Check if we're on a logged-in page (main chat, new, etc.)
            let isLoggedInPage = urlString.contains("claude.ai") &&
                !urlString.contains("/login") &&
                !urlString.contains("/signup") &&
                !urlString.contains("/verify")

            if isLoggedInPage {
                print("Periodic check: Detected logged-in page: \(urlString)")

                // Redirect to settings/usage page if not already there - cookies are fully set there
                if !hasRedirectedToUsage && !urlString.contains("/settings/usage") {
                    hasRedirectedToUsage = true
                    extractionAttempts = 0  // Reset attempts for fresh start on usage page
                    DispatchQueue.main.async {
                        self.onStatusChange("Redirecting to usage page...")
                    }
                    if let usageURL = URL(string: "https://claude.ai/settings/usage") {
                        webView.load(URLRequest(url: usageURL))
                    }
                    return
                }

                // We're on the usage page now, extract credentials
                DispatchQueue.main.async {
                    self.onStatusChange("Detected login! Extracting...")
                }
                checkTimer?.invalidate()
                extractCredentials(from: webView)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = webView.url else { return }
            let urlString = url.absoluteString

            print("Navigation finished: \(urlString)")

            // Check if we're on a logged-in page (not login/signup)
            if !urlString.contains("/login") && !urlString.contains("/signup") && urlString.contains("claude.ai") {
                // Redirect to settings/usage if not there yet
                if !hasRedirectedToUsage && !urlString.contains("/settings/usage") {
                    hasRedirectedToUsage = true
                    extractionAttempts = 0  // Reset for fresh start
                    DispatchQueue.main.async {
                        self.onStatusChange("Redirecting to usage page...")
                    }
                    if let usageURL = URL(string: "https://claude.ai/settings/usage") {
                        webView.load(URLRequest(url: usageURL))
                    }
                    return
                }

                // User appears to be logged in on usage page - wait a moment then extract
                DispatchQueue.main.async {
                    self.onStatusChange("On usage page! Extracting...")
                }
                // Small delay to ensure page is fully loaded
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.extractCredentials(from: webView)
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                print("Navigating to: \(url)")

                // Extract org ID from URL if present
                if url.absoluteString.contains("claude.ai") && !url.absoluteString.contains("/login") {
                    DispatchQueue.main.async {
                        self.onStatusChange("Loading Claude...")
                    }
                }
            }
            decisionHandler(.allow)
        }

        private func extractCredentials(from webView: WKWebView) {
            guard !hasExtracted else { return }
            extractionAttempts += 1

            DispatchQueue.main.async {
                self.onStatusChange("Extracting... (attempt \(self.extractionAttempts))")
            }

            // Try to get both session and org via JavaScript (more reliable)
            let script = """
            (async function() {
                try {
                    // Get cookies first
                    const cookies = document.cookie.split(';').reduce((acc, c) => {
                        const [key, val] = c.trim().split('=');
                        if (key) acc[key] = val;
                        return acc;
                    }, {});

                    // Try to get org ID from lastActiveOrg cookie (faster than API)
                    let orgId = cookies['lastActiveOrg'] || '';

                    // If no cookie, try API
                    if (!orgId) {
                        const orgResponse = await fetch('/api/organizations', { credentials: 'include' });
                        if (!orgResponse.ok) return { error: 'Not logged in' };
                        const orgs = await orgResponse.json();
                        orgId = orgs[0]?.uuid || '';
                    }

                    return {
                        orgId: orgId,
                        sessionKey: cookies['sessionKey'] || '',
                        allCookies: Object.keys(cookies)
                    };
                } catch (e) {
                    return { error: e.message };
                }
            })()
            """

            webView.evaluateJavaScript(script) { [weak self] result, error in
                guard let self = self else { return }

                if let dict = result as? [String: Any] {
                    print("JS Result: \(dict)")

                    if let errorMsg = dict["error"] as? String {
                        print("Error: \(errorMsg)")
                        self.retryOrFallback(webView: webView)
                        return
                    }

                    let orgId = dict["orgId"] as? String ?? ""
                    let sessionKey = dict["sessionKey"] as? String ?? ""

                    // Save org ID for fallback
                    if !orgId.isEmpty {
                        self.extractedOrgId = orgId
                    }

                    if !orgId.isEmpty && !sessionKey.isEmpty {
                        self.hasExtracted = true
                        DispatchQueue.main.async {
                            self.onSessionExtracted(sessionKey, orgId)
                        }
                        return
                    } else if !orgId.isEmpty {
                        // Got org but no session key - try cookie store
                        self.tryGetSessionFromCookies(webView: webView, orgId: orgId)
                        return
                    }
                }

                self.retryOrFallback(webView: webView)
            }
        }

        private func tryGetSessionFromCookies(webView: WKWebView, orgId: String) {
            extractedOrgId = orgId  // Store for fallback

            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self = self else { return }

                print("All cookies: \(cookies.map { "\($0.name): \($0.domain)" })")

                if let sessionCookie = cookies.first(where: { $0.name == "sessionKey" }) {
                    self.hasExtracted = true
                    DispatchQueue.main.async {
                        self.onSessionExtracted(sessionCookie.value, orgId)
                    }
                } else {
                    // Session cookie is HttpOnly - switch to manual with org pre-filled
                    self.hasExtracted = true
                    DispatchQueue.main.async {
                        self.onOrgIdOnly(orgId)
                    }
                }
            }
        }

        private func retryOrFallback(webView: WKWebView) {
            if extractionAttempts < maxAttempts {
                // Wait 2.5s between retries to give page time to fully load
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                    self?.extractCredentials(from: webView)
                }
            } else {
                // If we got org ID, use that
                if let orgId = extractedOrgId, !orgId.isEmpty {
                    hasExtracted = true
                    DispatchQueue.main.async {
                        self.onOrgIdOnly(orgId)
                    }
                } else {
                    DispatchQueue.main.async {
                        self.onStatusChange("Could not extract. Use Manual entry.")
                    }
                }
            }
        }

        private func fetchOrganizationId(sessionKey: String, webView: WKWebView) {
            // Use JavaScript to fetch the organization list
            let script = """
            (async function() {
                try {
                    const response = await fetch('https://claude.ai/api/organizations', {
                        credentials: 'include'
                    });
                    const data = await response.json();
                    if (data && data.length > 0) {
                        return data[0].uuid;
                    }
                    return null;
                } catch (e) {
                    return null;
                }
            })()
            """

            webView.evaluateJavaScript(script) { [weak self] result, error in
                guard let self = self else { return }

                if let orgId = result as? String, !orgId.isEmpty {
                    print("Found org ID: \(orgId)")
                    self.hasExtracted = true

                    DispatchQueue.main.async {
                        self.onSessionExtracted(sessionKey, orgId)
                    }
                } else {
                    print("Could not get org ID from API, trying URL fallback")
                    // Try to extract from current URL or use fallback method
                    self.extractOrgFromURL(webView: webView, sessionKey: sessionKey)
                }
            }
        }

        private func extractOrgFromURL(webView: WKWebView, sessionKey: String) {
            // Try to navigate to settings to get org from URL
            if let url = URL(string: "https://claude.ai/settings") {
                webView.load(URLRequest(url: url))

                // Check URL after navigation
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    guard let self = self, !self.hasExtracted else { return }

                    // Try the API call again
                    let script = """
                    (async function() {
                        const response = await fetch('https://claude.ai/api/organizations', { credentials: 'include' });
                        const data = await response.json();
                        return data[0]?.uuid || '';
                    })()
                    """

                    webView.evaluateJavaScript(script) { result, error in
                        if let orgId = result as? String, !orgId.isEmpty {
                            self.hasExtracted = true
                            DispatchQueue.main.async {
                                self.onSessionExtracted(sessionKey, orgId)
                            }
                        } else {
                            DispatchQueue.main.async {
                                self.onStatusChange("Could not extract org ID. Use manual entry.")
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    AuthWindowView { _, _ in }
}
