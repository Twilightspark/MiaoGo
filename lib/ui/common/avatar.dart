import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/storage/avatar_store.dart';
import 'package:miaogo/storage/user_store.dart';
import 'package:miaogo/ui/home/avatar_crop_page.dart';

/// 圆形头像：已设置显示图片，未设置显示姓名首字。首页 / 设置页复用。
class AvatarView extends StatelessWidget {
  const AvatarView({
    super.key,
    required this.avatarPath,
    required this.name,
    required this.radius,
  });

  final String avatarPath;
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: ClipOval(
        child: avatarPath.isNotEmpty
            ? Image.file(
                File(avatarPath),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _initialAvatar(),
              )
            : _initialAvatar(),
      ),
    );
  }

  Widget _initialAvatar() {
    final initial = name.isEmpty ? '棋' : name.characters.first;
    return ColoredBox(
      color: GoColors.pineContainer,
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: radius * 0.9,
            fontWeight: FontWeight.bold,
            color: GoColors.onPineContainer,
          ),
        ),
      ),
    );
  }
}

/// 弹出「头像修改框」：展示当前头像 + 更换头像按钮。
Future<void> showAvatarChangeDialog(BuildContext context, WidgetRef ref) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final profile = ref.read(userProfileProvider);
      return Dialog(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AvatarView(
                avatarPath: profile.avatarPath,
                name: profile.name,
                radius: 52,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('更换头像'),
                onPressed: () {
                  Navigator.pop(ctx);
                  pickAndSaveAvatar(context, ref);
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// 选图 → 圆形裁剪 → 保存 → 更新头像。
Future<void> pickAndSaveAvatar(BuildContext context, WidgetRef ref) async {
  final bytes = await AvatarStore.pickFromGallery();
  if (bytes == null) {
    if (context.mounted) _toast(context, '未选择图片');
    return;
  }
  if (!context.mounted) return;
  final cropped = await Navigator.of(context).push<Uint8List>(
    MaterialPageRoute<Uint8List>(
      builder: (_) => AvatarCropPage(imageBytes: bytes),
    ),
  );
  if (cropped == null) return;
  try {
    final path = await AvatarStore.save(cropped);
    if (!context.mounted) return;
    ref.read(userProfileProvider.notifier).updateAvatar(path);
    if (context.mounted) _toast(context, '头像已更新');
  } catch (_) {
    if (context.mounted) _toast(context, '头像保存失败');
  }
}

void _toast(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
