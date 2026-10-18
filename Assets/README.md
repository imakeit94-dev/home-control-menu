# 智能家居图标

原创几何图形，唯一绘制源为 `scripts/generate-icon.swift`。房屋轮廓内的四格窗呼应设备宫格，右下浅青格表达在线设备。固定蓝色仅用于应用标识，界面继续采用 macOS 动态系统色。

- `AppIcon.png`：1024 × 1024，透明外缘。
- `AppIcon.iconset` / `AppIcon.icns`：macOS 标准多分辨率应用图标。
- `MenuBarIcon.png`：72 × 72 单色模板，以 18 逻辑点显示，使用简化家形和中央窗。

执行 `zsh scripts/build-app.sh` 会重新生成图标、复制到应用包并签名。所有 PNG 内嵌绘制来源，不使用外部素材或图像模型。
