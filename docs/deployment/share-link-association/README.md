# Share Link platform association

The native apps claim the same HTTPS Share Link used by the browser. The
canonical host is a deployment value. The mobile projects use `supanotes.app`
as a local-build default, but production must set the real host before signing.

## Files to publish

Publish the rendered templates below on the Share Link host:

| URL | Source | Content type |
| --- | --- | --- |
| `/.well-known/apple-app-site-association` | `apple-app-site-association.json.tmpl` | `application/json` |
| `/.well-known/assetlinks.json` | `assetlinks.json.tmpl` | `application/json` |

The files must be served over HTTPS without a redirect. Do not publish the
`.tmpl` files or leave a placeholder in a production response.

## Required values

Replace these placeholders during deployment:

- `{{APPLE_TEAM_ID}}`: the Apple Developer Team ID that signs
  `com.rigley.supanotes`.
- `{{ANDROID_RELEASE_SHA256}}`: the SHA-256 fingerprint of the certificate
  that signs the release `com.example.supanotes` APK/AAB. Use one entry for
  each accepted signing certificate when key rotation is active.

The package and bundle IDs are existing project identifiers. This ticket does
not change them.

## Build configuration

- iOS: pass `SHARE_LINK_DOMAIN=<host>` to `xcodebuild`, or keep the
  `supanotes.app` default in the project settings.
- Android: pass `-PshareLinkHost=<host>` to Gradle. The manifest uses this
  value for the HTTPS intent filter and `/s/` path prefix.
- Android release builds must provide a real signing configuration. Pass
  `-PreleaseStoreFile`, `-PreleaseStorePassword`, `-PreleaseKeyAlias`, and
  `-PreleaseKeyPassword`; a debug certificate is never accepted for release.

The mobile host and `PUBLIC_BASE_URL` used by the backend must resolve to the
same canonical HTTPS origin. A mismatch makes the OS association check fail
even when both JSON files are valid.

## Validation

After publishing the files, run:

```powershell
.\scripts\validate-share-link-association.ps1 `
  -BaseUrl https://<share-link-host> `
  -AppleTeamId <apple-team-id> `
  -AndroidSha256 '<sha256-fingerprint>'
```

The validator checks both documents, the app identifiers, and the `/s/*`
path rule. It fails on a missing file, an HTTP redirect/error, invalid JSON,
or a missing expected app entry.
