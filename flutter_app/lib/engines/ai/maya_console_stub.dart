import 'maya_console.dart';

MayaConsole createMayaConsole() => _UnavailableMayaConsole();

class _UnavailableMayaConsole implements MayaConsole {
  @override
  bool get available => false;

  @override
  Future<Map<String, dynamic>> run(
    String action, [
    Map<String, String> fields = const {},
  ]) async =>
      throw UnsupportedError('The Maya console runs on PowerLine Web.');

  @override
  Future<String> audioUrl(String action, Map<String, String> fields) async =>
      throw UnsupportedError('The Maya console runs on PowerLine Web.');
}
