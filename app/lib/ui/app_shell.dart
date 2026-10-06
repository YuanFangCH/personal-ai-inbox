import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'pages/calendar_page.dart';
import 'pages/conversation_page.dart';
import 'pages/home_page.dart';
import 'pages/inbox_page.dart';
import 'pages/knowledge_page.dart';
import 'pages/matters_page.dart';
import 'pages/review_page.dart';
import 'pages/settings_page.dart';
import 'pages/sync_page.dart';
import 'pages/todos_page.dart';
import 'widgets/capture_sheet.dart';

enum AppPage {
  home('首页', Icons.space_dashboard_outlined),
  inbox('收件箱', Icons.inbox_outlined),
  calendar('日历', Icons.calendar_month_outlined),
  todos('待办', Icons.checklist_outlined),
  matters('事项', Icons.account_tree_outlined),
  knowledge('知识', Icons.menu_book_outlined),
  review('确认', Icons.rule_folder_outlined),
  sync('同步', Icons.sync_outlined),
  settings('设置', Icons.tune_outlined);

  const AppPage(this.label, this.icon);

  final String label;
  final IconData icon;
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppPage _page = AppPage.home;
  bool _startupChecked = false;
  String? _lastOpenedConversationId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_startupChecked) {
      return;
    }
    _startupChecked = true;
    _schedulePendingConversationOpen();
  }

  void _schedulePendingConversationOpen() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final conversationId = AppScope.of(context)
          .consumePendingConversationId();
      if (conversationId != null &&
          conversationId != _lastOpenedConversationId) {
        _lastOpenedConversationId = conversationId;
        openConversationPage(context, conversationId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _schedulePendingConversationOpen();
    final controller = AppScope.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        final content = AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: KeyedSubtree(
            key: ValueKey('page_${_page.name}'),
            child: _pageFor(_page),
          ),
        );
        return Scaffold(
          resizeToAvoidBottomInset: false,
          body: Stack(
            children: [
              Positioned.fill(
                child: SafeArea(
                  bottom: false,
                  child: wide
                      ? Row(
                          children: [
                            _WideNavigation(
                              selected: _page,
                              onSelected: (page) =>
                                  setState(() => _page = page),
                              extended: constraints.maxWidth >= 1220,
                            ),
                            const VerticalDivider(width: 1),
                            Expanded(child: content),
                          ],
                        )
                      : content,
                ),
              ),
              if (controller.isBusy)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          ),
          floatingActionButton: constraints.maxWidth < 600
              ? null
              : FloatingActionButton.extended(
                  key: const Key('capture_button'),
                  onPressed: _page == AppPage.inbox
                      ? _newConversation
                      : () => showCaptureSheet(context),
                  icon: Icon(
                    _page == AppPage.inbox
                        ? Icons.add_comment_outlined
                        : Icons.add,
                  ),
                  label: Text(_page == AppPage.inbox ? '新对话' : '收下'),
                  tooltip: _page == AppPage.inbox ? '新对话' : '捕获',
                ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _compactIndex(_page),
                  onDestinationSelected: (index) {
                    if (index < 4) {
                      setState(() => _page = AppPage.values[index]);
                    } else {
                      _showMore();
                    }
                  },
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(
                        Icons.space_dashboard_outlined,
                        key: Key('nav_home'),
                      ),
                      selectedIcon: Icon(
                        Icons.space_dashboard,
                        key: Key('nav_home'),
                      ),
                      label: '首页',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.inbox_outlined, key: Key('nav_inbox')),
                      selectedIcon: Icon(Icons.inbox, key: Key('nav_inbox')),
                      label: '收件箱',
                    ),
                    NavigationDestination(
                      icon: Icon(
                        Icons.calendar_month_outlined,
                        key: Key('nav_calendar'),
                      ),
                      selectedIcon: Icon(
                        Icons.calendar_month,
                        key: Key('nav_calendar'),
                      ),
                      label: '日历',
                    ),
                    NavigationDestination(
                      icon: Icon(
                        Icons.checklist_outlined,
                        key: Key('nav_todos'),
                      ),
                      selectedIcon: Icon(
                        Icons.checklist,
                        key: Key('nav_todos'),
                      ),
                      label: '待办',
                    ),
                    NavigationDestination(
                      icon: Icon(
                        Icons.grid_view_outlined,
                        key: Key('nav_more'),
                      ),
                      selectedIcon: Icon(Icons.grid_view, key: Key('nav_more')),
                      label: '更多',
                    ),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _newConversation() async {
    final conversation = await AppScope.of(context).createConversation();
    if (mounted) {
      await openConversationPage(context, conversation.id);
    }
  }

  Widget _pageFor(AppPage page) {
    return switch (page) {
      AppPage.home => const HomePage(),
      AppPage.inbox => const InboxPage(),
      AppPage.calendar => const CalendarPage(),
      AppPage.todos => const TodosPage(),
      AppPage.matters => const MattersPage(),
      AppPage.knowledge => const KnowledgePage(),
      AppPage.review => const ReviewPage(),
      AppPage.sync => const SyncPage(),
      AppPage.settings => const SettingsPage(),
    };
  }

  int _compactIndex(AppPage page) {
    if (page.index <= 3) {
      return page.index;
    }
    return 4;
  }

  Future<void> _showMore() async {
    final selected = await showModalBottomSheet<AppPage>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final page in const [
                  AppPage.matters,
                  AppPage.knowledge,
                  AppPage.review,
                  AppPage.sync,
                  AppPage.settings,
                ])
                  ListTile(
                    key: Key('sheet_nav_${page.name}'),
                    leading: Icon(page.icon),
                    title: Text(page.label),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(context, page),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _page = selected);
    }
  }
}

class _WideNavigation extends StatelessWidget {
  const _WideNavigation({
    required this.selected,
    required this.onSelected,
    required this.extended,
  });

  final AppPage selected;
  final ValueChanged<AppPage> onSelected;
  final bool extended;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NavigationRail(
      extended: extended,
      minExtendedWidth: 196,
      selectedIndex: selected.index,
      onDestinationSelected: (index) => onSelected(AppPage.values[index]),
      leading: Padding(
        padding: EdgeInsets.fromLTRB(extended ? 16 : 0, 20, 0, 18),
        child: extended
            ? Row(
                children: [
                  Icon(Icons.all_inbox, color: theme.colorScheme.primary),
                  const SizedBox(width: 9),
                  Text(
                    '个人收件箱',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              )
            : Icon(Icons.all_inbox, color: theme.colorScheme.primary),
      ),
      destinations: [
        for (final page in AppPage.values)
          NavigationRailDestination(
            icon: Icon(page.icon, key: Key('nav_${page.name}')),
            selectedIcon: Icon(
              _selectedIcon(page),
              key: Key('nav_${page.name}'),
            ),
            label: Text(page.label),
          ),
      ],
    );
  }

  IconData _selectedIcon(AppPage page) {
    return switch (page) {
      AppPage.home => Icons.space_dashboard,
      AppPage.inbox => Icons.inbox,
      AppPage.calendar => Icons.calendar_month,
      AppPage.todos => Icons.checklist,
      AppPage.matters => Icons.account_tree,
      AppPage.knowledge => Icons.menu_book,
      AppPage.review => Icons.rule_folder,
      AppPage.sync => Icons.sync,
      AppPage.settings => Icons.tune,
    };
  }
}
