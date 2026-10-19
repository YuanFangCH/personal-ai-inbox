# 秘书角色、更名与全局知识库规划核对

日期：2026-10-20；范围：规划和权威文档，业务代码未修改。

## 读取与依据

- `git status --short --branch`：起始工作区干净，`main` 相对 `origin/main` ahead 3。
- `git config --get core.hooksPath`：正确指向本仓库 `.githooks`。
- 复用本会话已读的权威文档与 ADR；本轮复核 README、RM 当前状态、术语、改造计划、同步协议、ADR 0002/0006/0017、模型接入和 ADR 索引。
- `rg -n` 检索角色、应用名称和安装显示名：当前对话角色在 `app/lib/services/model_client.dart`；显示名分布于 Flutter、Android manifest、Windows runner/安装器和 Web 文件。只读取，不修改运行文件。
- 最终用户指令优先：名称为“懒狗秘书”；AI 为秘书/助理；全局基础事实自动识别或人工命令提议，写入须人工确认。共享、读取及删除确认范围已发出问题，未收到答复前不视为默认选项已获批准。

## 文档检查

- `git diff --check`：通过，无空白错误。
- PowerShell 内联校验 `git diff --unified=0 -- '*.md'` 新增行和 `git ls-files --others --exclude-standard -- '*.md'` 新文件中的本地链接：通过，16 个目标存在。输出 `PASS: 16 added/changed local Markdown links exist.`。
- PowerShell 比较 `git show HEAD:RM_HANDOFF.md` 的第 8 节历史尾部与当前文件：通过，仅规范化换行后比较，先前全部历史原样保留。输出 `PASS: previous handoff history preserved verbatim after newline normalization.`。
- 人工检查确认与建议的区分；三项待答问题保持待答，未以预选项代替用户确认。

## 未执行

仅文档，未执行自动化测试、构建、模型请求或同步。未验证更名升级、候选审批、权限、生效事实、日期运算等运行行为，功能尚未实现。未改同步协议或持久化 schema。
