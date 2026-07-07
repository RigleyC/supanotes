import 'dart:convert';
import 'dart:io';

void main() {
  final cases = <String, Map<String, dynamic>>{};

  // Case 1: Basic Interop (Bilateral inserts)
  cases['01_basic_interop'] = {
    'name': 'Basic Interop (Bilateral inserts)',
    'clients': ['A', 'B'],
    'steps': [
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': 'Hello'},
      {'client': 'A', 'action': 'export_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'},
      {'client': 'B', 'action': 'text_insert', 'name': 'note', 'index': 5, 'value': ' World'},
      {'client': 'B', 'action': 'export_update', 'id': 'u2'},
      {'client': 'A', 'action': 'import_update', 'id': 'u2'}
    ],
    'expected': {
      'text': {'note': 'Hello World'}
    }
  };

  // Case 2: Cross Language Roundtrip
  cases['02_cross_language_roundtrip'] = {
    'name': 'Cross Language Roundtrip edits',
    'clients': ['A', 'B'],
    'steps': [
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': 'Start '},
      {'client': 'A', 'action': 'export_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'},
      {'client': 'B', 'action': 'text_insert', 'name': 'note', 'index': 6, 'value': 'Go '},
      {'client': 'B', 'action': 'export_update', 'id': 'u2'},
      {'client': 'A', 'action': 'import_update', 'id': 'u2'},
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 9, 'value': 'Dart '},
      {'client': 'A', 'action': 'export_update', 'id': 'u3'},
      {'client': 'B', 'action': 'import_update', 'id': 'u3'},
      {'client': 'B', 'action': 'text_insert', 'name': 'note', 'index': 14, 'value': 'Go2 '},
      {'client': 'B', 'action': 'export_update', 'id': 'u4'},
      {'client': 'A', 'action': 'import_update', 'id': 'u4'},
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 18, 'value': 'Dart2'},
      {'client': 'A', 'action': 'export_update', 'id': 'u5'},
      {'client': 'B', 'action': 'import_update', 'id': 'u5'}
    ],
    'expected': {
      'text': {'note': 'Start Go Dart Go2 Dart2'}
    }
  };

  // Case 3: Convergence Shuffle (4 clients, different order of operations/delivery)
  cases['03_convergence_shuffle'] = {
    'name': 'Convergence Shuffle (4 clients, concurrent edits)',
    'clients': ['A', 'B', 'C', 'D'],
    'steps': [
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': 'Start '},
      {'client': 'A', 'action': 'export_update', 'id': 'uInit'},
      {'client': 'B', 'action': 'import_update', 'id': 'uInit'},
      {'client': 'C', 'action': 'import_update', 'id': 'uInit'},
      {'client': 'D', 'action': 'import_update', 'id': 'uInit'},
      
      // Concurrent edits
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 6, 'value': 'A'},
      {'client': 'A', 'action': 'export_update', 'id': 'uA'},
      {'client': 'B', 'action': 'text_insert', 'name': 'note', 'index': 6, 'value': 'B'},
      {'client': 'B', 'action': 'export_update', 'id': 'uB'},
      {'client': 'C', 'action': 'text_insert', 'name': 'note', 'index': 6, 'value': 'C'},
      {'client': 'C', 'action': 'export_update', 'id': 'uC'},
      {'client': 'D', 'action': 'text_insert', 'name': 'note', 'index': 6, 'value': 'D'},
      {'client': 'D', 'action': 'export_update', 'id': 'uD'},

      // Shuffle deliveries
      {'client': 'A', 'action': 'import_update', 'id': 'uB'},
      {'client': 'A', 'action': 'import_update', 'id': 'uC'},
      {'client': 'A', 'action': 'import_update', 'id': 'uD'},

      {'client': 'B', 'action': 'import_update', 'id': 'uC'},
      {'client': 'B', 'action': 'import_update', 'id': 'uD'},
      {'client': 'B', 'action': 'import_update', 'id': 'uA'},

      {'client': 'C', 'action': 'import_update', 'id': 'uD'},
      {'client': 'C', 'action': 'import_update', 'id': 'uA'},
      {'client': 'C', 'action': 'import_update', 'id': 'uB'},

      {'client': 'D', 'action': 'import_update', 'id': 'uA'},
      {'client': 'D', 'action': 'import_update', 'id': 'uB'},
      {'client': 'D', 'action': 'import_update', 'id': 'uC'}
    ],
    'expected': {
      // Order of concurrent nodes is determined by client ID sort order
      // client ID: A=65, B=66, C=67, D=68
      // Since they are inserted concurrently at the same index 6, they will converge to a sorted client ID order
      'text': {'note': 'Start DCBA'}
    }
  };

  // Case 4: Out-of-order Updates
  cases['04_out_of_order'] = {
    'name': 'Out of Order updates delivery',
    'clients': ['A', 'B'],
    'steps': [
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': '1'},
      {'client': 'A', 'action': 'export_update', 'id': 'u1'},
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 1, 'value': '2'},
      {'client': 'A', 'action': 'export_update', 'id': 'u2'},
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 2, 'value': '3'},
      {'client': 'A', 'action': 'export_update', 'id': 'u3'},
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 3, 'value': '4'},
      {'client': 'A', 'action': 'export_update', 'id': 'u4'},
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 4, 'value': '5'},
      {'client': 'A', 'action': 'export_update', 'id': 'u5'},

      // Apply out of order on B
      {'client': 'B', 'action': 'import_update', 'id': 'u4'},
      {'client': 'B', 'action': 'import_update', 'id': 'u2'},
      {'client': 'B', 'action': 'import_update', 'id': 'u5'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u3'}
    ],
    'expected': {
      'text': {'note': '12345'}
    }
  };

  // Case 5: Duplicate Delivery
  cases['05_duplicate_delivery'] = {
    'name': 'Duplicate update delivery',
    'clients': ['A', 'B'],
    'steps': [
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': '1'},
      {'client': 'A', 'action': 'export_update', 'id': 'u1'},
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 1, 'value': '2'},
      {'client': 'A', 'action': 'export_update', 'id': 'u2'},
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 2, 'value': '3'},
      {'client': 'A', 'action': 'export_update', 'id': 'u3'},

      // Apply duplicates
      {'client': 'B', 'action': 'import_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u2'},
      {'client': 'B', 'action': 'import_update', 'id': 'u2'},
      {'client': 'B', 'action': 'import_update', 'id': 'u3'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u3'}
    ],
    'expected': {
      'text': {'note': '123'}
    }
  };

  // Case 6: Random Duplicate
  cases['06_random_duplicate'] = {
    'name': 'Random duplicate deliveries fuzzing scenario',
    'clients': ['A', 'B'],
    'steps': [
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': 'Initial'},
      {'client': 'A', 'action': 'export_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'}, // 30% duplicate
      
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 7, 'value': ' - EditA'},
      {'client': 'A', 'action': 'export_update', 'id': 'u2'},
      {'client': 'B', 'action': 'import_update', 'id': 'u2'},
      {'client': 'B', 'action': 'import_update', 'id': 'u2'}, // Duplicate u2
      
      {'client': 'B', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': 'EditB - '},
      {'client': 'B', 'action': 'export_update', 'id': 'u3'},
      {'client': 'A', 'action': 'import_update', 'id': 'u3'},
      {'client': 'A', 'action': 'import_update', 'id': 'u3'} // Duplicate u3
    ],
    'expected': {
      'text': {'note': 'EditB - Initial - EditA'}
    }
  };

  // Case 7: Random Network (delays, shuffles, duplicates)
  cases['07_random_network'] = {
    'name': 'Random network delay, shuffle, and duplicate simulation',
    'clients': ['A', 'B'],
    'steps': [
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': 'Initial'},
      {'client': 'A', 'action': 'export_update', 'id': 'u1'},
      
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 7, 'value': ' A'},
      {'client': 'A', 'action': 'export_update', 'id': 'u2'},
      
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 9, 'value': ' B'},
      {'client': 'A', 'action': 'export_update', 'id': 'u3'},
      
      // Shuffle & duplicate delivery on B: u2 -> u1 -> u3 -> u2 -> u1
      {'client': 'B', 'action': 'import_update', 'id': 'u2'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u3'},
      {'client': 'B', 'action': 'import_update', 'id': 'u2'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'},

      {'client': 'B', 'action': 'text_insert', 'name': 'note', 'index': 11, 'value': ' C'},
      {'client': 'B', 'action': 'export_update', 'id': 'u4'},
      {'client': 'A', 'action': 'import_update', 'id': 'u4'}
    ],
    'expected': {
      'text': {'note': 'Initial A B C'}
    }
  };

  // Case 8: Anti-interleaving
  cases['08_anti_interleaving'] = {
    'name': 'Anti-interleaving (concurrent inserts at same index)',
    'clients': ['A', 'B', 'C'],
    'steps': [
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': 'Hello'},
      {'client': 'A', 'action': 'export_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'},
      {'client': 'C', 'action': 'import_update', 'id': 'u1'},
      
      // Concurrent inserts at same index 5
      {'client': 'B', 'action': 'text_insert', 'name': 'note', 'index': 5, 'value': ' Ola'},
      {'client': 'B', 'action': 'export_update', 'id': 'u2'},
      {'client': 'C', 'action': 'text_insert', 'name': 'note', 'index': 5, 'value': ' World'},
      {'client': 'C', 'action': 'export_update', 'id': 'u3'},
      
      // Sync B and C
      {'client': 'B', 'action': 'import_update', 'id': 'u3'},
      {'client': 'C', 'action': 'import_update', 'id': 'u2'},
      {'client': 'A', 'action': 'import_update', 'id': 'u2'},
      {'client': 'A', 'action': 'import_update', 'id': 'u3'}
    ],
    'expected': {
      'text_any_of': {
        'note': ['Hello Ola World', 'Hello World Ola']
      }
    }
  };

  // Case 9: Adjacent Delete
  cases['09_adjacent_delete'] = {
    'name': 'Concurrent adjacent deletes',
    'clients': ['A', 'B'],
    'steps': [
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': 'The quick brown fox'},
      {'client': 'A', 'action': 'export_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'},
      
      // A deletes "quick " (index 4-10)
      {'client': 'A', 'action': 'text_delete', 'name': 'note', 'index': 4, 'length': 6},
      
      // B deletes "brown " (index 10-16)
      {'client': 'B', 'action': 'text_delete', 'name': 'note', 'index': 10, 'length': 6},
      
      // Sync A and B
      {'client': 'A', 'action': 'export_state_vector', 'id': 'svA'},
      {'client': 'B', 'action': 'import_state_vector_and_export_diff', 'state_vector_id': 'svA', 'diff_id': 'diffB'},
      {'client': 'A', 'action': 'import_update', 'id': 'diffB'},

      {'client': 'B', 'action': 'export_state_vector', 'id': 'svB'},
      {'client': 'A', 'action': 'import_state_vector_and_export_diff', 'state_vector_id': 'svB', 'diff_id': 'diffA'},
      {'client': 'B', 'action': 'import_update', 'id': 'diffA'}
    ],
    'expected': {
      'text': {'note': 'The fox'}
    }
  };

  // Case 10: Overlapping Delete
  cases['10_overlapping_delete'] = {
    'name': 'Concurrent overlapping deletes',
    'clients': ['A', 'B'],
    'steps': [
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': 'The quick brown fox jumps'},
      {'client': 'A', 'action': 'export_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'},
      
      // A deletes "quick brown" (indices 4-15)
      {'client': 'A', 'action': 'text_delete', 'name': 'note', 'index': 4, 'length': 11},
      
      // B deletes "brown fox" (indices 10-19)
      {'client': 'B', 'action': 'text_delete', 'name': 'note', 'index': 10, 'length': 9},
      
      // Sync A and B
      {'client': 'A', 'action': 'export_state_vector', 'id': 'svA'},
      {'client': 'B', 'action': 'import_state_vector_and_export_diff', 'state_vector_id': 'svA', 'diff_id': 'diffB'},
      {'client': 'A', 'action': 'import_update', 'id': 'diffB'},

      {'client': 'B', 'action': 'export_state_vector', 'id': 'svB'},
      {'client': 'A', 'action': 'import_state_vector_and_export_diff', 'state_vector_id': 'svB', 'diff_id': 'diffA'},
      {'client': 'B', 'action': 'import_update', 'id': 'diffA'}
    ],
    'expected': {
      'text': {'note': 'The  jumps'}
    }
  };

  // Case 11: Random Deletes
  cases['11_random_deletes'] = {
    'name': 'Random concurrent deletes simulation',
    'clients': ['A', 'B'],
    'steps': [
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': '0123456789ABCDEF'},
      {'client': 'A', 'action': 'export_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'},
      
      {'client': 'A', 'action': 'text_delete', 'name': 'note', 'index': 1, 'length': 2}, // deletes 1, 2
      {'client': 'A', 'action': 'text_delete', 'name': 'note', 'index': 5, 'length': 3}, // deletes 7, 8, 9 (after 1,2 gone)
      {'client': 'A', 'action': 'export_update', 'id': 'u2'},
      
      {'client': 'B', 'action': 'text_delete', 'name': 'note', 'index': 13, 'length': 2}, // deletes D, E
      {'client': 'B', 'action': 'text_delete', 'name': 'note', 'index': 8, 'length': 3}, // deletes 8, 9, A
      {'client': 'B', 'action': 'export_update', 'id': 'u3'},
      
      {'client': 'A', 'action': 'import_update', 'id': 'u3'},
      {'client': 'B', 'action': 'import_update', 'id': 'u2'}
    ],
    'expected': {
      'text': {'note': '03456BCF'}
    }
  };

  // Case 12: Random Inserts
  cases['12_random_inserts'] = {
    'name': 'Random concurrent inserts simulation',
    'clients': ['A', 'B'],
    'steps': [
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': 'Start'},
      {'client': 'A', 'action': 'export_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'},
      
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 2, 'value': 'X'}, // StXart
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 5, 'value': 'Y'}, // StXarYt
      {'client': 'A', 'action': 'export_update', 'id': 'u2'},
      
      {'client': 'B', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': 'W'}, // WStart
      {'client': 'B', 'action': 'text_insert', 'name': 'note', 'index': 4, 'value': 'Z'}, // WStaZrt
      {'client': 'B', 'action': 'export_update', 'id': 'u3'},
      
      {'client': 'A', 'action': 'import_update', 'id': 'u3'},
      {'client': 'B', 'action': 'import_update', 'id': 'u2'}
    ],
    'expected': {
      'text': {'note': 'WStXZarYt'} // Determined by Yjs client ordering
    }
  };

  // Case 13: Insert/Delete Mix
  cases['13_insert_delete_mix'] = {
    'name': 'Concurrent Insert and Delete mix',
    'clients': ['A', 'B'],
    'steps': [
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': 'ABCDEF'},
      {'client': 'A', 'action': 'export_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'},
      
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 3, 'value': 'xyz'}, // ABCxyzDEF
      {'client': 'A', 'action': 'text_delete', 'name': 'note', 'index': 0, 'length': 2}, // CxyzDEF
      {'client': 'A', 'action': 'export_update', 'id': 'u2'},
      
      {'client': 'B', 'action': 'text_delete', 'name': 'note', 'index': 4, 'length': 2}, // ABCD
      {'client': 'B', 'action': 'text_insert', 'name': 'note', 'index': 2, 'value': '123'}, // AB123CD
      {'client': 'B', 'action': 'export_update', 'id': 'u3'},
      
      {'client': 'A', 'action': 'import_update', 'id': 'u3'},
      {'client': 'B', 'action': 'import_update', 'id': 'u2'}
    ],
    'expected': {
      'text': {'note': 'C123xyzD'}
    }
  };

  // Case 14: State Vector Sync
  cases['14_state_vector'] = {
    'name': 'State Vector incremental sync',
    'clients': ['A', 'B'],
    'steps': [
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': 'Start'},
      {'client': 'A', 'action': 'export_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'},
      
      // Client A makes multiple incremental insertions
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 5, 'value': ' A'},
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 7, 'value': ' B'},
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 9, 'value': ' C'},
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 11, 'value': ' D'},
      
      // Sync A to B using State Vector
      {'client': 'B', 'action': 'export_state_vector', 'id': 'svB'},
      {'client': 'A', 'action': 'import_state_vector_and_export_diff', 'state_vector_id': 'svB', 'diff_id': 'diffA'},
      {'client': 'B', 'action': 'import_update', 'id': 'diffA'}
    ],
    'expected': {
      'text': {'note': 'Start A B C D'}
    }
  };

  // Case 15: State Vector Fuzz
  cases['15_state_vector_fuzz'] = {
    'name': 'Periodic State Vector exchange fuzzing scenario',
    'clients': ['A', 'B'],
    'steps': [
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': 'Initial'},
      {'client': 'A', 'action': 'export_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'},
      
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 7, 'value': ' A'},
      {'client': 'B', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': 'B '},
      
      // Periodic SV sync A -> B
      {'client': 'B', 'action': 'export_state_vector', 'id': 'svB1'},
      {'client': 'A', 'action': 'import_state_vector_and_export_diff', 'state_vector_id': 'svB1', 'diff_id': 'diffA1'},
      {'client': 'B', 'action': 'import_update', 'id': 'diffA1'},
      
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 9, 'value': ' C'},
      {'client': 'B', 'action': 'text_insert', 'name': 'note', 'index': 1, 'value': 'D'},
      
      // Periodic SV sync B -> A
      {'client': 'A', 'action': 'export_state_vector', 'id': 'svA1'},
      {'client': 'B', 'action': 'import_state_vector_and_export_diff', 'state_vector_id': 'svA1', 'diff_id': 'diffB1'},
      {'client': 'A', 'action': 'import_update', 'id': 'diffB1'},
      
      // Final SV sync A -> B to ensure convergence
      {'client': 'B', 'action': 'export_state_vector', 'id': 'svB2'},
      {'client': 'A', 'action': 'import_state_vector_and_export_diff', 'state_vector_id': 'svB2', 'diff_id': 'diffA2'},
      {'client': 'B', 'action': 'import_update', 'id': 'diffA2'}
    ],
    'expected': {
      'text': {'note': 'BD  Initial A C'}
    }
  };

  // Case 16: Snapshot
  cases['16_snapshot'] = {
    'name': 'Snapshot restore roundtrip',
    'clients': ['A', 'B'],
    'steps': [
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': 'First Version'},
      {'client': 'A', 'action': 'take_snapshot', 'id': 'snap1'},
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 13, 'value': ' and Second Version'},
      {'client': 'B', 'action': 'restore_snapshot', 'source_client': 'A', 'snapshot_id': 'snap1'}
    ],
    'expected': {
      'text': {'note': 'First Version'}
    }
  };

  // Case 17: Snapshot Peer Offline
  cases['17_snapshot_peer_offline'] = {
    'name': 'Snapshot restore with peer offline modifications',
    'clients': ['A', 'B', 'C'],
    'steps': [
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': 'Base'},
      {'client': 'A', 'action': 'export_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'},
      {'client': 'C', 'action': 'import_update', 'id': 'u1'},
      
      // Client C goes offline
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 4, 'value': ' + OnlineA'},
      {'client': 'A', 'action': 'take_snapshot', 'id': 'snapA'},
      
      // C edits offline
      {'client': 'C', 'action': 'text_insert', 'name': 'note', 'index': 4, 'value': ' + OfflineC'},
      
      // C comes back online and merges A's snapshot
      {'client': 'B', 'action': 'restore_snapshot', 'source_client': 'A', 'snapshot_id': 'snapA'}, // B gets snapshot A state
      {'client': 'B', 'action': 'export_update', 'id': 'uB_snap'},
      {'client': 'C', 'action': 'import_update', 'id': 'uB_snap'}, // C merges B's snapshot update
      {'client': 'C', 'action': 'export_update', 'id': 'uC_edits'},
      {'client': 'A', 'action': 'import_update', 'id': 'uC_edits'} // A merges C's offline edits
    ],
    'expected': {
      'text': {'note': 'Base + OfflineC + OnlineA'}
    }
  };

  // Case 18: Large Document
  final largeTextStr = 'Integration scale text...\n' * 2000; // ~50k characters
  cases['18_large_document'] = {
    'name': 'Large Document operations integration scale',
    'clients': ['A', 'B'],
    'steps': [
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': largeTextStr},
      {'client': 'A', 'action': 'export_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'}
    ],
    'expected': {
      'text': {'note': largeTextStr}
    }
  };

  // Case 19: UTF-8
  cases['19_utf8'] = {
    'name': 'UTF-8 multi-language and emoji validation',
    'clients': ['A', 'B'],
    'steps': [
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': 'Emojis: 👨‍👩‍👧‍👦, Accents: café, Chinese: 你好, Arabic: مرحبا'},
      {'client': 'A', 'action': 'export_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'}
    ],
    'expected': {
      'text': {'note': 'Emojis: 👨‍👩‍👧‍👦, Accents: café, Chinese: 你好, Arabic: مرحبا'}
    }
  };

  // Case 20: Persistence
  cases['20_persistence'] = {
    'name': 'Document persistence state restore and continue editing',
    'clients': ['A', 'B'],
    'steps': [
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': 'Offline State Saved'},
      {'client': 'A', 'action': 'export_update', 'id': 'save1'},
      
      // B loads the saved state as persistence init
      {'client': 'B', 'action': 'import_update', 'id': 'save1'},
      {'client': 'B', 'action': 'text_insert', 'name': 'note', 'index': 19, 'value': ' - Reopened'},
      {'client': 'B', 'action': 'export_update', 'id': 'u2'},
      {'client': 'A', 'action': 'import_update', 'id': 'u2'}
    ],
    'expected': {
      'text': {'note': 'Offline State Saved - Reopened'}
    }
  };

  // Case 21: Undo
  cases['21_undo'] = {
    'name': 'UndoManager basic undo/redo validation',
    'clients': ['A', 'B'],
    'steps': [
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': 'Hello'},
      {'client': 'A', 'action': 'export_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'},
      
      // Local edits on A
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 5, 'value': ' World'},
      {'client': 'A', 'action': 'undo', 'name': 'note'}, // Undoes " World" -> Hello
      
      // Sync B
      {'client': 'A', 'action': 'export_update', 'id': 'u2'},
      {'client': 'B', 'action': 'import_update', 'id': 'u2'},
      
      // Redo
      {'client': 'A', 'action': 'redo', 'name': 'note'}, // Redoes " World" -> Hello World
      {'client': 'A', 'action': 'export_update', 'id': 'u3'},
      {'client': 'B', 'action': 'import_update', 'id': 'u3'}
    ],
    'expected': {
      'text': {'note': 'Hello World'}
    }
  };

  // Case 22: Map
  cases['22_map'] = {
    'name': 'Map concurrent updates and merges',
    'clients': ['A', 'B'],
    'steps': [
      {'client': 'A', 'action': 'map_set', 'name': 'meta', 'key': 'title', 'value': 'DocA'},
      {'client': 'A', 'action': 'export_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'},
      
      // Concurrent sets
      {'client': 'A', 'action': 'map_set', 'name': 'meta', 'key': 'desc', 'value': 'A description'},
      {'client': 'B', 'action': 'map_set', 'name': 'meta', 'key': 'desc', 'value': 'B description'},
      {'client': 'B', 'action': 'map_set', 'name': 'meta', 'key': 'author', 'value': 'B'},
      
      {'client': 'A', 'action': 'export_update', 'id': 'u2'},
      {'client': 'B', 'action': 'export_update', 'id': 'u3'},
      
      {'client': 'A', 'action': 'import_update', 'id': 'u3'},
      {'client': 'B', 'action': 'import_update', 'id': 'u2'}
    ],
    'expected': {
      'map': {
        'meta': {
          'title': 'DocA',
          // Client ID B (66) is greater than A (65), so B's value wins for desc
          'desc': 'B description',
          'author': 'B'
        }
      }
    }
  };

  // Case 23: Array
  cases['23_array'] = {
    'name': 'Array concurrent insertions and merges',
    'clients': ['A', 'B'],
    'steps': [
      {'client': 'A', 'action': 'array_insert', 'name': 'list', 'index': 0, 'value': 'item1'},
      {'client': 'A', 'action': 'export_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'},
      
      // Concurrent array inserts
      {'client': 'A', 'action': 'array_insert', 'name': 'list', 'index': 0, 'value': 'itemA'},
      {'client': 'B', 'action': 'array_insert', 'name': 'list', 'index': 1, 'value': 'itemB'},
      
      {'client': 'A', 'action': 'export_update', 'id': 'u2'},
      {'client': 'B', 'action': 'export_update', 'id': 'u3'},
      
      {'client': 'A', 'action': 'import_update', 'id': 'u3'},
      {'client': 'B', 'action': 'import_update', 'id': 'u2'}
    ],
    'expected': {
      'array': {
        'list': ['itemA', 'item1', 'itemB'] // Resolved by Yjs index coordinates
      }
    }
  };

  // Case 24: Nested Structures
  cases['24_nested_structures'] = {
    'name': 'Nested shared types (map containing array and map)',
    'clients': ['A', 'B'],
    'steps': [
      {'client': 'A', 'action': 'map_set', 'name': 'meta', 'key': 'info', 'value': {'tags': ['crdt', 'yjs']}},
      {'client': 'A', 'action': 'export_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'},
      
      // Concurrently add a nested field and update existing tags
      {'client': 'A', 'action': 'map_set', 'name': 'meta', 'key': 'version', 'value': 1.0},
      {'client': 'A', 'action': 'export_update', 'id': 'u2'},
      {'client': 'B', 'action': 'import_update', 'id': 'u2'}
    ],
    'expected': {
      'map': {
        'meta': {
          'info': {'tags': ['crdt', 'yjs']},
          'version': 1.0
        }
      }
    }
  };

  // Case 25: Fuzzing Completo
  cases['25_fuzzing_completo'] = {
    'name': 'Comprehensive integration fuzzing scenario',
    'clients': ['A', 'B', 'C'],
    'steps': [
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 0, 'value': 'Initial state'},
      {'client': 'A', 'action': 'export_update', 'id': 'u1'},
      {'client': 'B', 'action': 'import_update', 'id': 'u1'},
      {'client': 'C', 'action': 'import_update', 'id': 'u1'},
      
      // Client A edits text, Client B sets map, Client C inserts into array
      {'client': 'A', 'action': 'text_insert', 'name': 'note', 'index': 13, 'value': ' plus A'},
      {'client': 'B', 'action': 'map_set', 'name': 'meta', 'key': 'sync', 'value': true},
      {'client': 'C', 'action': 'array_insert', 'name': 'list', 'index': 0, 'value': 42},
      
      {'client': 'A', 'action': 'export_update', 'id': 'uA'},
      {'client': 'B', 'action': 'export_update', 'id': 'uB'},
      {'client': 'C', 'action': 'export_update', 'id': 'uC'},
      
      // Delays and duplicates in delivery
      {'client': 'A', 'action': 'import_update', 'id': 'uB'},
      {'client': 'A', 'action': 'import_update', 'id': 'uC'},
      {'client': 'A', 'action': 'import_update', 'id': 'uB'}, // Duplicate
      
      {'client': 'B', 'action': 'import_update', 'id': 'uA'},
      {'client': 'B', 'action': 'import_update', 'id': 'uC'},
      
      {'client': 'C', 'action': 'import_update', 'id': 'uA'},
      {'client': 'C', 'action': 'import_update', 'id': 'uB'},
      {'client': 'C', 'action': 'import_update', 'id': 'uA'} // Duplicate
    ],
    'expected': {
      'text': {'note': 'Initial state plus A'},
      'map': {'meta': {'sync': true}},
      'array': {'list': [42]}
    }
  };

  // Write all case steps files
  cases.forEach((dirName, data) {
    final dir = Directory('cases/$dirName');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    
    // Write steps.json
    final stepsFile = File('${dir.path}/steps.json');
    stepsFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
    print('Generated cases/$dirName/steps.json');
  });

  print('Done generating all cases.');
}
