import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

typedef SpeechTextCallback = void Function(String text, bool isFinal);

abstract class VoiceService extends ChangeNotifier {
  bool get canTrySpeechInput;
  bool get canSpeak;
  bool get isListening;
  bool get isSpeaking;
  String? get lastError;

  Future<bool> startListening(SpeechTextCallback onResult);
  Future<void> stopListening();
  Future<void> speak(String text);
  Future<void> stopSpeaking();
  Future<void> close();
}

/// Uses the operating system speech recognizer and TTS engine only.
/// Recognition requests on-device processing and never falls back to network.
class SystemVoiceService extends VoiceService {
  SystemVoiceService({SpeechToText? speechToText, FlutterTts? flutterTts})
    : _speech = speechToText,
      _tts = flutterTts;

  static const _maxSpeakCharacters = 24000;
  static const _speechLength = Duration(seconds: 45);
  static const _speechPause = Duration(seconds: 3);

  SpeechToText? _speech;
  FlutterTts? _tts;
  bool _ttsHandlersInitialized = false;
  bool _speechInitialized = false;
  bool _speechAvailable = false;
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _closed = false;
  String? _lastError;

  SpeechToText get _speechClient => _speech ??= SpeechToText();

  FlutterTts get _ttsClient {
    final tts = _tts ??= FlutterTts();
    if (!_ttsHandlersInitialized) {
      tts
        ..setStartHandler(() {
          if (_closed) return;
          _isSpeaking = true;
          notifyListeners();
        })
        ..setCompletionHandler(() {
          if (_closed) return;
          _isSpeaking = false;
          notifyListeners();
        })
        ..setCancelHandler(() {
          if (_closed) return;
          _isSpeaking = false;
          notifyListeners();
        })
        ..setErrorHandler((error) {
          if (_closed) return;
          _isSpeaking = false;
          _lastError = '系统朗读失败：$error';
          notifyListeners();
        });
      _ttsHandlersInitialized = true;
    }
    return tts;
  }

  @override
  bool get canTrySpeechInput =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.windows);

  @override
  bool get canSpeak =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.windows);

  @override
  bool get isListening => _isListening || (_speech?.isListening ?? false);

  @override
  bool get isSpeaking => _isSpeaking;

  @override
  String? get lastError => _lastError;

  @override
  Future<bool> startListening(SpeechTextCallback onResult) async {
    if (!canTrySpeechInput || _closed) return false;
    _lastError = null;
    final speech = _speechClient;
    if (!_speechInitialized) {
      _speechAvailable = await speech.initialize(
        onStatus: _handleSpeechStatus,
        onError: _handleSpeechError,
      );
      _speechInitialized = true;
    }
    if (!_speechAvailable) {
      _lastError = '设备系统语音识别不可用；请检查麦克风权限和离线中文语音包。';
      notifyListeners();
      return false;
    }
    try {
      final localeId = await _preferredChineseLocale(speech);
      await speech.listen(
        onResult: (SpeechRecognitionResult result) =>
            onResult(result.recognizedWords, result.finalResult),
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.dictation,
          partialResults: true,
          cancelOnError: true,
          onDevice: true,
          listenFor: _speechLength,
          pauseFor: _speechPause,
          localeId: localeId,
        ),
      );
      _isListening = speech.isListening;
      if (!_isListening) {
        _lastError = '离线语音识别未能启动；不会改用联网识别。';
      }
      notifyListeners();
      return _isListening;
    } on Object catch (error) {
      _isListening = false;
      _lastError = '离线语音识别无法启动：$error';
      notifyListeners();
      return false;
    }
  }

  Future<String?> _preferredChineseLocale(SpeechToText speech) async {
    final locales = await speech.locales();
    for (final locale in locales) {
      final normalized = locale.localeId.replaceAll('_', '-').toLowerCase();
      if (normalized == 'zh-cn') return locale.localeId;
    }
    for (final locale in locales) {
      if (locale.localeId.toLowerCase().startsWith('zh')) {
        return locale.localeId;
      }
    }
    return null;
  }

  void _handleSpeechStatus(String status) {
    if (_closed) return;
    _isListening = status == 'listening';
    if (status == 'done' || status == 'notListening') {
      _isListening = false;
    }
    notifyListeners();
  }

  void _handleSpeechError(SpeechRecognitionError error) {
    if (_closed) return;
    _isListening = false;
    _lastError =
        error.errorMsg.contains('on-device') ||
            error.errorMsg.contains('offline')
        ? '没有可用的离线语音识别；请安装中文语音包。'
        : '语音识别失败：${error.errorMsg}';
    notifyListeners();
  }

  @override
  Future<void> stopListening() async {
    final speech = _speech;
    if (!_speechInitialized || speech == null || !speech.isListening) return;
    await speech.stop();
    _isListening = false;
    notifyListeners();
  }

  @override
  Future<void> speak(String text) async {
    if (!canSpeak || _closed) return;
    final bounded = _plainSpeechText(text);
    if (bounded.isEmpty) return;
    if (_runeLength(bounded) > _maxSpeakCharacters) {
      throw StateError('朗读内容超过 24,000 字符上限。');
    }
    await stopSpeaking();
    final tts = _ttsClient;
    try {
      await tts.setLanguage('zh-CN');
      await tts.awaitSpeakCompletion(true);
      for (final chunk in _speechChunks(bounded, 2800)) {
        _isSpeaking = true;
        notifyListeners();
        await tts.speak(chunk);
        if (_closed) return;
      }
    } on Object catch (error) {
      _lastError = '系统朗读不可用：$error';
      rethrow;
    } finally {
      _isSpeaking = false;
      notifyListeners();
    }
  }

  @override
  Future<void> stopSpeaking() async {
    final tts = _tts;
    if (!_isSpeaking || tts == null) return;
    await tts.stop();
    _isSpeaking = false;
    notifyListeners();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final speech = _speech;
    final tts = _tts;
    try {
      if (speech?.isListening == true) await speech!.cancel();
      if (_isSpeaking && tts != null) await tts.stop();
    } finally {
      _isListening = false;
      _isSpeaking = false;
    }
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }

  String _plainSpeechText(String value) => value
      .replaceAll(RegExp(r'```[\s\S]*?```'), '代码块')
      .replaceAll(RegExp(r'!\[([^\]]*)\]\([^)]*\)'), r'$1')
      .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]*\)'), r'$1')
      .replaceAll(RegExp(r'[`*_>#]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Iterable<String> _speechChunks(String value, int limit) sync* {
    final runes = value.runes.toList(growable: false);
    var start = 0;
    while (start < runes.length) {
      var end = (start + limit).clamp(0, runes.length);
      if (end < runes.length) {
        final boundary = runes.lastIndexWhere(
          (rune) => const [
            0x3002,
            0xFF01,
            0xFF1F,
            0x2C,
            0x2E,
            0x3B,
            0x3A,
          ].contains(rune),
          end,
        );
        if (boundary > start + limit ~/ 2) end = boundary + 1;
      }
      yield String.fromCharCodes(runes.sublist(start, end));
      start = end;
    }
  }

  int _runeLength(String value) => value.runes.length;
}
