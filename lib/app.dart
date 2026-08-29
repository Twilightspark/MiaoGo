import 'package:flutter/material.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/ui/home/home_page.dart';

class MiaoGoApp extends StatelessWidget {
  const MiaoGoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '喵棋 MiaoGo',
      debugShowCheckedModeBanner: false,
      theme: buildGoTheme(),
      home: const HomePage(),
    );
  }
}
