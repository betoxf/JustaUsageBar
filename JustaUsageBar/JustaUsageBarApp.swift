//
//  JustaUsageBarApp.swift
//  JustaUsageBar
//

import SwiftUI

@main
struct JustaUsageBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(viewModel: UsageViewModel.shared)
        }
    }
}
