import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';

/// Abre um seletor de arquivos e retorna o conteúdo do JSON + nome do arquivo.
/// Retorna null se o usuário cancelar.
Future<({String content, String name})?> pickAndReadJson(
    String dialogTitle) async {
  final result = await FilePicker.platform.pickFiles(
    dialogTitle: dialogTitle,
    type: FileType.custom,
    allowedExtensions: ['json'],
  );
  if (result == null || result.files.isEmpty) return null;
  final path = result.files.single.path;
  if (path == null) return null;
  return (
    content: await File(path).readAsString(),
    name: result.files.single.name,
  );
}

/// Abre um seletor de destino e salva o JSON no disco.
/// Retorna o caminho salvo, ou null se cancelado.
Future<String?> saveJson(String content, String defaultName) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Salvar modelo identificado',
    fileName: defaultName,
    type: FileType.custom,
    allowedExtensions: ['json'],
  );
  if (path == null) return null;
  await File(path).writeAsString(content, encoding: utf8);
  return path;
}
