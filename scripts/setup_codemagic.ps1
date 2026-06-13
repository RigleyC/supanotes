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
# Note: On Windows, pip installs CLI tools in the user's local site-packages or Python Scripts directory.
# Let's check for keychain.exe or check via Python import to verify.
$InstallSuccess = $false
if (Get-Command keychain -ErrorAction SilentlyContinue) {
    $InstallSuccess = $true
} else {
    # Check if we can run it via Python
    $VerifyCheck = python -c "import codemagic" 2>$null
    if ($LASTEXITCODE -eq 0) {
        $InstallSuccess = $true
    }
}

if ($InstallSuccess) {
    Write-Host "Codemagic CLI Tools successfully installed!" -ForegroundColor Green
} else {
    Write-Warning "Codemagic CLI Tools installed but binary paths may not be on your PATH."
    Write-Host "You may need to add the Python Scripts directory (e.g. C:\Users\<Username>\AppData\Roaming\Python\Python314\Scripts) to your PATH." -ForegroundColor Yellow
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
