import Foundation

enum JSONValue: Codable {
    case string(String), number(Double), bool(Bool), array([JSONValue]), object([String: JSONValue]), null
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let v = try? value.decode(Bool.self) { self = .bool(v) }
        else if let v = try? value.decode(Double.self) { self = .number(v) }
        else if let v = try? value.decode(String.self) { self = .string(v) }
        else if let v = try? value.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try value.decode([JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .string(let v): try value.encode(v)
        case .number(let v): try value.encode(v)
        case .bool(let v): try value.encode(v)
        case .array(let v): try value.encode(v)
        case .object(let v): try value.encode(v)
        case .null: try value.encodeNil()
        }
    }
    var string: String? { if case .string(let v) = self { return v }; return nil }
    var number: Double? { if case .number(let v) = self { return v }; return nil }
    var bool: Bool? { if case .bool(let v) = self { return v }; return nil }
    var strings: [String]? { if case .array(let v) = self { return v.compactMap(\.string) }; return nil }
}

struct HomeEntity: Codable, Identifiable {
    let entity_id: String
    let state: String
    let attributes: [String: JSONValue]
    var id: String { entity_id }
    var domain: String { String(id.split(separator: ".").first ?? "") }
    var name: String { text("friendly_name") ?? id }
    var available: Bool { state != "unavailable" }
    var stateKnown: Bool { available && state != "unknown" }
    var powered: Bool { stateKnown && !["off", "idle", "standby", "docked"].contains(state) }
    var features: Int { Int(number("supported_features") ?? 0) }
    func text(_ key: String) -> String? { attributes[key]?.string }
    func number(_ key: String) -> Double? { attributes[key]?.number }
    func list(_ key: String) -> [String] { attributes[key]?.strings ?? [] }
    func flag(_ key: String) -> Bool? { attributes[key]?.bool }
    func supports(_ feature: Int) -> Bool { features & feature != 0 }
    var climate: ClimateEntity? {
        guard domain == "climate" else { return nil }
        // These attributes are already decoded. Do not serialize the entire entity
        // again every time SwiftUI asks for its temperature or category.
        return ClimateEntity(entity_id: id, state: state, attributes: .init(
            friendly_name: text("friendly_name"), current_temperature: number("current_temperature"),
            temperature: number("temperature"), min_temp: number("min_temp"), max_temp: number("max_temp"),
            target_temp_step: number("target_temp_step"), hvac_modes: attributes["hvac_modes"]?.strings,
            hvac_action: text("hvac_action"), fan_mode: text("fan_mode"), fan_modes: attributes["fan_modes"]?.strings,
            swing_mode: text("swing_mode"), swing_modes: attributes["swing_modes"]?.strings,
            preset_mode: text("preset_mode"), preset_modes: attributes["preset_modes"]?.strings,
            supported_features: number("supported_features").flatMap { Int(exactly: $0) }))
    }
}

struct HAEntityRegistration: Decodable {
    let entity_id: String
    let device_id: String?
    let platform: String?
    let entity_category: String?
    let disabled_by: String?
    let hidden_by: String?
    let original_name: String?
    let name: String?
}
struct HADeviceRegistration: Decodable {
    let id: String
    let name: String?
    let name_by_user: String?
    let manufacturer: String?
    let model: String?
    let area_id: String?
    let disabled_by: String?
    let identifiers: [[String]]?
    let connections: [[String]]?
}

struct DevicePowerCommand {
    let entityID: String
    let service: String
    var values: [String: String] = [:]
}

struct DevicePowerControl {
    let on: DevicePowerCommand?
    let off: DevicePowerCommand?
    let isOn: Bool?

