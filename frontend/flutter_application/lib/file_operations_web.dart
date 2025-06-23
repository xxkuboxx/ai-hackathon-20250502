// Web環境用のファイル操作スタブ
import 'dart:typed_data';
import 'package:http/http.dart' as http;

// Web環境での録音ファイル管理用のマップ
final Map<String, Uint8List> _webAudioFiles = {};

Future<bool> fileExists(String path) async {
  // Web環境では_webAudioFilesに保存されているかチェック
  return _webAudioFiles.containsKey(path);
}

Future<int> getFileSize(String path) async {
  // Web環境では_webAudioFilesからファイルサイズを取得
  final data = _webAudioFiles[path];
  return data?.length ?? 0;
}

// Web環境で録音データを保存
void saveWebAudioFile(String path, Uint8List data) {
  _webAudioFiles[path] = data;
}

// Web環境でファイルデータを取得
Uint8List? getWebAudioFile(String path) {
  return _webAudioFiles[path];
}

// Web環境でのHTTPファイルアップロード
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