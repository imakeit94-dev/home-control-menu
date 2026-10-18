---
version: 1
slug: home-devices
primary_target: Sources/AirControl/HomeDeviceControlView.swift
related_targets: [Sources/AirControl/ControlPanel.swift, Sources/AirControl/HomeDevice.swift]
---

# 小米设备扩展

Mode: Operate. Code-led local extension to the established 420-point native panel.

THESIS: 用户确认全部小米设备已在现有 Home Assistant 中看到并可控制，要求全部融入 Mac 软件。读取小米集成的全部已启用设备及其实体，维持既有温控功能。
OWN-WORLD: 沿用 DESIGN.md 的原生动态外观、系统字体、二列圆角宫格与直接点选，不进行新的世界选择。卡片代表 HA 注册的设备，详情聚合开关、数值、模式、状态与扩展操作。
STORY: 全部设备 → 类别或名称/房间搜索 → 设备详情 → 常用操作与更多设置。冰箱各分区在同一详情中直接切换，传感器只读，摄像机有可用camera实体时可主动读取快照。
FIRST VIEWPORT: 420 点面板，现有固定头尾、搜索和横向类别、可滚动宫格。详情首屏身份、真实状态与主功能；读数与更多功能逐层展开。实体能力、服务可用性、上下限和步长决定控件。
FORM: 局部扩展，不做概念竞赛。按注册表device_id聚合，两个集成的记录在不能证明物理身份相同时保留来源，不用相同名称/型号强行合并。保留既有全部climate实体，避免同时列出HA系统维护实体。
FINISH: 本地模拟检查异构实体、分组、跨域服务与负温回归；实机只读取与导航，无真实设备写入；独立finish review与文档对照。高影响设备按钮由使用者在软件中明确确认。

## 卡片快捷开关（1.3）
卡片右下角的设备电源与详情导航为并列按钮，88 点卡片保留既有样式。真实状态已知时一键切换；红外开关动作使用无推测状态的原生菜单；冰箱多分区不推断整机电源。未知设备能力不添加按钮，指示灯和童锁不作为设备电源。发送等待与错误须在总览可见，沿用 1.2.2 不可变快照的性能修复。
