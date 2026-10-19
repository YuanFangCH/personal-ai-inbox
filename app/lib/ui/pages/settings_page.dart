import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../../domain/app_failure.dart';
import '../app_scope.dart';
import '../presentation/domain_presentation.dart';
import '../widgets/common.dart';
import 'global_knowledge_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _model;
  late final TextEditingController _headerTimeout;
  late final TextEditingController _idleTimeout;
  late final TextEditingController _totalTimeout;
  late final TextEditingController _contextLimit;
  late final TextEditingController _imageMessageLimit;
  late final TextEditingController _imageLimit;
  final _apiKey = TextEditingController();
  ThemeMode _themeMode = ThemeMode.system;
  bool? _visionOverride;
  bool? _toolCallsOverride;
  bool? _jsonOutputOverride;
  bool _allowImageEgress = true;
  AiPermissions _defaultAiPermissions = const AiPermissions();
  bool _initialized = false;
  bool _apiKeyChanged = false;
  bool _saving = false;
  bool _testingConnection = false;
  String? _saveError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }
    final settings = AppScope.preferences(context).settings;
    _baseUrl = TextEditingController(text: settings.modelBaseUrl);
    _model = TextEditingController(text: settings.modelName);
    _headerTimeout = TextEditingController(
      text: '${settings.responseHeaderTimeoutSeconds}',
    );
    _idleTimeout = TextEditingController(
      text: '${settings.streamIdleTimeoutSeconds}',
    );
    _totalTimeout = TextEditingController(
      text: '${settings.totalTimeoutSeconds}',
    );
    _contextLimit = TextEditingController(
      text: '${settings.contextMessageLimit}',
    );
    _imageMessageLimit = TextEditingController(
      text: '${settings.imageMessageLimit}',
    );
    _imageLimit = TextEditingController(text: '${settings.imageLimit}');
    _visionOverride = settings.capabilityOverrides.vision;
    _toolCallsOverride = settings.capabilityOverrides.toolCalls;
    _jsonOutputOverride = settings.capabilityOverrides.jsonOutput;
    _themeMode = materialThemeMode(settings.themeMode);
    _allowImageEgress = settings.allowImageEgress;
    _defaultAiPermissions = settings.defaultAiPermissions;
    final invalidSettings = settings.validate();
    if (invalidSettings.isNotEmpty) {
      _saveError = '当前配置需要修正：${invalidSettings.join('；')}';
    }
    _initialized = true;
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _model.dispose();
    _headerTimeout.dispose();
    _idleTimeout.dispose();
    _totalTimeout.dispose();
    _contextLimit.dispose();
    _imageMessageLimit.dispose();
    _imageLimit.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preferences = AppScope.preferences(context);
    final results = AppScope.results(context);
    final settings = preferences.settings;
    return PageFrame(
      title: '设置',
      subtitle: '本端配置与数据诊断',
      actions: [
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: const Text('保存'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SurfacePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeading(title: '外观'),
                const SizedBox(height: 12),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto_outlined),
                      label: Text('跟随系统'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode_outlined),
                      label: Text('浅色'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode_outlined),
                      label: Text('深色'),
                    ),
                  ],
                  selected: {_themeMode},
                  onSelectionChanged: (value) =>
                      setState(() => _themeMode = value.first),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SurfacePanel(
            padding: EdgeInsets.zero,
            child: ListTile(
              key: const Key('settings_global_knowledge'),
              leading: const Icon(Icons.lightbulb_outline),
              title: const Text('全局知识库'),
              subtitle: const Text('管理经确认并同步的基础事实'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const GlobalKnowledgePage(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SurfacePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeading(title: 'AI 权限默认值'),
                const SizedBox(height: 4),
                Text(
                  '只决定新对话的初始权限；已有对话保留自己的设置。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                _permissionSwitch(
                  title: '读取',
                  subtitle: '按需读取本端成果与其他对话',
                  value: _defaultAiPermissions.read,
                  onChanged: (value) => setState(() {
                    _defaultAiPermissions = _defaultAiPermissions.copyWith(
                      read: value,
                    );
                  }),
                ),
                _permissionSwitch(
                  title: '新增',
                  subtitle: '允许 AI 新建成果',
                  value: _defaultAiPermissions.create,
                  onChanged: (value) => setState(() {
                    _defaultAiPermissions = _defaultAiPermissions.copyWith(
                      create: value,
                    );
                  }),
                ),
                _permissionSwitch(
                  title: '修改与删除',
                  subtitle: '允许 AI 按要求修改或删除成果',
                  value: _defaultAiPermissions.modifyDelete,
                  onChanged: (value) => setState(() {
                    _defaultAiPermissions = _defaultAiPermissions.copyWith(
                      modifyDelete: value,
                    );
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SurfacePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeading(title: '云端模型'),
                const SizedBox(height: 12),
                TextField(
                  controller: _baseUrl,
                  decoration: const InputDecoration(
                    labelText: 'Base URL',
                    prefixIcon: Icon(Icons.link),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _model,
                  decoration: const InputDecoration(
                    labelText: '模型',
                    prefixIcon: Icon(Icons.memory),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _apiKey,
                  obscureText: true,
                  onChanged: (_) => _apiKeyChanged = true,
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    prefixIcon: const Icon(Icons.key_outlined),
                    hintText: settings.hasModelKey && !_apiKeyChanged
                        ? '已保存，留空则不修改'
                        : '输入后保存到系统安全存储',
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    StatusPill(
                      label: settings.hasModelKey ? '模型已配置' : '模型未配置',
                      icon: settings.hasModelKey
                          ? Icons.check_circle_outline
                          : Icons.info_outline,
                      tone: settings.hasModelKey
                          ? StatusTone.positive
                          : StatusTone.warning,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '密钥不写入 Markdown 或 Git，也不会进入日志。',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Material(
                  color: Colors.transparent,
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _allowImageEgress,
                    onChanged: (value) =>
                        setState(() => _allowImageEgress = value),
                    title: const Text('允许图片发送到云端'),
                    subtitle: const Text('关闭后聊天页不能选择、拍照或接收分享图片'),
                  ),
                ),
                const Divider(height: 24),
                OutlinedButton.icon(
                  onPressed: _testingConnection || _saving
                      ? null
                      : _testConnection,
                  icon: _testingConnection
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check),
                  label: const Text('测试模型连接'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SurfacePanel(
            child: Material(
              type: MaterialType.transparency,
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('高级模型设置'),
                subtitle: const Text('能力覆盖、超时和上下文上限'),
                children: [
                  _capabilityDropdown(
                    label: '图片能力',
                    value: _visionOverride,
                    onChanged: (value) =>
                        setState(() => _visionOverride = value),
                  ),
                  _capabilityDropdown(
                    label: '工具调用能力',
                    value: _toolCallsOverride,
                    onChanged: (value) =>
                        setState(() => _toolCallsOverride = value),
                  ),
                  _capabilityDropdown(
                    label: 'JSON 输出能力',
                    value: _jsonOutputOverride,
                    onChanged: (value) =>
                        setState(() => _jsonOutputOverride = value),
                  ),
                  const SizedBox(height: 12),
                  _numberField(_headerTimeout, '响应头等待（5–120 秒）'),
                  _numberField(_idleTimeout, '流空闲期限（10–180 秒）'),
                  _numberField(_totalTimeout, '请求总时限（30–600 秒）'),
                  _numberField(_contextLimit, '上下文消息数（2–20）'),
                  _numberField(_imageMessageLimit, '含图历史消息数（0–4）'),
                  _numberField(_imageLimit, '图片总数（0–8）'),
                ],
              ),
            ),
          ),
          if (_saveError != null) ...[
            const SizedBox(height: 8),
            Text(
              _saveError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          SurfacePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeading(title: '数据'),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.fingerprint),
                  title: const Text('设备 ID'),
                  subtitle: SelectableText(settings.deviceId),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.folder_outlined),
                  title: const Text('Markdown 主库'),
                  subtitle: SelectableText(results.vaultRoot),
                ),
                const Divider(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving ? null : _rebuildIndex,
                        icon: const Icon(Icons.refresh),
                        label: const Text('从 Markdown 重建索引'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _exportSettings,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('导出可移植设置'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _importSettings,
                      icon: const Icon(Icons.download),
                      label: const Text('导入设置'),
                    ),
                    TextButton.icon(
                      onPressed: _saving ? null : _restoreDefaults,
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('恢复默认'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await AppScope.preferences(context).update(
        themeMode: themePreference(_themeMode),
        modelBaseUrl: _baseUrl.text,
        modelName: _model.text,
        apiKey: _apiKeyChanged ? _apiKey.text : null,
        allowImageEgress: _allowImageEgress,
        defaultAiPermissions: _defaultAiPermissions,
        capabilityOverrides: ModelCapabilityOverrides(
          vision: _visionOverride,
          toolCalls: _toolCallsOverride,
          jsonOutput: _jsonOutputOverride,
        ),
        responseHeaderTimeoutSeconds: _intOrInvalid(_headerTimeout),
        streamIdleTimeoutSeconds: _intOrInvalid(_idleTimeout),
        totalTimeoutSeconds: _intOrInvalid(_totalTimeout),
        contextMessageLimit: _intOrInvalid(_contextLimit),
        imageMessageLimit: _intOrInvalid(_imageMessageLimit),
        imageLimit: _intOrInvalid(_imageLimit),
      );
      _saveError = null;
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('设置已保存')));
    } catch (error) {
      if (mounted) {
        setState(() => _saveError = _failureMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Widget _capabilityDropdown({
    required String label,
    required bool? value,
    required ValueChanged<bool?> onChanged,
  }) => DropdownButtonFormField<String>(
    initialValue: value == null
        ? 'default'
        : value
        ? 'enabled'
        : 'disabled',
    decoration: InputDecoration(labelText: label),
    items: const [
      DropdownMenuItem(value: 'default', child: Text('模型默认')),
      DropdownMenuItem(value: 'enabled', child: Text('强制启用')),
      DropdownMenuItem(value: 'disabled', child: Text('强制关闭')),
    ],
    onChanged: (selection) => onChanged(switch (selection) {
      'enabled' => true,
      'disabled' => false,
      _ => null,
    }),
  );

  Widget _permissionSwitch({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: Text(subtitle),
    value: value,
    onChanged: onChanged,
  );

  Widget _numberField(TextEditingController controller, String label) =>
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: label),
        ),
      );

  int _intOrInvalid(TextEditingController controller) =>
      int.tryParse(controller.text.trim()) ?? -1;

  String _failureMessage(Object error) => error is AppOperationException
      ? error.failure.message
      : error is ArgumentError
      ? error.message?.toString() ?? '设置值无效'
      : error.toString();

  void _loadSettingsIntoFields(AppSettings settings) {
    _baseUrl.text = settings.modelBaseUrl;
    _model.text = settings.modelName;
    _themeMode = materialThemeMode(settings.themeMode);
    _allowImageEgress = settings.allowImageEgress;
    _defaultAiPermissions = settings.defaultAiPermissions;
    _visionOverride = settings.capabilityOverrides.vision;
    _toolCallsOverride = settings.capabilityOverrides.toolCalls;
    _jsonOutputOverride = settings.capabilityOverrides.jsonOutput;
    _headerTimeout.text = '${settings.responseHeaderTimeoutSeconds}';
    _idleTimeout.text = '${settings.streamIdleTimeoutSeconds}';
    _totalTimeout.text = '${settings.totalTimeoutSeconds}';
    _contextLimit.text = '${settings.contextMessageLimit}';
    _imageMessageLimit.text = '${settings.imageMessageLimit}';
    _imageLimit.text = '${settings.imageLimit}';
  }

  Future<void> _testConnection() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('测试模型连接'),
        content: const Text('将发送 1 次网络请求，只包含固定测试文本，不会发送历史消息或图片。继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('发送测试请求'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _testingConnection = true;
      _saveError = null;
    });
    try {
      final reply = await AppScope.conversations(context).testModelConnection();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              reply.isEmpty
                  ? '文本连接成功；图片、工具和 JSON 能力未自动探测'
                  : '文本连接成功；图片、工具和 JSON 能力未自动探测。回复：$reply',
            ),
          ),
        );
    } catch (error) {
      if (mounted) setState(() => _saveError = _failureMessage(error));
    } finally {
      if (mounted) setState(() => _testingConnection = false);
    }
  }

  Future<void> _exportSettings() async {
    try {
      final portable = await AppScope.preferences(context)
          .exportPortableSettings();
      await Clipboard.setData(
        ClipboardData(
          text: const JsonEncoder.withIndent('  ').convert(portable),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('可移植设置 JSON 已复制；密钥和设备 ID 未导出')),
        );
    } catch (error) {
      if (mounted) setState(() => _saveError = _failureMessage(error));
    }
  }

  Future<void> _importSettings() async {
    final input = TextEditingController();
    try {
      final text = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导入可移植设置'),
          content: TextField(
            controller: input,
            minLines: 6,
            maxLines: 12,
            decoration: const InputDecoration(hintText: '粘贴导出的 JSON'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, input.text),
              child: const Text('预览差异'),
            ),
          ],
        ),
      );
      if (text == null || !mounted) return;
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('设置文件必须是 JSON 对象');
      }
      final current = AppScope.preferences(context).settings;
      final nextModel = decoded['model_name'];
      final nextUrl = decoded['model_base_url'];
      if (nextModel is! String || nextUrl is! String) {
        throw const FormatException('设置文件缺少模型或 Base URL');
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认导入'),
          content: Text(
            '${_portableDiff(decoded, current)}\n\n'
            '设备 ID 与 API Key 保持本机原值。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('返回'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('校验并导入'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await AppScope.preferences(context).importPortableSettings(decoded);
      if (!mounted) return;
      _loadSettingsIntoFields(AppScope.preferences(context).settings);
      setState(() => _saveError = null);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('设置导入完成')));
    } catch (error) {
      if (mounted) setState(() => _saveError = _failureMessage(error));
    } finally {
      input.dispose();
    }
  }

  String _portableDiff(Map<String, dynamic> values, AppSettings current) {
    final currentValues = <String, Object?>{
      'theme_mode': current.themeMode.name,
      'model_base_url': current.modelBaseUrl,
      'model_name': current.modelName,
      'show_completed_todos': current.showCompletedTodos,
      'calendar_month_detailed': current.calendarMonthDetailed,
      'allow_image_egress': current.allowImageEgress,
      'default_ai_permissions': jsonEncode(
        current.defaultAiPermissions.toJson(),
      ),
      'response_header_timeout_seconds': current.responseHeaderTimeoutSeconds,
      'stream_idle_timeout_seconds': current.streamIdleTimeoutSeconds,
      'total_timeout_seconds': current.totalTimeoutSeconds,
      'context_message_limit': current.contextMessageLimit,
      'image_message_limit': current.imageMessageLimit,
      'image_limit': current.imageLimit,
    };
    const labels = <String, String>{
      'theme_mode': '主题',
      'model_base_url': 'Base URL',
      'model_name': '模型',
      'show_completed_todos': '显示已完成待办',
      'calendar_month_detailed': '详细月历',
      'allow_image_egress': '图片出网',
      'default_ai_permissions': 'AI 权限默认值',
      'response_header_timeout_seconds': '响应头等待',
      'stream_idle_timeout_seconds': '流空闲期限',
      'total_timeout_seconds': '请求总时限',
      'context_message_limit': '上下文消息数',
      'image_message_limit': '含图历史消息数',
      'image_limit': '图片总数',
    };
    final changes = <String>[];
    for (final entry in labels.entries) {
      final rawNext = values[entry.key];
      final next = entry.key == 'default_ai_permissions'
          ? jsonEncode(
              rawNext == null
                  ? const AiPermissions().toJson()
                  : (rawNext as Map).map(
                      (key, value) => MapEntry(key.toString(), value),
                    ),
            )
          : rawNext;
      final currentValue = currentValues[entry.key];
      if (next != currentValue) {
        changes.add('${entry.value}：$currentValue → $next');
      }
    }
    final nextCapabilities = values['capability_overrides'];
    final currentCapabilities = <String, Object?>{
      'vision': current.capabilityOverrides.vision,
      'tool_calls': current.capabilityOverrides.toolCalls,
      'json_output': current.capabilityOverrides.jsonOutput,
    };
    if (nextCapabilities is Map<String, dynamic> &&
        jsonEncode(nextCapabilities) != jsonEncode(currentCapabilities)) {
      changes.add(
        '模型能力覆盖：${jsonEncode(currentCapabilities)} → '
        '${jsonEncode(nextCapabilities)}',
      );
    }
    return changes.isEmpty ? '设置内容与当前配置相同。' : changes.join('\n');
  }

  Future<void> _restoreDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复默认设置？'),
        content: const Text('保留本机设备 ID 与 API Key，只重置其他配置。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复默认'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await AppScope.preferences(context).restoreDefaults();
      if (!mounted) return;
      _loadSettingsIntoFields(AppScope.preferences(context).settings);
      setState(() => _saveError = null);
    } catch (error) {
      if (mounted) setState(() => _saveError = _failureMessage(error));
    }
  }

  Future<void> _rebuildIndex() async {
    final report = await AppScope.results(context).rebuildIndex();
    if (!mounted) return;
    final errorPaths = report.diagnostics
        .take(2)
        .map((diagnostic) => diagnostic.path)
        .join('、');
    final message = report.failed == 0
        ? '扫描 ${report.scanned} 项，索引 ${report.indexed} 项'
        : '扫描完成：索引 ${report.indexed}/${report.scanned} 项，失败 ${report.failed} 项'
              '${errorPaths.isEmpty ? '' : '（$errorPaths）'}';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
