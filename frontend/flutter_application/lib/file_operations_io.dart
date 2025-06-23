// モバイル環境用のファイル操作
import 'dart:io';

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