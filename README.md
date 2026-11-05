# MokaSkill v1.3.0

v1.3.0 新增集成式交互式 BOM，并包含 Anti-Pad 批量处理、切层交互、圆形过孔外扩及工具栏图标搜索路径修复。版本已发布，安装包及更新说明见 [GitHub Releases](https://github.com/Moyuuko/MokaSkill/releases/tag/v1.3.0)。

v1.1 已测试通过。Anti-Pad 的“放置层”新增 `All`，在 `ROUTE KEEPOUT/ALL` 创建全层生效的图形；读取 Via/Pin 轮廓时使用开始选择时的活动 ETCH 层，若无活动 ETCH 层则使用叠层中的首个 ETCH 层。

MokaSkill 是 Allegro的 SKILL 工具。

用以辅助PCB设计。

## 功能总览

| 功能 | 命令 | 说明 | 快捷键 |
| --- | --- | --- | --- |
| 层设置与显示 | `mokaskill` | 单层/多层显示、层切换、Place Bound 与 Anti Etch 显示设置 | `F12` |
| 对齐与分布 | `moka_align` | 拖动对齐、左/右/上/下对齐、水平/垂直居中、等间距和对齐栅格 | — |
| 走线等间距 | `moka_spread_between_clines` | 选择走线，在保持最外侧的情况下均匀分布间距 | — |
| Pin Swap | `moka_pin_swap` | 换Pin、Pin Map 导入导出 | — |
| Anti-Pad | `moka_dp_antipad` | 差分对和过孔相关的反焊盘设置工具 | — |
| 覆铜工具 | `moka_copper_corner` | 选择铜皮并进行批量或单角倒角/圆角处理 | — |
| 一键动态覆铜 | `moka_quick_copper` | 快速创建铜皮 | `Shift+D` |
| Stackup / Impedance | `moka_stackup_impedance` | 层叠与阻抗面板，支持工程数据导出和导入校验 | — |
| 交互式 BOM（MokaSkill 内置） | `moka_ibom` | 直接生成离线 HTML，支持分组、搜索及正反面器件定位；也可从 `mokaskill` 主面板运行 | — |
| 交互式 BOM 设置（MokaSkill 内置） | `moka_ibom_config` | 配置默认显示层、焊盘、深色模式、BOM 布局及自动打开；也可从 `mokaskill` 主面板打开 | — |
| PCB 标识 | `moka_symbols`、`moka_symbols_place` | 常见的PCB丝印标识一键放置 | — |
| 项目日志清理 | `moka_clean_logs` | 清理日志、临时文件 | — |
| 走线分析 | `moka_ta` | 识别目标层的走线线宽并高亮与跳转 | `F11` |
| PCB 信息 | `moka_info` | 查看管脚数、剩余飞线数和设计耗时 | — |
| 位号工具 | `moka_refdes` | 顶底层显示、位号补齐、居中、水平旋转和字体设置 | — |

顶层菜单可以选择中文或英文，功能面板保持中文。

交互式 BOM 已合并进 MokaSkill 主模块，并随 v1.3.0 安装器打包。它使用 Allegro SKILL 采集板数据，将 InteractiveHtmlBom v2.12.0 的中文界面和查看器内嵌到单个离线 HTML。运行时不需要安装 Python 或外部 InteractiveHtmlBom，也不生成中间 JSON 文件。从 Moka Skill 菜单或 `mokaskill` 主面板打开配置窗口并点击“导出”，即可保存配置并生成 HTML；也可使用 `moka_ibom` 直接导出或 `moka_ibom_config` 打开设置。设置会嵌入导出文件并优先于浏览器旧的 localStorage 配置。该功能尚未完成 Allegro 16.6/17.4 实板验证，数据采集和上游功能兼容性仍需测试。导出文件位于当前工程目录的 `ibom` 文件夹。

配置项及上游参数适配情况见 [Interactive BOM 配置说明](docs/interactive-bom-options.md)。配置面板中的版本号和公司名称会写入 HTML 元数据，填写后导出时不再弹出输入框。默认不导出 `COMPONENT VALUE/SILKSCREEN_TOP` 和 `COMPONENT VALUE/SILKSCREEN_BOTTOM`，不会影响 BOM 表格的 Value 列。

## 全部功能命令与快捷键

以下配置以安装程序生成的 `moka.env` 为准。完整命令和短别名在 Allegro 命令行输入后按回车执行；`F11`、`F12` 和 `funckey` 在画布获得焦点时直接触发。字母绑定在配置中使用大写，例如 `funckey D` 对应 `Shift+D`；表中同时列出配置字符，便于核对。`—` 表示没有默认绑定，可在 Allegro 的 Aliases/Function Keys 中自行设置。

### 层管理与设计信息

| 功能 | 完整命令 | 短别名 | 默认快捷键 |
| --- | --- | --- | --- |
| 层设置面板 | `mokaskill` | — | `F12` |
| 上一走线层 | `moka_prev` | — | `Shift+Z`（配置 `Z`） |
| 下一走线层 | `moka_next` | — | `Shift+X`（配置 `X`） |
| 单层/多层显示切换 | `moka_all` | — | `Shift+S`（配置 `S`） |
| 切换 Move Point / Connect Bubble 模式 | `moka_mode` | — | `Shift+B`（配置 `B`） |
| 切换当前布线过孔类型 | `moka_via` | — | `Shift+V`（配置 `V`） |
| 修改当前布线线宽 | `moka_width` | — | `Shift+W`（配置 `W`） |
| 位号工具 | `moka_refdes` | — | — |
| 走线分析 | `moka_ta` | — | `F11` |
| PCB 设计信息 | `moka_info` | `minfo` | — |

层显示矩阵、Place Bound、Anti Etch、自定义显示类别等在 `mokaskill` 面板内操作；位号显示与整理在 `moka_refdes` 面板内操作。

### 对齐、分布与走线等间距

| 功能 | 完整命令 | 短别名 | 默认快捷键 |
| --- | --- | --- | --- |
| 对齐工具面板 | `moka_align` | `aa`、`malign` | — |
| 拖动对齐 | `moka_al_drag` | `maldrag` | — |
| 左对齐 | `moka_al_left` | `al`、`malleft` | — |
| 右对齐 | `moka_al_right` | `ar`、`malright` | — |
| 上对齐 | `moka_al_top` | `at`、`maltop` | — |
| 下对齐 | `moka_al_bottom` | `ab`、`malbot` | — |
| 水平居中 | `moka_al_hcenter` | `ac`、`malhc` | — |
| 垂直居中 | `moka_al_vcenter` | `av`、`malvc` | — |
| 水平等间距 | `moka_al_hdist` | `ad`、`malhd` | — |
| 垂直等间距 | `moka_al_vdist` | `as`、`malvd` | — |
| 对齐到栅格 | `moka_al_grid` | `malgrid` | — |
| 走线等间距 | `moka_spread_between_clines` | `msbc` | — |

### Pin Swap、Anti-Pad 与覆铜

| 功能 | 完整命令 | 短别名/兼容命令 | 默认快捷键 |
| --- | --- | --- | --- |
| Pin Swap 面板 | `moka_pin_swap` | `ps`、`mpinswap`、`pin_swap` | — |
| 导出器件 Pin Map | `pin_swap_pinmap_export` | — | — |
| 导入 Pin Map 并批量换 Pin | `pin_swap_pinmap_import` | — | — |
| Anti-Pad 面板 | `moka_dp_antipad` | `mdpa`、`dp_antipad` | — |
| 全板差分对过孔一键设置反焊盘 | `moka_dp_antipad_all` | — | — |
| 覆铜倒角/圆角面板 | `moka_copper_corner` | `mcopper` | — |
| 按面板当前参数批量处理铜皮 | `moka_copper_corner_apply` | — | — |
| 按面板当前参数处理单个铜皮角 | `moka_copper_corner_single` | — | — |
| 一键动态覆铜 | `moka_quick_copper` | `mqc` | `Shift+D`（配置 `D`） |

Pin Map 导入导出也可从 Pin Swap 面板进入。Anti-Pad 的对象模式、几何方式、`All`/单层放置、替换和删除均在面板内设置。一键动态覆铜通过快捷键或命令启动，在当前 ETCH 层拖出矩形范围，自动创建带自适应倒角的动态铜皮。

Anti-Pad 新增“全板差分过孔”按钮：先设置几何、外扩量、尺寸、放置层（支持 `All`）及差分对过孔间距(Max)，再点击按钮，无需手动选择过孔。工具读取全板 `DIFF_PAIR` 约束，在两侧网络的过孔中按距离从近到远做一对一匹配，每个过孔最多使用一次；不处理 Pin，也不凭网络名称猜测。无匹配对象、超出距离或无有效差分约束的过孔不会创建反焊盘。匹配采用距离优先策略，不保证得到最多配对数；有未配对过孔时可检查其布局及距离设置。

批量模式不受面板“目标类型”影响，沿用几何、尺寸、放置层及“替换已有设置”。取消勾选替换时跳过已有 Moka 设置的过孔对；勾选时重建对应图形。生成后查看统计和板上结果，用“完成”/右键 Done 提交、Oops 撤销上一组、Cancel 回滚整批。提交后不进入 Allegro 全局 Undo，请在提交前检查。直接执行 `moka_dp_antipad_all` 使用当前面板参数，未选择放置层时默认首个 ETCH 层。

### 层叠、阻抗、PCB 标识与工程维护

| 功能 | 完整命令 | 短别名/兼容命令 | 默认快捷键 |
| --- | --- | --- | --- |
| 层叠/阻抗面板 | `moka_stackup_impedance` | `msi` | — |
| 导出层叠/阻抗工作簿 | `moka_stackup_export` | — | — |
| 校验并导入层叠/阻抗工作簿 | `moka_stackup_import` | — | — |
| PCB 标识面板 | `moka_symbols` | `msymbols`、`mts_symbols` | — |
| 按当前参数连续放置 PCB 标识 | `moka_symbols_place` | `mplace`、`mts_place` | — |
| 工程日志清理 | `moka_clean_logs` | `mclean` | — |

标识类型、放置层、旋转、镜像与反相在 PCB 标识面板内设置。日志清理处理当前工程中的 `.log` 和 `,<数字>` 备份文件，确认后执行。

### 面板内部交互命令

`pin_swap_run` 和 `moka_dp_antipad_run` 由对应面板管理选择会话，没有默认快捷键；日常操作从 `moka_pin_swap`、`moka_dp_antipad` 进入即可。交互期间按各工具右键菜单中的 Done、Cancel、Oops 完成、取消或撤销操作。

## 安装与卸载

从 [Releases](https://github.com/Moyuuko/MokaSkill/releases) 下载对应版本安装包；v1.1 的文件名为 `MokaSkill_Setup_v1.1.exe`。按向导完成：

1. 选择 Allegro `SPB_Data` 用户目录。
2. 选择 MokaSkill 菜单栏语言（中文或 English）。
3. 安装程序将自动维护 `pcbenv/env` 和 `pcbenv/allegro.ilinit` 中带标记的配置块。
4. 卸载可从 Windows“已安装的应用”或开始菜单进入，卸载只移除 MokaSkill 自己管理的配置，不影响用户其他设置。

## 目录结构

```text
src/                         运行时 SKILL 源码和内置模块
src/runtime/                 Stackup 辅助桥接程序源代码与二进制
copper-corner-tools/         覆铜工具的独立开发/测试入口
installer/                   Inno Setup 脚本和配置助手源代码
dist/                        可分发的安装程序
tests/                       MokaSkill 几何和回归测试
docs/                        功能说明和开发文档
docs/demos/                  功能演示 GIF/视频（后续补充）
```

## 打包流程

打包采用 Inno Setup 7，流程固定为：

1. `installer/Build-Installer.ps1` 定位 .NET Framework `csc.exe`。
2. 编译 `installer/MokaSkillConfig.cs`，生成配置助手并执行自检。
3. 自检验证重复安装幂等性、用户 `pcbenv` 配置保留、快捷键配置和卸载回滚。
4. 调用 Inno Setup `ISCC.exe` 编译 `installer/MokaSkillSetup.iss`。
5. 安装器输出到 `dist/MokaSkill_Setup_v1.3.0.exe`，包含交互式 BOM 查看器及许可证文件，并提供现代向导、语言选择、卸载入口和静默配置步骤。

本地构建命令：

```powershell
pwsh -NoProfile -File .\installer\Build-Installer.ps1
```

构建前需要安装 Inno Setup 7：

```powershell
winget install --id JRSoftware.InnoSetup.7 -e
```

## 测试

```powershell
& 'D:\Cadence\SPB_16.6\tools\bin\cnskill.exe' -nongraph .\tests\dp_antipad_layers_test.il
& 'D:\Cadence\SPB_16.6\tools\bin\cnskill.exe' -nongraph .\tests\dp_antipad_batch_test.il
python .\src\pcb-symbols\tests\test_generator.py
& 'D:\Cadence\SPB_16.6\tools\bin\cnskill.exe' -nongraph .\src\pcb-symbols\tests\syntax_smoke.il
& 'D:\Cadence\SPB_16.6\tools\bin\cnskill.exe' -nongraph .\tests\moka_copper_corner_geometry_test.il
```

## 功能演示素材约定

后续每个功能的动态图放在 `docs/demos/`，文件名建议使用命令名，例如：

```text
docs/demos/mokaskill-layer-settings.gif
docs/demos/moka-align.gif
docs/demos/moka-spread-between-clines.gif
docs/demos/moka-quick-copper.gif
docs/demos/moka-stackup-impedance.gif
```

README 的功能表会作为演示索引；添加 GIF 后，在对应行补充相对链接即可，不需要改变安装包目录。

## 版本

当前版本：**v1.3.0**。安装程序与更新说明见 [GitHub Releases](https://github.com/Moyuuko/MokaSkill/releases)。
