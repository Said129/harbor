set -euo pipefail
mkdir -p ios/build/logs
python3 scripts/ios/retain-simkl-playback-core.py
cargo test --locked --manifest-path harbor-ios-bridge/Cargo.toml --test bridge tracker_percentage_crosses_the_real_abi_and_preserves_legacy_entries -- --exact 2>&1 | tee ios/build/logs/simkl-playback-import-bridge-test.log
python3 scripts/ios/record-simkl-playback-import-rust.py
