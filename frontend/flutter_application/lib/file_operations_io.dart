// モバイル環境用のファイル操作
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

Future<bool> fileExists(String path) async {
  try {
    return await File(path).exists();
  } catch (e) {
    return false;
  }
}

Future<int> getFileSize(String path) async {
  try {
    return await File(path).length();
  } catch (e) {
    return 0;
  }
}

// Web環境用の関数をスタブとして追加（IO環境では使用されない）
void saveWebAudioFile(String path, Uint8List data) {
  // IO環境では何もしない
}

Uint8List? getWebAudioFile(String path) {
  // IO環境では何もしない
  return null;
}

Future<http.MultipartFile> createMultipartFileFromBytes(
  String fieldName,
  String filename,
  Uint8List bytes,
) async {
  return http.MultipartFile.fromBytes(
    fieldName,
    bytes,
    filename: filename,
  );
}