    var currentCommand: DevicePowerCommand? {
        guard let isOn else { return nil }
        return isOn ? off : on
    }
    func includes(_ entityID: String?) -> Bool {
        guard let entityID else { return false }
        return on?.entityID == entityID || off?.entityID == entityID
    }
    static func make(primary: HomeEntity?, entities: [HomeEntity]) -> DevicePowerControl? {
        if let entity = primary, let climate = entity.climate {
            // A multi-zone appliance has no proven device-wide power command.
            guard entities.filter({ $0.domain == "climate" }).count == 1 else { return nil }
            guard climate.supportsPowerOn || climate.supportsPowerOff else { return nil }
            let off = (climate.attributes.hvac_modes ?? []).contains("off")
                ? DevicePowerCommand(entityID: entity.id, service: "set_hvac_mode", values: ["hvac_mode": "off"])
                : DevicePowerCommand(entityID: entity.id, service: "turn_off")
            return DevicePowerControl(on: climate.supportsPowerOn ? .init(entityID: entity.id, service: "turn_on") : nil,
                                      off: climate.supportsPowerOff ? off : nil,
                                      isOn: entity.stateKnown ? climate.powered : nil)
        }
        if let entity = primary, let services = entity.powerServices {
            return DevicePowerControl(on: .init(entityID: entity.id, service: services.on),
                                      off: .init(entityID: entity.id, service: services.off),
                                      isOn: entity.stateKnown ? entity.state != "off" : nil)
        }
        // Explicit IR on/off actions are stateless. Never infer a toggle state from
        // the last command, or promote an indicator/child-lock switch to device power.
        let on = entities.filter { $0.domain == "button" && $0.id.contains("_turn_on_a_") }
        let off = entities.filter { $0.domain == "button" && $0.id.contains("_turn_off_a_") }
        guard on.count == 1, off.count == 1 else { return nil }
        return DevicePowerControl(on: .init(entityID: on[0].id, service: "press"),
                                  off: .init(entityID: off[0].id, service: "press"), isOn: nil)
    }
}

struct HomeDevice: Identifiable {
    let id: String
    let registryIDs: [String]
    let name: String
    let model: String
    let room: String
    let isXiaomi: Bool
    let entities: [HomeEntity]
    let registrations: [String: HAEntityRegistration]
    let source: String
    let primary: HomeEntity?
    let category: DeviceCategory
    let online: Bool
    let secondaryControls: [HomeEntity]
    let readings: [HomeEntity]
    let powerControl: DevicePowerControl?

