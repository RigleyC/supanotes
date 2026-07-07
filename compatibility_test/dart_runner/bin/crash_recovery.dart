import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:yjs_dart/yjs_dart.dart';
import 'package:yjs_dart/src/structs/item.dart';
import 'package:yjs_dart/src/structs/content.dart';

void main() {
  // Override buggy _ContentStringStub with real ContentString reader
  contentRefs[4] = (decoder) => ContentString(decoder.readString() as String);

  print('=======================================');
  print('Running Crash Recovery Spike');
  print('=======================================');

  // 1. Initial State Sync
  final clientA = Doc(DocOpts(gc: false, clientID: 65));
  final serverBeforeCrash = Doc(DocOpts(gc: false, clientID: 83));

  clientA.getText('note');
  serverBeforeCrash.getText('note');

  clientA.transact((tr) {
    clientA.getText('note')!.insert(0, 'Hello Server, this is the initial document state.');
  });

  // Client A syncs to Server
  final uInitial = encodeStateAsUpdate(clientA);
  applyUpdate(serverBeforeCrash, uInitial);

  print('Initial Sync complete.');
  print('Server text: "${serverBeforeCrash.getText('note')}"');

  // 2. Server persists state (exports all updates or takes snapshot)
  // In production, the server would write the update history or a snapshot to a db.
  final serverBackupUpdates = encodeStateAsUpdate(serverBeforeCrash);

  // 3. Client A goes offline and makes edits
  print('Client A goes offline and makes edits...');
  clientA.transact((tr) {
    clientA.getText('note')!.insert(6, ' (edited offline)');
    clientA.getText('note')!.delete(47, 7); // deletes "state."
    clientA.getText('note')!.insert(47, 'content.');
  });

  // 4. Server crashes and restarts (new Doc initialized, loaded from backup)
  print('Server crashes!');
  // Simulate server restart: new Doc initialized, database records re-applied
  final serverAfterCrash = Doc(DocOpts(gc: false, clientID: 83));
  serverAfterCrash.getText('note');
  applyUpdate(serverAfterCrash, serverBackupUpdates); // Reload state from db backup

  print('Server restarted from backup.');
  print('Server recovered text: "${serverAfterCrash.getText('note')}"');

  // 5. Client A reconnects and syncs with restarted server
  print('Client A reconnects and syncs...');
  // Sync Client A -> Server
  final svServer = encodeStateVector(serverAfterCrash);
  final diffA = encodeStateAsUpdate(clientA, svServer);
  applyUpdate(serverAfterCrash, diffA);

  // Sync Server -> Client A
  final svA = encodeStateVector(clientA);
  final diffServer = encodeStateAsUpdate(serverAfterCrash, svA);
  applyUpdate(clientA, diffServer);

  // 6. Verify Convergence
  final finalAText = clientA.getText('note')!.toString();
  final finalServerText = serverAfterCrash.getText('note')!.toString();

  print('---------------------------------------');
  print('Client A Final Text: "$finalAText"');
  print('Server Final Text:   "$finalServerText"');

  if (finalAText == finalServerText) {
    print('=======================================');
    print('✅ Crash Recovery Spike Passed Successfully!');
    print('=======================================');
  } else {
    print('❌ Convergence Error: Client A and Server did not converge!');
    exit(1);
  }
}
