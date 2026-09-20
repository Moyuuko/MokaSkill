# Copper Corner Tools

独立的 Cadence Allegro SKILL 插件，用于统一已有覆铜倒角，也可以新增倒角或圆角。插件不要求覆铜是矩形，会读取真实闭合轮廓并自动判断已有倒角边或可处理角点。

## 功能

- `Uniform chamfer (modify / add)`：默认模式。已有短斜边先还原到虚拟尖角并按统一退距重建；没有倒角的凸角直接新增倒角。
- `Uniform round (modify / add)`：已有短斜边先还原到虚拟尖角并改为统一半径圆角；没有倒角的凸角直接新增圆角。
- `Normalize existing only`：只统一已经存在的短斜边，不处理没有倒角的角。
- `Corner selection` 可选择只处理外角、只处理内凹角，或同时处理外角和内角。
- 支持矩形、梯形、L 形及其他非规则直线多边形覆铜。
- 只处理凸角，自动跳过凹角、接近直线的点和尺寸放不下的短边角。
- 原位修改 shape boundary，保留覆铜的层、网络、静态/动态类型、属性和原有 void。
- 点击动态覆铜生成的 ETCH 填充区时，会自动转换到对应的 BOUNDARY shape 后再修改。
- 动态覆铜修改后自动强制更新。
- 整个选择会话支持取消并整体回滚。

## 安装

在 PowerShell 中进入本目录并运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

脚本只会在 `%USERPROFILE%\pcbenv\allegro.ilinit` 中维护一段带标记的加载配置，不会复制或删除插件源码。重启 Allegro 后，在命令行输入：

```text
copper_corner
```

也可以输入短命令 `cct`。卸载启动项可运行 `uninstall.ps1`。

## 使用

1. 运行 `copper_corner` 打开面板。
2. 选择统一倒角或统一圆角。两种模式都会修改已有倒角，并在没有倒角的位置新增。
3. 在 `Corner selection` 中选择 `Outer corners`、`Inner corners` 或 `Outer + inner corners`。
4. 输入统一尺寸。倒角模式下该值是从虚拟尖角沿两侧主边量取的退距；圆角模式下该值是半径。
5. 设置允许处理的最小和最大角度，默认 `30` 到 `150` 度；内角使用凹口两边的较小夹角。
6. 点击 `Select and apply`，选择一个或多个覆铜 shape。
7. 右键选择 `Done` 提交，或选择 `Cancel session` 回滚本次会话全部修改。

## 自动判断规则

统一倒角和统一圆角模式会先寻找比两侧主边短的凸斜边，将其折叠回主边交点；随后在还原后的基础轮廓上统一生成目标倒角或圆角，没有原倒角的凸角也会同时处理。所有模式均不依赖矩形包围盒。

- 内角位于设置范围内。
- 相邻边都是有效直线段。
- 倒角退距或圆角切线长度不超过两侧边长的 45%。

45% 限制保证同一条短边两端同时处理时不会相交。只要有一个目标角无法容纳统一尺寸，整块覆铜会跳过并报告尺寸过大，不会只修改其中一部分。

## 当前限制

- 为避免破坏原有曲线轮廓，包含已有圆弧段的 shape 会整体跳过。
- 新边界如果与原有 void 冲突，Allegro 会拒绝修改，该 shape 会跳过并在命令窗口报告原因。
- 插件面向 Allegro PCB Editor 16.6 及兼容 AXL SKILL API；实际发布前应在目标 Allegro 版本和真实板文件副本上验证。
