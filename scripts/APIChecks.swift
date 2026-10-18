import Foundation

@main
struct APIChecks {
    static func main() async throws {
        let root = CommandLine.arguments[1]
        let client = try HAClient(address: root, token: "fixture-token")
        let devices = try await client.climates()
        precondition(devices.count == 2, "Non-climate entities must be ignored before decoding")
        let bedroom = devices.first { $0.id == "climate.bedroom" }!
        precondition(bedroom.available && bedroom.powered)
        precondition(bedroom.attributes.target_temp_step == 0.5)
        precondition(bedroom.attributes.current_temperature == nil)
        var cold = bedroom.attributes
        cold.friendly_name = "冰箱 冷冻区"
        cold.min_temp = -24
        cold.max_temp = -16
        cold.temperature = -18
        cold.target_temp_step = 1
        cold.hvac_modes = ["cool"]
        let freezer = ClimateEntity(entity_id: "climate.freezer", state: "cool", attributes: cold)
        precondition(freezer.category == .refrigerator)
        precondition(freezer.category.currentTemperatureLabel == "当前")
        precondition(freezer.temperatureAfterStep(-1) == -19)
        precondition(freezer.temperatureAfterStep(100) == -16)
        precondition(!freezer.supportsPowerOff, "Do not offer an unsupported power-off command")
        cold.temperature = -24
        let minimum = ClimateEntity(entity_id: "climate.freezer", state: "cool", attributes: cold)
        precondition(minimum.temperatureAfterStep(-1) == nil)
        cold.min_temp = nil
        let unspecifiedBounds = ClimateEntity(entity_id: "climate.freezer", state: "cool", attributes: cold)
        precondition(unspecifiedBounds.temperatureAfterStep(1) == nil, "Do not invent AC bounds for other devices")
        let offline = devices.first { $0.id == "climate.living" }!
        precondition(!offline.available && !offline.powered)
        let unit = try await client.temperatureUnit()
        precondition(unit == "°F", "Use the server's temperature unit")
        let states = try await client.states()
        precondition(states.count == 8, "Decode heterogeneous domains without climate-only assumptions")
        let registryEntities = try JSONDecoder().decode([HAEntityRegistration].self, from: Data("""
        [
          {"entity_id":"fan.fixture","device_id":"xiaomi-one","platform":"xiaomi_home"},
          {"entity_id":"light.indicator","device_id":"xiaomi-one","platform":"xiaomi_home","entity_category":"config"},
          {"entity_id":"number.delay","device_id":"xiaomi-one","platform":"xiaomi_home"},
          {"entity_id":"select.mode","device_id":"xiaomi-one","platform":"xiaomi_home"},
          {"entity_id":"button.reset","device_id":"xiaomi-one","platform":"xiaomi_home"},
          {"entity_id":"sensor.unrelated","device_id":"server","platform":"systemmonitor"}
        ]
        """.utf8))
        let registryDevices = try JSONDecoder().decode([HADeviceRegistration].self, from: Data("""
        [{"id":"xiaomi-one","name":"测试风扇","manufacturer":"Xiaomi","area_id":"living"},
         {"id":"server","name":"Home Assistant"}]
        """.utf8))
        let catalog = HomeCatalog.devices(states: states, registry: HomeRegistry(entities: registryEntities, devices: registryDevices,
            areas: [HAAreaRegistration(area_id: "living", name: "起居室")]))
        precondition(catalog.count == 3, "Group one device's functions, keep both original climates, and exclude HA system devices")
        let fanDevice = catalog.first { $0.id == "xiaomi-one" }!
        precondition(fanDevice.entities.count == 5 && fanDevice.category == .air && fanDevice.room == "起居室")
        precondition(fanDevice.primary?.domain == "fan", "An indicator light must not replace the fan as its primary control")
        let fan = fanDevice.primary!
        precondition(fan.powerServices != nil && fan.numericControls().first?.normalized(33) == 30)
        let number = states.first { $0.id == "number.delay" }!
        precondition(number.numericControls().first!.normalized(-99) == -24)
        let reset = states.first { $0.id == "button.reset" }!
        precondition(reset.available && reset.needsActionConfirmation, "A stateless button is usable even before first press; reset requires user confirmation")
        let services = try await client.services()
        precondition(services.contains("fan.set_percentage") && services.contains("light.turn_on"))
        try await client.call("set_temperature", entityID: bedroom.id, values: ["temperature": 24.5])
        try await client.call("set_hvac_mode", entityID: bedroom.id, values: ["hvac_mode": "off"])
        try await client.call("set_fan_mode", entityID: bedroom.id, values: ["fan_mode": "auto"])
        try await client.call("set_percentage", entityID: "fan.fixture", values: ["percentage": 30], domain: "fan")
        try await client.call("turn_on", entityID: "light.indicator", values: ["brightness_pct": 70], domain: "light")
        try await client.call("set_value", entityID: "number.delay", values: ["value": -18], domain: "number")
        try await client.call("select_option", entityID: "select.mode", values: ["option": "自然风"], domain: "select")
        for invalid in ["ftp://localhost", "localhost:8123", "http://user:password@localhost", "http://localhost/?token=secret"] {
            do {
                _ = try HAClient(address: invalid, token: "fixture-token")
                fatalError("Accepted an invalid URL")
            } catch HAError.invalidURL { }
        }
        for (path, expected) in [("unauthorized", 401), ("broken", 503), ("redirect", 302)] {
            let bad = try HAClient(address: root + "/" + path, token: "fixture-token")
            do {
                _ = try await bad.climates()
                fatalError("Accepted an HTTP error")
            } catch HAError.unauthorized { precondition(expected == 401) }
            catch HAError.status(let code) { precondition(code == expected) }
            catch HAError.unsafeRedirect { precondition(expected == 302) }
        }
        print("API checks passed: discovery, nullable attributes, units, commands, URL validation, authentication, server errors, redirect protection.")
    }
}
