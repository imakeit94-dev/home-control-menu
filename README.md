# 家居控制 for macOS

一个原生 macOS 菜单栏智能家居面板。它读取 Home Assistant 中已经启用的设备，用两列设备宫格浏览，并在卡片详情里控制空调、灯光、风扇、冰箱、除湿机、影音设备与传感器。

需要 macOS 14 或更高版本、Swift 6 工具链和可访问的 Home Assistant 实例。应用没有第三方运行时依赖。

## 功能

- 菜单栏快速打开设备宫格，按类别筛选，按名称、来源或房间搜索。
- 同一 Home Assistant 设备的多类实体聚合到一张卡片；温度范围、模式和可执行操作来自实体本身。
- 支持电源能力的设备在卡片右下角提供快捷开关，不必进入详情。
- 详情保留设备开关、温度步进、模式、风速、摆风和其他实际支持的控制。
- 高影响操作需要确认；离线、未知状态、权限错误与网络错误都有明确的可用性反馈。
- 令牌保存在 macOS 钥匙串，不写入源码或普通偏好设置。

## 安装

### 从源码构建

1. 安装 Apple 的 Swift 工具链，并确认 `swift`、`iconutil` 和 `codesign` 可用。
2. 在项目根目录执行：

```sh
zsh scripts/build-app.sh
open "dist/空调控制.app"
```

3. 应用使用本机临时签名，尚未经 Apple 公证。若要安装到「应用程序」，可把构建出的应用拖入该目录，或在 Finder 中选择「移动」。

若要随登录启动，请在 macOS「系统设置 → 通用 → 登录项」中添加已安装的应用。移动或重新编译应用后，系统可能再次要求确认钥匙串访问。

### 连接 Home Assistant

1. 点击菜单栏的房屋图标，打开连接设置。
2. 输入 Home Assistant 地址，例如 `http://homeassistant.local:8123`。
3. 在 Home Assistant 个人资料页的「安全」部分创建长期访问令牌。
4. 将令牌粘贴到应用中并连接。令牌会保存在当前用户的 macOS 钥匙串。
5. 若 macOS 阻止本地网络访问，请在「系统设置 → 隐私与安全 → 本地网络」中允许本应用。

远程访问需要由你的 Home Assistant 网络配置提供；应用侧不会建立额外的云连接。

## 设备与集成

应用直接使用 Home Assistant REST API 和 WebSocket 注册表接口。支持程度由每个实体暴露的状态、属性和服务决定，不能控制的实体只展示状态。

当前版本有意排除 `xiaomi_miot` 来源的实体。其他 Home Assistant 设备来源仍会显示，包括 Xiaomi Home 已启用的设备。此过滤只影响本应用，不修改 Home Assistant 配置。

同一 `device_id` 下的实体合并为一张设备卡片。不同注册记录即使名称或型号相同也保留来源与卡片，避免控制到错误设备。

## 工作方式

- `GET /api/config` 读取温度单位。
- `GET /api/states` 读取实体状态与能力。
- WebSocket `config/entity_registry/list`、`config/device_registry/list` 和 `config/area_registry/list` 读取设备与房间注册表。
- `GET /api/services` 读取当前可调用的服务。
- `POST /api/services/{domain}/{service}` 执行用户点选的控制。
- `GET /api/camera_proxy/{entity_id}` 仅在用户主动查看或刷新摄像机快照时读取。

应用每 20 秒刷新状态，设备元数据约每 5 分钟更新。可访问性和控制能力取决于 Home Assistant、设备集成与本地网络连接。

参考：[Home Assistant REST API](https://developers.home-assistant.io/docs/api/rest/) 与 [Climate 集成](https://www.home-assistant.io/integrations/climate/)。

## 检查

接口检查使用一次性本地模拟服务，不读取或修改真实设备：

```sh
swiftc -parse-as-library \
  Sources/AirControl/HomeAssistant.swift \
  Sources/AirControl/DevicePresentation.swift \
  Sources/AirControl/HomeDevice.swift \
  scripts/APIChecks.swift \
  -o .build/api-checks
python3 scripts/check-api.py .build/api-checks
```

## 隐私

仓库不包含真实访问令牌、家庭地址、实体清单、家庭照片或运行日志。应用只保存你输入的 Home Assistant 地址到本机偏好设置，并把访问令牌保存在 macOS 钥匙串。

## 已知限制

- 应用尚未经 Apple 公证，系统可能提示开发者身份或本地网络权限。
- 控制结果取决于 Home Assistant 中实体报告的能力与设备响应，应用会随后重新读取状态。
- Home Assistant 不可达、设备离线或服务不可用时，相应操作会禁用并显示说明。
- 仓库中的构建脚本生成开发版本；发布构建、签名与公证需由维护者另行配置。

## License

[MIT](LICENSE)
