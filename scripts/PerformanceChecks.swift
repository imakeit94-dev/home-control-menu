import Foundation

// Offline profile fixture reconstructed from the existing redacted inventory.
// This exercises the view's model reads without network access or device writes.
@main
struct PerformanceChecks {
    struct Inventory: Decodable {
        struct Entity: Decodable {
            let id: String, name: String, state: String, platform: String, device_id: String, category: String
            let attributes: [String: String]
        }
        let entities: [Entity]
        let devices: [HADeviceRegistration]
    }
    static func milliseconds(_ operation: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        operation()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }
    @inline(never) static func renderReads(_ devices: [HomeDevice]) -> Int {
        let categories = DeviceCategory.allCases.filter { value in devices.contains { $0.category == value } }
        var checksum = categories.count
        for device in devices {
            // Same properties requested by card drawing, hover help and accessibility.
            for _ in 0..<3 {
                checksum += device.category.rawValue.count + (device.primary?.id.count ?? 0)
                checksum += device.source.count + device.statusText.count + (device.reading?.count ?? 0)
                checksum += device.online ? 1 : 0
                checksum += device.active ? 1 : 0
                checksum += device.secondaryControls.count + device.readings.count
            }
        }
        return checksum
    }
    static func main() throws {
        let inventory = try JSONDecoder().decode(Inventory.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let states = inventory.entities.map { row -> HomeEntity in
            var attributes: [String: JSONValue] = ["friendly_name": .string(row.name)]
            for (key, value) in row.attributes {
                attributes[key] = (try? JSONDecoder().decode(JSONValue.self, from: Data(value.utf8))) ?? .string(value)
            }
            return HomeEntity(entity_id: row.id, state: row.state, attributes: attributes)
        }
        let entries = inventory.entities.map { row in
            HAEntityRegistration(entity_id: row.id, device_id: row.device_id.isEmpty ? nil : row.device_id,
                platform: row.platform, entity_category: row.category.isEmpty ? nil : row.category,
                disabled_by: nil, hidden_by: nil, original_name: row.name, name: nil)
        }
        let registry = HomeRegistry(entities: entries, devices: inventory.devices)
        let devices = HomeCatalog.devices(states: states, registry: registry)
        precondition(devices.count == 18)
        precondition(!devices.flatMap(\.entities).contains { entity in entries.first { $0.entity_id == entity.id }?.platform == "xiaomi_miot" })
        // Reference implementation retains the former ordering and full JSON conversion.
        for device in devices {
            let expected = device.entities.sorted { a, b in
                func score(_ e: HomeEntity) -> Int {
                    let order = ["climate", "humidifier", "fan", "camera", "media_player", "water_heater", "light", "cover", "vacuum", "lock", "switch", "binary_sensor", "sensor", "remote", "button", "number", "select", "event"]
                    let mainSwitch = e.domain == "switch" && (e.id.contains("_on_p_") || e.id.hasSuffix("_switch_status") || e.id.hasSuffix("_on"))
                    return (device.registrations[e.id]?.entity_category == nil ? 0 : 100) + (order.firstIndex(of: e.domain) ?? 99) * 2 - (mainSwitch ? 1 : 0)
                }
                return score(a) == score(b) ? a.id < b.id : score(a) < score(b)
            }.first
            precondition(device.primary?.id == expected?.id)
            for entity in device.entities where entity.domain == "climate" {
                let reference = try JSONDecoder().decode(ClimateEntity.self, from: JSONEncoder().encode(entity))
                precondition(entity.climate?.id == reference.id && entity.climate?.attributes.preset_modes == reference.attributes.preset_modes)
                precondition(entity.climate?.attributes.supported_features == reference.attributes.supported_features)
                precondition(entity.climate?.attributes.friendly_name == reference.attributes.friendly_name)
                precondition(entity.climate?.attributes.current_temperature == reference.attributes.current_temperature)
                precondition(entity.climate?.attributes.temperature == reference.attributes.temperature)
                precondition(entity.climate?.attributes.min_temp == reference.attributes.min_temp && entity.climate?.attributes.max_temp == reference.attributes.max_temp)
                precondition(entity.climate?.attributes.target_temp_step == reference.attributes.target_temp_step)
                precondition(entity.climate?.attributes.hvac_modes == reference.attributes.hvac_modes && entity.climate?.attributes.hvac_action == reference.attributes.hvac_action)
                precondition(entity.climate?.attributes.fan_mode == reference.attributes.fan_mode && entity.climate?.attributes.fan_modes == reference.attributes.fan_modes)
                precondition(entity.climate?.attributes.swing_mode == reference.attributes.swing_mode && entity.climate?.attributes.swing_modes == reference.attributes.swing_modes)
                precondition(entity.climate?.attributes.preset_mode == reference.attributes.preset_mode)
            }
        }
        var total = 0
        _ = renderReads(devices)
        let passes = Int(CommandLine.arguments.dropFirst(2).first ?? "") ?? 5
        let time = milliseconds { for _ in 0..<passes { total += renderReads(devices) } }
        var buildCount = 0
        let buildTime = milliseconds { for _ in 0..<20 { buildCount += HomeCatalog.devices(states: states, registry: registry).count } }
        print("devices=\(devices.count), entities=\(devices.flatMap(\.entities).count), passes=\(passes), checksum=\(total), catalogChecksum=\(buildCount)")
        print(String(format: "model reads per pass: %.3f ms; catalog per rebuild: %.3f ms", time / Double(passes), buildTime / 20))
    }
}
