import AppKit
import SwiftUI

struct HomeDeviceControlView: View {
    @ObservedObject var store: AirConditionerStore
    let device: HomeDevice
    @ViewState<Bool> private var more = false
    @ViewState<Bool> private var allReadings = false
    @ViewState<String?> private var climateID = nil
    private var climates: [HomeEntity] { device.entities.filter { $0.domain == "climate" } }
    private var climate: ClimateEntity? { (climates.first { $0.id == climateID } ?? climates.first)?.climate }
    private var extra: [HomeEntity] { device.secondaryControls.filter { $0.domain != "climate" } }
    private var readings: [HomeEntity] {
        device.readings.sorted { a, b in
            if (a.domain == "event") != (b.domain == "event") { return a.domain != "event" }
            if a.stateKnown != b.stateKnown { return a.stateKnown }
            return device.label(for: a).localizedStandardCompare(device.label(for: b)) == .orderedAscending
        }
    }
    private var initialReadings: [HomeEntity] { Array(readings.filter { $0.domain != "event" }.prefix(5)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                identity
                if let error = store.connectionError { InlineNotice(text: error) }
                else if let id = store.commandErrorEntityID, device.entities.contains(where: { $0.id == id }), let error = store.commandError {
                    InlineNotice(text: error)
                } else if !device.entities.isEmpty && device.entities.allSatisfy({ $0.state == "unavailable" }) {
                    InlineNotice(text: "设备暂时离线，恢复连接后即可控制。")
                }
                if let climate {
                    if climates.count > 1 { climateSections }
                    DeviceControlView(store: store, entity: climate, embedded: true)
                } else if let primary = device.primary {
                    HomeEntityControl(store: store, entity: primary, title: device.label(for: primary), prominent: true)
                }
                if !readings.isEmpty { readingsSection }
                if !extra.isEmpty { moreSection }
                Button { store.openDevice(device) } label: {
                    Label("在 Home Assistant 中查看设备", systemImage: "arrow.up.forward.square")
                        .font(.system(size: 12))
                }.buttonStyle(.link).padding(.top, 4)
            }.padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 24)
        }.scrollIndicators(.visible)
    }
    private var identity: some View {
        HStack(spacing: 14) {
            Image(systemName: device.category.symbol).font(.system(size: 28, weight: .light))
                .foregroundStyle(device.active ? PanelStyle.accent : PanelStyle.secondaryText)
                .frame(width: 54, height: 54).background(PanelStyle.tile, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 5) {
                Text(store.name(for: device)).font(.system(size: 20, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                Text([device.category.rawValue, device.room, device.source].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 12)).foregroundStyle(PanelStyle.secondaryText)
            }
            Spacer(minLength: 0)
        }
    }
    private var climateSections: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(climates) { entity in
                    Button { climateID = entity.id; store.selectedID = entity.id } label: {
                        Text(device.label(for: entity)).font(.system(size: 12))
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .foregroundStyle(entity.id == climate?.id ? Color.white : Color.primary)
                            .background(entity.id == climate?.id ? PanelStyle.accent : Color.primary.opacity(0.055), in: Capsule())
                    }.buttonStyle(.plain).accessibilityAddTraits(entity.id == climate?.id ? .isSelected : [])
                }
            }
        }
    }
    private var readingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("设备状态").font(.system(size: 13, weight: .semibold))
            ForEach(allReadings ? readings : initialReadings) { entity in
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(device.label(for: entity)).foregroundStyle(PanelStyle.secondaryText).lineLimit(2).help(device.label(for: entity))
                    Spacer(minLength: 0)
                    Text(entity.displayState).multilineTextAlignment(.trailing).textSelection(.enabled)
                }.font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            }
            if readings.count > initialReadings.count {
                Button(allReadings ? "收起状态" : "查看其余 \(readings.count - initialReadings.count) 项状态与事件") { allReadings.toggle() }
                    .buttonStyle(.link).font(.system(size: 12))
            }
        }
    }
    private var moreSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button { more.toggle() } label: {
                HStack {
                    Text("更多功能与设置").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text("\(extra.count) 项").font(.system(size: 11)).foregroundStyle(PanelStyle.secondaryText)
                    Image(systemName: more ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .semibold))
                }.padding(.vertical, 10).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityValue(more ? "已展开" : "已收起")
            if more {
                ForEach(extra) { entity in
                    HomeEntityControl(store: store, entity: entity, title: device.label(for: entity))
                    if entity.id != extra.last?.id { Divider() }
                }
            }
        }
    }
}

