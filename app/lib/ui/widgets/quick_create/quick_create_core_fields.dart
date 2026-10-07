import 'package:flutter/material.dart';

import '../../../core/models.dart';
import '../common.dart';
import 'quick_create_form_model.dart';
import 'quick_date_time_field.dart';

class QuickCreateCoreFields extends StatelessWidget {
  const QuickCreateCoreFields({
    super.key,
    required this.form,
    required this.onChanged,
  });

  final QuickCreateFormModel form;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('quick_create_title'),
          controller: form.title,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: '标题',
            hintText: '输入日程或待办内容',
            prefixIcon: Icon(Icons.edit_outlined),
          ),
        ),
        const SizedBox(height: 14),
        SegmentedButton<ResultType>(
          segments: const [
            ButtonSegment(
              value: ResultType.event,
              icon: Icon(Icons.event_outlined),
              label: Text('事件'),
            ),
            ButtonSegment(
              value: ResultType.todo,
              icon: Icon(Icons.check_circle_outline),
              label: Text('待办'),
            ),
          ],
          selected: {form.type},
          onSelectionChanged: (value) {
            form.setType(value.first);
            onChanged();
          },
        ),
        const SizedBox(height: 14),
        SurfacePanel(
          child: Column(
            children: [
              if (form.type == ResultType.event)
                Row(
                  children: [
                    Expanded(
                      child: QuickDateTimeField(
                        key: const Key('quick_create_start'),
                        label: '开始',
                        value: form.start,
                        allDay: form.allDay,
                        onChanged: (value) {
                          form.setStart(value);
                          onChanged();
                        },
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.arrow_forward),
                    ),
                    Expanded(
                      child: QuickDateTimeField(
                        key: const Key('quick_create_end'),
                        label: '结束',
                        value: form.end,
                        allDay: form.allDay,
                        onChanged: (value) {
                          form.setEnd(value);
                          onChanged();
                        },
                      ),
                    ),
                  ],
                )
              else
                QuickDateTimeField(
                  key: const Key('quick_create_due'),
                  label: '截止',
                  value: form.due,
                  allDay: false,
                  onChanged: (value) {
                    form.setDue(value);
                    onChanged();
                  },
                ),
              const SizedBox(height: 4),
              TextButton.icon(
                key: const Key('quick_create_more'),
                onPressed: () {
                  form.toggleExpanded();
                  onChanged();
                },
                icon: Icon(
                  form.expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                ),
                label: Text(form.expanded ? '收起设置' : '更多设置'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
