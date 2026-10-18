import AppKit
import SwiftUI

// Qualify the property-wrapper type to remain compatible with SDKs that also export a State macro.
typealias ViewState<Value> = SwiftUI.State<Value>

enum PanelStyle {
    static let width: CGFloat = 420
    static var height: CGFloat { min(644, (NSScreen.main?.visibleFrame.height ?? 900) - 80) }
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let tile = Color(nsColor: .controlBackgroundColor)
    static let accent = Color.accentColor
    static let secondaryText = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor(calibratedWhite: isDark ? 0.72 : 0.36, alpha: 1)
    })
    static let radius: CGFloat = 16
}

struct ControlPanel: View {
    @ObservedObject var store: AirConditionerStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState<String?> private var detailID = nil
    @ViewState<DeviceCategory?> private var category = nil
    @ViewState<String> private var search = ""

    private var detail: HomeDevice? { store.homeDevices.first { $0.id == detailID } }
    private var filtered: [HomeDevice] {
        store.homeDevices.filter { device in
            (category == nil || device.category == category) &&
            (search.isEmpty || (store.name(for: device) + " " + device.room + " " + device.source).localizedCaseInsensitiveContains(search))
        }
    }
    private var categories: [DeviceCategory] { DeviceCategory.allCases.filter { value in store.homeDevices.contains { $0.category == value } } }

