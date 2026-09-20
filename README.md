# MokaSkill v1.0

Cadence Allegro 16.6/17.4 SKILL 工具集合，所有功能源码均为明文 `.il`，并集成 Mooretronics PCB 标识放置模块。

## 功能

- 图层切换、显示模式、过孔和线宽快捷操作
- 对齐工具、走线等间距、Pin Swap、Anti-Pad
- Stackup / Impedance 管理
- 动态覆铜工具：`Shift+D` 一键框选生成带自适应倒角的动态铜皮
- Mooretronics PCB 标识面板：26 个抗锯齿图标和连续放置
- 项目日志清理、PCB 信息和 Trace Analyzer 入口

## 安装

运行 [MokaSkill_Setup_v1.0.exe](dist/MokaSkill_Setup_v1.0.exe)，安装程序支持：

- 中文或英文 MokaSkill 菜单栏选择
- Allegro `SPB_Data` 用户目录选择
- 安装、升级和卸载时自动维护 `pcbenv`
- Mooretronics 字形数据与 26 个 BMP 图标统一部署

英文菜单只影响菜单栏，功能面板仍保持中文。

## 常用命令

```text
mokaskill                    ; 打开层设置/主面板
moka_copper_corner           ; 覆铜工具面板
moka_quick_copper            ; 动态一键覆铜（快捷键 Shift+D）
moka_symbols                 ; Mooretronics PCB 标识面板
moka_symbols_place           ; 按当前设置连续放置标识
msymbols / mplace            ; 标识工具快捷别名
```

旧的 `mts_symbols`、`mts_place` 和 `mooretronics_symbols` 命令继续兼容。

## 源码结构

```text
moka_loader*.il              MokaSkill 中英文菜单与模块加载器
*.il                         MokaSkill 功能模块
mooretronics-symbols/        PCB 标识模块、26 个图标和字形数据
installer/                   Inno Setup 安装器与环境配置助手
tests/                       SKILL / 几何回归测试
dist/                        发布安装包
```

## 构建安装包

需要 Cadence `cnskill.exe`、PowerShell 和 Inno Setup 7：

```powershell
pwsh -NoProfile -File .\installer\Build-Installer.ps1
```

构建脚本会先编译并自测 `MokaSkillConfig.exe`，再生成 `dist/MokaSkill_Setup_v1.0.exe`。

## 测试

```powershell
python .\mooretronics-symbols\tests\test_generator.py
& 'D:\Cadence\SPB_16.6\tools\bin\cnskill.exe' -nongraph .\mooretronics-symbols\tests\syntax_smoke.il
& 'D:\Cadence\SPB_16.6\tools\bin\cnskill.exe' -nongraph .\tests\moka_copper_corner_geometry_test.il
```

原始 `资源/Mooretronics.ttf` 仅用于重新生成字形数据，不纳入公开仓库；仓库中已包含可直接运行的 `mooretronics_glyphs.il` 和 BMP 图标资源。