struct HomeEntityControl: View {
    @ObservedObject var store: AirConditionerStore
    let entity: HomeEntity
    let title: String
    var prominent = false
    @ViewState<Bool> private var confirmingAction = false

    private var enabled: Bool { store.canControl(entity) }
    private func enabled(_ service: String) -> Bool { enabled && store.supportsService(entity, service) }
    private func send(_ service: String, _ values: [String: Any] = [:]) {
        Task { await store.perform(service, entityID: entity.id, values: values) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if entity.domain == "button" { actionButton }
            else if ["sensor", "binary_sensor", "event"].contains(entity.domain) { sensor }
            else {
                if let power = entity.powerServices { powerControl(on: power.on, off: power.off) }
                else if entity.domain != "camera" { sectionTitle }
                specificControls
                ForEach(entity.numericControls(temperatureUnit: store.temperatureUnit)) { spec in
                    HomeValueControl(spec: spec, enabled: enabled(spec.service)) { value in send(spec.service, spec.payload(value)) }
                }
            }
        }
        .opacity(entity.available ? 1 : 0.6)
    }
    private var sectionTitle: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 13, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Text(entity.displayState).font(.system(size: 11)).foregroundStyle(PanelStyle.secondaryText)
                .lineLimit(2).multilineTextAlignment(.trailing)
        }
    }
    private func powerControl(on: String, off: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 14, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                Text(store.pendingEntityID == entity.id ? "正在应用设置…" : entity.displayState)
                    .font(.system(size: 12)).foregroundStyle(PanelStyle.secondaryText)
            }
            Spacer(minLength: 10)
            let isOn = entity.stateKnown && entity.state != "off"
            Button { send(isOn ? off : on) } label: {
                Image(systemName: "power").font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isOn ? Color.white : Color.primary).frame(width: 46, height: 46)
                    .background(isOn ? PanelStyle.accent : Color.primary.opacity(0.08), in: Circle())
            }.buttonStyle(.plain).disabled(!enabled(isOn ? off : on))
                .accessibilityLabel("\(isOn ? "关闭" : "开启")\(title)")
        }
    }
    private var sensor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13)).foregroundStyle(PanelStyle.secondaryText)
            Text(entity.displayState).font(.system(size: prominent ? 26 : 16, weight: .semibold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(prominent ? 18 : 0)
            .background(prominent ? PanelStyle.tile : Color.clear, in: RoundedRectangle(cornerRadius: 16))
    }
    private var actionButton: some View {
        Button {
            if entity.needsActionConfirmation { confirmingAction = true } else { send("press") }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: entity.needsActionConfirmation ? "exclamationmark.circle" : "hand.tap")
                Text(title).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }.font(.system(size: 12)).padding(.vertical, 4)
        }.buttonStyle(.bordered).disabled(!enabled("press"))
            .confirmationDialog("确定执行「\(title)」？", isPresented: $confirmingAction, titleVisibility: .visible) {
                Button("执行", role: .destructive) { send("press") }
                Button("取消", role: .cancel) { }
            } message: { Text("此操作会改变设备或设备中的数据。") }
    }
    @ViewBuilder private var specificControls: some View {
        switch entity.domain {
        case "fan": fanControls
        case "humidifier":
            if let value = entity.number("current_humidity") { readout("当前湿度", "\(formatTemperature(value))%") }
            choices("模式", current: entity.text("mode"), options: entity.list("available_modes"), service: "set_mode", key: "mode")
        case "light": lightControls
        case "water_heater":
            if let value = entity.number("current_temperature") { readout("当前水温", "\(formatTemperature(value))\(store.temperatureUnit)") }
            choices("运行模式", current: entity.text("operation_mode"), options: entity.list("operation_list"), service: "set_operation_mode", key: "operation_mode")
        case "select":
            choices("选项", current: entity.stateKnown ? entity.state : nil, options: entity.list("options"), service: "select_option", key: "option")
        case "text", "notify":
            HomeTextControl(entity: entity, enabled: enabled(entity.domain == "text" ? "set_value" : "send_message")) { value in
                send(entity.domain == "text" ? "set_value" : "send_message", [entity.domain == "text" ? "value" : "message": value])
            }
        case "media_player": mediaControls
        case "camera": HomeCameraView(store: store, entity: entity, title: title)
        case "cover":
            HStack {
                if entity.supports(1) { commandButton("打开", "arrow.up", "open_cover") }
                if entity.supports(8) { commandButton("停止", "stop.fill", "stop_cover") }
                if entity.supports(2) { commandButton("关闭", "arrow.down", "close_cover") }
            }
        case "number", "switch": EmptyView()
        default:
            Text("可在页面下方打开 Home Assistant，使用此设备的专用控制。")
                .font(.system(size: 12)).foregroundStyle(PanelStyle.secondaryText).fixedSize(horizontal: false, vertical: true)
        }
    }
    @ViewBuilder private var fanControls: some View {
        choices("模式", current: entity.text("preset_mode"), options: entity.supports(8) ? entity.list("preset_modes") : [], service: "set_preset_mode", key: "preset_mode")
        if entity.supports(2) {
            Toggle("摇头", isOn: Binding(get: { entity.flag("oscillating") ?? false }, set: { send("oscillate", ["oscillating": $0]) }))
                .toggleStyle(.switch).font(.system(size: 12)).disabled(!enabled("oscillate"))
        }
        if entity.supports(4) {
            choices("方向", current: entity.text("direction"), options: ["forward", "reverse"], service: "set_direction", key: "direction")
        }
    }
    @ViewBuilder private var lightControls: some View {
        if entity.list("supported_color_modes").contains(where: { ["hs", "rgb", "rgbw", "rgbww", "xy"].contains($0) }) {
            HomeLightColorControl(enabled: enabled("turn_on")) { send("turn_on", $0) }
        }
        if entity.supports(4) { choices("灯效", current: entity.text("effect"), options: entity.list("effect_list"), service: "turn_on", key: "effect") }
    }
    @ViewBuilder private var mediaControls: some View {
        if let name = entity.text("media_title"), !name.isEmpty { readout("正在播放", name) }
        HStack(spacing: 8) {
            if entity.supports(16) { commandButton("上一首", "backward.end.fill", "media_previous_track") }
            if entity.state == "playing", entity.supports(1) { commandButton("暂停", "pause.fill", "media_pause") }
            else if entity.supports(16384) { commandButton("播放", "play.fill", "media_play") }
            if entity.supports(4096) { commandButton("停止", "stop.fill", "media_stop") }
            if entity.supports(32) { commandButton("下一首", "forward.end.fill", "media_next_track") }
        }
        if entity.supports(8) {
            Toggle("静音", isOn: Binding(get: { entity.flag("is_volume_muted") ?? false }, set: { send("volume_mute", ["is_volume_muted": $0]) }))
                .toggleStyle(.switch).font(.system(size: 12)).disabled(!enabled("volume_mute"))
        }
        if entity.supports(2048) { choices("播放来源", current: entity.text("source"), options: entity.list("source_list"), service: "select_source", key: "source") }
    }
    @ViewBuilder private func choices(_ title: String, current: String?, options: [String], service: String, key: String) -> some View {
        if !options.isEmpty {
            ChoiceSection(title: title, current: current, options: options, display: homeOptionName, enabled: enabled(service)) { value in send(service, [key: value]) }
        }
    }
    private func commandButton(_ title: String, _ symbol: String, _ service: String) -> some View {
        Button { send(service) } label: {
            Label(title, systemImage: symbol).font(.system(size: 11)).frame(maxWidth: .infinity).padding(.vertical, 6)
        }.buttonStyle(.bordered).disabled(!enabled(service)).accessibilityLabel(title)
    }
    private func readout(_ title: String, _ value: String) -> some View {
        HStack { Text(title).foregroundStyle(PanelStyle.secondaryText); Spacer(); Text(value).multilineTextAlignment(.trailing) }
            .font(.system(size: 12))
    }
}

