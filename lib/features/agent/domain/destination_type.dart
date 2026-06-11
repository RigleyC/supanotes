enum DestinationType {
  newNote('new_note'),
  existingNote('existing_note'),
  keep('keep');

  const DestinationType(this.value);
  final String value;

  static DestinationType fromJson(String value) {
    return switch (value) {
      'new_note' => DestinationType.newNote,
      'existing_note' => DestinationType.existingNote,
      'keep' => DestinationType.keep,
      _ => DestinationType.keep,
    };
  }
}
