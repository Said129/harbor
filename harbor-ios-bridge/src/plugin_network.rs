//! Asynchronous network ABI. Callbacks own no Rust allocation and occur exactly once.
use crate::plugin_http;
use serde_json::{json, Value};
use std::{
    collections::HashMap,
    ffi::c_void,
    future::Future,
    sync::{
        atomic::{AtomicU64, Ordering},
        Mutex, OnceLock,
    },
};
use tokio::runtime::Runtime;
use tokio_util::sync::CancellationToken;

const MAX_REQUEST: usize = 16 * 1024 * 1024;
const MAX_REQUESTS: usize = 64;
type Callback = extern "C" fn(*mut c_void, *const u8, usize);
static NEXT_ID: AtomicU64 = AtomicU64::new(1);
static REQUESTS: OnceLock<Mutex<HashMap<u64, CancellationToken>>> = OnceLock::new();

fn requests() -> &'static Mutex<HashMap<u64, CancellationToken>> {
    REQUESTS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn runtime() -> Option<&'static Runtime> {
    static RUNTIME: OnceLock<Option<Runtime>> = OnceLock::new();
    RUNTIME
        .get_or_init(|| {
            tokio::runtime::Builder::new_multi_thread()
                .worker_threads(2)
                .thread_name("harbor-network")
                .enable_all()
                .build()
                .ok()
        })
        .as_ref()
}

fn start<F>(context: usize, callback: Callback, operation: F) -> u64
where
    F: Future<Output = Result<Value, &'static str>> + Send + 'static,
{
    let Some(runtime) = runtime() else {
        return 0;
    };
    let Ok(id) = NEXT_ID.try_update(Ordering::Relaxed, Ordering::Relaxed, |id| id.checked_add(1))
    else {
        return 0;
    };
    let cancellation = CancellationToken::new();
    {
        let Ok(mut values) = requests().lock() else {
            return 0;
        };
        if values.len() >= MAX_REQUESTS {
            return 0;
        }
        values.insert(id, cancellation.clone());
    }
    runtime.spawn(async move {
        // A separate supervised task converts an execution panic to a terminal callback too.
        let mut task = tokio::spawn(operation);
        let result = tokio::select! {
            biased;
            _ = cancellation.cancelled() => { task.abort(); let _ = task.await; Err("plugin-network-cancelled") }
            result = &mut task => result.unwrap_or(Err("plugin-network-panic")),
        };
        if let Ok(mut values) = requests().lock() { values.remove(&id); }
        let response = match result {
            Ok(value) => json!({"ok":true,"data":value}),
            Err(code) => json!({"ok":false,"error":{"code":code}}),
        };
        let response = response.to_string();
        callback(context as *mut c_void, response.as_ptr(), response.len());
    });
    id
}

#[no_mangle]
pub extern "C" fn harbor_ios_network_abi_version() -> u32 {
    1
}

/// A nonzero handle promises exactly one callback, including cancellation or malformed JSON.
/// Zero means no callback and the caller retains its context. No Rust pointer escapes.
///
/// # Safety
/// `input` must name `length` readable bytes for this call. The callback/context must
/// remain valid until its one invocation, on a background thread. The callback must
/// copy the length-delimited response JSON before returning; it must not free the pointer.
#[no_mangle]
pub unsafe extern "C" fn harbor_ios_network_start(
    input: *const u8,
    length: usize,
    context: *mut c_void,
    callback: Option<Callback>,
) -> u64 {
    let Some(callback) = callback else {
        return 0;
    };
    if input.is_null() || length == 0 || length > MAX_REQUEST {
        return 0;
    }
    let parsed = serde_json::from_slice::<plugin_http::Request>(unsafe {
        std::slice::from_raw_parts(input, length)
    });
    start(context as usize, callback, async move {
        let request = parsed.map_err(|_| "plugin-network-request-format")?;
        let response = plugin_http::execute(request).await?;
        serde_json::to_value(response).map_err(|_| "plugin-network-response-format")
    })
}

/// Cancel an outstanding operation; the promised callback still fires exactly once.
#[no_mangle]
pub extern "C" fn harbor_ios_network_cancel(handle: u64) {
    let token = requests()
        .lock()
        .ok()
        .and_then(|values| values.get(&handle).cloned());
    if let Some(token) = token {
        token.cancel();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{sync::mpsc, time::Duration};

    extern "C" fn completion(context: *mut c_void, bytes: *const u8, length: usize) {
        let sender = unsafe { Box::from_raw(context.cast::<mpsc::Sender<Value>>()) };
        let bytes = unsafe { std::slice::from_raw_parts(bytes, length) };
        sender.send(serde_json::from_slice(bytes).unwrap()).unwrap();
    }

    #[test]
    fn plugin_network_cancel_delivers_one_terminal_callback_and_releases_registration() {
        let (sender, receiver) = mpsc::channel::<Value>();
        let context = Box::into_raw(Box::new(sender)) as usize;
        let handle = start(context, completion, std::future::pending());
        assert_ne!(handle, 0);
        harbor_ios_network_cancel(handle);
        let result = receiver.recv_timeout(Duration::from_secs(5)).unwrap();
        assert_eq!(result["error"]["code"], "plugin-network-cancelled");
        assert!(!requests().lock().unwrap().contains_key(&handle));
        assert!(receiver.recv_timeout(Duration::from_millis(30)).is_err());
        harbor_ios_network_cancel(handle);
    }

    #[test]
    fn plugin_network_malformed_json_completes_and_empty_input_never_takes_context() {
        let (sender, receiver) = mpsc::channel::<Value>();
        let context = Box::into_raw(Box::new(sender));
        let bytes = b"owned invalid json";
        let handle = unsafe {
            harbor_ios_network_start(
                bytes.as_ptr(),
                bytes.len(),
                context.cast(),
                Some(completion),
            )
        };
        assert_ne!(handle, 0);
        assert_eq!(
            receiver.recv_timeout(Duration::from_secs(5)).unwrap()["error"]["code"],
            "plugin-network-request-format"
        );
        assert_eq!(
            unsafe {
                harbor_ios_network_start(
                    std::ptr::null(),
                    0,
                    std::ptr::null_mut(),
                    Some(completion),
                )
            },
            0
        );
    }
}
