#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
export IPHONEOS_DEPLOYMENT_TARGET=17.0
output="$PWD/ios/Frameworks/HarborCore.xcframework"
export CARGO_TARGET_DIR="$PWD/harbor-ios-bridge/target"
mode="${1:---all}"
case "$mode" in
  --all) targets=(aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios) ;;
  --simulator-only)
    case "$(uname -m)" in
      x86_64) targets=(x86_64-apple-ios); simulator_architecture=x86_64 ;;
      arm64) targets=(aarch64-apple-ios-sim); simulator_architecture=arm64 ;;
      *) echo "Unsupported simulator host architecture" >&2; exit 1 ;;
    esac ;;
  *) echo "Usage: build-rust.sh [--all|--simulator-only]" >&2; exit 1 ;;
esac
for target in "${targets[@]}"; do
  case "$target" in
    aarch64-apple-ios) export SDKROOT="$(xcrun --sdk iphoneos --show-sdk-path)" ;;
    aarch64-apple-ios-sim|x86_64-apple-ios) export SDKROOT="$(xcrun --sdk iphonesimulator --show-sdk-path)" ;;
  esac
  # cargo rustc builds the shared dependency too. The full delivery retains its
  # explicit checks; focused simulator validation does not repeat that check pass.
  if [[ "$mode" == "--all" ]]; then
    cargo check --locked --manifest-path harbor-core/Cargo.toml --no-default-features --target "$target"
  fi
  cargo rustc --locked --release --lib --manifest-path harbor-ios-bridge/Cargo.toml --target "$target" -- \
    -C link-arg=-Wl,-install_name,@rpath/HarborCore.framework/HarborCore
done
if [[ "$mode" == "--simulator-only" ]]; then
  simulator_framework="$PWD/ios/build/RustFrameworks/simulator/HarborCore.framework"
  python3 scripts/ios/package-core.py --binary "$CARGO_TARGET_DIR/${targets[0]}/release/libharbor_ios_bridge.dylib" \
    --framework "$simulator_framework" --platform iPhoneSimulator --simulator-architecture "$simulator_architecture"
  mkdir -p ios/Frameworks
  if [[ -d "$output" ]]; then rm -rf "$output"; fi
  xcodebuild -create-xcframework -framework "$simulator_framework" -output "$output"
  exit 0
fi
# Generic simulator builds target both Apple Silicon and Intel architectures.
simulator_library="$CARGO_TARGET_DIR/ios-simulator/libharbor_ios_bridge.dylib"
mkdir -p "$(dirname "$simulator_library")"
xcrun lipo -create \
  "$CARGO_TARGET_DIR/aarch64-apple-ios-sim/release/libharbor_ios_bridge.dylib" \
  "$CARGO_TARGET_DIR/x86_64-apple-ios/release/libharbor_ios_bridge.dylib" \
  -output "$simulator_library"
xcrun lipo "$simulator_library" -verify_arch arm64 x86_64
device_framework="$PWD/ios/build/RustFrameworks/device/HarborCore.framework"
simulator_framework="$PWD/ios/build/RustFrameworks/simulator/HarborCore.framework"
python3 scripts/ios/package-core.py --binary "$CARGO_TARGET_DIR/aarch64-apple-ios/release/libharbor_ios_bridge.dylib" --framework "$device_framework" --platform iPhoneOS
python3 scripts/ios/package-core.py --binary "$simulator_library" --framework "$simulator_framework" --platform iPhoneSimulator
mkdir -p ios/Frameworks
if [[ -d "$output" ]]; then
  # Exact generated artifact below the repository; no source directories removed.
  rm -rf "$output"
fi
xcodebuild -create-xcframework \
  -framework "$device_framework" \
  -framework "$simulator_framework" \
  -output "$output"
