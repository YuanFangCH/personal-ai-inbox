import '../core/chat_models.dart';

/// Pure policy for selecting conversation context and deciding whether image
/// bytes may be added to a model request.
class ModelRequestPolicy {
  const ModelRequestPolicy();

  static const messageLimit = 20;
  static const imageMessageLimit = 4;
  static const imageLimit = 8;

  ModelRequestPlan prepare({
    required List<ChatMessage> history,
    required bool imagesAllowed,
    required String imageBlockReason,
    int messageLimit = ModelRequestPolicy.messageLimit,
    int imageMessageLimit = ModelRequestPolicy.imageMessageLimit,
    Set<String> excludedMessageIds = const {},
  }) {
    final complete = history
        .where(
          (message) =>
              !excludedMessageIds.contains(message.id) &&
              message.status != ChatMessageStatus.streaming &&
              (message.role != ChatRole.assistant ||
                  message.status == ChatMessageStatus.complete) &&
              (message.content.trim().isNotEmpty ||
                  message.attachments.isNotEmpty),
        )
        .toList(growable: false);
    final start = complete.length > messageLimit
        ? complete.length - messageLimit
        : 0;
    final selected = complete.sublist(start);
    ChatMessage? latestUser;
    for (final message in selected.reversed) {
      if (message.role == ChatRole.user) {
        latestUser = message;
        break;
      }
    }
    if (!imagesAllowed &&
        latestUser != null &&
        latestUser.content.trim().isEmpty &&
        latestUser.attachments.isNotEmpty) {
      return ModelRequestPlan(
        messages: selected,
        imageMessageIds: const {},
        imagesAllowed: false,
        blockedReason: '$imageBlockReason；图片仍保存在本机，请添加文字后重试。',
      );
    }

    final imageMessages = imagesAllowed
        ? selected
              .where((message) => message.attachments.isNotEmpty)
              .toList(growable: false)
        : const <ChatMessage>[];
    final imageStart = imageMessages.length > imageMessageLimit
        ? imageMessages.length - imageMessageLimit
        : 0;
    return ModelRequestPlan(
      messages: List.unmodifiable(selected),
      imageMessageIds: Set.unmodifiable(
        imageMessages.skip(imageStart).map((message) => message.id),
      ),
      imagesAllowed: imagesAllowed,
    );
  }
}

class ModelRequestPlan {
  const ModelRequestPlan({
    required this.messages,
    required this.imageMessageIds,
    required this.imagesAllowed,
    this.blockedReason,
  });

  final List<ChatMessage> messages;
  final Set<String> imageMessageIds;
  final bool imagesAllowed;
  final String? blockedReason;
}
