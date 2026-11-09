import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../core/ai_policy.dart';
import '../domain/app_failure.dart';
import '../modules/home_widgets/home_widgets.dart';
import 'agent_tool_contracts.dart';

/// AI-facing adapter over the widget workspace.
///
/// Read results are filtered against the current table scope. Writes remain
/// owned by [WidgetWorkspace], which persists commands and receipts and runs
/// the supplied authorization callback again before committing.
class WidgetTools {
  WidgetTools(WidgetWorkspace workspace) : _workspace = workspace;

  final WidgetWorkspace _workspace;

  Future<String> listCardsForAgent(AiPolicy policy) async {
    if (!_canReadCards(policy)) return _readError('forbidden');
    final summaries = await _workspace.listCards(includeArchived: true);
    return jsonEncode({
      'status': 'ok',
      'data': {
        'cards': [
          for (final summary in summaries)
            if (_coversSpec(summary.spec, policy))
              {
                'card_id': summary.cardId,
                'revision': summary.revision,
                'archived': summary.archived,
                'visibility': summary.visibility.wireName,
              },
        ],
      },
    });
  }

  Future<String> getCardForAgent(String cardId, AiPolicy policy) async {
    if (!_canReadCards(policy)) return _readError('forbidden');
    final normalizedId = cardId.trim();
    if (normalizedId.isEmpty) return _readError('invalid_argument');
    final card = await _workspace.getCard(normalizedId);
    if (card == null || !_coversSpec(card.spec, policy)) {
      return jsonEncode({'status': 'not_found', 'card_id': normalizedId});
    }
    return jsonEncode({
      'status': 'ok',
      'data': {'card': card.toJson()},
    });
  }

  /// Executes a widget-manage call as an exclusive, recoverable write.
  Future<ChatWriteToolReceipt> manage(
    ChatWriteToolCall call, {
    required Future<AiPolicy?> Function() resolveCurrentPolicy,
  }) async {
    if (call.name != 'widget.manage') {
      return ChatWriteToolReceipt.rejected(
        code: 'invalid_argument',
        message: '不是桌面小组件管理工具。',
      );
    }
    final operationId = _operationId(call);

    late final CardCommand command;
    try {
      command = CardCommand.parse(call.arguments);
      if (!const {
        CardCommandKind.create,
        CardCommandKind.replace,
        CardCommandKind.archive,
        CardCommandKind.restore,
      }.contains(command.kind)) {
        throw const FormatException('unsupported widget command');
      }
    } on FormatException catch (error) {
      return ChatWriteToolReceipt.failed(
        operationId: operationId,
        code: WidgetCommandError.invalidArgument.wireName,
        message: '桌面小组件操作参数无效：${error.message}',
      );
    }

    final currentPolicy = await resolveCurrentPolicy();
    if (currentPolicy == null ||
        !await _isAuthorized(command, currentPolicy, includeCard: true)) {
      return ChatWriteToolReceipt.rejected(
        operationId: operationId,
        code: WidgetCommandError.forbidden.wireName,
        message: '当前会话没有桌面小组件管理权限，或卡片超出可读取表范围。',
      );
    }

    try {
      final receipt = await _workspace.applyCardCommand(
        command,
        operationId: operationId,
        authorize: () async {
          final latestPolicy = await resolveCurrentPolicy();
          return latestPolicy != null &&
              await _isAuthorized(command, latestPolicy, includeCard: true);
        },
      );
      final data = receipt.toJson();
      if (!receipt.succeeded) {
        return ChatWriteToolReceipt.failed(
          operationId: operationId,
          code:
              receipt.error?.wireName ??
              WidgetCommandError.storageError.wireName,
          message: receipt.message ?? '桌面小组件操作失败，未确认配置生效。',
          data: data,
        );
      }
      return ChatWriteToolReceipt.succeeded(
        operationId: receipt.operationId,
        message: _successMessage(command.kind, receipt.publishStatus),
        data: data,
      );
    } on AppOperationException catch (error) {
      final rawCode = error.failure.code;
      final code = WidgetCommandError.values
          .where((item) => item.wireName == rawCode)
          .firstOrNull
          ?.wireName;
      return ChatWriteToolReceipt.failed(
        operationId: operationId,
        code: code ?? WidgetCommandError.storageError.wireName,
        message: error.failure.message,
        retryable: error.failure.retryable,
      );
    } on ArgumentError catch (error) {
      return ChatWriteToolReceipt.failed(
        operationId: operationId,
        code: WidgetCommandError.invalidArgument.wireName,
        message: '桌面小组件操作参数无效：${error.message ?? error}',
      );
    } on FormatException catch (error) {
      return ChatWriteToolReceipt.failed(
        operationId: operationId,
        code: WidgetCommandError.invalidArgument.wireName,
        message: '桌面小组件操作参数无效：${error.message}',
      );
    } on Object catch (error) {
      return ChatWriteToolReceipt.failed(
        operationId: operationId,
        code: WidgetCommandError.storageError.wireName,
        message: '桌面小组件操作未完成：$error',
      );
    }
  }

