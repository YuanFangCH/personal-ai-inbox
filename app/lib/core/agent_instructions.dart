typedef InstructionSnapshot = ({String markdown, String revision});
typedef InstructionEdit = ({String? oldText, String newText});
typedef InstructionUndo = ({
  String operationId,
  String revision,
  DateTime until,
});

sealed class InstructionReadResult {
  const InstructionReadResult();
}

final class InstructionsReady extends InstructionReadResult {
  const InstructionsReady(this.snapshot);
  final InstructionSnapshot snapshot;
}

final class InstructionsReadFailed extends InstructionReadResult {
  const InstructionsReadFailed(this.code, this.message);
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

bool requestsInstructionEdit(String text) {
  final firstLine = text.trimLeft().split(RegExp(r'[\r\n]')).first;
  if (RegExp(r'[?？]').hasMatch(firstLine)) return false;
  return RegExp(
    r'^(?:请\s*)?(?:(?:从今以后|从现在起|以后|今后|往后)\s*(?:请|都|一律|始终|默认|务必|不要|别|避免|优先|只|仅|每次|一直|保持|使用|采用|回答|回复|称呼|叫|提醒|记录|把|改成|改为|在|记住|我(?:希望|要求|想|要|不|喜欢|偏好|习惯))|(?:记住|长期记住|永久记住)\s*\S|(?:新增|添加|修改|更新|删除|清空)\s*(?:全局\s*)?(?:`?AGENTS\.md`?|秘书指令|长期规则)|(?:在\s*)?(?:`?AGENTS\.md`?|秘书指令|长期规则)\s*(?:中|里)?\s*(?:新增|添加|修改|更新|删除|清空))',
    caseSensitive: false,
  ).hasMatch(firstLine);
}
