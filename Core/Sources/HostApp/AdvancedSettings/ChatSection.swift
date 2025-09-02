import Client
import ComposableArchitecture
import SwiftUI
import Toast
import XcodeInspector

struct ChatSection: View {
    @AppStorage(\.autoAttachChatToXcode) var autoAttachChatToXcode

    var body: some View {
        SettingsSection(title: "Chat Settings") {
            // Auto Attach toggle
            SettingsToggle(
                title: "Auto-attach Chat Window to Xcode",
                isOn: $autoAttachChatToXcode
            )

            Divider()

            // Response language picker
            ResponseLanguageSetting()
                .padding(SettingsToggle.defaultPadding)

            Divider()

            // Copilot instructions - .github/copilot-instructions.md
            CopilotInstructionSetting()
                .padding(SettingsToggle.defaultPadding)

            Divider()

            // Custom Instructions - .github/instructions/*.instructions.md
            PromptFileSetting(promptType: .instructions)
                .padding(SettingsToggle.defaultPadding)

            Divider()

            // Custom Prompts - .github/prompts/*.prompt.md
            PromptFileSetting(promptType: .prompt)
                .padding(SettingsToggle.defaultPadding)
        }
    }
}

struct ResponseLanguageSetting: View {
    @AppStorage(\.chatResponseLocale) var chatResponseLocale

    // Locale codes mapped to language display names
    // reference: https://code.visualstudio.com/docs/configure/locales#_available-locales
    private let localeLanguageMap: [String: String] = [
        "en": "English",
        "zh-cn": "Chinese, Simplified",
        "zh-tw": "Chinese, Traditional",
        "fr": "French",
        "de": "German",
        "it": "Italian",
        "es": "Spanish",
        "ja": "Japanese",
        "ko": "Korean",
        "ru": "Russian",
        "pt-br": "Portuguese (Brazil)",
        "tr": "Turkish",
        "pl": "Polish",
        "cs": "Czech",
        "hu": "Hungarian",
    ]

    var selectedLanguage: String {
        if chatResponseLocale == "" {
            return "English"
        }

        return localeLanguageMap[chatResponseLocale] ?? "English"
    }

    // Display name to locale code mapping (for the picker UI)
    var sortedLanguageOptions: [(displayName: String, localeCode: String)] {
        localeLanguageMap.map { (displayName: $0.value, localeCode: $0.key) }
            .sorted { $0.displayName < $1.displayName }
    }

    var body: some View {
        WithPerceptionTracking {
            HStack {
                VStack(alignment: .leading) {
                    Text("Response Language")
                        .font(.body)
                    Text("This change applies only to new chat sessions. Existing ones won't be impacted.")
                        .font(.footnote)
                }

                Spacer()

                Picker("", selection: $chatResponseLocale) {
                    ForEach(sortedLanguageOptions, id: \.localeCode) { option in
                        Text(option.displayName).tag(option.localeCode)
                    }
                }
                .frame(maxWidth: 200, alignment: .leading)
            }
        }
    }
}

struct CopilotInstructionSetting: View {
    @State var isGlobalInstructionsViewOpen = false
    @Environment(\.toast) var toast

    var body: some View {
        WithPerceptionTracking {
            HStack {
                VStack(alignment: .leading) {
                    Text("Copilot Instructions")
                        .font(.body)
                    Text("Configure `.github/copilot-instructions.md` to apply to all chat requests.")
                        .font(.footnote)
                }

                Spacer()

                Button("Current Workspace") {
                    openCustomInstructions()
                }

                Button("Global") {
                    isGlobalInstructionsViewOpen = true
                }
            }
            .sheet(isPresented: $isGlobalInstructionsViewOpen) {
                GlobalInstructionsView(isOpen: $isGlobalInstructionsViewOpen)
            }
        }
    }

    func openCustomInstructions() {
        Task {
            guard let projectURL = await getCurrentProjectURL() else {
                toast("No active workspace found", .error)
                return
            }

            let configFile = projectURL.appendingPathComponent(".github/copilot-instructions.md")

            // If the file doesn't exist, create one with a proper structure
            if !FileManager.default.fileExists(atPath: configFile.path) {
                do {
                    // Create directory if it doesn't exist using reusable helper
                    let gitHubDir = projectURL.appendingPathComponent(".github")
                    try ensureDirectoryExists(at: gitHubDir)

                    // Create empty file
                    try "".write(to: configFile, atomically: true, encoding: .utf8)
                } catch {
                    toast("Failed to create config file .github/copilot-instructions.md: \(error)", .error)
                }
            }

            if FileManager.default.fileExists(atPath: configFile.path) {
                NSWorkspace.shared.open(configFile)
            }
        }
    }
}

struct PromptFileSetting: View {
    let promptType: PromptType
    @State private var isCreateSheetPresented = false
    @Environment(\.toast) var toast

    var body: some View {
        WithPerceptionTracking {
            HStack {
                VStack(alignment: .leading) {
                    Text(promptType.settingTitle)
                        .font(.body)
                    Text(
                        (try? AttributedString(markdown: promptType.description)) ?? AttributedString(
                            promptType.description
                        )
                    )
                    .font(.footnote)
                }

                Spacer()

                Button("Create") {
                    isCreateSheetPresented = true
                }

                Button("Open \(promptType.directoryName.capitalized) Folder") {
                    openDirectory()
                }
            }
            .sheet(isPresented: $isCreateSheetPresented) {
                CreateCustomCopilotFileView(
                    isOpen: $isCreateSheetPresented,
                    promptType: promptType
                )
            }
        }
    }

    private func openDirectory() {
        Task {
            guard let projectURL = await getCurrentProjectURL() else {
                toast("No active workspace found", .error)
                return
            }

            let directory = promptType.getDirectoryPath(projectURL: projectURL)

            do {
                try ensureDirectoryExists(at: directory)
                NSWorkspace.shared.open(directory)
            } catch {
                toast("Failed to create \(promptType.directoryName) directory: \(error)", .error)
            }
        }
    }
}

#Preview {
    ChatSection()
        .frame(width: 600)
}
