//! Pure synchronous operations and a separate cancellable asynchronous network ABI.
//! No Rust-owned object crosses either boundary.
mod dispatch;
mod font_decode;
mod plugin_http;
pub use font_decode::{harbor_ios_font_decode, harbor_ios_font_free};
mod plugin_network;
pub mod music;
pub use plugin_network::{
    harbor_ios_network_abi_version, harbor_ios_network_cancel, harbor_ios_network_start, harbor_ios_music_start,
};
use std::ffi::{c_char, CString};

pub const MAX_REQUEST_BYTES: usize = 8 * 1024 * 1024;

#[no_mangle]
pub extern "C" fn harbor_ios_abi_version() -> u32 {
    1
}

pub fn call(request: &[u8]) -> String {
    let outcome = std::panic::catch_unwind(|| dispatch::dispatch(request));
    let response = match outcome {
        Ok(Ok(data)) => serde_json::json!({"ok":true,"data":data}),
        Ok(Err(code)) => serde_json::json!({"ok":false,"error":{"code":code}}),
        Err(_) => serde_json::json!({"ok":false,"error":{"code":"core-panic"}}),
    };
    response.to_string()
}

/// Returns a NUL-terminated JSON response, owned by Rust. Free exactly once.
///
/// # Safety
/// Input must point to `length` readable bytes, remain valid during this call,
/// and not be mutated concurrently. Null is allowed only as an invalid request.
#[no_mangle]
pub unsafe extern "C" fn harbor_ios_call(input: *const u8, length: usize) -> *mut c_char {
    let response = if input.is_null() || length == 0 || length > MAX_REQUEST_BYTES {
        "{\"ok\":false,\"error\":{\"code\":\"invalid-request-size\"}}".to_owned()
    } else {
        call(unsafe { std::slice::from_raw_parts(input, length) })
    };
    // JSON escaping guarantees no interior NUL. No user payload is logged.
    CString::new(response)
        .expect("serialized JSON contains no NUL")
        .into_raw()
}

/// # Safety
/// Pass only an unfreed pointer returned by harbor_ios_call (or null).
#[no_mangle]
pub unsafe extern "C" fn harbor_ios_response_free(response: *mut c_char) {
    if !response.is_null() {
        drop(unsafe { CString::from_raw(response) });
    }
}
