import 'dart:async';
import 'dart:js_interop';

import 'local_prayer_reference_repository.dart';

@JS('document.createElement')
external JSObject _createElement(String tag);
@JS('document.body.appendChild')
external JSObject _append(JSObject node);
@JS('URL.createObjectURL')
external String _objectUrl(_JSBlob blob);
@JS('URL.revokeObjectURL')
external void _revokeObjectUrl(String url);

extension type _JSInput(JSObject _) implements JSObject {
  external set type(String value);
  external set accept(String value);
  external _JSFileList? get files;
  external set onchange(JSFunction? listener);
  external set oncancel(JSFunction? listener);
  external void click();
  external void remove();
}

extension type _JSFileList(JSObject _) implements JSObject {
  external _JSFile? item(int index);
}

extension type _JSFile(JSObject _) implements JSObject {
  external int get size;
  external JSPromise<JSString> text();
}

@JS('Blob')
extension type _JSBlob._(JSObject _) implements JSObject {
  external factory _JSBlob(JSArray<JSAny> parts, JSObject options);
}

extension type _JSAnchor(JSObject _) implements JSObject {
  external set href(String value);
  external set download(String value);
  external void click();
  external void remove();
}

bool get supportsLocalReferenceFilePicker => true;

Future<String?> pickLocalReferenceFile() async {
  final input = _JSInput(_createElement('input'))
    ..type = 'file'
    ..accept = '.json,application/json';
  final completed = Completer<String?>();
  Future<void> readSelection() async {
    try {
      final file = input.files?.item(0);
      if (file == null) {
        completed.complete(null);
        return;
      }
      if (file.size > LocalPrayerReferenceRepository.maximumBytes) {
        throw const FormatException(
            'ملف المرجع أكبر من الحد المحلي (2 ميجابايت).');
      }
      final content = (await file.text().toDart).toDart;
      if (!completed.isCompleted) completed.complete(content);
    } catch (error, stack) {
      if (!completed.isCompleted) completed.completeError(error, stack);
    }
  }

  input.onchange = ((JSObject event) {
    unawaited(readSelection());
  }).toJS;
  input.oncancel = ((JSObject event) {
    if (!completed.isCompleted) completed.complete(null);
  }).toJS;
  input.click();
  try {
    return await completed.future;
  } finally {
    input.onchange = null;
    input.oncancel = null;
    input.remove();
  }
}

Future<bool> downloadLocalReference(String source) async {
  final blob = _JSBlob([source.toJS].toJS,
      {'type': 'application/json;charset=utf-8'}.jsify() as JSObject);
  final url = _objectUrl(blob);
  final anchor = _JSAnchor(_createElement('a'))
    ..href = url
    ..download = 'iqtadi-prayer-reference.json';
  _append(anchor);
  anchor.click();
  anchor.remove();
  Timer(const Duration(seconds: 1), () => _revokeObjectUrl(url));
  return true;
}
