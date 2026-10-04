#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
export IPHONEOS_DEPLOYMENT_TARGET=17.0
output="$PWD/ios/Frameworks/HarborCore.xcframework"
export CARGO_TARGET_DIR="$PWD/harbor-ios-bridge/target"
for target in aarch64-apple-ios aarch64-apple-ios-sim; do
  case "$target" in
    aarch64-apple-ios) export SDKROOT="$(xcrun --sdk iphoneos --show-sdk-path)" ;;
    aarch64-apple-ios-sim) export SDKROOT="$(xcrun --sdk iphonesimulator --show-sdk-path)" ;;
  esac
  cargo check --locked --manifest-path harbor-core/Cargo.toml --no-default-features --target "$target"
  cargo build --locked --release --manifest-path harbor-ios-bridge/Cargo.toml --target "$target"
done
mkdir -p ios/Frameworks
if [[ -d "$output" ]]; then
  # Exact generated artifact below the repository; no source directories removed.
  rm -rf "$output"
fi
xcodebuild -create-xcframework \
  -library "$CARGO_TARGET_DIR/aarch64-apple-ios/release/libharbor_ios_bridge.a" -headers harbor-ios-bridge/include \
  -library "$CARGO_TARGET_DIR/aarch64-apple-ios-sim/release/libharbor_ios_bridge.a" -headers harbor-ios-bridge/include \
  -output "$output"
