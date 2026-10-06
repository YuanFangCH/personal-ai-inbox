import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../widgets/common.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _model;
  final _apiKey = TextEditingController();
  ThemeMode _themeMode = ThemeMode.system;
  bool _allowImageEgress = true;
  bool _initialized = false;
  bool _apiKeyChanged = false;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }
    final settings = AppScope.of(context).settings;
    _baseUrl = TextEditingController(text: settings?.modelBaseUrl ?? '');
    _model = TextEditingController(text: settings?.modelName ?? '');
    _themeMode = settings?.themeMode ?? ThemeMode.system;
    _allowImageEgress = settings?.allowImageEgress ?? true;
    _initialized = true;
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final settings = app.settings;
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
                    hintText: settings?.hasModelKey == true && !_apiKeyChanged
                        ? '已保存，留空则不修改'
                        : '输入后保存到系统安全存储',
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    StatusPill(
                      label: settings?.hasModelKey == true ? '模型已配置' : '模型未配置',
                      icon: settings?.hasModelKey == true
                          ? Icons.check_circle_outline
                          : Icons.info_outline,
                      tone: settings?.hasModelKey == true
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
              ],
            ),
          ),
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
                  subtitle: SelectableText(settings?.deviceId ?? ''),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.folder_outlined),
                  title: const Text('Markdown 主库'),
                  subtitle: SelectableText(app.vaultRoot),
                ),
                const Divider(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: app.isBusy ? null : app.rebuildIndex,
                        icon: const Icon(Icons.refresh),
                        label: const Text('从 Markdown 重建索引'),
                      ),
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
    final app = AppScope.of(context);
    try {
      await app.saveSettings(
        themeMode: _themeMode,
        modelBaseUrl: _baseUrl.text,
        modelName: _model.text,
        apiKey: _apiKeyChanged ? _apiKey.text : null,
        allowImageEgress: _allowImageEgress,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('设置已保存')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}
