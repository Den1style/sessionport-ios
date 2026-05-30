#!/bin/bash
# Run this script on Mac to generate the Xcode project
# Usage: bash setup_mac.sh

set -e

echo "==> Checking dependencies..."
if ! command -v brew &>/dev/null; then
  echo "Install Homebrew first: https://brew.sh"
  exit 1
fi

if ! command -v xcodegen &>/dev/null; then
  echo "==> Installing XcodeGen..."
  brew install xcodegen
fi

echo "==> Generating Xcode project..."
xcodegen generate

echo ""
echo "✅ Done! Open SessionPort.xcodeproj in Xcode."
echo ""
echo "Next steps:"
echo "  1. Set your Team ID in Xcode (Signing & Capabilities)"
echo "  2. Replace YOUR_GOOGLE_CLIENT_ID in GoogleDriveService.swift"
echo "  3. Add StoreKit config: File → New → StoreKit Configuration File"
echo "     Product ID: com.sessionport.app.pro.monthly"
echo "     Type: Auto-Renewable Subscription, Price: \$4.99"
echo "  4. Build & run on device (keyboard extensions need real device)"
