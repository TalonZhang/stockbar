# 应用图标

设计：白色圆角底、单一蓝色上涨折线与右上箭头；加粗圆润笔画，不使用红绿双线、发光、镜面或装饰图形。

- `AppIcon-artwork.png`：用户确认的原始图稿，使用内置 ImageGen 生成并修改。
- `AppIcon-1024.png`：标准 1024 像素透明外沿导出。
- `AppIcon.icns`：应用实际使用的多尺寸资源。
- `Tools/MakeICNS.m`：ICNS 导出工具，通过 `make icon` 运行。

导出只按标准几何圆角边界裁切外侧画布并缩放，不重画用户确认的蓝色标志。菜单栏继续使用 `chart.line.uptrend.xyaxis`，与此图标独立。

## 最终图稿提示词

内置 ImageGen，基于白底蓝线方案编辑：

> Preserve the white rounded-square tile, pale neutral-gray exterior background, blue-and-white palette, centered layout and three-segment upward stock-trend silhouette. Make the blue stroke approximately 35 percent thicker; add a small open upper-right arrowhead with the same stroke weight. Preserve generous margins, rounded caps and softly rounded joins. One connected blue upward-trending arrow only; no axes, bars, grids, dots, text, red/green secondary lines, reflections, gloss or 3D.
