import 'projected_task.dart';

/// The local projections derived from one canonical note document.
class ProjectedDocument {
  const ProjectedDocument({
    required this.content,
    required this.excerpt,
    required this.tasks,
  });

  final String content;
  final String? excerpt;
  final List<ProjectedTask> tasks;
}
