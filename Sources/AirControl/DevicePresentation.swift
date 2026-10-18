import Foundation

enum DeviceCategory: String, CaseIterable, Identifiable {
    case airConditioner = "空调", refrigerator = "冰箱", waterHeater = "热水", bathroom = "浴室", other = "其他"
    case lighting = "灯光", air = "空气", switches = "开关", curtains = "窗帘", media = "影音", camera = "摄像机", sensors = "传感器", cleaning = "清洁", security = "安防"
    static let allCases: [DeviceCategory] = [.airConditioner, .lighting, .air, .media, .camera, .sensors, .refrigerator, .waterHeater, .bathroom, .switches, .curtains, .cleaning, .security, .other]
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .airConditioner: return "air.conditioner.horizontal"
        case .refrigerator: return "refrigerator"
        case .waterHeater: return "water.waves"
        case .bathroom: return "shower"
        case .other: return "thermometer.medium"
        case .lighting: return "lightbulb"
        case .air: return "fan"
        case .switches: return "powerplug"
        case .curtains: return "curtains.vertical"
        case .media: return "hifispeaker"
        case .camera: return "web.camera"
        case .sensors: return "sensor"
        case .cleaning: return "circle.dotted.circle"
        case .security: return "lock.shield"
        }
    }
    var currentTemperatureLabel: String {
        switch self {
        case .airConditioner, .bathroom: return "室内"
        case .refrigerator: return "当前"
        case .waterHeater: return "水温"
        default: return "当前"
        }
    }
}

extension ClimateEntity {
    // Presentation-only categorization. Capabilities always come from the entity, never its name.
    var category: DeviceCategory {
        let source = (name + " " + id).lowercased()
        if ["冰箱", "冷藏", "冷冻", "变温", "fridge", "refrigerator"].contains(where: source.contains) { return .refrigerator }
        if ["热水", "water_heater"].contains(where: source.contains) { return .waterHeater }
        if ["浴霸", "bath", "浴室"].contains(where: source.contains) { return .bathroom }
        if ["空调", "aircondition", "air_condition", "gree", "温控器"].contains(where: source.contains) { return .airConditioner }
        return .other
    }
    var supportsPowerOff: Bool { (attributes.hvac_modes ?? []).contains("off") || (attributes.supported_features ?? 0) & 256 != 0 }
    var supportsPowerOn: Bool { (attributes.hvac_modes ?? []).contains(where: { $0 != "off" }) || (attributes.supported_features ?? 0) & 128 != 0 }
    var powerActionAvailable: Bool { powered ? supportsPowerOff : supportsPowerOn }
    var statusText: String {
        if !available { return "离线" }
        if state == "off" { return "已关闭" }
        if category == .refrigerator { return "运行中" }
        return modeName(state)
    }
    var temperatureBounds: ClosedRange<Double>? {
        guard let minimum = attributes.min_temp, let maximum = attributes.max_temp,
              minimum.isFinite, maximum.isFinite, minimum < maximum else { return nil }
        return minimum...maximum
    }
    func temperatureAfterStep(_ direction: Double) -> Double? {
        guard let current = attributes.temperature, current.isFinite,
              let bounds = temperatureBounds else { return nil }
        let reportedStep = attributes.target_temp_step ?? 1
        let step = reportedStep.isFinite && reportedStep > 0 ? reportedStep : 1
        let value = min(bounds.upperBound, max(bounds.lowerBound, ((current + direction * step) * 100).rounded() / 100))
        return value == current ? nil : value
    }
}

func formatTemperature(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...1)))
}


func modeName(_ raw: String) -> String {
    ["off": "已关闭", "cool": "制冷", "heat": "制热", "auto": "自动", "heat_cool": "冷暖自动",
     "dry": "除湿", "fan_only": "送风", "unavailable": "设备离线", "unknown": "状态未知"][raw] ?? raw
}
func modeSymbol(_ raw: String) -> String {
    ["cool": "snowflake", "heat": "sun.max", "auto": "arrow.triangle.2.circlepath",
     "heat_cool": "thermometer.medium", "dry": "drop", "fan_only": "fan"][raw] ?? "air.conditioner.horizontal"
}
func optionName(_ raw: String) -> String {
    ["auto": "自动", "Auto": "自动", "low": "低风", "medium": "中风", "high": "高风",
     "silent": "静音", "Silence": "静音", "turbo": "强劲", "Turbo": "强劲",
     "off": "关闭", "on": "开启", "vertical": "上下", "horizontal": "左右",
     "both": "上下左右", "none": "无", "eco": "节能", "sleep": "睡眠",
     "medium_low": "中低风", "medium_high": "中高风", "max": "最大风", "min": "最小风",
     "comfort": "舒适", "boost": "强劲", "away": "离家", "normal": "标准"][raw] ?? raw
}
