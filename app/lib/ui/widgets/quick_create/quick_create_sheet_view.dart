import 'package:flutter/material.dart';

import '../../../core/models.dart';
import '../../app_scope.dart';
import 'quick_create_core_fields.dart';
import 'quick_create_form_model.dart';
import 'quick_create_more_settings.dart';

class QuickCreateSheetView extends StatefulWidget {
  const QuickCreateSheetView({
    super.key,
    required this.initialDate,
    required this.initialType,
    this.initialStart,
  });

  final DateTime initialDate;
  final ResultType initialType;
  final DateTime? initialStart;

  @override
  State<QuickCreateSheetView> createState() => _QuickCreateSheetViewState();
}

class _QuickCreateSheetViewState extends State<QuickCreateSheetView> {
  late final QuickCreateFormModel _form;

  @override
  void initState() {
    super.initState();
    _form = QuickCreateFormModel(
      initialType: widget.initialType,
      initialDate: widget.initialDate,
      initialStart: widget.initialStart,
    );
  }

  @override
  void dispose() {
    _form.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableHeight = constraints.hasBoundedHeight
              ? constraints.maxHeight
              : MediaQuery.sizeOf(context).height;
          final sheetHeight = availableHeight * (bottomInset > 0 ? 0.98 : 0.88);
          if (sheetHeight <= 1) {
            return const SizedBox.shrink();
          }
          return SizedBox(
            height: sheetHeight,
            child: Column(
              children: [
                _QuickCreateHeader(
                  saving: _form.saving,
                  onClose: () => Navigator.pop(context),
                  onSave: _save,
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        QuickCreateCoreFields(
                          form: _form,
                          onChanged: _onChanged,
                        ),
                        if (_form.expanded)
                          Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: QuickCreateMoreSettings(
                              form: _form,
                              matters: app.matters,
                              onChanged: _onChanged,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _onChanged() {
    setState(() {});
  }

  Future<void> _save() async {
    final title = _form.title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('标题不能为空')));
      return;
    }
    if (_form.type == ResultType.event && !_form.end.isAfter(_form.start)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('结束时间必须晚于开始时间')));
      return;
    }
    setState(() => _form.setSaving(true));
    final app = AppScope.of(context);
    try {
      final document = await app.createManual(
        type: _form.type,
        title: title,
        body: _form.body.text,
        status: _form.status,
        due: _form.type == ResultType.todo ? _form.due : null,
        matterId: _form.matterId,
        start: _form.type == ResultType.event ? _form.start : null,
        end: _form.type == ResultType.event ? _form.end : null,
        allDay: _form.type == ResultType.event && _form.allDay,
        recurrence: _form.type == ResultType.event
            ? _form.recurrenceRule()
            : null,
        tags: _form.parsedTags(),
      );
      if (mounted) {
        Navigator.pop(context, document);
      }
    } finally {
      if (mounted) {
        setState(() => _form.setSaving(false));
      }
    }
  }
}

class _QuickCreateHeader extends StatelessWidget {
  const _QuickCreateHeader({
    required this.saving,
    required this.onClose,
    required this.onSave,
  });

  final bool saving;
  final VoidCallback onClose;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: '关闭',
            onPressed: saving ? null : onClose,
            icon: const Icon(Icons.close),
          ),
          const Expanded(
            child: Text(
              '快速新建',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            key: const Key('quick_create_save'),
            tooltip: '保存',
            onPressed: saving ? null : onSave,
            icon: saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
          ),
        ],
      ),
    );
  }
}
