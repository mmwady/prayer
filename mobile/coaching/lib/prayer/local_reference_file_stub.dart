/// Native authoring supports local JSON paste/copy through the shared editor.
/// File import is optional; it never routes through a server.
bool get supportsLocalReferenceFilePicker => false;
Future<String?> pickLocalReferenceFile() async => null;
Future<bool> downloadLocalReference(String source) async => false;
