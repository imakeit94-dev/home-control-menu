---
version: 1
slug: "sources-aircontrol-aircontrolapp-swift"
primary_target: "Sources/AirControl/AirControlApp.swift"
related_targets: ["Sources/AirControl/DevicePresentation.swift"]
---

# 家居控制：设备宫格

Mode: Operate. Native macOS SwiftUI menu-bar utility. Code-led.

## Direction contract

THESIS: 用户已选择手机控制中心式的「设备宫格 → 点击展开控制 → 返回全部设备」。首页显示全部 10 个温控实体，支持按设备类别浏览，设备选择不再使用下拉框。

OWN-WORLD: 继承 macOS 原生系统字体、动态明暗色和 SF Symbols。参考用户提供的 vivo 控制中心录屏：中性圆角设备块、蓝色开启状态、独立开关、横向减号／温度／加号，更多操作渐进展开。状态颜色只用于表达设备状态和选中项。

STORY: 打开菜单栏即可看设备。点卡片进入该设备，调节完成后返回宫格。全程保留 Home Assistant 的实际能力、读数和错误；冰箱与热水器不标作室内温度。

FIRST VIEWPORT: 宽 420 点，高度按屏幕上限约束、最高 644 点。顶部家庭标题和设置，下面横向类别筛选，主区域两列设备宫格，底部同步时间与刷新。详情顶部返回全部设备，主体显示设备身份、开关、横向温度步进，模式直接点选，更多操作包含风速／扫风／预设。

FORM: User-pinned composition, confirmed in chat 2026-10-18. 手机录屏是交互参考，不是需要像素复刻的设计稿。No random concept selection: the user supplied the reference and explicitly selected this precise composition.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## Constraints

全部已发现设备保留。维持现有服务器地址和钥匙串凭据。状态颜色不能成为唯一指示。重做导航不触发设备控制。没有用户要求，不为验证而改变真实空调温度或开关。