    var body: some View {
        VStack(spacing: 0) {
            header
            if store.showingSettings {
                ConnectionSettings(store: store)
            } else if let detail {
                HomeDeviceControlView(store: store, device: detail).id(detail.id)
                    .transition(.opacity.combined(with: .offset(x: reduceMotion ? 0 : 12)))
            } else if store.homeDevices.isEmpty {
                emptyState
            } else {
                overview
                    .transition(.opacity)
            }
            footer
        }
        .frame(width: PanelStyle.width, height: PanelStyle.height)
        .background(PanelStyle.canvas)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: detailID)
        .onAppear {
            detailID = nil
            category = nil
            search = ""
            Task { await store.refresh() }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if detailID != nil || store.showingSettings && store.configured {
                Button {
                    if store.showingSettings { store.showingSettings = false }
                    else { detailID = nil; category = nil; search = "" }
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold)).frame(width: 30, height: 32)
                }
                .buttonStyle(.plain).accessibilityLabel(store.showingSettings ? "返回" : "返回全部设备")
                .help(store.showingSettings ? "返回" : "全部设备")
                .keyboardShortcut(.leftArrow, modifiers: .command)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(store.showingSettings ? "连接设置" : detailID == nil ? "家居控制" : "设备控制")
                    .font(.system(size: 19, weight: .semibold))
                if detailID == nil && !store.showingSettings {
                    Text("\(store.homeDevices.count) 个设备，随手掌控")
                        .font(.system(size: 11)).foregroundStyle(PanelStyle.secondaryText)
                }
            }
            Spacer()
            if !store.showingSettings {
                Button {
                    store.settingsError = nil
                    store.showingSettings = true
                } label: {
                    Image(systemName: "gearshape").font(.system(size: 15)).frame(width: 30, height: 32)
                }
                .buttonStyle(.plain).foregroundStyle(PanelStyle.secondaryText)
                .help("连接与设备名称").accessibilityLabel("连接与设备名称")
                .disabled(store.isSending || store.isConnecting)
            }
        }
        .padding(.horizontal, 20).frame(height: 66)
    }

    private var overview: some View {
        VStack(spacing: 0) {
            if let error = store.connectionError {
                InlineNotice(text: error).padding(.horizontal, 20).padding(.bottom, 8)
            }
            if let notice = store.inventoryNotice {
                InlineNotice(text: notice).padding(.horizontal, 20).padding(.bottom, 8)
            }
            if let error = store.commandError {
                InlineNotice(text: error).padding(.horizontal, 20).padding(.bottom, 8)
            }
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(PanelStyle.secondaryText)
                TextField("搜索设备或房间", text: $search).textFieldStyle(.plain)
                    .accessibilityLabel("搜索设备或房间")
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("清除搜索")
                }
            }
            .font(.system(size: 12)).padding(.horizontal, 10).frame(height: 30)
            .background(PanelStyle.tile, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 20).padding(.bottom, 8)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    filterButton("全部", value: nil)
                    ForEach(categories) { item in filterButton(item.rawValue, value: item) }
                }.padding(.horizontal, 20)
            }.frame(height: 34).padding(.bottom, 10)
            if filtered.isEmpty {
                VStack(spacing: 10) {
                    Text(search.isEmpty ? "此分类暂时没有设备" : "没有找到匹配的设备").foregroundStyle(PanelStyle.secondaryText)
                    Button("显示全部设备") { category = nil; search = "" }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(filtered) { entity in
                            HomeDeviceTile(device: entity, name: store.name(for: entity),
                                       distinguishSource: store.homeDevices.filter { store.name(for: $0) == store.name(for: entity) }.count > 1,
                                       connected: store.connectionError == nil,
                                       pendingEntityID: store.pendingEntityID,
                                       canPerformPower: store.canPerformPower,
                                       performPower: { command in Task { await store.performPower(command) } }) {
                                store.selectedID = entity.id
                                detailID = entity.id
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 2).padding(.bottom, 14)
                }
                .scrollIndicators(.visible)
            }
        }
    }

    private func filterButton(_ title: String, value: DeviceCategory?) -> some View {
        Button { category = value } label: {
            Text(title).font(.system(size: 12, weight: category == value ? .semibold : .regular))
                .padding(.horizontal, 13).frame(height: 29)
                .background(category == value ? Color.primary : Color.primary.opacity(0.045), in: Capsule())
                .foregroundStyle(category == value ? PanelStyle.canvas : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)设备").accessibilityAddTraits(category == value ? .isSelected : [])
    }

    private var footer: some View {
        HStack(spacing: 7) {
            if store.isRefreshing || store.isConnecting || store.isSending {
                ProgressView().controlSize(.mini)
                Text(store.isSending ? "正在应用设置…" : "正在同步…")
            } else if store.connectionError != nil {
                Image(systemName: "wifi.slash").foregroundStyle(.orange)
                Text("连接中断 · 显示上次状态")
            } else if let updated = store.lastUpdated {
                Circle().fill(.green).frame(width: 5, height: 5)
                Text("已同步 \(updated.formatted(date: .omitted, time: .shortened))")
            } else { Text("通过 Home Assistant 连接") }
            Spacer(minLength: 4)
            Button { Task { await store.refresh(forceMetadata: true) } } label: {
                Image(systemName: "arrow.clockwise").frame(width: 24, height: 24)
            }
            .buttonStyle(.plain).accessibilityLabel("刷新设备状态").help("刷新设备状态")
            .disabled(store.isRefreshing || store.isSending || store.isConnecting || !store.configured)
            Menu {
                Button("打开 Home Assistant") {
                    if let url = try? HAClient(address: store.address, token: "").baseURL { NSWorkspace.shared.open(url) }
                }
                Divider()
                Button("退出家居控制") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
            } label: { Image(systemName: "ellipsis").frame(width: 24, height: 24) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("应用菜单")
        }
        .font(.system(size: 11)).foregroundStyle(PanelStyle.secondaryText)
        .padding(.horizontal, 20).frame(height: 40)
        .background(PanelStyle.canvas)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: store.connectionError == nil ? "house" : "wifi.slash")
                .font(.system(size: 32)).foregroundStyle(PanelStyle.secondaryText)
            Text(store.isRefreshing ? "正在读取设备" : store.connectionError == nil ? "还没有发现设备" : "暂时无法连接")
                .font(.headline)
            Text(store.connectionError ?? "确认设备已接入 Home Assistant，然后刷新。")
                .font(.callout).foregroundStyle(PanelStyle.secondaryText).multilineTextAlignment(.center)
            Button("重新读取") { Task { await store.refresh(forceMetadata: true) } }.disabled(store.isRefreshing)
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HomeDeviceTile: View {
    let device: HomeDevice
    let name: String
    let distinguishSource: Bool
    let connected: Bool
    let pendingEntityID: String?
    let canPerformPower: (DevicePowerCommand) -> Bool
    let performPower: (DevicePowerCommand) -> Void
    let action: () -> Void
    @ViewState<Bool> private var hovered = false

    private var active: Bool { connected && device.active }
    private var status: String { connected ? device.statusText : "连接中断" }
    var body: some View {
        // Sibling buttons keep a power click from opening device details.
        ZStack(alignment: .bottomTrailing) {
            detailButton
            if let power = device.powerControl {
                DeviceTilePowerButton(control: power, name: name,
                                      pending: power.includes(pendingEntityID),
                                      canPerform: canPerformPower, perform: performPower)
                    .padding(10)
            }
        }
        .onHover { hovered = $0 }
        .accessibilityElement(children: .contain)
    }
    private var detailButton: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: device.category.symbol).font(.system(size: 20))
                        .foregroundStyle(active ? PanelStyle.accent : PanelStyle.secondaryText)
                    Spacer(minLength: 4)
                    if let reading = device.reading, reading.count <= 9 {
                        Text(reading).font(.system(size: 16, weight: .semibold, design: .rounded)).monospacedDigit()
                    } else if !device.online {
                        Image(systemName: device.statusText == "离线" ? "wifi.slash" : "questionmark.circle").font(.system(size: 12)).foregroundStyle(PanelStyle.secondaryText)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    Text([status, distinguishSource ? device.source : device.room.isEmpty ? device.source : device.room].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 10.5)).foregroundStyle(PanelStyle.secondaryText).lineLimit(1)
                }
                .padding(.trailing, device.powerControl == nil ? 0 : 34)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(13).frame(height: 88).frame(maxWidth: .infinity, alignment: .leading)
            .background(PanelStyle.tile, in: RoundedRectangle(cornerRadius: PanelStyle.radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PanelStyle.radius, style: .continuous)
                    .strokeBorder(hovered ? PanelStyle.accent.opacity(0.65) : Color.primary.opacity(0.06), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: PanelStyle.radius))
        }
        .buttonStyle(.plain)
        .help("\(name) · \(status)，点击打开控制")
        .accessibilityElement(children: .ignore).accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(name)，\(status)\(distinguishSource ? "，" + device.source : "")\(device.reading.map { "，" + $0 } ?? "")")
        .accessibilityHint("打开设备控制面板")
    }
}

