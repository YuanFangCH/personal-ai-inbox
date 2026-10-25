import 'package:flutter/material.dart';

import 'conversation_page.dart';

/// The old inbox entry now opens directly into a fresh secretary conversation.
class InboxPage extends StatelessWidget {
  const InboxPage({
    super.key,
    this.isWide = false,
    this.onReturnHome,
    this.onNavigate,
  });

  final bool isWide;
  final VoidCallback? onReturnHome;
  final ValueChanged<String>? onNavigate;

  @override
  Widget build(BuildContext context) => ConversationPage(
    isRoot: true,
    isWide: isWide,
    onReturnHome: onReturnHome,
    onNavigate: onNavigate,
  );
}
