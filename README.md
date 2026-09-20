# MokaSkill v1.0

MokaSkill 是面向 Cadence Allegro 16.6/17.4 的 SKILL 工具集合，目标是把常用的层管理、布局整理、走线辅助、覆铜、阻抗管理和项目维护操作集中到一个可安装、可卸载的工具中。

所有运行时功能都以明文 `.il` 提供，不加密、不生成 `.ile`，便于审阅、调试和按项目需要扩展。

## 功能总览

| 功能 | 命令 | 说明 | 快捷键 |
| --- | --- | --- | --- |
| 层设置与显示 | `mokaskill` | 单层/全层显示、层切换、Via 显示、线宽切换、Place Bound 和 Anti Etch 设置 | — |
| 对齐与分布 | `moka_align` | 拖动对齐、左/右/上/下对齐、水平/垂直居中、等间距和吸附网格 | — |
| 走线等间距 | `moka_spread_between_clines` | 选择平行 Cline，在保持两侧边界的情况下重新分配中间间距 | — |
| Pin Swap | `moka_pin_swap` | Pin 交换、Pin Map 导入和交换辅助操作 | — |
| Anti-Pad | `moka_dp_antipad` | 差分对和过孔相关的 Anti-Pad 设置工具 | — |
| 覆铜工具 | `moka_copper_corner` | 选择铜皮并进行倒角/圆角处理，倒角尺寸会根据几何范围自动约束 | — |
| 一键动态覆铜 | `moka_quick_copper` | 启用后左键拖动矩形范围，自动创建带自适应倒角的动态铜皮 | `Shift+D` |
| Stackup / Impedance | `moka_stackup_impedance` | Stackup 与阻抗计算面板，支持工程数据导出和导入校验 | — |
| PCB 标准标识 | `moka_symbols`、`moka_symbols_place` | 图标面板、层类别/子类选择、旋转/镜像/反相和连续放置 | — |
| 项目日志清理 | `moka_clean_logs` | 按类别预览和清理日志、临时文件、缓存和锁文件 | — |
| Trace 分析与信息 | `moka_ta`、`moka_info` | 打开 Trace Analyzer 和查看当前 PCB 信息 | — |

兼容命令 `mts_symbols`、`mts_place`、`cct`、`mcopper` 等仍保留。顶层菜单可以选择中文或英文，选择英文时只切换菜单栏，功能面板仍使用中文。

## 安装与卸载

从 [Releases](https://github.com/Moyuuko/MokaSkill/releases) 下载 `MokaSkill_Setup_v1.0.exe`，按向导完成：

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
assets/source-font/          本地数据生成所需的授权资源，不参与公开发布
signoise.run/                Trace 分析相关工程配置
```

## 打包流程

打包采用 Inno Setup 7，流程固定为：

1. `installer/Build-Installer.ps1` 定位 .NET Framework `csc.exe`。
2. 编译 `installer/MokaSkillConfig.cs`，生成配置助手并执行自检。
3. 自检验证重复安装幂等性、用户 `pcbenv` 配置保留、快捷键配置和卸载回滚。
4. 调用 Inno Setup `ISCC.exe` 编译 `installer/MokaSkillSetup.iss`。
5. 安装器输出到 `dist/MokaSkill_Setup_v1.0.exe`，带现代向导、语言选择、卸载入口和静默配置步骤。

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

当前版本：**v1.0**。发布安装包、源码和变更说明统一放在 GitHub Release 中。