  bool _canReadCards(AiPolicy policy) =>
      policy.decisionFor(AiPermissionAction.appSettingsRead) ==
          AiPolicyDecision.allow &&
      policy.decisionFor(AiPermissionAction.tableRead) ==
          AiPolicyDecision.allow;

  bool _coversSpec(CardSpec spec, AiPolicy policy) {
    if (policy.tableScope.isNone) return false;
    return switch (spec.sourceMode) {
      WidgetSourceMode.allTables => policy.tableScope.isAll,
      WidgetSourceMode.selectedTables => spec.referencedTableIds.every(
        policy.tableScope.covers,
      ),
    };
  }

  Future<bool> _isAuthorized(
    CardCommand command,
    AiPolicy policy, {
    required bool includeCard,
  }) async {
    if (policy.preset != AiPolicyPreset.fullAccess ||
        policy.decisionFor(AiPermissionAction.appSettingsUpdate) !=
            AiPolicyDecision.allow ||
        policy.decisionFor(AiPermissionAction.tableRead) !=
            AiPolicyDecision.allow) {
      return false;
    }
    final nextSpec = command.spec;
    if (nextSpec != null && !_coversSpec(nextSpec, policy)) return false;
    if (!includeCard || command.cardId == null) return true;
    final card = await _workspace.getCard(command.cardId!);
    return card == null || _coversSpec(card.spec, policy);
  }

  String _operationId(ChatWriteToolCall call) {
    final callIdentity = call.callId.trim().isEmpty
        ? '${call.round}:${call.index}'
        : call.callId;
    final digest = sha256
        .convert(utf8.encode('${call.turnId}\u0000$callIdentity'))
        .toString();
    return 'widget_${digest.substring(0, 32)}';
  }

  String _successMessage(
    CardCommandKind kind,
    WidgetPublishStatus publishStatus,
  ) {
    final action = switch (kind) {
      CardCommandKind.create => '已创建',
      CardCommandKind.replace => '已替换',
      CardCommandKind.archive => '已归档',
      CardCommandKind.restore => '已恢复',
      CardCommandKind.setVisibility => '已调整可见性',
      CardCommandKind.undo => '已撤销',
    };
    final publish = switch (publishStatus) {
      WidgetPublishStatus.published => '系统快照已发布。',
      WidgetPublishStatus.pending => '配置已提交，系统快照发布待完成。',
      WidgetPublishStatus.failed => '配置已提交，但系统快照发布失败。',
      WidgetPublishStatus.cleared => '配置已提交，系统快照已清除。',
      WidgetPublishStatus.blocked => '配置已提交，但迁移门阻断系统快照发布。',
    };
    return '$action桌面小组件配置；$publish';
  }

  String _readError(String code) {
    final message = switch (code) {
      'forbidden' => '当前会话没有桌面小组件读取权限。',
      _ => '桌面小组件读取参数无效。',
    };
    return jsonEncode({'error': message, 'code': code});
  }
}
