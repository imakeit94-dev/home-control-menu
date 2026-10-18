---
name: 家居控制 · 原生菜单栏
description: 原生系统外观下的设备宫格与渐进式家居控制详情
colors:
  accent: "AccentColor"
  canvas: "Canvas"
  tile: "Field"
  primary-text: "CanvasText"
  secondary-text: "light-dark(rgb(36% 36% 36%), rgb(72% 72% 72%))"
  on-accent: "#ffffff"
typography:
  temperature:
    fontFamily: "ui-rounded, system-ui"
    fontSize: "42pt"
    fontWeight: 600
  device-title:
    fontFamily: "system-ui"
    fontSize: "20pt"
    fontWeight: 600
  panel-title:
    fontFamily: "system-ui"
    fontSize: "19pt"
    fontWeight: 600
  tile-temperature:
    fontFamily: "ui-rounded, system-ui"
    fontSize: "16pt"
    fontWeight: 600
  section-title:
    fontFamily: "system-ui"
    fontSize: "14pt"
    fontWeight: 600
  tile-title:
    fontFamily: "system-ui"
    fontSize: "13pt"
    fontWeight: 600
  body:
    fontFamily: "system-ui"
    fontSize: "12pt"
    fontWeight: 400
  label:
    fontFamily: "system-ui"
    fontSize: "11pt"
    fontWeight: 400
  tile-status:
    fontFamily: "system-ui"
    fontSize: "10.5pt"
    fontWeight: 400
rounded:
  choice: "9pt"
  notice: "12pt"
  identity: "14pt"
  surface: "16pt"
spacing:
  compact: "3pt"
  label: "5pt"
  tight: "6pt"
  small: "8pt"
  grid: "10pt"
  control: "12pt"
  tile-inset: "13pt"
  icon-gap: "14pt"
  section: "20pt"
  detail-inset: "22pt"
  detail-section: "24pt"
components:
  device-tile:
    backgroundColor: "{colors.tile}"
    textColor: "{colors.primary-text}"
    rounded: "{rounded.surface}"
    padding: "{spacing.tile-inset}"
    height: "88pt"
  temperature-panel:
    backgroundColor: "{colors.tile}"
    rounded: "{rounded.surface}"
    padding: "20pt 14pt"
  power-active:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.on-accent}"
    size: "48pt"
  temperature-step:
    textColor: "{colors.primary-text}"
    width: "44pt"
    height: "48pt"
  choice-selected:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.on-accent}"
    rounded: "{rounded.choice}"
    padding: "0pt 6pt"
  category-selected:
    backgroundColor: "{colors.primary-text}"
    textColor: "{colors.canvas}"
    padding: "0pt 13pt"
    height: "29pt"
  navigation-button:
    width: "30pt"
    height: "32pt"
  panel:
    backgroundColor: "{colors.canvas}"
    width: "420pt"
---

# Design System: 家居控制

## Overview

**Creative North Star: "原生家居控制中心"**

以已确认的「原生家居控制中心」为方向：中性圆角设备块、清楚的状态文字、独立开关与横向温度步进。用户先浏览设备，再打开详情；密度适合菜单栏短时操作。

采用 SwiftUI 与 AppKit、系统字体和 SF Symbols，跟随 macOS 明暗外观及强调色。系统字体是明确的原生平台约束。无外部字体、装饰图片或网页容器；HTML/CSS 仅用于设计面板的近似组件预览。

**Key Characteristics:**

- 原生动态外观与系统文字。
- 两列设备宫格，详情内逐层展开控制。
- 状态同时使用文字、图标与颜色。
- 控制能力、温度单位及范围来自实际实体。

## Colors

色彩以 macOS 语义颜色为准，中性底面承载设备状态；当前截图使用系统蓝色强调色，但蓝色不是固定品牌色。

### Primary

- `accent` 对应 `Color.accentColor`，用于开启设备图标、开关和已选功能。`on-accent` 用于这些实色控件上的文字与图标。

### Neutral

- `canvas` 对应 `NSColor.windowBackgroundColor`；`tile` 对应 `NSColor.controlBackgroundColor`。
- `primary-text` 对应 SwiftUI `Color.primary`。前述 CSS 系统色关键字是跨工具语义桥接，不保证浏览器与 AppKit 像素一致；原生来源记录于 sidecar，不能用一次截图取色替代。
- `secondary-text` 对应 `PanelStyle.secondaryText` 的动态 `NSColor(calibratedWhite:)`，承载状态、类别、辅助读数与底栏文字。该值由源代码明确指定，随 aqua / darkAqua 切换。
- 图标局部使用 SwiftUI `.secondary`；告警、同步与设置错误分别沿用系统 `.orange`、`.green`、`.red`。它们不形成额外品牌配色。

