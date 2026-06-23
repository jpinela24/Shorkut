import Foundation

struct TemplateField: Identifiable {
    let id = UUID()
    let key: String
    let label: String
    let placeholder: String
    let defaultValue: String
}

enum ShortcutTemplate: String, CaseIterable, Identifiable {
    case ssh
    case curl
    case dockerRestart
    case restartLaunchAgent
    case customCommand

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ssh: return "SSH Connection"
        case .curl: return "Curl a URL"
        case .dockerRestart: return "Restart Docker Container"
        case .restartLaunchAgent: return "Restart a macOS Service"
        case .customCommand: return "Custom Command"
        }
    }

    var fields: [TemplateField] {
        switch self {
        case .ssh:
            return [
                TemplateField(key: "user", label: "User", placeholder: "jpinela", defaultValue: ""),
                TemplateField(key: "host", label: "Host", placeholder: "10.0.0.10", defaultValue: ""),
                TemplateField(key: "port", label: "Port", placeholder: "22", defaultValue: "22")
            ]
        case .curl:
            return [
                TemplateField(key: "method", label: "Method", placeholder: "GET", defaultValue: "GET"),
                TemplateField(key: "url", label: "URL", placeholder: "https://10.0.0.20:8088/status", defaultValue: "")
            ]
        case .dockerRestart:
            return [
                TemplateField(key: "container", label: "Container name", placeholder: "plex", defaultValue: "")
            ]
        case .restartLaunchAgent:
            return [
                TemplateField(key: "label", label: "Service label", placeholder: "com.local.shorkut", defaultValue: "")
            ]
        case .customCommand:
            return [
                TemplateField(key: "command", label: "Command", placeholder: "echo hello", defaultValue: "")
            ]
        }
    }

    /// Wraps a value in single quotes so it's inserted as one shell argument,
    /// neutralizing spaces, `$`, backticks, `;`, etc. (single quotes themselves
    /// are escaped by closing, inserting an escaped quote, and reopening).
    private static func shellQuoted(_ raw: String) -> String {
        "'" + raw.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    func script(values: [String: String]) -> String {
        func value(_ key: String) -> String {
            values[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        func quoted(_ key: String) -> String {
            Self.shellQuoted(value(key))
        }

        let body: String
        switch self {
        case .ssh:
            let port = value("port").isEmpty ? "22" : value("port")
            body = "ssh -p \(Self.shellQuoted(port)) \(quoted("user"))@\(quoted("host"))"
        case .curl:
            let method = value("method").isEmpty ? "GET" : value("method")
            body = "curl -s -X \(Self.shellQuoted(method)) \(quoted("url"))"
        case .dockerRestart:
            body = "docker restart \(quoted("container"))"
        case .restartLaunchAgent:
            body = "launchctl kickstart -k gui/$(id -u)/\(quoted("label"))"
        case .customCommand:
            // Intentionally unquoted — this field is a full shell command the
            // user is writing on purpose, not a single token to neutralize.
            body = value("command")
        }

        return "#!/bin/bash\n\(body)\n"
    }
}
