# Moka Skill 安装器

安装器使用开源 [Inno Setup](https://jrsoftware.org/isinfo.php) 构建，提供现代化 Windows 向导、“已安装的应用”注册、开始菜单卸载入口、静默安装和完整卸载。

## 构建

1. 安装 Inno Setup 7：

   ```powershell
   winget install --id JRSoftware.InnoSetup.7 -e
   ```

2. 在项目根目录运行：

   ```powershell
   .\installer\Build-Installer.ps1
   ```

3. 输出文件位于 `dist\MokaSkill_Setup_v1.0.exe`。

构建脚本会先编译 `MokaSkillConfig.exe` 并执行自检，再编译安装包。自检会验证重复安装的幂等性、卸载回滚和用户 Allegro 配置保留。

## 发行内容

- 只发布明文 `.il` SKILL 源码，不生成或打包 `.ile`。
- 安装向导可选择 MokaSkill 中文或英文菜单栏；选择 English 时只切换菜单栏，各功能界面仍为中文。
- 安装时在 `pcbenv/env` 和 `pcbenv/allegro.ilinit` 中添加带标记的配置块。
- 卸载时只删除 Moka Skill 管理的配置块，保留其他用户配置。
