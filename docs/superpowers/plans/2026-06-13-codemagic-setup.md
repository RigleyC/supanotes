# Codemagic Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Configure Codemagic CI/CD for building unsigned and signed iOS IPAs, set up the local Codemagic CLI tools, and configure the community Codemagic MCP server.

**Architecture:** Create `codemagic.yaml` with dual-mode build workflows (unsigned and signed distribution). Provide a PowerShell setup script to install `codemagic-cli-tools` and print MCP server configuration.

**Tech Stack:** Codemagic YAML configuration, Python/pip (local CLI), Node/npx (MCP server).

---

### Task 1: Create `codemagic.yaml`

**Files:**
- Create: `codemagic.yaml` (Project Root)

- [ ] **Step 1: Write `codemagic.yaml` file**

Create the file `codemagic.yaml` with the following content:
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
        - app_store_credentials
      vars:
        API_BASE_URL: "https://backend-winter-waterfall-5807.fly.dev/api/v1"
        APP_STORE_APP_ID: 6440000000
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

- [ ] **Step 2: Commit the file**
Run:
```bash
git add codemagic.yaml
git commit -m "ci(codemagic): add codemagic.yaml with signed and unsigned ios build workflows"
```

---

### Task 2: Create local setup script for Windows CLI and MCP

**Files:**
- Create: `scripts/setup_codemagic.ps1`

- [ ] **Step 1: Write `scripts/setup_codemagic.ps1`**

Create the file `scripts/setup_codemagic.ps1` to check dependencies, install `codemagic-cli-tools` via pip, and output the Claude Desktop / Cursor MCP server instructions.

```powershell
# scripts/setup_codemagic.ps1

Write-Host "=== Setting up Codemagic CLI Tools ===" -ForegroundColor Cyan

# Check Python/pip
if (Get-Command pip -ErrorAction SilentlyContinue) {
    Write-Host "Found pip. Installing codemagic-cli-tools..." -ForegroundColor Green
    pip install codemagic-cli-tools
} else {
    Write-Warning "pip is not found on PATH. Please install Python and add it to your PATH."
    exit 1
}

# Verify installation
if (Get-Command keychain -ErrorAction SilentlyContinue) {
    Write-Host "Codemagic CLI Tools successfully installed!" -ForegroundColor Green
} else {
    Write-Warning "Codemagic CLI Tools installed but binary paths are not on PATH."
    Write-Host "You may need to add the Python Scripts directory (e.g. %APPDATA%\Python\Scripts) to your PATH." -ForegroundColor Yellow
}

# Output MCP Server Instructions
Write-Host "`n=== Codemagic MCP Server Setup Instructions ===" -ForegroundColor Cyan
Write-Host "To enable your AI assistant (like Claude or Cursor) to trigger builds, add the following" -ForegroundColor White
Write-Host "configuration to your Claude Desktop config file at %APPDATA%\Claude\claude_desktop_config.json" -ForegroundColor White
Write-Host "or your Cursor MCP settings:" -ForegroundColor White
Write-Host ""
Write-Host @"
{
  "mcpServers": {
    "codemagic": {
      "command": "npx",
      "args": [
        "-y",
        "codemagic-mcp"
      ],
      "env": {
        "CODEMAGIC_API_KEY": "YOUR_CODEMAGIC_API_KEY_HERE"
      }
    }
  }
}
"@ -ForegroundColor Gray

Write-Host ""
Write-Host "Ensure you replace 'YOUR_CODEMAGIC_API_KEY_HERE' with your actual Codemagic API key." -ForegroundColor Yellow
```

- [ ] **Step 2: Commit the setup script**
Run:
```bash
git add scripts/setup_codemagic.ps1
git commit -m "chore(scripts): add setup_codemagic.ps1 helper script"
```

---

### Task 3: Execute and Verify Local Setup

- [ ] **Step 1: Execute `setup_codemagic.ps1` locally**

Run:
```powershell
powershell -ExecutionPolicy Bypass -File scripts/setup_codemagic.ps1
```
Expected output: Successful installation of `codemagic-cli-tools` and printed instructions for MCP Server.
