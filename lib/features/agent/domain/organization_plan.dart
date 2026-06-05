/// Inbox organization plan returned by the agent backend.
///
/// The agent is asked to look at the user's inbox note and propose a set
/// of moves — each item in the plan represents a snippet that should be
/// routed to an existing note, a new note, or kept in the inbox.
///
/// The model is intentionally minimal: the backend is expected to return
/// JSON shaped like
///
/// ```json
/// {
///   "plan_id": "uuid",
///   "items": [
///     {
///       "item_id": "uuid",
///       "original_snippet": "string",
///       "destination_type": "new_note|existing_note|keep",
///       "destination_note_id": "uuid|null",
///       "destination_title": "string|null"
///     }
///   ]
/// }
/// ```
class OrganizationPlan {
  OrganizationPlan({required this.planId, required this.items});

  final String planId;
  final List<OrganizationPlanItem> items;

  factory OrganizationPlan.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List?) ?? const [];
    return OrganizationPlan(
      planId: (json['plan_id'] ?? '') as String,
      items: rawItems
          .whereType<Map<String, dynamic>>()
          .map(OrganizationPlanItem.fromJson)
          .toList(growable: false),
    );
  }
}

/// One proposed move in an [OrganizationPlan].
///
/// `accepted` is purely a UI-side flag toggled by the user before
/// applying. It is never read or written by the backend.
class OrganizationPlanItem {
  OrganizationPlanItem({
    required this.itemId,
    required this.originalSnippet,
    required this.destinationType,
    this.destinationNoteId,
    this.destinationTitle,
    this.accepted = true,
  });

  final String itemId;
  final String originalSnippet;
  final String destinationType;
  final String? destinationNoteId;
  final String? destinationTitle;
  final bool accepted;

  OrganizationPlanItem copyWith({bool? accepted}) {
    return OrganizationPlanItem(
      itemId: itemId,
      originalSnippet: originalSnippet,
      destinationType: destinationType,
      destinationNoteId: destinationNoteId,
      destinationTitle: destinationTitle,
      accepted: accepted ?? this.accepted,
    );
  }

  factory OrganizationPlanItem.fromJson(Map<String, dynamic> json) {
    return OrganizationPlanItem(
      itemId: (json['item_id'] ?? '') as String,
      originalSnippet: (json['original_snippet'] ?? '') as String,
      destinationType: (json['destination_type'] ?? 'keep') as String,
      destinationNoteId: json['destination_note_id'] as String?,
      destinationTitle: json['destination_title'] as String?,
      accepted: true,
    );
  }
}
