set -euo pipefail
mkdir -p ios/build/logs
export RUSTFLAGS="${RUSTFLAGS:-} -D warnings"
cargo check --locked --manifest-path harbor-core/Cargo.toml --no-default-features 2>&1 | tee ios/build/logs/music-large-core-check.log
cargo check --locked --manifest-path harbor-ios-bridge/Cargo.toml 2>&1 | tee ios/build/logs/music-large-bridge-check.log
cargo test --locked --manifest-path harbor-core/Cargo.toml --no-default-features --lib music::tests::large_playlist_order_preserves_every_member_and_full_transport_ids -- --exact --test-threads=1 2>&1 | tee ios/build/logs/music-large-rust-test.log
python3 scripts/ios/record-music-export-large-rust.py
