import 'package:supanotes/core/utils/fractional_indexing.dart';

void main() {
  String? pos = null;
  for (int i = 0; i < 70; i++) {
    pos = FractionalIndex.between(pos, null);
    print('$i: $pos');
  }
}