    init(id: String, registryIDs: [String], name: String, model: String, room: String,
         isXiaomi: Bool, entities: [HomeEntity], registrations: [String: HAEntityRegistration]) {
        self.id = id; self.registryIDs = registryIDs; self.name = name
        self.model = model; self.room = room; self.isXiaomi = isXiaomi
        self.entities = entities; self.registrations = registrations
        // A device is an immutable state snapshot. Resolve expensive derived data
        // once per incoming update, not on every layout, hover or category scan.
        let platforms = Set(entities.compactMap { registrations[$0.id]?.platform })
        source = platforms.contains("xiaomi_home") ? "米家" : platforms.contains("xiaomi_miot") ? "米家 MIoT" : ""
        let order = ["climate", "humidifier", "fan", "camera", "media_player", "water_heater", "light", "cover", "vacuum", "lock", "switch", "binary_sensor", "sensor", "remote", "button", "number", "select", "event"]
        let ranked = entities.map { entity -> (entity: HomeEntity, score: Int) in
            let domain = entity.domain
            let mainSwitch = domain == "switch" && (entity.id.contains("_on_p_") || entity.id.hasSuffix("_switch_status") || entity.id.hasSuffix("_on"))
            let score = (registrations[entity.id]?.entity_category == nil ? 0 : 100) + (order.firstIndex(of: domain) ?? 99) * 2 - (mainSwitch ? 1 : 0)
            return (entity, score)
        }
        let primary = ranked.min { $0.score == $1.score ? $0.entity.id < $1.entity.id : $0.score < $1.score }?.entity
        self.primary = primary
        category = Self.category(primary: primary, model: model, entities: entities)
        online = entities.contains { $0.stateKnown && !["button", "event", "notify"].contains($0.domain) }
        secondaryControls = entities.filter { $0.id != primary?.id && !["sensor", "binary_sensor", "event"].contains($0.domain) }
        readings = entities.filter { ["sensor", "binary_sensor", "event"].contains($0.domain) && $0.id != primary?.id }
        powerControl = DevicePowerControl.make(primary: primary, entities: entities)
    }
    private static func category(primary: HomeEntity?, model: String, entities: [HomeEntity]) -> DeviceCategory {
        if let climate = primary?.climate { return climate.category }
        let type = model.lowercased()
        if type.contains("aircondition") { return .airConditioner }
        if type.contains("camera") || entities.contains(where: { $0.domain == "camera" }) { return .camera }
        if type.contains("wifispeaker") || type.contains(".tv.") { return .media }
        switch primary?.domain {
        case "light": return .lighting
        case "fan", "humidifier": return .air
        case "media_player", "remote": return .media
        case "cover": return .curtains
        case "water_heater": return .waterHeater
        case "switch": return .switches
        case "sensor", "binary_sensor", "event": return .sensors
        case "vacuum": return .cleaning
        case "lock": return .security
        default: return .other
        }
    }
    var active: Bool {
        if let main = primary, ["climate", "light", "fan", "humidifier", "water_heater", "media_player", "cover", "vacuum", "switch"].contains(main.domain) { return main.powered }
        return online
    }
    var statusText: String {
        guard let primary else { return "暂无状态" }
        if !online { return entities.contains { $0.state == "unknown" } ? "状态未提供" : "离线" }
        if !primary.available { return "部分功能可用" }
        return primary.displayState
    }
    var reading: String? {
        guard let primary, primary.stateKnown else { return nil }
        if primary.domain == "climate", primary.powered, let value = primary.number("temperature") { return "\(formatTemperature(value))°" }
        if primary.domain == "light", primary.powered, let brightness = primary.number("brightness") { return "\(Int((brightness / 255 * 100).rounded()))%" }
        if primary.domain == "fan", primary.powered, let percentage = primary.number("percentage") { return "\(Int(percentage))%" }
        if primary.domain == "humidifier", let humidity = primary.number("current_humidity") { return "\(Int(humidity))%" }
        if primary.domain == "sensor", Double(primary.state) != nil { return primary.displayState }
        return nil
    }
    func label(for entity: HomeEntity) -> String {
        let entry = registrations[entity.id]
        let value = entry?.name ?? entry?.original_name ?? entity.name
        let shorter = value.hasPrefix(name) ? String(value.dropFirst(name.count)) : value
        let words = shorter.split(whereSeparator: \.isWhitespace).map(String.init)
        let result = words.reduce(into: [String]()) { list, word in if list.last != word { list.append(word) } }.joined(separator: " ")
        if entity.domain == "event", result.lowercased().contains("ble专用") { return "蓝牙自定义事件" }
        return result.isEmpty ? domainName(entity.domain) : result
    }
}

enum HomeCatalog {
    static func excludes(_ registration: HAEntityRegistration?) -> Bool {
        registration?.platform?.lowercased().hasPrefix("xiaomi_miot") == true
    }

