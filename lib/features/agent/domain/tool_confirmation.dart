enum ConfirmationStatus {
  approved,
  cancelled,
  pending,
  expired,
  unknown;

  factory ConfirmationStatus.fromJson(String value) {
    return ConfirmationStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => ConfirmationStatus.unknown,
    );
  }
}

class ToolConfirmationResolution {
  const ToolConfirmationResolution({
    required this.confirmationId,
    required this.status,
    required this.message,
  });

  final String confirmationId;
  final ConfirmationStatus status;
  final String message;

  factory ToolConfirmationResolution.fromJson(Map<String, dynamic> json) {
    return ToolConfirmationResolution(
      confirmationId: (json['confirmation_id'] ?? '') as String,
      status: ConfirmationStatus.fromJson((json['status'] ?? '') as String),
      message: (json['message'] ?? '') as String,
    );
  }
}
