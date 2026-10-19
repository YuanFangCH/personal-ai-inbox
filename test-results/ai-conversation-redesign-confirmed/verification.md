# AI 对话改造确认与方案核对

日期：2026-10-20。范围：规划、术语和 ADR；未修改业务代码。

## 检查范围与执行

- `git status --short --branch`：开始时工作区干净，`main` 相对 `origin/main` ahead 2。
- `git config --get core.hooksPath`：指向本仓库 `.githooks`，无需安装。
- 人工核对用户两轮答复：三组权限、初始全开、各会话独立、改删直接执行且可撤销、只操作成果、每次进入新对话、独立待处理页、语音转写/朗读、仅当前模型接口内置联网均已记录；通过。
- 源码只读核对：沿用上一轮的会话/UI/模型编排证据，本轮补查成果库写入入口、设置页、依赖清单；未改变相关代码，不重复运行既有测试。
- 官方资料只读核对：[思考模式](https://api-docs.deepseek.com/guides/thinking_mode/)、[工具调用](https://api-docs.deepseek.com/guides/tool_calls/)、[Search & Fetch](https://api-docs.deepseek.com/guides/search/)、[Chat Completions](https://api-docs.deepseek.com/api/create-chat-completion/)。未使用用户 Key 或发送项目内容到模型。
- 联网结论为文档与代码推断：当前 `/chat/completions` 的工具声明仅列函数，没有内置联网依据，因此计划禁用；独立 Search / Fetch 已按用户选择排除。这不等同于真实模型联网回归。

## 文档验证

- `git diff --check`：通过；无空白错误。
- PowerShell 内联校验 `git diff --unified=0 -- '*.md'` 的新增行及 `git ls-files --others --exclude-standard -- '*.md'` 的新文件链接：通过，16 个新增/修改的本地 Markdown 链接目标存在；输出 `PASS: 16 added/changed local Markdown links exist.`。不扩大到既有文档所有历史链接。
- `git diff --unified=0 -- RM_HANDOFF.md` 加人工检查：通过，原变更记录未删除或改写，新记录插入顶部；输出 `PASS: no removals in historical handoff records.`。
- 旧 ADR 仅增加取代注记；RM 第 8 节原有记录保留，新记录插入顶部。
- 规划建议（文件格式、统一撤销期限、技术来源和限额）与用户明确决定分开标注。

## 未执行与未覆盖

未运行自动化测试、静态分析、构建、设备/真实模型/搜索/语音请求；仅文档变更，按项目规则不运行。未验证迁移、权限、工具编排、撤销、文件解析或语音行为，功能尚待实现。
