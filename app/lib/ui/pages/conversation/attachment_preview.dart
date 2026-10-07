part of '../conversation_page.dart';

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({required this.app, required this.attachment});

  final AppController app;
  final ChatAttachment attachment;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: app.readAttachment(attachment),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          return const SizedBox.square(
            dimension: 120,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            bytes,
            width: 180,
            height: 160,
            fit: BoxFit.cover,
          ),
        );
      },
    );
  }
}
