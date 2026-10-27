set -euo pipefail
mkdir -p ios/build/logs
cargo check --locked --manifest-path harbor-ios-bridge/Cargo.toml 2>&1 | tee ios/build/logs/simkl-playback-import-rust-check.log
cargo test --locked --manifest-path harbor-core/Cargo.toml --no-default-features --test resume tracker_percentage_survives_validation_and_uses_real_runtime_from_the_same_entry -- --exact 2>&1 | tee ios/build/logs/simkl-playback-import-core-test.log
cargo test --locked --manifest-path harbor-ios-bridge/Cargo.toml --test bridge tracker_percentage_crosses_the_real_abi_and_preserves_legacy_entries -- --exact 2>&1 | tee ios/build/logs/simkl-playback-import-bridge-test.log
python3 scripts/ios/record-simkl-playback-import-rust.py