    static func devices(states: [HomeEntity], registry: HomeRegistry) -> [HomeDevice] {
        let entries = Dictionary(registry.entities.map { ($0.entity_id, $0) }, uniquingKeysWith: { a, _ in a })
        let devices = Dictionary(registry.devices.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let areas = Dictionary(registry.areas.map { ($0.area_id, $0.name) }, uniquingKeysWith: { a, _ in a })
        // Filter by integration before grouping so MIoT entities cannot reappear as
        // climate devices or secondary controls on a device shared by integrations.
        let grouped = Dictionary(grouping: states.filter {
            entries[$0.id]?.disabled_by == nil && !excludes(entries[$0.id])
        }, by: { entries[$0.id]?.device_id ?? $0.id })
        var result: [HomeDevice] = []
        for (key, entities) in grouped {
            let device = devices[key]
            guard device?.disabled_by == nil else { continue }
            let xiaomi = entities.contains { entity in
                let platform = entries[entity.id]?.platform ?? ""
                return platform.contains("xiaomi") || platform.contains("miot") || platform == "yeelight"
            }
            guard xiaomi || entities.contains(where: { $0.domain == "climate" }) else { continue }
            guard device != nil || entities.contains(where: { $0.domain == "climate" }) else { continue }
            // Entity IDs, device IDs and registry relationships are the grouping authority.
            // Matching names/models alone must never combine two different physical devices.
            let name = device?.name_by_user ?? device?.name ?? entities.first?.name ?? key
            result.append(HomeDevice(id: key, registryIDs: device == nil ? [] : [key], name: name,
                                     model: device?.model ?? "", room: device?.area_id.flatMap { areas[$0] } ?? "",
                                     isXiaomi: xiaomi, entities: entities.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }, registrations: entries))
        }
        return result.sorted {
            let comparison = $0.name.localizedStandardCompare($1.name)
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
    }
}

struct NumericControlSpec: Identifiable {
    let title: String
    let value: Double?
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let service: String
    let key: String
    var multiplier: Double = 1
    var id: String { key }
    func normalized(_ value: Double) -> Double {
        min(range.upperBound, max(range.lowerBound, range.lowerBound + ((value - range.lowerBound) / step).rounded() * step))
    }
    func payload(_ value: Double) -> [String: Any] { [key: normalized(value) * multiplier] }
}

extension HomeEntity {
    func numericControls(temperatureUnit: String = "°C") -> [NumericControlSpec] {
        func spec(_ title: String, value: Double?, min: Double?, max: Double?, step: Double = 1,
                  unit: String, service: String, key: String, multiplier: Double = 1) -> NumericControlSpec? {
            guard let min, let max, min.isFinite, max.isFinite, min < max, step.isFinite, step > 0 else { return nil }
            return NumericControlSpec(title: title, value: value.flatMap { $0.isFinite ? $0 : nil }, range: min...max,
                                      step: step, unit: unit, service: service, key: key, multiplier: multiplier)
        }
        switch domain {
        case "number": return [spec("数值", value: Double(state), min: number("min"), max: number("max"), step: number("step") ?? 1,
                                    unit: text("unit_of_measurement") ?? "", service: "set_value", key: "value")].compactMap { $0 }
        case "light":
            var controls: [NumericControlSpec?] = []
            if list("supported_color_modes").contains(where: { !["onoff", "unknown"].contains($0) }) {
                controls.append(spec("亮度", value: number("brightness").map { $0 / 255 * 100 }, min: 1, max: 100, unit: "%", service: "turn_on", key: "brightness_pct"))
            }
            if list("supported_color_modes").contains("color_temp") {
                controls.append(spec("色温", value: number("color_temp_kelvin"), min: number("min_color_temp_kelvin"), max: number("max_color_temp_kelvin"), step: 50,
                                     unit: "K", service: "turn_on", key: "color_temp_kelvin"))
            }
            return controls.compactMap { $0 }
        case "fan": return supports(1) ? [spec("风速", value: number("percentage"), min: 0, max: 100, step: number("percentage_step") ?? 1,
                                               unit: "%", service: "set_percentage", key: "percentage")].compactMap { $0 } : []
        case "humidifier": return [spec("目标湿度", value: number("humidity"), min: number("min_humidity"), max: number("max_humidity"),
                                        unit: "%", service: "set_humidity", key: "humidity")].compactMap { $0 }
        case "water_heater": return supports(1) ? [spec("目标水温", value: number("temperature"), min: number("min_temp"), max: number("max_temp"), step: number("target_temp_step") ?? 1,
                                                       unit: text("temperature_unit") ?? temperatureUnit, service: "set_temperature", key: "temperature")].compactMap { $0 } : []
        case "media_player": return supports(4) ? [spec("音量", value: number("volume_level").map { $0 * 100 }, min: 0, max: 100,
                                                        unit: "%", service: "volume_set", key: "volume_level", multiplier: 0.01)].compactMap { $0 } : []
        case "cover": return supports(4) ? [spec("打开程度", value: number("current_position"), min: 0, max: 100,
                                                unit: "%", service: "set_cover_position", key: "position")].compactMap { $0 } : []
        default: return []
        }
    }
}

extension HomeEntity {
    var displayState: String {
        if domain == "text", text("mode") == "password" { return "受保护设置" }
        if state == "unavailable" { return "离线" }
        if state == "unknown" { return ["button", "notify", "event"].contains(domain) ? "暂无记录" : "状态未提供" }
        if let climate { return climate.statusText }
        if domain == "binary_sensor" {
            let active = state == "on"
            switch text("device_class") {
            case "moisture": return active ? "检测到水浸" : "未检测到水浸"
            case "door", "window", "opening": return active ? "已打开" : "已关闭"
            case "motion", "occupancy", "presence": return active ? "检测到活动" : "未检测到活动"
            case "battery": return active ? "电量低" : "电量正常"
            case "problem", "smoke", "gas", "safety": return active ? "检测到异常" : "正常"
            case "connectivity": return active ? "已连接" : "断开连接"
            default: return active ? "是" : "否"
            }
        }
        if domain == "event" {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: state) ?? ISO8601DateFormatter().date(from: state) {
                return date.formatted(date: .abbreviated, time: .shortened)
            }
        }
        if let value = Double(state) { return "\(formatTemperature(value))\(text("unit_of_measurement") ?? "")" }
        return ["on": "已开启", "off": "已关闭", "idle": "待机", "playing": "播放中", "paused": "已暂停",
                "buffering": "缓冲中", "standby": "待机", "open": "已打开", "closed": "已关闭",
                "opening": "正在打开", "closing": "正在关闭", "locked": "已上锁", "unlocked": "已解锁",
                "docked": "已回充", "cleaning": "清扫中", "returning": "回充中", "error": "异常"] [state] ?? state
    }
    var powerServices: (on: String, off: String)? {
        switch domain {
        case "switch", "light", "humidifier", "input_boolean": return ("turn_on", "turn_off")
        case "fan": return supports(16) && supports(32) ? ("turn_on", "turn_off") : nil
        case "media_player": return supports(128) && supports(256) ? ("turn_on", "turn_off") : nil
        case "water_heater": return supports(8) ? ("turn_on", "turn_off") : nil
        default: return nil
        }
    }
    var needsActionConfirmation: Bool {
        let value = (name + " " + id).lowercased()
        return ["格式化", "重置", "出厂", "删除", "清空", "重启", "format", "reset", "factory", "delete", "reboot", "restart"].contains(where: value.contains)
    }
}

func domainName(_ value: String) -> String {
    ["climate": "温控", "fan": "风扇", "light": "灯光", "humidifier": "湿度控制", "switch": "开关", "sensor": "传感器",
     "binary_sensor": "状态", "media_player": "影音", "camera": "摄像机", "water_heater": "热水器", "cover": "窗帘",
     "vacuum": "清洁", "number": "数值设置", "select": "选项", "text": "文本设置", "button": "操作", "event": "事件", "notify": "消息"] [value] ?? value
}
struct HAAreaRegistration: Decodable { let area_id: String; let name: String }
struct HomeRegistry {
    var entities: [HAEntityRegistration] = []
    var devices: [HADeviceRegistration] = []
    var areas: [HAAreaRegistration] = []
}
