use harbor_ios_bridge::{call, harbor_ios_call, harbor_ios_response_free, MAX_REQUEST_BYTES};
use serde_json::{json, Value};

#[test]
fn invalid_request_does_not_echo_secret() {
    let response = call(br#"{"operation":"unknown","token":"private-value"}"#);
    assert!(!response.contains("private-value"));
    assert_eq!(
        serde_json::from_str::<Value>(&response).unwrap()["error"]["code"],
        "invalid-request"
    );
}

#[test]
fn ownership_utf8_null_and_size_boundaries() {
    let request = br#"{"operation":"normalizeAddon","url":"https://example.com/manifest.json"}"#;
    unsafe {
        let pointer = harbor_ios_call(request.as_ptr(), request.len());
        let value: Value =
            serde_json::from_slice(std::ffi::CStr::from_ptr(pointer).to_bytes()).unwrap();
        assert_eq!(value["ok"], true);
        harbor_ios_response_free(pointer);
        for (pointer, length) in [
            (std::ptr::null(), 0),
            (request.as_ptr(), MAX_REQUEST_BYTES + 1),
        ] {
            let response = harbor_ios_call(pointer, length);
            let value: Value =
                serde_json::from_slice(std::ffi::CStr::from_ptr(response).to_bytes()).unwrap();
            assert_eq!(value["error"]["code"], "invalid-request-size");
            harbor_ios_response_free(response);
        }
        harbor_ios_response_free(std::ptr::null_mut());
    }
}

#[test]
fn rejects_header_injection_and_keeps_real_headers_and_subtitles() {
    let stream = json!({"addonId":"a","addonName":"A","url":"https://example.com/video.mkv","subtitles":[{"url":"https://example.com/a.ass","lang":"spa"}],"behaviorHints":{"proxyHeaders":{"request":{"Authorization":"Bearer private"}}}});
    let run = |s| {
        serde_json::from_str::<Value>(&call(
            &serde_json::to_vec(&json!({"operation":"resolveDirect","stream":s})).unwrap(),
        ))
        .unwrap()
    };
    let response = run(stream.clone());
    assert_eq!(
        response["data"]["headers"]["Authorization"],
        "Bearer private"
    );
    assert_eq!(response["data"]["subtitles"][0]["lang"], "spa");
    let mut bad = stream;
    bad["behaviorHints"]["proxyHeaders"]["request"]["Authorization"] =
        json!("secret\r\nInjected: true");
    assert_eq!(run(bad)["error"]["code"], "invalid-playback-header");
}

#[test]
fn torrent_offer_remains_visible_and_resolution_error_is_explicit() {
    let request = json!({"operation":"resolveDirect","stream":{"addonId":"a","addonName":"A","infoHash":"abc"}});
    let response: Value =
        serde_json::from_str(&call(&serde_json::to_vec(&request).unwrap())).unwrap();
    assert_eq!(response["error"]["code"], "torrent-resolver-pending");
}

#[test]
fn rejects_control_characters_before_c_string_transport_without_echoing_urls() {
    for control in ['\0', '\n', '\r', '\t'] {
        for subtitle in [false, true] {
            let mut stream =
                json!({"addonId":"a","addonName":"A","url":"https://example.com/video.mp4"});
            let bad = format!("https://example.com/private{control}value");
            if subtitle {
                stream["subtitles"] = json!([{"url":bad}]);
            } else {
                stream["url"] = json!(bad);
            }
            let response = call(
                &serde_json::to_vec(&json!({"operation":"resolveDirect","stream":stream})).unwrap(),
            );
            assert!(!response.contains("private"));
            let response: Value = serde_json::from_str(&response).unwrap();
            assert_eq!(
                response["error"]["code"],
                if subtitle {
                    "invalid-subtitle-url"
                } else {
                    "invalid-playback-url"
                }
            );
        }
    }
}

#[test]
fn resume_operations_transport_episode_keys_and_optional_checkpoints() {
    let run = |request: Value| -> Value {
        serde_json::from_str(&call(&serde_json::to_vec(&request).unwrap())).unwrap()
    };
    let target = json!({"id":"tt123","season":1,"episode":2});
    let key = run(json!({"operation":"resumeKey","target":target}));
    assert_eq!(key["data"]["key"], "tt123|s1e2");
    let mut request = json!({"operation":"resumeCheckpoint","target":target,"positionMs":12000.0,"durationMs":200000.0,"timestampMs":123,"exiting":false});
    let saved = run(request.clone());
    assert_eq!(saved["data"]["checkpoint"]["key"], "tt123|s1e2");
    assert_eq!(saved["data"]["checkpoint"]["entry"]["ms"], 12000.0);
    request["positionMs"] = json!(0);
    let empty = run(request);
    assert_eq!(empty["ok"], true);
    assert!(empty["data"]["checkpoint"].is_null());
    let read = run(
        json!({"operation":"resumePosition","target":target,"document":{"version":1,"entries":{"tt123|s1e2":{"ms":60000,"t":123}}},"durationMs":0,"playback":true,"prompt":true}),
    );
    assert_eq!(read["data"]["ms"], 60000.0);
    assert_eq!(read["data"]["prompt"], true);
    let invalid = run(json!({"operation":"validateResume","document":{"version":2,"entries":{}}}));
    assert_eq!(invalid["error"]["code"], "unsupported-resume-version");
}