**The 状态有文字 Rule.** 开启、关闭、离线与选中状态必须同时有文字或可访问性语义；颜色不能独自承担状态。

## Typography

**Display Font:** macOS 系统圆体（SwiftUI `.system(design: .rounded)`），用于温度读数。  
**Body Font:** macOS 系统字体（SwiftUI `.system`）。中文由系统自动选择字形。  
**Label/Mono Font:** 同一系统字体；温度应用 `.monospacedDigit()`，不引入独立等宽字体。

### Hierarchy

frontmatter 记录源代码明确给出的字号与字重；尺寸单位是原生逻辑点。`temperature` 是详情读数，`tile-temperature` 是卡片的温度、百分比等短读数；`device-title` 与 `panel-title` 区分设备身份与导航标题；`section-title`、`tile-title`、`body`、`label`、`tile-status` 依次承载控制标题、设备名、选项和辅助状态。选项选中时字重由 regular 切换 semibold。

行高和字距采用原生默认值，不创造固定 token。连接设置保留 `.callout`、`.caption`、`.caption2` 等原生文本样式，未锁定为自定义字号。卡片长设备名单行居中截断，详情名称允许换行，选项最多两行。

**The 读数先于装饰 Rule.** 温度使用系统圆体与等宽数字，单位缩小；不添加脱离设备能力的读数或操作。

## Layout

当前菜单面板宽度取 `panel.width`，高度为 `min(644, NSScreen.main.visibleFrame.height - 80)` 逻辑点；屏幕信息缺失时按 900 点高计算。没有网页断点或手机响应式布局。头部固定 66 点、底栏固定 40 点，中部内容滚动；首屏是否容纳全部设备取决于屏幕高度。

总览左右内边距采用 `section`，两列等宽宫格，行列间距采用 `grid`；横向类别条可滚动，条高 34 点。卡片整体高度为 `device-tile.height`，内部使用 `tile-inset`。详情左右内边距采用 `detail-inset`、主段间距采用 `detail-section`，顶部 10 点、底部 24 点。

选项网格最小列宽 76 点、行列间距 8 点，按钮最小高度 35 点；列数随可用宽度自然分配。连接设置沿用原生滚动表单，内容内边距 20 点。所有尺寸以 SwiftUI 代码为来源，CSS 样例以 1 逻辑点约对应 1 CSS 像素展示比例。

## Elevation & Depth

内容没有自定义阴影。动态背景与卡片表面、连续圆角和细描边构成层次；窗口本身的阴影和焦点表现交给 macOS。设备卡片静止描边使用主文字色 6% 不透明度，悬停切换为强调色 65% 不透明度，线宽 1 点。非选类别、普通选项和关闭开关分别使用主色低透明度底面，准确的混色关系存于 sidecar。

**The 原生平面层次 Rule.** 内容表面依靠动态底色、留白和细描边分层，不添加自定义卡片投影。

## Shapes

设备卡片与温度面板使用 `surface` 圆角；设备卡片是连续曲线圆角，温度面板采用默认 RoundedRectangle。身份图标底座使用 `identity`，选项使用 `choice`，错误提示使用 `notice`。分类为 Capsule，独立开关为 Circle；这些形状由 SwiftUI 几何体定义，不编造极大圆角数值。

## Components

### Navigation

头部展示家庭或设备控制标题、返回与设置。返回按钮的命令快捷键是 Command–Left Arrow，返回设备总览时清空分类与搜索。每次打开面板回到总览并同步。底栏显示同步、连接中断或发送中状态，提供刷新与应用菜单。

### Cards / Containers

设备卡片作为一个按钮打开详情，显示类别 SF Symbol、名称、文字状态，以及可用时的温度、百分比等短读数；较长读数留在详情。状态行优先展示房间，同名设备展示集成来源以便区分。卡片悬停强调描边；卡片主体进入详情，右下角独立电源按钮执行快捷开关，两个按钮为并列控件，电源点击不会触发详情导航。详情身份图标底座为 54 点方形。

一张卡片对应 HA 设备记录，关联实体在同一详情中呈现。保留注册表关系与来源，不凭相同名称或型号合并卡片。详情身份区显示类别、房间与来源；温控控件嵌入聚合详情时不重复身份区。

### Buttons

