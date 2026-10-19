# 检索约束规划核对

日期：2026-10-20。范围：仅文档，业务代码未改。

## 已执行

- `git status --short --branch`：起始工作区干净，`main` 相对 `origin/main` ahead 5。
- `git config --get core.hooksPath`：正确指向本仓库 `.githooks`。
- 读取 README、RM、已确认全局知识计划；复用本会话已读的其他权威文档，检索当前模型与成果模块和计划中的读取约束。
- 人工核对：非必要零检索、不额外云端判断、范围/片段/总限额、去重、缓存失效、停止条件和写前一致性检查保留均已记录。未改变三组权限、知识审批或联网范围。

## 提交前文档检查

- `git diff --check`：通过，无空白错误。
- PowerShell 内联检查 `git diff --unified=0 -- '*.md'` 新增行与 `git ls-files --others --exclude-standard -- '*.md'` 新文件的本地 Markdown 链接：通过，7 个目标存在；输出 `PASS: 7 added/changed local Markdown links exist.`。
- PowerShell 比较 `git show HEAD:RM_HANDOFF.md` 第 8 节历史尾部与当前文件（仅规范化换行）：通过，原记录未改写或删除。

## 未执行与未覆盖

仅文档，未运行自动化测试、构建、真实模型调用、性能或费用基准。预算值是初始实施建议，没有宣称实际减少的检索次数、费用或时延。未证明语义上每次检索均必要，也未扩大测试范围。
