# Design Specification: Codemagic IPA Builds & Integrations

**Date:** 2026-06-13  
**Status:** Draft  
**Author:** Antigravity

---

## 1. Goal Description

Configure the SupaNotes project to build iOS `.ipa` files using Codemagic CI/CD. This includes:
1. Creating a `codemagic.yaml` in the root of the project with support for unsigned builds (for sideloading/testing) and signed builds (for distribution).
2. Configuring the Codemagic CLI tools locally on the developer's Windows machine.
3. Setting up the community Codemagic MCP server (`stefanoamorelli/codemagic-mcp`) to allow triggering builds and monitoring pipelines from AI clients (Claude Desktop, Cursor).

---

## 2. Proposed Changes

### `codemagic.yaml` (Project Root)
We will add `codemagic.yaml` to the root folder. It will define the environment, workflows, and build scripts.

```yaml
# codemagic.yaml
workflows:
  ios-unsigned:
    name: iOS Unsigned Build
    max_build_duration: 60
    instance_type: mac_mini_m1
    environment:
      groups:
        - api_config
      vars:
        API_BASE_URL: "https://backend-winter-waterfall-5807.fly.dev/api/v1"
      flutter: 3.44.1
      xcode: latest
      cocoapods: default
    triggering:
      events:
        - push
      branch_patterns:
        - pattern: 'master'
          include: true
    scripts:
      - name: Flutter pub get
        script: |
          flutter pub get
      - name: Flutter build config-only
        script: |
          flutter build ios --config-only --dart-define=API_BASE_URL="$API_BASE_URL"
      - name: Clean Swift Package Manager artifacts
        script: |
          rm -rf ~/Library/Caches/org.swift.swiftpm/artifacts
      - name: Build iOS project with xcodebuild
        script: |
          cd ios
          xcodebuild -workspace Runner.xcworkspace \
            -scheme Runner \
            -configuration Release \
            -destination 'generic/platform=iOS' \
            -derivedDataPath ../DerivedData \
            CODE_SIGNING_ALLOWED=NO \
            DEVELOPMENT_TEAM="" \
            COMPILER_INDEX_STORE_ENABLE=NO \
            IPHONEOS_DEPLOYMENT_TARGET=15.0 \
            FLUTTER_BUILD_EXTRA_FRONT_END_OPTIONS="--dart-define=API_BASE_URL=$API_BASE_URL" \
            clean build
      - name: Package Unsigned IPA
        script: |
          APP_PATH=$(find DerivedData/Build/Products/Release-iphoneos -name "*.app" -type d | head -1)
          if [ -z "$APP_PATH" ]; then
            echo "Error: Could not find .app"
            exit 1
          fi
          mkdir -p build/Payload
          cp -R "$APP_PATH" build/Payload/
          cd build
          zip -rq supanotes-unsigned.ipa Payload
          rm -rf Payload
    artifacts:
      - build/*.ipa

  ios-signed:
    name: iOS Signed Release Build
    max_build_duration: 60
    instance_type: mac_mini_m1
    environment:
      groups:
        - api_config
        - app_store_credentials # Stores APP_STORE_CONNECT_ISSUER_ID, APP_STORE_CONNECT_KEY_IDENTIFIER, APP_STORE_CONNECT_PRIVATE_KEY, APP_STORE_CONNECT_CERTIFICATE_PRIVATE_KEY
      vars:
        API_BASE_URL: "https://backend-winter-waterfall-5807.fly.dev/api/v1"
        APP_STORE_APP_ID: 6440000000 # Example App ID
      flutter: 3.44.1
      xcode: latest
      cocoapods: default
    triggering:
      events:
        - push
      branch_patterns:
        - pattern: 'master'
          include: true
    scripts:
      - name: Flutter pub get
        script: |
          flutter pub get
      - name: Set up keychain
        script: |
          keychain initialize
      - name: Fetch signing certificates and profiles
        script: |
          app-store-connect fetch-signing-files "com.example.supanotes" \
            --issuer-id "$APP_STORE_CONNECT_ISSUER_ID" \
            --key-id "$APP_STORE_CONNECT_KEY_IDENTIFIER" \
            --private-key "$APP_STORE_CONNECT_PRIVATE_KEY" \
            --certificate-key "$APP_STORE_CONNECT_CERTIFICATE_PRIVATE_KEY" \
            --create
      - name: Use profiles
        script: |
          xcode-project use-profiles
      - name: Build iOS IPA
        script: |
          flutter build ipa --release \
            --dart-define=API_BASE_URL="$API_BASE_URL" \
            --export-options-plist=/Users/builder/export_options.plist
    artifacts:
      - build/ios/ipa/*.ipa
```

---

## 3. Local CLI Configuration (Windows)

The Codemagic CLI tools can be installed locally on Windows via Python/pip. Although you cannot compile iOS binaries on Windows, the CLI provides options for interacting with Codemagic's APIs and fetching signing metadata.

### Installation
Run:
```powershell
pip install codemagic-cli-tools
```

### Authentication
To authenticate the CLI locally, set the `CODEMAGIC_API_KEY` environment variable in your Windows shell:
```powershell
$env:CODEMAGIC_API_KEY="your-api-key-here"
```

---

## 4. Codemagic MCP Server Setup

The community Codemagic MCP Server (`stefanoamorelli/codemagic-mcp`) lets AI agents trigger builds and fetch artifacts from tools like Claude Desktop or Cursor.

### Config integration for Claude Desktop
Add the following to your Claude Desktop configuration file (usually located at `%APPDATA%\Claude\claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "codemagic": {
      "command": "npx",
      "args": [
        "-y",
        "codemagic-mcp"
      ],
      "env": {
        "CODEMAGIC_API_KEY": "your-api-key-here"
      }
    }
  }
}
```

---

## 5. Verification Plan

### Manual Verification
1. Verify `codemagic.yaml` is syntax-valid using the Codemagic YAML linter or website checker.
2. Confirm the installation of `codemagic-cli-tools` via `pip` on the local command line.
3. Verify that the MCP server is configured in the workspace/user profile.
