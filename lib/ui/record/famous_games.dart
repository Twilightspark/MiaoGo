import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/core/sgf.dart';

/// 历史名谱条目元数据（SGF 文件 + 中文标题/说明）。
///
/// 数据来源：baduk-study-material（自由共享棋谱库，见 docs/data-sources.md）。
class FamousGameInfo {
  const FamousGameInfo({
    required this.asset,
    required this.title,
    required this.subtitle,
  });

  final String asset;
  final String title;
  final String subtitle;
}

const List<FamousGameInfo> kFamousGames = [
  // AI 时代：AlphaGo 系列
  FamousGameInfo(
    asset: 'assets/famous/alphago-leesedol-2016-game1.sgf',
    title: 'AlphaGo 对 李世石 第 1 局',
    subtitle: '2016 人机大战 · 五番棋',
  ),
  FamousGameInfo(
    asset: 'assets/famous/alphago-leesedol-2016-game2.sgf',
    title: 'AlphaGo 对 李世石 第 2 局',
    subtitle: '2016 人机大战 · 五番棋',
  ),
  FamousGameInfo(
    asset: 'assets/famous/alphago-leesedol-2016-game3.sgf',
    title: 'AlphaGo 对 李世石 第 3 局',
    subtitle: '2016 人机大战 · 五番棋',
  ),
  FamousGameInfo(
    asset: 'assets/famous/alphago-leesedol-2016-game4.sgf',
    title: '李世石 对 AlphaGo 第 4 局',
    subtitle: '2016 人机大战 · 五番棋（第 78 手妙手）',
  ),
  FamousGameInfo(
    asset: 'assets/famous/alphago-leesedol-2016-game5.sgf',
    title: 'AlphaGo 对 李世石 第 5 局',
    subtitle: '2016 人机大战 · 五番棋',
  ),
  FamousGameInfo(
    asset: 'assets/famous/alphago-kejie-2017-game1.sgf',
    title: '柯洁 对 AlphaGo 第 1 局',
    subtitle: '2017 乌镇峰会 · 三番棋',
  ),
  FamousGameInfo(
    asset: 'assets/famous/alphago-kejie-2017-game3.sgf',
    title: 'AlphaGo 对 柯洁 第 3 局',
    subtitle: '2017 乌镇峰会 · 三番棋',
  ),
  FamousGameInfo(
    asset: 'assets/famous/alphago-fanhui-2015-game1.sgf',
    title: '樊麾 对 AlphaGo 第 1 局',
    subtitle: '2015 年 10 月 · 历史性首胜职业棋手',
  ),
  // 经典名局
  FamousGameInfo(
    asset: 'assets/famous/go-seigen-kitani-1933-shinfuseki.sgf',
    title: '吴清源 对 木谷实',
    subtitle: '1933 新布局革命名局',
  ),
  FamousGameInfo(
    asset: 'assets/famous/kitani-go-seigen-1933-jigo.sgf',
    title: '木谷实 对 吴清源',
    subtitle: '1933 新布局对局 · 和棋',
  ),
  FamousGameInfo(
    asset: 'assets/famous/shusaku-gennan-inseki-1846.sgf',
    title: '本因坊秀策 对 幻庵因硕',
    subtitle: '1846 耳赤之妙手',
  ),
];

/// 已解析的名谱（含展示信息）。
class FamousGame {
  const FamousGame({
    required this.info,
    required this.game,
  });

  final FamousGameInfo info;
  final SgfGame game;

  String get blackName => game.blackName ?? '?';
  String get whiteName => game.whiteName ?? '?';
  String get result => game.result ?? '';
  String get date => game.date ?? '';
}

/// 加载全部历史名谱（解析失败的文件跳过）。
final famousGamesProvider = FutureProvider<List<FamousGame>>((ref) async {
  final games = <FamousGame>[];
  for (final info in kFamousGames) {
    try {
      final data = await rootBundle.loadString(info.asset);
      games.add(FamousGame(info: info, game: Sgf.parse(data)));
    } catch (_) {
      // 单个名谱解析失败不阻塞列表。
    }
  }
  return games;
});
