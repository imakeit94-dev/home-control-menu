import SwiftUI

struct DeviceControlView: View {
    @ObservedObject var store: AirConditionerStore
    let entity: ClimateEntity
    var embedded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState<Bool> private var moreExpanded = false

    private var online: Bool { entity.available && store.connectionError == nil }
    private var enabled: Bool { store.canControl(entity) }
    private var modes: [String] { (entity.attributes.hvac_modes ?? []).filter { $0 != "off" } }
    private var hasMore: Bool {
        !(entity.attributes.fan_modes ?? []).isEmpty || !(entity.attributes.swing_modes ?? []).isEmpty || !(entity.attributes.preset_modes ?? []).isEmpty
    }

    @ViewBuilder var body: some View {
        if embedded { content } else { ScrollView { content }.scrollIndicators(.visible) }
    }
    private var content: some View {
            VStack(alignment: .leading, spacing: 24) {
                if !embedded { identity }
                if !embedded, let error = store.connectionError {
                    InlineNotice(text: error)
                } else if !embedded, store.commandErrorEntityID == entity.id, let error = store.commandError {
                    InlineNotice(text: error)
                } else if !embedded, !entity.available {
                    InlineNotice(text: "设备暂时离线，请检查电源与网络。")
                }
                powerRow
                if entity.powered || !entity.available {
                    temperatureControl
                } else if store.supportsTargetTemperature(entity) {
                    HStack(spacing: 10) {
                        Image(systemName: "thermometer.medium").font(.system(size: 23)).foregroundStyle(PanelStyle.secondaryText)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("开启后调节温度").font(.system(size: 14, weight: .medium))
                            if let value = entity.attributes.current_temperature {
                                Text("\(entity.category.currentTemperatureLabel)温度 \(formatTemperature(value))\(store.temperatureUnit)")
                                    .font(.system(size: 12)).foregroundStyle(PanelStyle.secondaryText)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 20)
                }
                if !modes.isEmpty {
                    ChoiceSection(title: "模式", current: entity.state, options: modes,
                                  display: modeName, symbol: { modeSymbol($0) }, enabled: enabled) { value in
                        Task { await store.send("set_hvac_mode", entityID: entity.id, values: ["hvac_mode": value]) }
                    }
                }
                if hasMore { moreControls }
            }
            .padding(.horizontal, embedded ? 0 : 22).padding(.top, embedded ? 0 : 10).padding(.bottom, embedded ? 0 : 24)
    }

    private var identity: some View {
        HStack(spacing: 14) {
            Image(systemName: entity.category.symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(entity.powered && online ? PanelStyle.accent : Color.secondary)
                .frame(width: 54, height: 54)
                .background(PanelStyle.tile, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 5) {
                Text(store.name(for: entity)).font(.system(size: 20, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                Text(entity.category.rawValue).font(.system(size: 12)).foregroundStyle(PanelStyle.secondaryText)
            }
            Spacer(minLength: 0)
        }
    }

    private var powerRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(entity.supportsPowerOff || entity.supportsPowerOn ? "设备开关" : "运行状态")
                    .font(.system(size: 14, weight: .semibold))
                Text(store.pendingEntityID == entity.id ? "正在应用设置…" : online ? entity.statusText : "设备离线")
                    .font(.system(size: 12)).foregroundStyle(PanelStyle.secondaryText)
            }
            Spacer()
            if entity.supportsPowerOff || entity.supportsPowerOn {
                Button { Task { await store.togglePower(entityID: entity.id) } } label: {
                    Image(systemName: "power").font(.system(size: 21, weight: .medium))
                        .foregroundStyle(entity.powered && online ? Color.white : Color.primary)
                        .frame(width: 48, height: 48)
                        .background(entity.powered && online ? PanelStyle.accent : Color.primary.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain).disabled(!enabled || !entity.powerActionAvailable)
                .accessibilityLabel("\(entity.powered ? "关闭" : "开启")\(store.name(for: entity))")
                .help(entity.powered ? "关闭设备" : "开启设备")
            } else {
                Label(entity.statusText, systemImage: "checkmark.circle").font(.callout).foregroundStyle(PanelStyle.secondaryText)
            }
        }
    }

    @ViewBuilder
    private var temperatureControl: some View {
        if let target = entity.attributes.temperature {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    temperatureStep("minus", direction: -1)
                    VStack(spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(formatTemperature(target)).font(.system(size: 42, weight: .semibold, design: .rounded)).monospacedDigit()
                            Text(store.temperatureUnit).font(.system(size: 16, weight: .medium))
                        }
                        Text("目标温度").font(.system(size: 11)).foregroundStyle(PanelStyle.secondaryText)
                    }.frame(maxWidth: .infinity)
                    temperatureStep("plus", direction: 1)
                }
                .padding(.horizontal, 14).padding(.vertical, 20)
                .background(PanelStyle.tile, in: RoundedRectangle(cornerRadius: PanelStyle.radius))
                .accessibilityElement(children: .contain)
                HStack {
                    if let current = entity.attributes.current_temperature {
                        Text("\(entity.category.currentTemperatureLabel) \(formatTemperature(current))\(store.temperatureUnit)")
                    }
                    Spacer()
                    if let bounds = entity.temperatureBounds {
                        Text("\(formatTemperature(bounds.lowerBound))–\(formatTemperature(bounds.upperBound))\(store.temperatureUnit)")
                    }
                }.font(.system(size: 11)).foregroundStyle(PanelStyle.secondaryText)
            }.opacity(online ? 1 : 0.5)
        } else if let current = entity.attributes.current_temperature {
            HStack {
                Text("\(entity.category.currentTemperatureLabel)温度").font(.callout).foregroundStyle(PanelStyle.secondaryText)
                Spacer()
                Text("\(formatTemperature(current))\(store.temperatureUnit)").font(.title2.weight(.medium)).monospacedDigit()
            }.padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func temperatureStep(_ symbol: String, direction: Double) -> some View {
        if store.supportsTargetTemperature(entity) {
            Button { Task { await store.adjustTemperature(by: direction, entityID: entity.id) } } label: {
                Image(systemName: symbol).font(.system(size: 19, weight: .medium)).frame(width: 44, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!enabled || !entity.powered || entity.temperatureAfterStep(direction) == nil)
            .accessibilityLabel(direction < 0 ? "降低温度" : "升高温度")
        }
    }

    private var moreControls: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { moreExpanded.toggle() }
            } label: {
                HStack {
                    Text("更多操作").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text(moreSummary).font(.system(size: 11)).foregroundStyle(PanelStyle.secondaryText)
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(moreExpanded ? 180 : 0))
                }
                .padding(.vertical, 12).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityValue(moreExpanded ? "已展开" : "已收起")
            if moreExpanded {
                if let options = entity.attributes.fan_modes, !options.isEmpty {
                    choices("风速", current: entity.attributes.fan_mode, options: options, service: "set_fan_mode", key: "fan_mode")
                }
                if let options = entity.attributes.swing_modes, !options.isEmpty {
                    choices("扫风", current: entity.attributes.swing_mode, options: options, service: "set_swing_mode", key: "swing_mode")
                }
                if let options = entity.attributes.preset_modes, !options.isEmpty {
                    choices("预设", current: entity.attributes.preset_mode, options: options, service: "set_preset_mode", key: "preset_mode")
                }
            }
        }
    }

    private var moreSummary: String {
        [!(entity.attributes.fan_modes ?? []).isEmpty ? "风速" : nil,
         !(entity.attributes.swing_modes ?? []).isEmpty ? "扫风" : nil,
         !(entity.attributes.preset_modes ?? []).isEmpty ? "预设" : nil].compactMap { $0 }.joined(separator: " · ")
    }

    private func choices(_ title: String, current: String?, options: [String], service: String, key: String) -> some View {
        ChoiceSection(title: title, current: current, options: options, display: optionName, enabled: enabled) { value in
            Task { await store.send(service, entityID: entity.id, values: [key: value]) }
        }
    }
}

struct ChoiceSection: View {
    let title: String
    let current: String?
    let options: [String]
    var display: (String) -> String
    var symbol: ((String) -> String)? = nil
    let enabled: Bool
    let choose: (String) -> Void

    private var unique: [String] { var seen = Set<String>(); return options.filter { seen.insert($0).inserted } }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.system(size: 12, weight: .semibold))
                Spacer()
                if current == nil { Text("状态未提供").font(.system(size: 10)).foregroundStyle(PanelStyle.secondaryText) }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 8) {
                ForEach(unique, id: \.self) { option in
                    Button { choose(option) } label: {
                        HStack(spacing: 5) {
                            if let symbol { Image(systemName: symbol(option)).font(.system(size: 12)) }
                            Text(display(option)).font(.system(size: 12, weight: current == option ? .semibold : .regular))
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity).frame(minHeight: 35).padding(.horizontal, 6)
                        .foregroundStyle(current == option ? Color.white : Color.primary)
                        .background(current == option ? PanelStyle.accent : Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain).disabled(!enabled)
                    .accessibilityLabel("\(title)：\(display(option))").accessibilityAddTraits(current == option ? .isSelected : [])
                }
            }
        }
    }
}
