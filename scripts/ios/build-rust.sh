#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
export IPHONEOS_DEPLOYMENT_TARGET=17.0
output="$PWD/ios/Frameworks/HarborCore.xcframework"
export CARGO_TARGET_DIR="$PWD/harbor-ios-bridge/target"
for target in aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios; do
  case "$target" in
    aarch64-apple-ios) export SDKROOT="$(xcrun --sdk iphoneos --show-sdk-path)" ;;
    aarch64-apple-ios-sim|x86_64-apple-ios) export SDKROOT="$(xcrun --sdk iphonesimulator --show-sdk-path)" ;;
  esac
  cargo check --locked --manifest-path harbor-core/Cargo.toml --no-default-features --target "$target"
  cargo build --locked --release --manifest-path harbor-ios-bridge/Cargo.toml --target "$target"
done
# Generic simulator builds target both Apple Silicon and Intel architectures.
simulator_library="$CARGO_TARGET_DIR/ios-simulator/libharbor_ios_bridge.a"
mkdir -p "$(dirname "$simulator_library")"
xcrun lipo -create \
  "$CARGO_TARGET_DIR/aarch64-apple-ios-sim/release/libharbor_ios_bridge.a" \
  "$CARGO_TARGET_DIR/x86_64-apple-ios/release/libharbor_ios_bridge.a" \
  -output "$simulator_library"
xcrun lipo -verify_arch arm64 x86_64 "$simulator_library"
mkdir -p ios/Frameworks
if [[ -d "$output" ]]; then
  # Exact generated artifact below the repository; no source directories removed.
  rm -rf "$output"
fi
xcodebuild -create-xcframework \
  -library "$CARGO_TARGET_DIR/aarch64-apple-ios/release/libharbor_ios_bridge.a" -headers harbor-ios-bridge/include \
  -library "$simulator_library" -headers harbor-ios-bridge/include \
  -output "$output"
