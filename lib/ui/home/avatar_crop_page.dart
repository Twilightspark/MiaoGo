import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/ui/common/responsive.dart';

/// 头像圆形裁剪页：接收原图字节，确认后通过 `Navigator.pop` 返回裁剪结果字节。
class AvatarCropPage extends StatefulWidget {
  const AvatarCropPage({super.key, required this.imageBytes});

  final Uint8List imageBytes;

  @override
  State<AvatarCropPage> createState() => _AvatarCropPageState();
}

class _AvatarCropPageState extends State<AvatarCropPage> {
  final _controller = CropController();
  bool _cropping = false;

  void _confirm() {
    if (_cropping) return;
    setState(() => _cropping = true);
    _controller.cropCircle();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: GoColors.white,
        title: const Text('裁剪头像'),
      ),
      body: SafeArea(
        child: isWideLayout(context)
            ? Row(
                children: [
                  Expanded(child: _buildCrop()),
                  SizedBox(width: 220, child: Center(child: _buildAction())),
                ],
              )
            : Column(
                children: [
                  Expanded(child: _buildCrop()),
                  _buildAction(),
                ],
              ),
      ),
    );
  }

  Widget _buildCrop() {
    return Crop(
      image: widget.imageBytes,
      controller: _controller,
      withCircleUi: true,
      interactive: true,
      baseColor: Colors.black,
      maskColor: Colors.black.withValues(alpha: 0.5),
      onCropped: (result) {
        if (!mounted) return;
        switch (result) {
          case CropSuccess(:final croppedImage):
            Navigator.pop(context, croppedImage);
          case CropFailure():
            setState(() => _cropping = false);
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('裁剪失败，请重试')));
        }
      },
    );
  }

  Widget _buildAction() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _confirm,
          icon: const Icon(Icons.check),
          label: const Text('确认裁剪'),
        ),
      ),
    );
  }
}
