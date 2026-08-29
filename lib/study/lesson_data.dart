// 功课静态数据：入门基础图文 + 定式布局目录。
//
// 纯数据，不依赖 Flutter；入门内容为自编，定式 SGF 见 `assets/lessons/`。

/// 一节课的一个小节。
class LessonSection {
  const LessonSection(this.heading, this.body);

  final String heading;
  final String body;
}

/// 入门基础一课。
class Lesson {
  const Lesson(this.id, this.title, this.summary, this.sections);

  final String id;
  final String title;
  final String summary;
  final List<LessonSection> sections;
}

/// 定式布局条目（SGF 文件 + 元信息）。
class JosekiEntry {
  const JosekiEntry(this.title, this.subtitle, this.asset);

  final String title;
  final String subtitle;
  final String asset;
}

const List<Lesson> kLessons = [
  Lesson('intro1', '棋具与基本规则', '认识棋盘、棋子与胜负基本概念', [
    LessonSection('棋盘与棋子', '围棋盘为 19×19 格（练习常用 9 路、13 路）。'
        '黑白双方轮流落子，每次一子，落在交叉点上。'),
    LessonSection('执子与先手', '黑先白后。正式对局黑方贴目（中国规则贴 7.5 目），'
        '以平衡先后手优势。'),
    LessonSection('胜负', '终局后比较双方所围之地与棋子，占多者胜；'
        '也可数子（中国）或数目（日韩）。'),
  ]),
  Lesson('intro2', '气与提子', '棋子的“气”与吃子原理', [
    LessonSection('什么是气', '与棋子直线相邻的空交叉点称为“气”。'
        '一颗棋子周围的气就是它相邻的空点。'),
    LessonSection('提子', '当一方的棋子气被完全堵死（气数为 0），'
        '这些棋子被对方提走，从盘面取下。'),
    LessonSection('连接与切断', '相邻同色棋子连成一个整体共享气。'
        '棋子的价值在于连接成块、避免被切断围死。'),
  ]),
  Lesson('intro3', '禁着点与打劫', '不能落子的地方与劫争', [
    LessonSection('禁着点（自杀）', '落子后己方棋子无气且不产生提子，'
        '该点禁止落子（自杀禁着）。'),
    LessonSection('打劫', '提子后若对方可立即回提同一形状，'
        '规则禁止立即回提，须先在别处走一手（找劫材），再回提，称为“打劫”。'),
    LessonSection('劫材与粘劫', '他处有较大价值且对方必须应的地方叫劫材；'
        '劫争持续到一方不再应劫、粘住劫为止。'),
  ]),
  Lesson('intro4', '终局与点目', '如何结束一局并计算胜负', [
    LessonSection('终局', '双方连续 Pass（或一方认输）即终局。'
        '也可在确定地盘后主动点目结束。'),
    LessonSection('死子与双活', '终局时被围且无法做活的棋为死子，'
        '从盘面移除计入对方；双方互相无法吃掉且各有一只眼时称“双活”。'),
    LessonSection('数子与数目', '中国规则数子：存活子 + 围空。'
        '日韩规则数目：空 + 提子。白方另加贴目。'),
  ]),
  Lesson('terms', '常用术语', '对弈与复盘常见术语速览', [
    LessonSection('布局术语', '星位、小目、高目、目外是常见占角方式；'
        '挂角、守角、拆边、跳、飞是常见行棋。'),
    LessonSection('中盘术语', '打入、侵消、夹、靠、扳、长、虎、跳、断、征子、枷等。'),
    LessonSection('死活术语', '眼、假眼、活棋、死棋、双活、扑、倒脱靴、金鸡独立等。'),
  ]),
];

const List<JosekiEntry> kJosekiEntries = [
  JosekiEntry('星位·小飞挂·一间跳', '星位对低挂的基本应法', 'assets/lessons/joseki-star-kakari-jump.sgf'),
  JosekiEntry('星位·小飞挂·小尖', '重视角地的简明应法', 'assets/lessons/joseki-star-kakari-diagonal.sgf'),
  JosekiEntry('星位·高挂', '白高一路挂角的变化', 'assets/lessons/joseki-star-kakari-high.sgf'),
  JosekiEntry('星位小飞挂完整定式', '星位最常见的完整定型', 'assets/lessons/joseki-star-basic.sgf'),
  JosekiEntry('1 段必备定式精讲', '专业定式综合讲解（来源：baduk-study-material）', 'assets/lessons/joseki-essentials.sgf'),
];
