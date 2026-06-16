import 'dart:convert';
import 'dart:js_interop';
import 'package:file_picker/file_picker.dart';

/// Chama window.aegisDownloadJson (definido em aegis_wasm_loader.js).
@JS('aegisDownloadJson')
external void _aegisDownloadJson(JSString content, JSString filename);

/// Abre o seletor de arquivos do browser e retorna conteúdo + nome.
/// No web, FilePicker retorna bytes (withData: true) — sem acesso a path.
Future<({String content, String name})?> pickAndReadJson(
    String dialogTitle) async {
  final result = await FilePicker.platform.pickFiles(
    dialogTitle: dialogTitle,
    type: FileType.custom,
    allowedExtensions: ['json'],
    withData: true, // obrigatório no web: não há path, só bytes
  );
  if (result == null || result.files.isEmpty) return null;
  final bytes = result.files.single.bytes;
  if (bytes == null) return null;
  return (
    content: utf8.decode(bytes),
    name: result.files.single.name,
  );
}

/// Aciona download do arquivo JSON via browser (não há "salvar como" no web).
/// Sempre retorna o nome do arquivo (sem path real).
Future<String?> saveJson(String content, String defaultName) async {
  _aegisDownloadJson(content.toJS, defaultName.toJS);
  return defaultName;
}
