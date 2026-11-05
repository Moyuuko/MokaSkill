# MokaSkill Interactive BOM 配置

入口：Moka Skill 菜单或 `mokaskill` 主面板 → `交互式BOM`，也可使用命令 `moka_ibom_config`。在面板中点击“导出”，会先保存当前配置，再生成 HTML；“保存配置”仅保存设置。设置保存在插件安装目录下的 `moka_ibom.ini`。已有配置会继续生效，首次使用默认勾选显示焊盘、显示丝印、自动打开浏览器和拖动重绘。

## 已接入的设置

| 配置名称 | 上游对应选项 | 效果 |
| --- | --- | --- |
| Dark mode | `--dark-mode` | 页面默认深色模式 |
| Show pads | `--show-pads` / `--hide-pads` | 默认显示焊盘 |
| Show fabrication layer | `--show-fabrication` | 默认显示装配层 |
| Show silkscreen geometry | `--show-silkscreen` | 默认显示丝印几何和位号 |
| Show component values on canvas | MokaSkill 扩展项 | 默认关闭，控制已采集的装配层 Value 文本；不影响 BOM 表格中的 Value 列 |
| 版本号 | MokaSkill 扩展项 | 写入导出 HTML 的板卡 revision 元数据；留空时不再弹出命令行输入框 |
| 公司名称 | MokaSkill 扩展项 | 写入导出 HTML 的 company 元数据；留空时不再弹出命令行输入框 |
| Layer view | `--layer-view` | 正面、双面或背面 |
| BOM view | `--bom-view` | 左右、上下或仅 BOM |
| Highlight pin 1 | `--highlight-pin1` | None、All、Selected；依赖封装焊盘的首脚标记 |
| Redraw board while dragging | `--redraw-on-drag` | 拖动时刷新画布 |
| Board rotation (degrees) | `--board-rotation` | -180～180 度，保存时取最接近的 5 度倍数 |
| Rotate back side by 180 degrees | `--offset-back-rotation` | 背面增加 180 度旋转偏移 |
| BOM checkbox columns | `--checkboxes` | 用英文逗号分隔，例如 `Sourced,Placed,Checked`；留空可去掉这些列 |
| Mark when checked | `--mark-when-checked` | 填一个与上项完全一致的列名，例如 `Placed`；留空关闭自动标记 |
| Open result automatically | `--browser` | 导出后自动打开浏览器 |
| Include track and zone data | `--include-tracks` | 采集顶底层走线和铜皮；关闭时跳过铜皮采集并隐藏页面对应控制 |
| Include netlist data | `--include-nets` | 采集网络列表；关闭时跳过网络列表采集并隐藏网络列表按钮 |

这些初始设置优先于浏览器保存的旧显示偏好。装配进度复选框的勾选记录仍由上游查看器保存。

配置面板沿用 MokaSkill 其他 Allegro 面板的做法：源码只保存 ASCII，并使用 CP936 八进制转义生成中文表单文本，因此在 Allegro 16.6 和 17.4 的 SKILL 环境中不会依赖 UTF-8 源文件编码。导出的 HTML 使用 UTF-8，并将查看器菜单、BOM 表头、统计和提示显示为中文。

## Component Value 丝印排除

导出映射始终排除 `COMPONENT VALUE/SILKSCREEN_TOP` 和 `COMPONENT VALUE/SILKSCREEN_BOTTOM`。即使打开丝印或画布 Value 显示，这两个层也不会被导出。保留 `BOARD GEOMETRY/SILKSCREEN_*`、`PACKAGE GEOMETRY/SILKSCREEN_*` 和 `REF DES/SILKSCREEN_*`。

此设置仅影响导出 HTML，不删除或修改板文件中的器件值、丝印或 BOM 表格值。画布 Value 开关可显示已采集的 `COMPONENT VALUE/ASSEMBLY_*` 文本。

## 其余上游参数的处理

| 参数组 | 当前处理 |
| --- | --- |
| `--help`、`--version`、`--show-dialog`、`--use-ini` | 属于命令行或配置入口，由 MokaSkill 菜单、INI 读取替代 |
| `--kicad-variant` | KiCad 特有；Allegro 采集器有自己的变体流程，不复制此参数 |
| `--netlist-file`、`--extra-data-file` | 当前直接读取 Allegro 数据库，不要求外部输入文件 |
| `--compression`、`--no-compression` | 当前直接内嵌数据到 HTML，尚未提供压缩开关 |
| `--dest-dir`、`--name-format` | 当前固定输出到工程工作目录 `ibom`，文件名沿用板名及变体名加 `_ibom.html`；尚未实现自定义模板 |
| `--sort-order`、`--blacklist`、`--blacklist-empty-val` | 适合 BOM 整理，但需要补齐分组、过滤及器件索引验证，当前未添加无效控件 |
| `--blacklist-virtual` | 需要先定义 Allegro 中虚拟器件的判定规则，当前未提供 |
| `--show-fields`、`--group-fields`、`--extra-fields`、`--normalize-field-case` | 当前表格显示和分组使用 Value、Footprint，自定义属性映射尚未接入这些开关 |
| `--variant-field`、`--variants-whitelist`、`--variants-blacklist`、`--dnp-field` | 自定义字段和筛选规则尚未接入；不能直接等同于 Allegro 变体信息 |

## 验证范围

自动检查包括 Allegro 16.6 SKILL 解释器下的配置保存重读、顶底面图层排除、导出选项组合，以及浏览器里旧缓存与新配置冲突时的初始化行为。仍需在 Allegro 16.6 和 17.4 的实际板文件中验证表单外观、特殊封装、走线/铜皮几何和网络高亮。
