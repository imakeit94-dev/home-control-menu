import Foundation
import Security

struct ClimateEntity: Decodable, Identifiable {
    let entity_id: String
    let state: String
    let attributes: Attributes
    var id: String { entity_id }
    var name: String { attributes.friendly_name ?? entity_id }
    var available: Bool { state != "unavailable" && state != "unknown" }
    var powered: Bool { available && state != "off" }

    struct Attributes: Decodable {
        var friendly_name: String?
        var current_temperature: Double?
        var temperature: Double?
        var min_temp: Double?
        var max_temp: Double?
        var target_temp_step: Double?
        var hvac_modes: [String]?
        var hvac_action: String?
        var fan_mode: String?
        var fan_modes: [String]?
        var swing_mode: String?
        var swing_modes: [String]?
        var preset_mode: String?
        var preset_modes: [String]?
        var supported_features: Int?
    }
}

struct HAConfig: Decodable {
    let unit_system: UnitSystem
    struct UnitSystem: Decodable { let temperature: String }
}

enum HAError: LocalizedError {
    case invalidURL, unauthorized, status(Int), badResponse, unsafeRedirect, keychain(OSStatus)
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "请输入完整的 Home Assistant 地址，例如 http://homeassistant.local:8123。"
        case .unauthorized: return "访问令牌无效或已过期，请到连接设置中重新填写。"
        case .status(let code): return "Home Assistant 返回错误（\(code)），请稍后重试。"
        case .badResponse: return "无法读取 Home Assistant 的响应，请确认地址正确。"
        case .unsafeRedirect: return "地址跳转到了其他服务器，请直接填写最终的 Home Assistant 地址。"
        case .keychain(let code): return "无法访问 Mac 钥匙串（\(code)），请检查钥匙串权限后重试。"
        }
    }
}

enum TokenStore {
    private static let service = "local.ivan.AirControl.homeassistant"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "access-token"]
    }
    static func read() throws -> String {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess else { throw HAError.keychain(status) }
        return (result as? Data).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
    static func save(_ token: String) throws {
        let data = Data(token.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw HAError.keychain(added) }
        } else if status != errSecSuccess { throw HAError.keychain(status) }
    }
}

final class SameOriginRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let original = task.originalRequest?.url, let next = request.url,
              original.scheme == next.scheme, original.host == next.host,
              original.port == next.port else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

final class HAClient {
    let baseURL: URL
    private let token: String
    private let redirectDelegate = SameOriginRedirects()
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: redirectDelegate, delegateQueue: nil)
    }()

    init(address: String, token: String) throws {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw HAError.invalidURL
        }
        baseURL = url
        self.token = token
    }
    deinit { session.invalidateAndCancel() }

    private func request(_ path: String, body: [String: Any]? = nil) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw HAError.badResponse }
        if [401, 403].contains(response.statusCode) { throw HAError.unauthorized }
        if (300..<400).contains(response.statusCode) { throw HAError.unsafeRedirect }
        guard (200..<300).contains(response.statusCode) else { throw HAError.status(response.statusCode) }
        return data
    }
    func climates() async throws -> [ClimateEntity] {
        let data = try await request("api/states")
        // Other entity domains have different attribute types; filter before typed decoding.
        guard let objects = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw HAError.badResponse
        }
        let climates = objects.filter { ($0["entity_id"] as? String)?.hasPrefix("climate.") == true }
        return try JSONDecoder().decode([ClimateEntity].self, from: JSONSerialization.data(withJSONObject: climates))
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func states() async throws -> [HomeEntity] {
        try JSONDecoder().decode([HomeEntity].self, from: await request("api/states"))
    }

    func registry() async throws -> HomeRegistry {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/websocket"), resolvingAgainstBaseURL: false)!
        components.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        let socket = session.webSocketTask(with: components.url!)
        socket.maximumMessageSize = 16 * 1024 * 1024
        socket.resume()
        let deadline = Task {
            try? await Task.sleep(for: .seconds(15))
            if !Task.isCancelled { socket.cancel(with: .goingAway, reason: nil) }
        }
        defer { deadline.cancel(); socket.cancel(with: .normalClosure, reason: nil) }
        func receive() async throws -> [String: Any] {
            let message = try await socket.receive()
            let data: Data
            switch message {
            case .data(let value): data = value
            case .string(let value): data = Data(value.utf8)
            @unknown default: throw HAError.badResponse
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw HAError.badResponse }
            return object
        }
        func send(_ value: [String: Any]) async throws {
            let data = try JSONSerialization.data(withJSONObject: value)
            try await socket.send(.string(String(decoding: data, as: UTF8.self)))
        }
        guard try await receive()["type"] as? String == "auth_required" else { throw HAError.badResponse }
        try await send(["type": "auth", "access_token": token])
        guard try await receive()["type"] as? String == "auth_ok" else { throw HAError.unauthorized }
        func command<T: Decodable>(_ type: String, id: Int, as: T.Type) async throws -> T {
            try await send(["id": id, "type": type])
            let result = try await receive()
            guard result["id"] as? Int == id, result["success"] as? Bool == true,
                  let value = result["result"] else { throw HAError.badResponse }
            return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: value))
        }
        let entities = try await command("config/entity_registry/list", id: 1, as: [HAEntityRegistration].self)
        let devices = try await command("config/device_registry/list", id: 2, as: [HADeviceRegistration].self)
        let areas = (try? await command("config/area_registry/list", id: 3, as: [HAAreaRegistration].self)) ?? []
        return HomeRegistry(entities: entities, devices: devices, areas: areas)
    }
    func temperatureUnit() async throws -> String {
        let data = try await request("api/config")
        return try JSONDecoder().decode(HAConfig.self, from: data).unit_system.temperature
    }
    func services() async throws -> Set<String> {
        let data = try await request("api/services")
        guard let domains = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw HAError.badResponse }
        return Set(domains.flatMap { domain -> [String] in
            guard let name = domain["domain"] as? String, let services = domain["services"] as? [String: Any] else { return [] }
            return services.keys.map { "\(name).\($0)" }
        })
    }
    func cameraImage(entityID: String) async throws -> Data {
        guard entityID.hasPrefix("camera."), !entityID.contains("/") else { throw HAError.badResponse }
        return try await request("api/camera_proxy/\(entityID)")
    }
    func call(_ service: String, entityID: String, values: [String: Any] = [:], domain: String = "climate") async throws {
        var body = values
        body["entity_id"] = entityID
        _ = try await request("api/services/\(domain)/\(service)", body: body)
    }
}
