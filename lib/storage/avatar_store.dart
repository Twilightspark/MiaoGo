import 'dart:io';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// 头像文件存取：相册选图 + 保存/删除应用文档目录下的头像文件。
class AvatarStore {
  AvatarStore._();

  static const _dirName = 'avatars';
  static const _fileName = 'avatar.png';

  /// 从相册选择一张图片，返回图片字节；用户取消或失败返回 null。
  static Future<Uint8List?> pickFromGallery() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 90,
      );
      if (file == null) return null;
      return file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// 将头像字节写入应用文档目录（覆盖旧头像），返回绝对路径。
  static Future<String> save(Uint8List bytes) async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}${Platform.pathSeparator}$_dirName');
    await dir.create(recursive: true);
    final file = File(
        '${dir.path}${Platform.pathSeparator}$_fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// 删除头像文件（若存在）。
  static Future<void> remove(String path) async {
    if (path.isEmpty) return;
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
