library;

import 'destination_type.dart';

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

  Map<String, dynamic> toJson() => {
    'plan_id': planId,
    'items': items.map((i) => i.toJson()).toList(),
  };
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
  final DestinationType destinationType;
  final String? destinationNoteId;
  final String? destinationTitle;
  final bool accepted;

  OrganizationPlanItem copyWith({
    bool? accepted,
    DestinationType? destinationType,
  }) {
    return OrganizationPlanItem(
      itemId: itemId,
      originalSnippet: originalSnippet,
      destinationType: destinationType ?? this.destinationType,
      destinationNoteId: destinationNoteId,
      destinationTitle: destinationTitle,
      accepted: accepted ?? this.accepted,
    );
  }

  Map<String, dynamic> toJson() => {
    'item_id': itemId,
    'original_snippet': originalSnippet,
    'destination_type': destinationType.value,
    'destination_note_id': destinationNoteId,
    'destination_title': destinationTitle,
    'accepted': accepted,
  };

  factory OrganizationPlanItem.fromJson(Map<String, dynamic> json) {
    return OrganizationPlanItem(
      itemId: (json['item_id'] ?? '') as String,
      originalSnippet: (json['original_snippet'] ?? '') as String,
      destinationType: DestinationType.fromJson(
        (json['destination_type'] ?? 'keep') as String,
      ),
      destinationNoteId: json['destination_note_id'] as String?,
      destinationTitle: json['destination_title'] as String?,
      accepted: true,
    );
  }
}
