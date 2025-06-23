// Web環境用のファイル操作スタブ

Future<bool> fileExists(String path) async {
  // Web環境ではファイル存在チェックをスキップ
  return true;
}

Future<int> getFileSize(String path) async {
  // Web環境ではファイルサイズを0として返す
  return 0;
}