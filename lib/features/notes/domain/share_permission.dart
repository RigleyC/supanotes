enum SharePermission {
  view,
  edit;

  String toJson() => name;
  factory SharePermission.fromJson(String value) {
    return SharePermission.values.byName(value);
  }
}