struct HomeValueControl: View {
    let spec: NumericControlSpec
    let enabled: Bool
    let commit: (Double) -> Void
    @ViewState<Double> private var draft: Double
    @ViewState<Bool> private var editing = false
    @ViewState<String> private var input = ""
    init(spec: NumericControlSpec, enabled: Bool, commit: @escaping (Double) -> Void) {
        self.spec = spec; self.enabled = enabled; self.commit = commit
        _draft = ViewState(initialValue: spec.normalized(spec.value ?? spec.range.lowerBound))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(spec.title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(spec.value == nil ? "状态未提供" : "\(formatTemperature(editing ? draft : spec.value!))\(spec.unit)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            if spec.value != nil {
                Group {
                    if (spec.range.upperBound - spec.range.lowerBound) / spec.step <= 20 {
                        Slider(value: $draft, in: spec.range, step: spec.step, onEditingChanged: editingChanged)
                    } else {
                        Slider(value: $draft, in: spec.range, onEditingChanged: editingChanged)
                    }
                }.disabled(!enabled).accessibilityLabel(spec.title)
            } else {
                HStack(spacing: 8) {
                    TextField("输入\(spec.title)", text: $input).textFieldStyle(.roundedBorder).accessibilityLabel(spec.title)
                    Button("设置") { if let value = Double(input) { commit(spec.normalized(value)) } }
                        .disabled(!enabled || parsedInput == nil)
                }
            }
            HStack {
                Text("\(formatTemperature(spec.range.lowerBound))\(spec.unit)")
                Spacer()
                Text("\(formatTemperature(spec.range.upperBound))\(spec.unit)")
            }.font(.system(size: 10)).foregroundStyle(PanelStyle.secondaryText)
        }
        .onChange(of: spec.value) { _, value in if !editing, let value { draft = spec.normalized(value) } }
    }
    private var parsedInput: Double? {
        guard let value = Double(input), value.isFinite, spec.range.contains(value) else { return nil }
        return value
    }
    private func editingChanged(_ isEditing: Bool) {
        editing = isEditing
        if !isEditing {
            draft = spec.normalized(draft)
            if spec.value.map({ abs(draft - $0) > 0.0001 }) ?? false { commit(draft) }
        }
    }
}

