# Riverpod 3.x — Convenções do SupaNotes

## Stack
- `flutter_riverpod: ^3.3.1`
- **Sem codegen** (`@riverpod`, `riverpod_generator`, `.g.dart`).
- Providers escritos manualmente.

## Quando usar cada provider

| Caso | Provider |
|---|---|
| Fetch único (HTTP, do cache) | `FutureProvider<T>` |
| Stream do banco (Drift) | `StreamProvider<T>` |
| Stream do banco parametrizado | `StreamProvider.family<T, Arg>` |
| Fetch único parametrizado | `FutureProvider.family<T, Arg>` |
| State compartilhado + mutação complexa | `Notifier<T>` / `AsyncNotifier<T>` |
| State UI local | `setState` ou `ValueNotifier` no widget (não vira provider) |

## Padrões de declaração

### FutureProvider
```dart
final xProvider = FutureProvider<X>((ref) async {
  return ref.read(repoProvider).getX();
});
```

### StreamProvider
```dart
final yProvider = StreamProvider<List<Y>>((ref) {
  return ref.read(repoProvider).watchY();
});
```

### Provider (singleton / DI)
```dart
final myServiceProvider = Provider<MyService>((ref) {
  final service = MyService(ref.watch(depProvider));
  ref.onDispose(service.dispose);
  return service;
});
```

### Notifier
```dart
class MyNotifier extends Notifier<MyState> {
  @override
  MyState build() {
    final dep = ref.watch(depProvider);
    return MyState(dep);
  }

  void doSomething() {
    state = state.copyWith(...);
  }
}

final myNotifierProvider =
    NotifierProvider<MyNotifier, MyState>(MyNotifier.new);
```

## autoDispose vs keepAlive

### autoDispose (padrão)
```dart
final noteProvider = FutureProvider.autoDispose<Note>((ref) async {
  return ref.read(notesRepoProvider).getNote(id);
});
```

### keepAlive (exceções — só os globais)
- `authControllerProvider`
- `goRouterProvider`
- `appDatabaseProvider`
- `apiClientProvider`
- `authLocalStorageProvider`
- `authRepositoryProvider`
- `rawDioProvider`
- `syncServiceProvider`
- `syncStateProvider`
- `connectivityMonitorProvider`
- `sessionCacheProvider`

## Erros comuns (antes/depois)

### ❌ Classe State com copyWith manual
```dart
class MyState { // EVITAR
  final int value;
  const MyState(this.value);
  MyState copyWith({int? value}) => MyState(value: value ?? this.value);
}
```

### ✅ AsyncValue ou record
```dart
// Provider retorna AsyncValue<int>
// ou: typedef MyState = ({int value});
```

### ❌ state.value! sem checar
```dart
state = AsyncValue.data(state.value!.copyWith(x: 1)); // 💥
```

### ✅ valueOrNull ou when
```dart
if (state.hasValue) {
  state = AsyncValue.data(state.value!.copyWith(x: 1));
}
```

### ❌ .first em stream no build
```dart
final data = await repo.watchNotes().first; // 💥 perde o stream
```

### ✅ StreamProvider
```dart
final notesProvider = StreamProvider<List<Note>>((ref) {
  return ref.read(notesRepoProvider).watchNotes();
});
```

### ❌ Engolir erro
```dart
try { ... } catch (e) {
  return const EmptyState(); // 💥 esconde erro do usuário
}
```

### ✅ Propagar
```dart
try { ... } catch (e, st) {
  state = AsyncValue.error(e, st);
}
```

## Checklist PR
Antes de abrir PR:
- [ ] Provider manual (sem `@riverpod`, sem `.g.dart`).
- [ ] Sem `StateNotifier` (deprecated).
- [ ] Sem classe `State`/`Store` com `copyWith` manual.
- [ ] `autoDispose` por padrão (exceto globais).
- [ ] Stream do Drift virou `StreamProvider` — não `.first` em `build()`.
- [ ] UI local está no widget (`setState`/`ValueNotifier`), não no provider.
- [ ] Erros propagam na UI (não engolidos).
- [ ] Sem `state.value!` — usa `valueOrNull` ou `when`/`maybeWhen`.
