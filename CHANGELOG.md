# 变更记录

## v1.3.1 — 2026-11-05

- 新增 Interactive BOM：从 Allegro 板数据生成独立 HTML，支持 BOM 搜索、分组、正反面查看及配置选项；可从菜单、层设置面板或 `moka_ibom` / `moka_ibom_config` 命令使用。
- 将 InteractiveHtmlBom 查看器与 Allegro 数据采集器集成进安装包，导出不需要 Python、外部 InteractiveHtmlBom 安装或中间 JSON 文件。
- Anti-Pad 新增全板差分过孔批量设置，并修正圆形过孔反焊盘外扩按铜 pad 外径计算。
- Anti-Pad 批量完成后安全结束交互状态，避免切层命令与数据库事务同时运行。
- 不再用 Moka 图标目录覆盖 Allegro 全局 BMPPATH，保留原生功能栏图标和间距。
- 层设置新增独立 `DRC ALL` 选项，用于显示 `DRC ERROR CLASS/ALL`，不再把全局 DRC 误认为各层 DRC 的简单汇总。

## v1.2（待测试，未发布）

- Anti-Pad 增加“全板差分过孔”按钮，以及 `moka_dp_antipad_all` 命令。
- 按 Allegro `DIFF_PAIR` 约束识别全板过孔，在差分对过孔间距(Max)内按距离优先进行一对一匹配，只处理过孔，不凭网络名称猜测差分关系。
- 沿用面板中的几何、外扩、尺寸、放置层（含 `All`）和替换设置；显示匹配、未配对、成功、跳过及失败统计。
- 生成后可检查结果，Done 提交、Oops 撤销上一组、Cancel 回滚整批；单组失败会回滚该组，其他组可继续处理。

## v1.1 — 2026-10-15

- Anti-Pad 工具的“放置层”新增 `All`，将图形放置在 `ROUTE KEEPOUT/ALL`，对所有走线层生效。
- 选择 `All` 时，Via/Pin 的 Padstack 轮廓取自开始选择时的活动 ETCH 层；无活动 ETCH 层时使用叠层中的首个 ETCH 层。整个操作使用同一参考层，不逐层合并不同 Padstack 轮廓。
- 统一更新功能面板与安装程序版本号为 v1.1。

## v1.0

- 首个正式发布版本。