struct HomeTextControl: View {
    let entity: HomeEntity
    let enabled: Bool
    let commit: (String) -> Void
    @ViewState<String> private var draft = ""
    @ViewState<Bool> private var editing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(entity.domain == "notify" ? "填写要发送的内容" : "填写设置值", text: $draft, axis: .vertical)
                .lineLimit(1...4).textFieldStyle(.roundedBorder).onChange(of: draft) { _, _ in editing = true }
                .disabled(entity.text("mode") == "password" || !enabled)
            HStack {
                if entity.domain == "notify" { Text("内容按设备要求原样发送").font(.system(size: 10)).foregroundStyle(PanelStyle.secondaryText) }
                Spacer()
                Button(entity.domain == "notify" ? "发送" : "保存") { commit(draft); editing = false }
                    .disabled(!enabled || !valid)
            }
        }.onAppear { if entity.domain == "text", entity.stateKnown, entity.text("mode") != "password" { draft = entity.state } }
    }
    private var valid: Bool {
        if entity.domain == "notify" { return !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return draft.count >= Int(entity.number("min") ?? 0) && draft.count <= Int(entity.number("max") ?? 255) && entity.text("mode") != "password"
    }
}

struct HomeLightColorControl: View {
    let enabled: Bool
    let commit: ([String: Any]) -> Void
    @ViewState<Color> private var color = .blue
    var body: some View {
        HStack {
            ColorPicker("设定颜色", selection: $color, supportsOpacity: false).font(.system(size: 12))
            Button("应用颜色") {
                if let value = NSColor(color).usingColorSpace(.deviceRGB) { commit(["hs_color": [value.hueComponent * 360, value.saturationComponent * 100]]) }
            }
        }.disabled(!enabled)
    }
}

struct HomeCameraView: View {
    @ObservedObject var store: AirConditionerStore
    let entity: HomeEntity
    let title: String
    @ViewState<NSImage?> private var image = nil
    @ViewState<String?> private var error = nil
    @ViewState<Bool> private var loading = false
    @ViewState<Date?> private var capturedAt = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 13, weight: .semibold))
            if let image { Image(nsImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12)) }
            if let capturedAt { Text("快照读取于 \(capturedAt.formatted(date: .omitted, time: .standard))").font(.system(size: 10)).foregroundStyle(PanelStyle.secondaryText) }
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(PanelStyle.secondaryText) }
            if !entity.available { Text("Home Assistant 暂未提供可用画面。").font(.system(size: 12)).foregroundStyle(PanelStyle.secondaryText) }
            Button(loading ? "正在读取…" : image == nil ? "查看当前画面" : "刷新画面") {
                loading = true
                Task {
                    defer { loading = false }
                    do {
                        let data = try await store.cameraImage(entity)
                        guard let picture = NSImage(data: data) else { throw HAError.badResponse }
                        image = picture; capturedAt = Date(); error = nil
                    } catch { self.error = "暂时无法读取画面，可在 Home Assistant 中检查摄像机。" }
                }
            }.buttonStyle(.bordered).disabled(loading || !entity.available || store.connectionError != nil)
        }
    }
}

func homeOptionName(_ value: String) -> String {
    let translated = ["forward": "正向", "reverse": "反向", "Low": "低", "Medium": "中", "High": "高", "On": "打开", "Off": "关闭",
                      "All Record": "全天录像", "Motion Record": "移动录像", "No Record": "停止录像", "sleep": "睡眠", "favorite": "最爱",
                      "straight_wind": "直吹", "natural_wind": "自然风", "heat": "加热", "Cool": "制冷", "Heat": "制热", "Dry": "除湿", "Fan": "送风"]
    return translated[value] ?? optionName(value)
}
