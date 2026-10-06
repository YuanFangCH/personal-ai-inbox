# Agent 协作规则

## 强制阅读顺序

任何 Agent 在修改文件、制定实现方案或执行验证前，必须：

1. 阅读 [RM_HANDOFF.md](./RM_HANDOFF.md)。
2. 阅读 [CONTEXT.md](./CONTEXT.md)，确认正式术语。
3. 阅读 [可执行方案](./docs/personal-ai-inbox-executable-plan.md)，确认目标、范围和架构。
4. 阅读 [同步协议](./docs/sync-protocol.md)，确认成果文件与同步不变量。
5. 阅读 [模型接入](./docs/model-integration.md)，确认模型边界和凭据规则。
6. 阅读 [ADR 索引](./docs/adr/README.md)，并读取与当前任务相关的 ADR。

不得只依据聊天记录继续工作。发现文档冲突时，先在 `RM_HANDOFF.md` 的“风险、阻塞与下一步”中记录，再向用户说明。

## 正式修改的定义

正式修改包括：

- 新增、修改、移动或删除任何仓库跟踪文件。
- 改变项目规范、架构决定、接口契约或实施顺序。
- 形成需要后续 Agent 继承的永久决定。

只读探索、非落盘分析和纯聊天回答不要求提交；一旦结论需要持久化，必须按正式修改处理。

## 开始任务

1. 运行 `git status --short --branch`，确认当前分支和工作区状态。
2. 检查 `core.hooksPath` 是否指向本仓库 `.githooks`。
3. 如果 hooks 未启用，运行 `powershell -ExecutionPolicy Bypass -File .\scripts\install-git-hooks.ps1`。
4. 对照 `RM_HANDOFF.md` 确认当前目标、已锁定决定、风险和下一步。
5. 明确本任务的产物、验证方式和完成标准。

## 结束任务

每项任务完成且验证通过后，必须：

1. 更新 `RM_HANDOFF.md` 的文档状态、进度、验证、风险、下一步和变更记录。
2. 在“变更记录”顶部插入一条记录，旧记录只追加、不改写、不删除。
3. 记录真实执行过的验证；未执行或失败的检查必须明确标注。
4. 暂存本任务的全部文件，包括 `RM_HANDOFF.md`。
5. 使用 Conventional Commit：`type(scope): 摘要` 或 `type: 摘要`。
6. 创建提交后运行 `git status --short`，确认工作区为空。

允许的类型：`chore`、`docs`、`feat`、`fix`、`refactor`、`test`、`build`、`ci`、`perf`、`revert`。

一个完成并验证过的任务只创建一个原子提交。任务过程中可以多次编辑，但提交前必须全部收敛。

## Git 强制门禁

- 禁止使用 `--no-verify` 绕过 hook。
- `pre-commit` 要求工作区已跟踪修改全部暂存，且没有未忽略的未跟踪文件。
- 有业务或文档变更时，`pre-commit` 要求 `RM_HANDOFF.md` 同步暂存。
- `pre-commit` 要求 `RM_HANDOFF.md` 的必要章节存在且非空。
- `commit-msg` 拒绝不符合 Conventional Commits 的标题。
- `pre-push` 要求工作区干净，且 `HEAD` 已包含 `RM_HANDOFF.md`。
- 不允许提交 API Key、OAuth 令牌、密码或其他秘密。

## 文档权威与维护

- `RM_HANDOFF.md` 是协作状态最高入口。
- `CONTEXT.md` 是术语权威。
- ADR 记录已经接受的架构决定；新增难以回退的决定时，先新增 ADR，再同步交接。
- 同步与数据语义以 `docs/sync-protocol.md` 为准。
- 研究文档用于事实和候选方案，不自动提升为架构决定。
- 不删除或改写历史交接记录；纠正错误时应新增记录并说明取代关系。
