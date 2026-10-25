import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as markdown;

abstract final class MarkdownPresentation {
  static MarkdownStyleSheet styleSheet(ThemeData theme) {
    final body = theme.textTheme.bodyLarge;
    final surface = theme.colorScheme.surfaceContainerLow;
    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: body,
      pPadding: const EdgeInsets.only(bottom: 12),
      h1: theme.textTheme.headlineSmall,
      h1Padding: const EdgeInsets.only(top: 20, bottom: 10),
      h2: theme.textTheme.titleLarge,
      h2Padding: const EdgeInsets.only(top: 20, bottom: 10),
      h3: theme.textTheme.titleMedium?.copyWith(fontSize: 18),
      h3Padding: const EdgeInsets.only(top: 16, bottom: 8),
      h4: body?.copyWith(fontWeight: FontWeight.w600),
      h5: body?.copyWith(fontWeight: FontWeight.w600),
      h6: body?.copyWith(fontWeight: FontWeight.w600),
      blockSpacing: 12,
      listIndent: 24,
      tableCellsPadding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 8,
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      blockquoteDecoration: BoxDecoration(
        color: surface,
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 2),
        ),
      ),
      codeblockPadding: const EdgeInsets.all(14),
      codeblockDecoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }

  static Map<String, MarkdownElementBuilder> get builders => {
    'pre': _CodeBlockBuilder(),
  };
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    markdown.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final source = element.textContent;
    if (source.isEmpty) return const SizedBox.shrink();
    var className = element.attributes['class'] ?? '';
    for (final child in element.children ?? const <markdown.Node>[]) {
      if (child is markdown.Element && child.tag == 'code') {
        className = child.attributes['class'] ?? className;
        break;
      }
    }
    final language = RegExp(r'(?:^|\s)language-([^\s]+)')
        .firstMatch(className)
        ?.group(1);
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (language != null && language.isNotEmpty) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      language,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '复制代码',
                    visualDensity: VisualDensity.compact,
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: source));
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(const SnackBar(content: Text('代码已复制')));
                      }
                    },
                    icon: const Icon(Icons.content_copy_outlined, size: 16),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ] else
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: '复制代码',
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: source));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('代码已复制')));
                    }
                  },
                  icon: const Icon(Icons.content_copy_outlined, size: 16),
                ),
              ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                source,
                style:
                    preferredStyle ??
                    theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                    ),
                textWidthBasis: TextWidthBasis.longestLine,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
