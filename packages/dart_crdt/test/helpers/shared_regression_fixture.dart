import 'dart:convert';
import 'dart:io';

/// Deterministic shared-type regression scenario settings.
final class SharedRegressionScenario {
  /// Creates shared-type regression scenario settings.
  const SharedRegressionScenario({
    required this.seed,
    required this.replicaCount,
    required this.operationCount,
    required this.networkChurnEvery,
    required this.duplicateDeliveries,
  });

  /// Creates scenario settings from JSON.
  factory SharedRegressionScenario.fromJson(Map<String, Object?> json) {
    return SharedRegressionScenario(
      seed: json['seed'] as int,
      replicaCount: json['replicaCount'] as int,
      operationCount: json['operationCount'] as int,
      networkChurnEvery: json['networkChurnEvery'] as int,
      duplicateDeliveries: json['duplicateDeliveries'] as int,
    );
  }

  /// Deterministic pseudo-random seed.
  final int seed;

  /// Number of replicas in the convergence harness.
  final int replicaCount;

  /// Number of generated operations to apply.
  final int operationCount;

  /// Operation interval for network churn.
  final int networkChurnEvery;

  /// Number of duplicate deliveries to inject for each connected update.
  final int duplicateDeliveries;
}

/// Returns a named shared-type regression scenario from test fixtures.
SharedRegressionScenario sharedRegressionScenario(String name) {
  final file = File('test/fixtures/shared/regression_scenarios.json');
  final root = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final scenarios = root['scenarios']! as Map<String, Object?>;
  final scenario = scenarios[name] as Map<String, Object?>?;
  if (scenario == null) {
    throw StateError('Missing shared regression scenario "$name".');
  }
  return SharedRegressionScenario.fromJson(scenario);
}
