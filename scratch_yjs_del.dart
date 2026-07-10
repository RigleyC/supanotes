import 'package:yjs_dart/yjs_dart.dart';

void main() {
  final doc = Doc();
  final ytext = doc.getText('content')!;
  ytext.insert(0, "Hello");
  print("before: ${ytext.toString()}");
  
  if (ytext.length > 0) {
    ytext.delete(0, ytext.length);
  }
  
  ytext.insert(0, "World");
  print("after: ${ytext.toString()}");
}
