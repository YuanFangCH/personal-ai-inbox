# 懒狗秘书

[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

一个本地优先的个人信息捕获、整理与提醒系统。Android 手机、Android 平板和 Windows 端各自运行独立 Flutter App，以 Markdown 为权威成果库，通过端内规则、云端模型和可替换同步接口完成闭环。

## 下载与安装

首个预发布版本从 [GitHub Releases](https://github.com/YuanFangCH/personal-ai-inbox/releases) 下载：

- Android 7.0 及以上：安装通用 APK。
- Windows 11 x64：选择安装包或便携 ZIP。
- 发布页同时提供 `SHA256SUMS.txt`，下载后应校验文件哈希。

`v1.2.0` 预览版已发布（pre-release），资产见 [GitHub Release](https://github.com/YuanFangCH/personal-ai-inbox/releases/tag/v1.2.0)，并附 `SHA256SUMS.txt`。升级前请完整备份旧版应用数据与 Markdown 主库，并先阅读[发行说明](docs/releases/v1.2.0.md)；真实资料迁移需要在应用内确认，不能把迁移演练当作真实资料升级验证。v1.1.3 及之前的包无法保证与固定签名版本直接覆盖安装。

## 核心能力

- 本地优先：文本、分享内容和图片先在本端落盘，离线时捕获、编辑和查看不受影响。
- Markdown 主库：一个成果一个 `.md` 文件，SQLite 保存派生索引、同步游标和本地操作/撤销账本。Markdown 仍是成果正文权威副本；可撤销的前一版本仅在本地账本短暂保留，现采用 10 分钟窗口。
- AI 秘书对话：会话管理、SSE 多轮工具回复；按会话保存读取/新增/修改删除权限，表内内容操作默认执行并可撤销，表结构变更在当前对话确认。
- 图片输入：相册、拍照、Android 图片分享、自动缩放和 EXIF 清理。
- 笔记式表：三个不可删除的默认收纳表和可自定义表；每张表可写正文并混合收纳笔记、待办、未来日程和事件，支持六类自定义字段及整表回收恢复。
- 首页与日历：首页保留安排、待办和笔记区块，并可排序展示表模块；日历只投影表内带业务时间的待办、日程与事件，支持按表筛选，不复制或存储日历条目。
- 受控 AI 与知识：AI 按表检索并执行表内内容增改删和跨表移动；新增/删除表及字段变更在聊天卡片确认。普通知识进入表，全局知识继续独立管理并逐项确认。
- 行动与同步：保留捕获审核、旧草稿迁入、同步冲突处理和设置入口；没有独立待处理页。跨设备云盘同步和通知尚未接入。
- 系统接入：Android 注册 `ACTION_SEND` 与 `ACTION_PROCESS_TEXT`，支持从其他 App 分享文本和图片。
- 多端形态：同一套 Flutter 代码适配手机、平板、Windows 和 Web 预览。

## 项目交接

每次在本项目开启新对话，先读本 README，再读 [RM_HANDOFF.md](RM_HANDOFF.md) 获取最新交接状态，并遵守 [AGENTS.md](AGENTS.md)。项目内正式修改同步更新 RM_HANDOFF。

## 当前进展

秘书已改为 AppShell 内的常驻页面：手机/宽屏保留全局导航，新建、历史会话和系统分享均在秘书页内切换；主页面往返保留当前会话草稿和阅读状态，回复生成不中断。主机定向 UI 与跨宽度用例通过；当前本机 Android 集成测试受 Gradle/Java 与模拟器环境阻塞，详见 [本轮验证记录](test-results/secretary-embedded-20261031/VALIDATION.md)。架构约定见 [ADR 0022](docs/adr/0022-persistent-embedded-secretary-page.md)。

表与笔记改版已细化为 [10 个工作包、80 个执行步骤](docs/table-notebook-implementation-plan.md)。
P3本地数据层首轮已实现：SQLite v10恢复账本、单条内容撤销、整表30天恢复/到期清理，以及“通知事件与原日程同批更新/撤销”。P5b新增的字段删除恢复账本从schema v9升级到v10。21项P3 repository/index用例及相关 analyzer 通过；Android 15 AVD默认表重启核验通过。完整状态以 `RM_HANDOFF.md` 与执行计划为准。
P4 迁移预检/暂存首轮已实现：可判定旧成果映射、备份 vault 与 SQLite/会话/设置并关联 journal，支持重放和 hash 回滚。Android/Windows 容量探测已接入。发现旧资料时应用启动进入只读预检；用户确认后可在本地生成新格式副本，源件保留。完成后主应用可继续使用表、首页、日历、秘书、全局知识和设置；非全局旧源保持只读，旧同步入口关闭。主机和 AVD 的迁移验证只用合成资料。
P5a 已将“事项”导航换成“表与笔记”列表，支持默认表/自定义表浏览、创建/改名/删除与 30 天恢复，表正文编辑及笔记/待办/日程/事件的基本新增编辑。P5b 接入六类字段和值、字段删除恢复和安全跨表移动；P5c 增加选项稳定 ID 编辑、阻止删除仍被使用的选项，以及回收站表名/内容预览/剩余期限/整表恢复。SQLite 索引为 v10。P5c定向主机用例25/25、Android 15 AVD 1/1通过，见 `test-results/table-notebook-p5c-20261030/VALIDATION.md`。
P6首轮已将日历改为表内待办/日程/带发生时间事件的只读投影，支持按表筛选和选中日期快速创建；首页今日安排、待办和普通笔记从表读取，并可添加/移除/排序表模块，默认显示五行、可展开。P6定向主机测试28/28、Android15 AVD首页/日历/回收站流程1/1通过。
P5表列表、详情、字段管理和内容编辑器已通过320/800/1280宽度下的主机响应式检查（26/26相关用例）；检查未包含实际截图美术走查，详情见 `test-results/table-notebook-p5d-responsive-20261030/VALIDATION.md`。
P7已接通 AI 按表检索和表内内容操作；表结构变更在聊天卡片确认。P8首页笔记区采用参考图的分组卡片，表管理作为单独视图；旧事项/待处理入口已替换。P9 Android Debug APK 已直接安装到原本没有 Aitext 数据的 Android 15 AVD；应用内确认迁移四条合成旧资料后，首页、日历、秘书、表页与全局知识入口均可达，旧事项跳转新表、旧同步入口关闭。强制停止并重启后，表/条目 ID、正文、关系均读回，四个旧源文件的 SHA-256 未变。完整验证矩阵与候选哈希见[本轮验证记录](test-results/table-notebook-p8-p9-20261030/VALIDATION.md)。真实用户资料未迁移；v1.2.0 已发布，但 Android 秘书页 AVD 交互与 Windows 启动验收仍未完成。

2026-10-29 已启动表与笔记改版：三个默认表仅兜底且不可删除，表混合收纳内容；日历只显示表内正式内容，首页可排序展示表模块。AI 内容操作默认免逐次确认，表结构操作在对话确认；普通知识进表，全局知识独立审批。首版支持六种自定义字段；调整通知保留为事件并更新原日程，自定义表及内容可在 30 天内整表恢复。旧事项迁移保留正文和关联内容。完整需求见[改版规划](docs/table-notebook-redesign-plan.md)，执行顺序和代码状态见[执行计划](docs/table-notebook-implementation-plan.md)。

`v1.2.0` 已发布并完成资产与签名核验；模拟器交互与 Windows 启动验收状态以[发行说明](docs/releases/v1.2.0.md)、[发布验证记录](test-results/v1.2.0-release-prep/VALIDATION.md)、[发布验收记录](test-results/v1.2.0-release-acceptance-20261101/VALIDATION.md)及 GitHub Actions 为准。

后续产品工作包括补齐前端高保真状态稿和剩余页面视觉细节，以及接入 OneDrive 双向同步、百度网盘归档和跨端同步。真实云盘与通知能力目前尚未接入。

改版规格见[前端方案](docs/frontend-visual-redesign-plan.md)。产品决策与项目术语见[ADR 索引](docs/adr/README.md)和 [CONTEXT.md](CONTEXT.md)。

## 模型配置

设置页支持 OpenAI 兼容配置：

- `Base URL`
- 模型名
- API Key
- 是否允许图片发送到云端
- 高级能力覆盖、响应期限与上下文/图片上限

默认端点为 `https://api.deepseek.com`，默认模型为 `deepseek-flash`。

API Key 单独保存在本机安全存储中。设置导入/导出不包含 Key 或设备 ID。连接诊断会单独发送一条固定文本请求，不会发送历史消息或图片，也不会自动更改能力声明。

Web 版本仅用于界面预览。浏览器中的 Markdown 结果可能写入本地浏览器存储，但索引、会话与图片使用内存 adapter；不要把 Web 当作可靠备份或数据迁移来源。




## 许可证

Copyright (c) 2026 YuanFangCH

本项目采用 [MIT License](LICENSE)。
