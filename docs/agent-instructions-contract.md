# 秘书长期指令文件合同

本合同定义本机 `AGENTS.md` 的存储、注入、编辑和旧全局知识归档行为。架构决定见 [ADR 0028](adr/0028-secretary-instructions-file.md)。

## 文件布局

| 路径（相对 Vault 根） | 用途 |
|---|---|
| `AGENTS.md` | 唯一权威的长期秘书指令，UTF-8，最大 8 KiB |
| `.local/agent-instructions/pending.json` | 原子提交期间的崩溃恢复记录 |
| `.local/agent-instructions/latest.json` | 最近一次撤销信息；有效期 10 分钟 |
| `.local/agent-instructions/receipts/<operation-id>.json` | 幂等写入回执 |
| `.local/global-knowledge-retirement/v1/archive.zip.base64` | 用户确认后生成的旧知识 ZIP，Base64 存储 |

`.local` 内容不得作为模型上下文、普通成果、同步对象或 UI 用户文件暴露。旧索引中的全局知识只为归档迁移保留，不再参与 Agent 检索、写入或审批。

## Dart 接口

核心值和结果定义在 `app/lib/core/agent_instructions.dart`：

```dart
typedef InstructionSnapshot = ({String markdown, String revision});
typedef InstructionEdit = ({String? oldText, String newText});
typedef InstructionUndo = ({String operationId, String revision, DateTime until});

sealed class InstructionReadResult {}
final class InstructionsReady extends InstructionReadResult {
  final InstructionSnapshot snapshot;
}
final class InstructionsReadFailed extends InstructionReadResult {
  final String code;
  final String message;
}

enum InstructionWriteStatus { applied, unchanged, conflict, rejected, failed }
typedef InstructionWriteResult = ({
  InstructionWriteStatus status,
  String? operationId,
  String? revision,
  DateTime? undoUntil,
  String? removed,
  String? added,
  String? code,
  String message,
});
```

`AgentInstructionsStore` (`app/lib/data/agent_instructions_store.dart`) 的 public contract：

```dart
Future<InstructionReadResult> load();
Future<List<int>?> exportBytes();
Future<String?> repairRevision();
Future<InstructionWriteResult> save({
  required String expectedRevision,
  required String markdown,
});
Future<InstructionWriteResult> edit({
  required String operationId,
  required String expectedRevision,
  required List<InstructionEdit> edits,
  required Future<bool> Function() canCommit,
});
Future<InstructionWriteResult> undo({
  required String operationId,
  required String expectedRevision,
});
Future<InstructionUndo?> latestUndo();
```

`revision` 是文件原始 UTF-8 字节的 SHA-256 小写十六进制；缺失文件使用 `missing`。读取到无效 UTF-8 或超限文件时返回 `InstructionsReadFailed` 并阻止模型请求；设置页可显式修复。写入先检查 revision、编辑匹配唯一性和字节上限，再使用 Vault 原子写入；提交前 `canCommit` 必须为真。幂等重试返回原回执，操作 ID 复用但参数不同则拒绝。内容无变化返回 `unchanged`。写入结果不确定时返回 `failed`，调用者应重读当前 revision。

`repairRevision()` 仅返回已损坏/超限源文件的 `invalid:<sha256>` revision，以便设置页通过显式完整替换覆盖该版本；文件有效或缺失时返回 `null`。损坏原始字节不向调用者暴露。

编辑项按传入顺序定位唯一且非空的原文，原文不能缺失或多次出现，变更范围不能重叠。`oldText == null` 表示末尾追加，且只允许出现在最后一项；空文件直接追加，不额外插入换行。任何新内容超过 8 KiB UTF-8 都拒绝。成功变更可在 10 分钟内撤销；revision 不匹配、撤销记录过期或后续已有其他写入时拒绝撤销。

## Agent 请求与工具

`ChatService.streamReply` 每轮开始加载一次快照。非空指令以独立 `system` 消息注入请求，不写入 ChatRepository transcript。无法加载文件时本轮失败关闭，不悄悄跳过指令。

仅当设备完全体模式开启，且本轮指定的当前用户消息是无附件直接请求长期规则变更时，工具 schema 才包含：

- `agent_instructions_read()` → JSON `{ "revision": string, "markdown": string }`。
- `agent_instructions_edit({expected_revision, edits})`。每项格式为 `{ "old_text": string | null, "new_text": string }`；结果 JSON 包含 `status`、`message`、可选 `revision`、`undo_until`、`removed`、`added`。

写入前重新验证用户消息仍属于当前会话、角色为 user、无附件、文本满足长期指令请求规则；设备完全体模式仍开启且 `fullAgentModeRevision` 等于本轮开始值。设置开关每次发生状态切换递增此代际，因此关闭后重开也会撤销旧的在途授权。事务真正替换 `AGENTS.md` 前再次验证上述授权。模型工具参数自身不构成授权。

## 旧全局知识归档

`LegacyGlobalKnowledgeRetirement.preview()` 返回旧条目、候选、相关冲突副本数量和确认 revision。`archive(expectedRevision)` 只接受预览 revision 未变化的确认；ZIP 含原始 Markdown、候选 JSON、相关冲突副本和 manifest SHA-256。预览和归档使用相同的关联判定，包括候选目标 ID。写入归档后会重读归档并逐条校验；清理在仓库写锁内先验证 ZIP、manifest、活动源哈希及候选 digest/status 快照，再开始删除，避免恢复期间清除归档后变化的数据。已保存归档存在时允许重入并续跑未完成清理。旧全局知识不迁入 `AGENTS.md`，不纳入同步；归档导出由用户显式发起。

运行时 `ResultLibrary` 默认拒绝旧全局知识候选的创建、审批和重试；仅旧格式兼容测试可通过 `enableLegacyGlobalKnowledgeForTests` 显式启用旧状态构造。活动 UI、Agent 工具和同步均不启用该开关。
