import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/storage/user_store.dart';
import 'package:miaogo/ui/settings/settings_common.dart';

/// 修改用户名页：从设置页右侧滑出，最上方为名称输入框。
class EditNamePage extends ConsumerStatefulWidget {
  const EditNamePage({super.key});

  @override
  ConsumerState<EditNamePage> createState() => _EditNamePageState();
}

class _EditNamePageState extends ConsumerState<EditNamePage> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: ref.read(userProfileProvider).name);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    ref.read(userProfileProvider.notifier).updateName(text);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: settingsAppBar(
        context,
        '修改名称',
        action: IconButton(
          key: const ValueKey('edit_name_save'),
          tooltip: '保存',
          onPressed: _save,
          icon: const Icon(Icons.check, color: GoColors.pine),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Card(
              elevation: 0,
              margin: EdgeInsets.zero,
              color: theme.colorScheme.surfaceContainerHighest,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  maxLength: 12,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                  decoration: const InputDecoration(
                    labelText: '名称',
                    border: InputBorder.none,
                    counterText: '',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
