import AppKit
import Combine
import Foundation

@MainActor
final class AirConditionerStore: ObservableObject {
    static let shared = AirConditionerStore()
    @Published var address: String
    @Published var tokenInput = ""
    @Published var showingSettings = false
    @Published var entities: [ClimateEntity] = []
    @Published var homeEntities: [HomeEntity] = []
    @Published var homeDevices: [HomeDevice] = []
    @Published var inventoryNotice: String?
    @Published var availableServices: Set<String> = []
    var homeRegistry = HomeRegistry()
    private var registryUpdated: Date?
    @Published var selectedID: String {
        didSet { UserDefaults.standard.set(selectedID, forKey: "selectedEntity") }
    }
    @Published var isRefreshing = false
    @Published var isSending = false
    @Published var pendingEntityID: String?
    @Published var commandErrorEntityID: String?
    @Published var isConnecting = false
    @Published var connectionError: String?
    @Published var commandError: String?
    @Published var settingsError: String?
    @Published var lastUpdated: Date?
    @Published var temperatureUnit = "°C"
    @Published var configured = false
    @Published var aliases: [String: String]

    private var client: HAClient?
    private var timer: AnyCancellable?
    private var wakeObserver: NSObjectProtocol?
    private var generation = UUID()

    init() {
        address = UserDefaults.standard.string(forKey: "serverAddress") ?? "http://homeassistant.local:8123"
        selectedID = UserDefaults.standard.string(forKey: "selectedEntity") ?? ""
        aliases = UserDefaults.standard.dictionary(forKey: "deviceAliases") as? [String: String] ?? [:]
        do {
            let token = try TokenStore.read()
            if !token.isEmpty {
                client = try HAClient(address: address, token: token)
                configured = true
            } else { showingSettings = true }
        } catch {
            settingsError = error.localizedDescription
            showingSettings = true
        }
        timer = Timer.publish(every: 20, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in await self?.refresh() } }
        Task { await refresh() }
    }

    var selected: ClimateEntity? { entities.first { $0.id == selectedID } }
    var selectedDevice: HomeDevice? { homeDevices.first { $0.id == selectedID || $0.entities.contains { $0.id == selectedID } } }
    var controlsEnabled: Bool { selected.map(canControl) ?? false }
    func canControl(_ entity: ClimateEntity) -> Bool {
        entities.contains { $0.id == entity.id } && entity.available && connectionError == nil && !isSending && !isConnecting && !isRefreshing
    }
    func canControl(_ entity: HomeEntity) -> Bool {
        homeDevices.contains { $0.entities.contains { $0.id == entity.id } } && entity.available && connectionError == nil && !isSending && !isConnecting && !isRefreshing
    }
    func supportsService(_ entity: HomeEntity, _ service: String) -> Bool {
        availableServices.contains("\(entity.domain).\(service)")
    }
    func canPerformPower(_ command: DevicePowerCommand) -> Bool {
        guard let entity = homeEntities.first(where: { $0.id == command.entityID }) else { return false }
        return canControl(entity) && supportsService(entity, command.service)
    }
    func performPower(_ command: DevicePowerCommand) async {
        await perform(command.service, entityID: command.entityID, values: command.values.mapValues { $0 as Any })
    }
    var menuTitle: String {
        guard configured else { return "" }
        guard connectionError == nil else { return "离线" }
        if let device = selectedDevice {
            if !device.online { return "离线" }
            if let climate = selected, climate.powered, let target = climate.attributes.temperature { return "\(formatTemperature(target))°" }
            if let reading = device.reading, reading.count <= 8 { return reading }
            if device.primary?.state == "off" { return "关" }
            return ""
        }
        return ""
    }
    func name(for entity: ClimateEntity) -> String {
        let alias = aliases[entity.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return alias.isEmpty ? entity.name : alias
    }
    func name(for device: HomeDevice) -> String {
        let alias = aliases[device.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !alias.isEmpty { return alias }
        if let main = device.primary, let legacy = aliases[main.id], !legacy.isEmpty { return legacy }
        return device.name
    }
    func rename(_ entityID: String, to name: String) {
        aliases[entityID] = name
        UserDefaults.standard.set(aliases, forKey: "deviceAliases")
    }

    func connect() async {
        guard !isConnecting && !isSending else { return }
        isConnecting = true
        settingsError = nil
        defer { isConnecting = false }
        do {
            let trimmed = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
            let token = trimmed.isEmpty ? try TokenStore.read() : trimmed
            guard !token.isEmpty else { settingsError = "请先填写 Home Assistant 的长期访问令牌。"; return }
            let candidate = try HAClient(address: address, token: token)
            async let discovered = candidate.states()
            async let unit = candidate.temperatureUnit()
            let (states, temperatureUnit) = try await (discovered, unit)
            try TokenStore.save(token)
            generation = UUID()
            client = candidate
            homeRegistry = HomeRegistry()
            registryUpdated = nil
            availableServices = []
            self.temperatureUnit = temperatureUnit
            applyStates(states)
            UserDefaults.standard.set(candidate.baseURL.absoluteString, forKey: "serverAddress")
            address = candidate.baseURL.absoluteString
            tokenInput = ""
            configured = true
            connectionError = nil
            await readMetadata(candidate, generation: generation)
            commandError = nil
            showingSettings = false
        } catch { settingsError = readableError(error) }
    }

    func refresh(forceMetadata: Bool = false) async {
        guard let client, !isRefreshing, !isConnecting, !isSending else { return }
        let currentGeneration = generation
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let states = try await client.states()
            if lastUpdated == nil {
                let unit = try await client.temperatureUnit()
                guard generation == currentGeneration else { return }
                temperatureUnit = unit
            }
            guard generation == currentGeneration else { return }
            applyStates(states)
            connectionError = nil
            if forceMetadata || inventoryNotice != nil || registryUpdated == nil || Date().timeIntervalSince(registryUpdated!) > 300 {
                await readMetadata(client, generation: currentGeneration)
            }
        } catch {
            if generation == currentGeneration { connectionError = readableError(error) }
        }
    }

    private func applyStates(_ states: [HomeEntity]) {
        homeEntities = states
        rebuildDevices()
        lastUpdated = Date()
    }
    private func rebuildDevices() {
        // Wait for source metadata at launch; an unclassified climate entity may
        // belong to the excluded MIoT integration. Retain the last registry on retry.
        homeDevices = registryUpdated == nil ? [] : HomeCatalog.devices(states: homeEntities, registry: homeRegistry)
        entities = homeDevices.flatMap(\.entities).compactMap(\.climate)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        normalizeSelection()
    }
    private func readMetadata(_ client: HAClient, generation expected: UUID) async {
        var notices: [String] = []
        do {
            let registry = try await client.registry()
            guard generation == expected else { return }
            homeRegistry = registry
            registryUpdated = Date()
        } catch {
            notices.append(registryUpdated == nil ? "暂时无法读取设备来源，读取成功后将显示设备，请刷新重试。" : "暂时无法更新设备来源，正在使用上次的设备分组，请刷新重试。")
        }
        do {
            let services = try await client.services()
            guard generation == expected else { return }
            availableServices = services
        } catch { notices.append("控制服务列表暂不可用。") }
        guard generation == expected else { return }
        rebuildDevices()
        inventoryNotice = notices.isEmpty ? nil : notices.joined(separator: " ")
        writeInventoryReport()
    }
    private func normalizeSelection() {
        if selectedDevice == nil { selectedID = homeDevices.first?.id ?? "" }
    }

    func send(_ service: String, entityID: String? = nil, values: [String: Any] = [:]) async {
        guard let id = entityID ?? selected?.id ?? selectedDevice?.primary?.id else { return }
        await perform(service, entityID: id, values: values)
    }
    func perform(_ service: String, entityID: String, values: [String: Any] = [:]) async {
        guard let entity = homeEntities.first(where: { $0.id == entityID }), canControl(entity), let client else { return }
        guard supportsService(entity, service) else {
            commandErrorEntityID = entity.id
            commandError = "Home Assistant 尚未提供此控制，请刷新后重试。"
            return
        }
        isSending = true
        pendingEntityID = entity.id
        commandError = nil
        commandErrorEntityID = nil
        let expected = generation
        defer { isSending = false; pendingEntityID = nil }
        do {
            try await client.call(service, entityID: entity.id, values: values, domain: entity.domain)
            let states = try await client.states()
            guard generation == expected else { return }
            applyStates(states)
            connectionError = nil
        } catch {
            if generation == expected { commandError = readableError(error); commandErrorEntityID = entity.id }
        }
    }
    func togglePower(entityID: String? = nil) async {
        guard let entity = entities.first(where: { $0.id == (entityID ?? selectedID) }), entity.powerActionAvailable else { return }
        if entity.powered {
            if (entity.attributes.hvac_modes ?? []).contains("off") {
                await send("set_hvac_mode", entityID: entity.id, values: ["hvac_mode": "off"])
            } else { await send("turn_off", entityID: entity.id) }
        } else { await send("turn_on", entityID: entity.id) }
    }
    func adjustTemperature(by direction: Double, entityID: String? = nil) async {
        guard let entity = entities.first(where: { $0.id == (entityID ?? selectedID) }), supportsTargetTemperature(entity),
              let next = entity.temperatureAfterStep(direction) else { return }
        await send("set_temperature", entityID: entity.id, values: ["temperature": next])
    }
    func supportsTargetTemperature(_ entity: ClimateEntity) -> Bool { (entity.attributes.supported_features ?? 0) & 1 != 0 }
    func cameraImage(_ entity: HomeEntity) async throws -> Data {
        guard let client, entity.available, connectionError == nil else { throw HAError.badResponse }
        return try await client.cameraImage(entityID: entity.id)
    }
    func openDevice(_ device: HomeDevice) {
        guard let root = client?.baseURL else { return }
        NSWorkspace.shared.open(device.registryIDs.first.map { root.appendingPathComponent("config/devices/device/\($0)") } ?? root)
    }

    // Optional local development report, restricted to device metadata and capability fields.
    // It never writes tokens, entity pictures, access URLs, or raw attribute payloads.
    private func writeInventoryReport() {
        guard let index = CommandLine.arguments.firstIndex(of: "--inventory-report"), CommandLine.arguments.count > index + 1 else { return }
        let rows: [[String: Any]] = homeDevices.map { device in
            ["id": device.id, "name": device.name, "category": device.category.rawValue, "xiaomi": device.isXiaomi,
             "entities": device.entities.map { ["id": $0.id, "name": device.label(for: $0), "domain": $0.domain, "state": ["text", "notify"].contains($0.domain) ? "已隐藏" : $0.state,
                                                  "attributeKeys": $0.attributes.keys.sorted().joined(separator: ",")] }]
        }
        if let data = try? JSONSerialization.data(withJSONObject: ["devices": rows, "notice": inventoryNotice ?? ""], options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]), options: .atomic)
        }
    }

    func openProfile() {
        guard let url = try? HAClient(address: address, token: "").baseURL else { return }
        NSWorkspace.shared.open(url.appendingPathComponent("profile"))
    }
}

func readableError(_ error: Error) -> String {
    if let error = error as? URLError {
        switch error.code {
        case .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .timedOut, .networkConnectionLost:
            return "连接不到 Home Assistant。请确认 Mac 已连上家中网络，且服务器正在运行。"
        case .serverCertificateUntrusted, .serverCertificateHasBadDate, .secureConnectionFailed:
            return "服务器的 HTTPS 证书无法验证，请检查证书或使用可信的服务器地址。"
        default: break
        }
    }
    if error is DecodingError { return "设备返回了无法识别的数据，请检查 Home Assistant 中的设备实体。" }
    return error.localizedDescription
}

