import 'package:flutter/material.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/study/lesson_data.dart';

/// 入门基础：课程列表。
class LessonsPage extends StatelessWidget {
  const LessonsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('入门基础')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: kLessons.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final lesson = kLessons[i];
          return Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest,
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(
                radius: 24,
                backgroundColor: GoColors.pineContainer,
                child: const Icon(Icons.auto_stories, color: GoColors.pineDark),
              ),
              title: Text(
                lesson.title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(lesson.summary, style: theme.textTheme.bodySmall),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => LessonDetailPage(lesson: lesson),
              )),
            ),
          );
        },
      ),
    );
  }
}

/// 课程详情：图文小节。
class LessonDetailPage extends StatelessWidget {
  const LessonDetailPage({super.key, required this.lesson});

  final Lesson lesson;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(lesson.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final section in lesson.sections) ...[
            Text(
              section.heading,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: GoColors.pineDark,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              section.body,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
            ),
            const SizedBox(height: 18),
          ],
        ],
      ),
    );
  }
}
