import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

@JS('document.createElement')
external JSObject _createElement(JSString tag);

extension type _Frame(JSObject _) implements JSObject {
  external JSObject? get contentWindow;
  external set src(JSString value);
  external set title(JSString value);
  external void setAttribute(JSString key, JSString value);
  external void remove();
}

extension type _FrameWindow(JSObject _) implements JSObject {
  external void postMessage(JSAny? message, JSString targetOrigin);
}

class BrowserRecognizerScreen extends StatefulWidget {
  const BrowserRecognizerScreen({super.key});
  @override
  State<BrowserRecognizerScreen> createState() =>
      _BrowserRecognizerScreenState();
}

class _BrowserRecognizerScreenState extends State<BrowserRecognizerScreen> {
  static int _nextId = 0;
  late final String _view;
  late final _Frame _frame;
  String? _language;

  @override
  void initState() {
    super.initState();
    _view = 'iqtadi-browser-recognizer-${_nextId++}';
    _frame = _Frame(_createElement('iframe'.toJS));
    _frame.setAttribute('allow'.toJS, 'camera'.toJS);
    _frame.setAttribute('style'.toJS, 'width:100%;height:100%;border:0'.toJS);
    ui_web.platformViewRegistry.registerViewFactory(_view, (_) => _frame);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final language = Localizations.localeOf(context).languageCode;
    if (_language == null) {
      _frame.src = Uri.base
          .resolve('recognizer/index.html')
          .replace(queryParameters: {'lang': language})
          .toString()
          .toJS;
    } else if (_language != language) {
      final window = _frame.contentWindow;
      if (window != null) {
        _FrameWindow(window).postMessage(
            {'type': 'iqtadi-locale', 'locale': language}.jsify(),
            Uri.base.origin.toJS);
      }
    }
    _language = language;
    _frame.title = localized(context, 'تحليل حركات الصلاة على جهازك').toJS;
  }

  @override
  void dispose() {
    // Navigating away unloads the recognizer and releases camera/worker resources.
    _frame.src = 'about:blank'.toJS;
    _frame.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title:
                Text(localized(context, 'تحليل محلي — الصور تبقى على جهازك'))),
        body: HtmlElementView(viewType: _view),
      );
}
