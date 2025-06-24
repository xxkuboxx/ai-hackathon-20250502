// Web環境用のファイル操作スタブ
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http_parser;

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
  // バックエンドがサポートする形式に変換
  // WebM/OGGファイルの場合はWAVとして送信（データはそのまま）
  String contentType = 'audio/wav'; // デフォルト（バックエンドサポート対象）
  String adjustedFilename = filename;

  if (filename.toLowerCase().endsWith('.webm') ||
      filename.toLowerCase().endsWith('.ogg')) {
    // WebM/OGGファイルはWAVとして扱う（バックエンド互換性のため）
    contentType = 'audio/wav';
    adjustedFilename = filename.replaceAll(RegExp(r'\.(webm|ogg)$'), '.wav');
  } else if (filename.toLowerCase().endsWith('.wav')) {
    contentType = 'audio/wav';
  } else if (filename.toLowerCase().endsWith('.mp3')) {
    contentType = 'audio/mpeg';
  } else if (filename.toLowerCase().endsWith('.m4a')) {
    contentType = 'audio/mp4';
  } else if (filename.toLowerCase().endsWith('.aac')) {
    contentType = 'audio/aac';
  }

  return http.MultipartFile.fromBytes(
    fieldName,
    bytes,
    filename: adjustedFilename,
    contentType: http_parser.MediaType.parse(contentType),
  );
}