private struct DeviceTilePowerButton: View {
    let control: DevicePowerControl
    let name: String
    let pending: Bool
    let canPerform: (DevicePowerCommand) -> Bool
    let perform: (DevicePowerCommand) -> Void

    private var actionName: String { control.isOn == true ? "关闭" : "开启" }
    var body: some View {
        Group {
            if control.isOn != nil {
                Button {
                    if let command = control.currentCommand { perform(command) }
                } label: { icon }
                .buttonStyle(.plain)
                .disabled(pending || (control.currentCommand.map { !canPerform($0) } ?? true))
                .help("\(actionName)\(name)")
                .accessibilityLabel("\(actionName)\(name)")
            } else {
                Menu {
                    if let on = control.on {
                        Button("开机") { perform(on) }.disabled(!canPerform(on))
                    }
                    if let off = control.off {
                        Button("关机") { perform(off) }.disabled(!canPerform(off))
                    }
                } label: { icon }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .disabled(pending || !(control.on.map(canPerform) ?? false) && !(control.off.map(canPerform) ?? false))
                .help("\(name)未提供开关状态，点击选择开机或关机")
                .accessibilityLabel("\(name)电源，选择开机或关机")
            }
        }
        .frame(width: 30, height: 30)
        .background(control.isOn == true ? PanelStyle.accent : Color.primary.opacity(0.09), in: Circle())
        .accessibilityValue(pending ? "正在应用设置" : control.isOn.map { $0 ? "已开启" : "已关闭" } ?? "状态未提供")
    }
    private var icon: some View {
        ZStack {
            if pending {
                ProgressView().controlSize(.mini).tint(control.isOn == true ? .white : .primary)
            } else {
                Image(systemName: "power").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(control.isOn == true ? Color.white : Color.primary)
            }
        }
        .frame(width: 30, height: 30)
        .contentShape(Circle())
    }
}

struct InlineNotice: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.system(size: 12)).foregroundStyle(PanelStyle.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
    }
}
