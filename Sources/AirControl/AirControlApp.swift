import AppKit
import SwiftUI

@main
struct AirControlApp: App {
    @NSApplicationDelegateAdaptor(AirControlDelegate.self) private var delegate
    @StateObject private var store = AirConditionerStore.shared

    var body: some Scene {
        MenuBarExtra {
            ControlPanel(store: store)
        } label: {
            HStack(spacing: 4) {
                Image(nsImage: AppIdentity.menuBarIcon)
                if !store.menuTitle.isEmpty { Text(store.menuTitle) }
            }
            .accessibilityLabel("家居控制，\(store.menuTitle)")
        }
        .menuBarExtraStyle(.window)
    }
}

private enum AppIdentity {
    static let menuBarIcon: NSImage = {
        let image = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) }
            ?? NSImage(systemSymbolName: "house", accessibilityDescription: "家居控制")!
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()
}

@MainActor
final class AirControlDelegate: NSObject, NSApplicationDelegate {
    private var setupWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // An agent app has no Dock icon; make its first-run setup immediately discoverable.
        if !AirConditionerStore.shared.configured || CommandLine.arguments.contains("--show-window") { showSetup() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSetup()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func showSetup() {
        if setupWindow == nil {
            let controller = NSHostingController(rootView: ControlPanel(store: .shared))
            let window = NSWindow(contentViewController: controller)
            window.title = "空调控制"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            setupWindow = window
        }
        setupWindow?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

struct ConnectionSettings: View {
    @ObservedObject var store: AirConditionerStore
    @FocusState private var tokenFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("连接 Home Assistant，在菜单栏查看和控制家里的设备。")
                    .font(.callout).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 7) {
                    Text("服务器地址").font(.callout.weight(.medium))
                    TextField("http://homeassistant.local:8123", text: $store.address)
                        .textFieldStyle(.roundedBorder).autocorrectionDisabled()
                        .accessibilityLabel("Home Assistant 服务器地址")
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text("长期访问令牌").font(.callout.weight(.medium))
                    SecureField(store.configured ? "留空以使用已保存的令牌" : "粘贴令牌", text: $store.tokenInput)
                        .textFieldStyle(.roundedBorder).focused($tokenFocused)
                        .accessibilityLabel("Home Assistant 长期访问令牌")
                    Text("令牌保存在这台 Mac 的钥匙串中。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Button("打开 Home Assistant 个人资料 ↗") { store.openProfile() }
                        .buttonStyle(.link)
                    Text("在个人资料的「安全」页面找到「长期访问令牌」，创建名为「Mac 空调控制」的令牌，再粘贴到上方。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if let error = store.settingsError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
                Button { Task { await store.connect() } } label: {
                    Text(store.isConnecting ? "正在连接…" : "连接并发现设备").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(store.isConnecting || store.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if !store.homeDevices.isEmpty {
                    Divider()
                    Text("设备名称").font(.callout.weight(.medium))
                    ForEach(store.homeDevices) { entity in
                        VStack(alignment: .leading, spacing: 5) {
                            TextField(entity.name, text: Binding(
                                get: { store.aliases[entity.id] ?? "" },
                                set: { store.rename(entity.id, to: $0) }
                            )).textFieldStyle(.roundedBorder).accessibilityLabel("\(entity.name)的显示名称")
                            Text([entity.room, entity.source, entity.model].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }
            }
            .padding(20)
            .disabled(store.isConnecting)
        }
        .frame(maxHeight: .infinity)
    }
}
