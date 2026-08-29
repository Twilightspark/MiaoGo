import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/engine/gtp_client.dart';

import 'mock_gtp_io.dart';

void main() {
  group('GtpClient.send', () {
    test('成功响应（忽略前导空行）', () async {
      final io = MockGtpIo({'boardsize 9': ['', '= ']});
      final client = GtpClient(io);
      final r = await client.send('boardsize 9');
      expect(r.ok, isTrue);
      expect(r.body, '');
      expect(io.sent, ['boardsize 9']);
    });

    test('带内容响应', () async {
      final io = MockGtpIo({'genmove b': ['', '= E4']});
      final client = GtpClient(io);
      final r = await client.send('genmove b');
      expect(r.ok, isTrue);
      expect(r.body, 'E4');
    });

    test('错误响应 ?', () async {
      final io = MockGtpIo({'boardsize 99': ['? unacceptable size']});
      final client = GtpClient(io);
      final r = await client.send('boardsize 99');
      expect(r.isError, isTrue);
      expect(r.body, 'unacceptable size');
    });

    test('超时抛 GtpTimeoutException', () async {
      final io = MockGtpIo(); // 无脚本，永不响应
      final client = GtpClient(io, defaultTimeout: const Duration(milliseconds: 50));
      await expectLater(
          client.send('boardsize 9'), throwsA(isA<GtpTimeoutException>()));
    });
  });

  group('GtpClient.streamLines', () {
    test('跳过首个 ack `=`，回调 info 行，play 行结束', () async {
      final io = MockGtpIo({
        'kata-search_analyze b 100': [
          '',
          '=',
          'info move E4 visits 50 winrate 0.5 order 0 pv E4',
          'info move D5 visits 40 winrate 0.48 order 1 pv D5',
          'play E4',
        ],
      });
      final client = GtpClient(io);
      final infos = <String>[];
      String? chosen;
      await client.streamLines(
        'kata-search_analyze b 100',
        (line) {
          if (line.startsWith('play ')) {
            chosen = line.substring(5);
            return true;
          }
          return false;
        },
        onLine: (line) {
          if (line.startsWith('info ')) infos.add(line);
        },
      );
      expect(infos, hasLength(2));
      expect(chosen, 'E4');
    });

    test('收到 `?` 报错', () async {
      final io = MockGtpIo({'kata-search_analyze b 100': ['? boom']});
      final client = GtpClient(io);
      await expectLater(
          client.streamLines('kata-search_analyze b 100', (_) => false),
          throwsA(isA<GtpTimeoutException>()));
    });
  });
}