开关使用独立圆形按钮；开启且在线时使用强调色底与白色电源图标，关闭时使用中性底。设备卡片的快捷电源为 30 点圆形，距右侧与底部各 10 点，名称与状态为它保留 34 点右侧空间；卡片仍高 88 点。只为有明确设备电源能力的条目显示，不把指示灯或童锁当成整机电源。红外设备无状态反馈时，电源打开原生开机／关机菜单，不推测当前状态；多温控分区的冰箱不显示未经证实的整机电源。发送时显示等待，离线及操作处理中禁用电源；错误在总览可见。温度加减按钮分列目标读数两侧。不可控制、发送中、关闭或到达温度边界时，按实际条件禁用相应操作。未提供开关能力的设备显示运行状态。

类别按钮采用黑白反相的胶囊选中态。模式、风速、扫风、预设使用圆角网格按钮；选中为强调色与白色，未选中为中性浅底。SwiftUI 原生焦点与禁用语义负责交互反馈；只有设备卡片显式定义悬停描边，其他按钮不记录自创悬停动画。

### Inputs / Fields

总览搜索使用放大镜、无边框 TextField、输入后出现的清除按钮和控件底面；高度 30 点、圆角 8 点。搜索与类别共同筛选，匹配设备名、房间及来源；无结果时提供「显示全部设备」清空二者。此尺寸仅描述现有搜索组件，不扩展为全局输入规范。

连接设置使用 `.roundedBorder` TextField 和 SecureField、原生 `.borderedProminent` 大号连接按钮与 `.link` 链接按钮。密码存储提示及连接错误保持原生文本样式。没有自定义输入高度、圆角或焦点色 token；外观取决于 macOS。

### Temperature & Disclosure

横向温度卡片呈现减号、目标读数和加号，当前值与能力边界置于下方。关闭且支持目标温度时显示「开启后调节温度」。无目标读数时仅展示实际当前读数；离线温度区域降低不透明度。

模式直接展示；有风速、扫风或预设能力时才显示「更多操作」。该行提供当前可展开内容摘要，展开后显示各组选项，缺失当前值时写「状态未提供」。详情切换与温控的更多操作使用 0.18 秒 ease-out；减少动态效果开启时取消动画与详情水平位移。位移、角度与不透明度的准确值见 sidecar。

### Multi-domain Controls & Readings

各类设备复用身份区、圆形开关、选项网格、中性读数面板与原生控件。通用实体开关为 46 点圆形；既有温控开关继续使用 `power-active.size`。同一设备的多个温控分区使用横向胶囊切换，选中沿用强调色；复用已有温度卡片，不复制设备身份区。

数值设置使用标题、右侧圆体等宽读数、原生 Slider 及两端边界；拖动结束才提交。状态缺失时展示「状态未提供」，提供输入与「设置」，不填造当前读数。灯光颜色、摇头、静音、媒体传输与文本设置沿用原生 ColorPicker、Toggle、边框按钮和输入框；仅展示实际支持的能力，服务不可用或发送中时禁用。高影响动作使用原生确认对话框。

只读传感器使用中性大读数面板；「设备状态」用左右对齐的名称与值，名称允许两行、值允许换行。先展示少量非事件状态，其余由文字链接展开并可收起；事件呈现时间或「暂无记录」。辅助控制折叠在「更多功能与设置」，逐项垂直排列并用原生 Divider 分隔；没有额外折叠动画规范。摄像机由用户主动读取快照，显示读取时间与真实失败或离线说明。

### Notices

InlineNotice 使用警告图标、可换行文字、内边距 12 点及系统橙色 9% 不透明度底面。全局连接错误、当前设备命令错误和设备离线分别呈现真实状态；旧读数不会伪装成已经同步的新状态。

## Do's and Don'ts

### Do:

- Do 保留系统字体、SF Symbols、动态明暗色与系统强调色。
- Do 用设备宫格进入详情，并提供「返回全部设备」；长内容在固定头尾之间滚动。
- Do 只呈现实体报告的能力、单位和范围；冰箱写「当前」，热水设备写「水温」。
- Do 保留网络操作禁用、状态未提供、离线及错误说明，并支持刷新。
- Do 为图标按钮提供可访问性标签，选中项提供选中语义，并遵守减少动态效果设置。

### Don't:

- Don't 恢复旧版设备下拉框或 360 点面板作为当前导航规范。
- Don't 以固定蓝色或固定明暗色替换系统动态颜色。
- Don't 增加装饰图片、额外字体、网页容器或自定义卡片投影。
- Don't 按设备名称推断控制能力，也不要把所有设备读数标成室内温度。
