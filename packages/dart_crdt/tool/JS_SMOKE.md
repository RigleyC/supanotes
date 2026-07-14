# Compiled JavaScript Smoke Checks

Run the web compatibility smoke check from the package root:

```sh
dart run tool/run_js_smoke.dart
```

The runner compiles `tool/js_smoke.dart` with `dart compile js` and executes the
generated JavaScript with Node. Generated artifacts are written under
`.dart_tool/ycrdt_js_smoke/`, which is intentionally outside the publishable
package contents.

Covered scenarios:

- Binary primitives: byte readers/writers, varints, and state-vector encoding.
- Update algebra: V1/V2 merge, diff, and apply.
- Random convergence: V1/V2 update delivery with disconnects, out-of-order
  delivery, duplicate delivery, insert updates, and delete-set updates.

Platform notes:

- RSS and VM allocation metrics are intentionally unsupported in compiled
  JavaScript; those remain VM benchmark metrics.
- The smoke threshold is a loose catastrophic limit for CI stability, not a
  calibrated browser benchmark.
- Node is used as the scheduled CI runtime for the compiled output. Browser
  matrix coverage can be added later if package dependencies introduce a web
  test runner.
