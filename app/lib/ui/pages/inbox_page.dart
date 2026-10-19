import 'package:flutter/material.dart';

import 'conversation_page.dart';

/// The old inbox entry now opens directly into a fresh secretary conversation.
class InboxPage extends StatelessWidget {
  const InboxPage({super.key});

  @override
  Widget build(BuildContext context) => const ConversationPage(isRoot: true);
}
