#!/bin/bash
# Runs every editor POC sequentially (no CPU contention) at each scale.
cd "$(dirname "$0")"
for scale in 1 5; do
  for poc in super_editor_poc quill_poc appflowy_poc; do
    for run in 1 2; do
      (cd $poc && timeout 900 flutter test --no-pub --dart-define=SCALE=$scale test/benchmark_test.dart 2>&1 \
        | grep -E "^RESULT" | sed "s/^/scale=$scale run=$run /")
    done
  done
done
