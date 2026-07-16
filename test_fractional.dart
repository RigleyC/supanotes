import 'package:supanotes/core/utils/fractional_indexing.dart';

void main() {
  String? pos = null;
  for (int i = 0; i < 10; i++) {
    pos = FractionalIndex.between(pos, null);
    print('pos $i: $pos');
  }
}
