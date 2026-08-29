import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/core/board.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/core/sgf.dart';

void main() {
  group('P1 兼容接口', () {
    test('生成并解析棋步（含 PASS），坐标往返', () {
      final moves = [
        const Move.point(PlayerColor.black, 8, 8), // jj
        const Move.pass(PlayerColor.white),
        const Move.point(PlayerColor.black, 0, 0), // aa
        const Move.point(PlayerColor.white, 3, 7),
      ];
      final sgf = Sgf.build(
        size: 9,
        rules: 'chinese',
        komi: 7.5,
        blackName: '棋手',
        whiteName: 'AI',
        result: 'B+1.5',
        moves: moves,
      );
      expect(sgf, contains('(;GM[1]FF[4]'));
      expect(sgf, contains('SZ[9]'));
      expect(sgf, contains('RU[chinese]'));
      expect(sgf, contains('KM[7.5]'));
      expect(sgf, contains('PB[棋手]'));
      expect(sgf, contains('PW[AI]'));
      expect(sgf, contains('RE[B+1.5]'));
      expect(sgf, contains(';B[jj]'));
      expect(sgf, contains(';W[]'));
      expect(sgf, contains(';B[aa]'));

      expect(Sgf.parseMoves(sgf), moves);
    });

    test('属性读取', () {
      final sgf = Sgf.build(
        size: 19,
        rules: 'japanese',
        komi: 6.5,
        result: 'W+3.5',
        moves: const [Move.point(PlayerColor.black, 15, 3)],
      );
      expect(Sgf.prop(sgf, 'SZ'), '19');
      expect(Sgf.prop(sgf, 'RU'), 'japanese');
      expect(Sgf.prop(sgf, 'KM'), '6.5');
      expect(Sgf.prop(sgf, 'RE'), 'W+3.5');
      expect(Sgf.prop(sgf, 'PB'), isNull);
    });

    test('认输不入谱，RE 记录', () {
      final sgf = Sgf.build(
        size: 9,
        rules: 'chinese',
        komi: 7.5,
        result: 'W+R',
        moves: const [
          Move.point(PlayerColor.black, 4, 4),
          Move.resign(PlayerColor.white),
        ],
      );
      expect(sgf, contains(';B[ee]'));
      expect(sgf.contains(';W['), isFalse);
      expect(Sgf.prop(sgf, 'RE'), 'W+R');
    });

    test('无棋步的空对局', () {
      final sgf = Sgf.build(size: 9, rules: 'chinese', komi: 7.5);
      expect(Sgf.parseMoves(sgf), isEmpty);
    });
  });

  group('完整解析', () {
    test('元数据读取（含让子/来源/日期）', () {
      const text = '(;GM[1]FF[4]SZ[19]RU[Old Chinese]KM[0]'
          'PB[Go Seigen]PW[Kitani Minoru]BR[7d]WR[9d]'
          'DT[1933-08-27]EV[Shin Fuseki]RE[B+4]HA[0]SO[https://x]'
          'AB[dp][pd]AW[dd][pp];B[qd];W[dc])';
      final g = Sgf.parse(text);
      expect(g.size, 19);
      expect(g.rulesProp, 'Old Chinese');
      expect(g.komi, 0);
      expect(g.blackName, 'Go Seigen');
      expect(g.whiteName, 'Kitani Minoru');
      expect(g.blackRank, '7d');
      expect(g.event, 'Shin Fuseki');
      expect(g.date, '1933-08-27');
      expect(g.result, 'B+4');
      expect(g.source, 'https://x');
      // AB[dp][pd]：字母对为 (列, 行)。
      expect(g.setupBlack, [(14, 3), (3, 14)]);
      expect(g.setupWhite, [(3, 3), (14, 14)]);
      expect(g.moves, [
        const Move.point(PlayerColor.black, 3, 15), // B[qd]
        const Move.point(PlayerColor.white, 2, 3), // W[dc]
      ]);
    });

    test('主变化链跟随首子；变化分支保留', () {
      // 死活题结构：根布子 → 首分支为正解，其余为错解。
      const text = '(;SZ[19]AW[op][pp][qp][or][pr]AB[pq][rq]'
          'C[Black to play]'
          '(;B[qr](;W[os];B[rs]C[Correct])(;W[ps]))'
          '(;B[qs](;W[qq]))'
          '(;B[os]))';
      final g = Sgf.parse(text);
      expect(g.mainline.length, 4); // root, Bqr, Wos, Brs
      expect(g.mainline[3].comment, 'Correct');
      // 分支：根节点 3 个子节点。
      expect(g.root.children.length, 3);
      expect(g.root.children[0].move,
          const Move.point(PlayerColor.black, 16, 15)); // B[qr]
      expect(g.root.children[1].move,
          const Move.point(PlayerColor.black, 17, 15)); // B[qs]
      // 变化内的次级分支。
      expect(g.root.children[0].children.length, 2);
      // 主变化（取首子链）正确。
      expect(g.moves, [
        const Move.point(PlayerColor.black, 16, 15), // B[qr]
        const Move.point(PlayerColor.white, 17, 13), // W[os]
        const Move.point(PlayerColor.black, 17, 16), // B[rs]
      ]);
      // playerToMove：无 PL，取首步颜色 = 黑。
      expect(g.playerToMove, PlayerColor.black);
    });

    test('PL 指定执子方', () {
      const text = '(;SZ[19]PL[W]AW[op]AB[pq];W[qq];B[pp])';
      final g = Sgf.parse(text);
      expect(g.playerToMove, PlayerColor.white);
    });

    test('转义字符（\\\\ 与 \\]）', () {
      const text = r'(;SZ[9]C[a\]b\\c])';
      final g = Sgf.parse(text);
      expect(g.root.value('C'), r'a]b\c');
    });

    test('多值属性', () {
      const text = '(;SZ[9]LB[aa:A][bb:B])';
      final g = Sgf.parse(text);
      expect(g.root.values('LB'), ['aa:A', 'bb:B']);
    });

    test('多值属性与空白容错', () {
      const text = '(;\n  GM[1]\r\n SZ[19]\n AB[aa][bb][cc]\n'
          ' ;B[dd]\n ;W[ee]\n)';
      final g = Sgf.parse(text);
      expect(g.root.values('AB'), ['aa', 'bb', 'cc']);
      expect(g.moves, [
        const Move.point(PlayerColor.black, 3, 3),
        const Move.point(PlayerColor.white, 4, 4),
      ]);
    });

    test('经典谱面容忍：JD/OH 等非标属性与换行', () {
      const text = '(;\nPB[Yasuda Eisai]\nPW[Itagaki Chuzo]\n'
          'WR[2d]\nRE[B+2]\nJD[Tenpo 10-11-9]\nDT[1839-12-14]\nOH[B]\n'
          ';B[qd];W[dc];B[oc])';
      final g = Sgf.parse(text);
      expect(g.blackName, 'Yasuda Eisai');
      expect(g.date, '1839-12-14');
      expect(g.root.value('JD'), 'Tenpo 10-11-9');
      expect(g.moves.length, 3);
    });

    test('序列化往返解析一致', () {
      const text = '(;SZ[19]AB[aa][bb];B[cc](;W[dd];B[ee])(;W[ff]))';
      final g1 = Sgf.parse(text);
      final encoded = Sgf.encode(g1);
      final g2 = Sgf.parse(encoded);
      expect(g2.size, 19);
      expect(g2.setupBlack, [(0, 0), (1, 1)]);
      expect(g2.moves, [
        const Move.point(PlayerColor.black, 2, 2),
        const Move.point(PlayerColor.white, 3, 3),
        const Move.point(PlayerColor.black, 4, 4),
      ]);
      // 分支出现在 B[cc] 之后（两个白变化），根仅一个子节点。
      expect(g2.root.children.length, 1);
      expect(g2.root.children.first.children.length, 2);
      expect(g2.mainline[3].comment, isNull);
    });

    test('畸形输入抛 FormatException', () {
      expect(() => Sgf.parse(''), throwsFormatException);
      expect(() => Sgf.parse(';B[aa]'), throwsFormatException); // 无外括号
      expect(() => Sgf.parse('(;B[aa'), throwsFormatException); // 缺 ] 或 )
    });
  });

  group('死活题 SGF（gogameguru 结构）', () {
    test('布子 + 分支 + C[Correct] 可完整解析', () {
      // 抽取 ggg-easy-08 的代表结构（缩简）：
      const text = '(;GM[1]FF[4]CA[UTF-8]AP[CGoban:3]ST[2]\n'
          'RU[Japanese]SZ[19]KM[0.00]\n'
          'SO[https://gogameguru.com/]AW[op][pp][qp][rp][mq][oq][rq][sq][nr]'
          'AB[pq][or][pr][rr][sr]C[Black to play.\n\nhttps://gogameguru.com/]\n'
          '(;B[qq]\n(;W[qs]\n(;B[rs]\n;W[os]\n(;B[qr]\n;W[ns]\n;B[ps]C[Correct])\n'
          '(;B[ps]\n;W[qr]))\n(;B[qr]\n;W[rs])\n(;B[ps]\n;W[rs])\n'
          '(;B[os]\n;W[qr]))\n(;W[os]\n;B[qs]\n;W[ns]\n;B[ps]C[Correct]))\n'
          '(;B[os]\n;W[qr])\n(;B[qs]\n;W[qq])\n(;B[rs]\n;W[ps]))';
      final g = Sgf.parse(text);
      expect(g.size, 19);
      expect(g.setupWhite.length, 9);
      expect(g.setupBlack.length, 5);
      expect(g.playerToMove, PlayerColor.black);
      expect(g.root.comment, contains('Black to play'));
      // 正解主线：首子链直到 C[Correct]（含根节点，无棋步）。
      final main = g.mainline;
      expect(main.map((n) => n.move).toList(), [
        null,
        const Move.point(PlayerColor.black, 15, 15), // B[qq]
        const Move.point(PlayerColor.white, 17, 15), // W[qs]
        const Move.point(PlayerColor.black, 17, 16), // B[rs]
        const Move.point(PlayerColor.white, 17, 13), // W[os]
        const Move.point(PlayerColor.black, 16, 15), // B[qr]
        const Move.point(PlayerColor.white, 17, 12), // W[ns]
        const Move.point(PlayerColor.black, 17, 14), // B[ps]
      ]);
      expect(main.last.comment, 'Correct');
      expect(g.root.children.length, 4); // 4 个黑分支
    });

    test('PASS 在完整解析中体现', () {
      const text = '(;SZ[9];B[aa];W[];B[bb])';
      final g = Sgf.parse(text);
      expect(g.moves, [
        const Move.point(PlayerColor.black, 0, 0),
        const Move.pass(PlayerColor.white),
        const Move.point(PlayerColor.black, 1, 1),
      ]);
    });

    test('GoBoard 坐标与布子互转', () {
      // sgfCoord(row, col) → "列字母+行字母"（跳过 i）。
      expect(GoBoard.sgfCoord(3, 11), 'md');
      expect(GoBoard.sgfCoord(8, 8), 'jj');
      expect(GoBoard.coordFromSgf('dp'), (14, 3));
      expect(GoBoard.coordFromSgf('jj'), (8, 8));
      expect(() => GoBoard.coordFromSgf('a'), throwsArgumentError);
      expect(() => GoBoard.coordFromSgf('ai'), throwsArgumentError);
      expect(() => GoBoard.coordFromSgf('ii'), throwsArgumentError);
    });
  });
}
