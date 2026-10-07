import 'package:flutter/material.dart';

import '../../../core/models.dart';
import '../common.dart';
import 'quick_create_form_model.dart';
import 'quick_date_time_field.dart';

class QuickCreateMoreSettings extends StatelessWidget {
  const QuickCreateMoreSettings({
    super.key,
    required this.form,
    required this.matters,
    required this.onChanged,
  });

  final QuickCreateFormModel form;
  final List<ResultDocument> matters;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (form.type == ResultType.event) ...[
            Material(
              type: MaterialType.transparency,
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: form.allDay,
                title: const Text('全天'),
                onChanged: (value) {
                  form.setAllDay(value);
                  onChanged();
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: QuickDateTimeField(
                    label: '开始',
                    value: form.start,
                    allDay: form.allDay,
                    onChanged: (value) {
                      form.setStart(value);
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: QuickDateTimeField(
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
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<QuickCreateRepeatFrequency>(
              initialValue: form.repeatFrequency,
              decoration: const InputDecoration(
                labelText: '重复',
                prefixIcon: Icon(Icons.repeat),
              ),
              items: const [
                DropdownMenuItem(
                  value: QuickCreateRepeatFrequency.none,
                  child: Text('不重复'),
                ),
                DropdownMenuItem(
                  value: QuickCreateRepeatFrequency.daily,
                  child: Text('每天'),
                ),
                DropdownMenuItem(
                  value: QuickCreateRepeatFrequency.weekly,
                  child: Text('每周'),
                ),
                DropdownMenuItem(
                  value: QuickCreateRepeatFrequency.monthly,
                  child: Text('每月'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  form.setRepeatFrequency(value);
                  onChanged();
                }
              },
            ),
            if (form.repeatFrequency != QuickCreateRepeatFrequency.none) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<QuickCreateRepeatEnd>(
                initialValue: form.repeatEnd,
                decoration: const InputDecoration(
                  labelText: '重复结束',
                  prefixIcon: Icon(Icons.event_repeat),
                ),
                items: const [
                  DropdownMenuItem(
                    value: QuickCreateRepeatEnd.until,
                    child: Text('在日期结束'),
                  ),
                  DropdownMenuItem(
                    value: QuickCreateRepeatEnd.count,
                    child: Text('重复次数'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    form.setRepeatEnd(value);
                    onChanged();
                  }
                },
              ),
              const SizedBox(height: 12),
              if (form.repeatEnd == QuickCreateRepeatEnd.until)
                QuickDateTimeField(
                  label: '结束日期',
                  value: form.repeatUntil,
                  allDay: true,
                  onChanged: (value) {
                    form.setRepeatUntil(value);
                    onChanged();
                  },
                )
              else
                TextField(
                  controller: form.repeatCount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '重复次数',
                    prefixIcon: Icon(Icons.numbers),
                  ),
                ),
            ],
            const SizedBox(height: 12),
          ] else ...[
            QuickDateTimeField(
              label: '截止',
              value: form.due,
              allDay: false,
              onChanged: (value) {
                form.setDue(value);
                onChanged();
              },
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: form.tags,
            decoration: const InputDecoration(
              labelText: '标签',
              hintText: '用逗号或空格分隔',
              prefixIcon: Icon(Icons.tag),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: form.matterId,
            decoration: const InputDecoration(
              labelText: '所属事项',
              prefixIcon: Icon(Icons.account_tree_outlined),
            ),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('无')),
              for (final matter in matters)
                DropdownMenuItem<String?>(
                  value: matter.id,
                  child: Text(matter.title),
                ),
            ],
            onChanged: (value) {
              form.setMatterId(value);
              onChanged();
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<ResultStatus>(
            initialValue: form.status,
            decoration: const InputDecoration(
              labelText: '状态',
              prefixIcon: Icon(Icons.verified_outlined),
            ),
            items: [
              for (final value in ResultStatus.values)
                DropdownMenuItem(value: value, child: Text(value.label)),
            ],
            onChanged: (value) {
              if (value != null) {
                form.setStatus(value);
                onChanged();
              }
            },
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('quick_create_body'),
            controller: form.body,
            minLines: 5,
            maxLines: 10,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              labelText: 'Markdown 正文',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }
}
