//! Stand-ins for the desktop-only modules, compiled on Android only.
//!
//! The Desktop builds a tray icon, floating always-on-top windows, picture in picture and an embedded libmpv window.
//! None of that exists on a phone. Each module below keeps the names the command list in `lib.rs` expects, so the
//! web interface can still call them, and answers "not available" or does nothing. Spike code, not a real port.

pub mod tray {
    pub fn close_to_tray() -> bool {
        false
    }

    #[tauri::command]
    pub fn tray_set_prefs() {}

    #[tauri::command]
    pub fn tray_set_custom_themes() {}
}

pub mod fullscreen {
    pub struct FullscreenState;

    impl FullscreenState {
        pub fn new() -> Self {
            Self
        }
    }

    #[tauri::command]
    pub async fn window_fullscreen_enter() -> Result<(), String> {
        Ok(())
    }

    #[tauri::command]
    pub async fn window_fullscreen_exit() -> Result<(), String> {
        Ok(())
    }
}

pub mod pip {
    pub struct PipState;

    impl PipState {
        pub fn new() -> Self {
            Self
        }
    }

    const UNAVAILABLE: &str = "picture in picture is not available on Android";

    #[tauri::command]
    pub async fn pip_open() -> Result<(), String> {
        Err(UNAVAILABLE.into())
    }

    #[tauri::command]
    pub async fn pip_get_session() -> Result<Option<serde_json::Value>, String> {
        Ok(None)
    }

    #[tauri::command]
    pub async fn pip_close() -> Result<(), String> {
        Ok(())
    }

    #[tauri::command]
    pub async fn pip_publish_state() -> Result<(), String> {
        Ok(())
    }

    #[tauri::command]
    pub async fn window_pip_enter() -> Result<(), String> {
        Err(UNAVAILABLE.into())
    }

    #[tauri::command]
    pub async fn window_pip_exit() -> Result<(), String> {
        Ok(())
    }
}

pub mod modal_overlay {
    pub struct ModalOverlayState;

    impl ModalOverlayState {
        pub fn new() -> Self {
            Self
        }
    }

    #[tauri::command]
    pub async fn modal_overlay_open() -> Result<(), String> {
        Err("modal overlay windows are not available on Android".into())
    }

    #[tauri::command]
    pub async fn modal_overlay_close() -> Result<(), String> {
        Ok(())
    }

    #[tauri::command]
    pub async fn modal_overlay_emit_state() -> Result<(), String> {
        Ok(())
    }

    #[tauri::command]
    pub async fn modal_overlay_emit_action() -> Result<(), String> {
        Ok(())
    }

    #[tauri::command]
    pub async fn modal_overlay_sync() -> Result<(), String> {
        Ok(())
    }

    #[tauri::command]
    pub async fn modal_overlay_get_pending() -> Result<Option<serde_json::Value>, String> {
        Ok(None)
    }
}

pub mod hdr_overlay {
    #[tauri::command]
    pub async fn hdr_overlay_open() -> Result<(), String> {
        Ok(())
    }

    #[tauri::command]
    pub async fn hdr_overlay_close() -> Result<(), String> {
        Ok(())
    }

    #[tauri::command]
    pub async fn hdr_overlay_hide() -> Result<(), String> {
        Ok(())
    }

    #[tauri::command]
    pub async fn hdr_overlay_sync() -> Result<(), String> {
        Ok(())
    }

    #[tauri::command]
    pub async fn hdr_overlay_emit_props() -> Result<(), String> {
        Ok(())
    }

    #[tauri::command]
    pub async fn hdr_overlay_emit_action() -> Result<(), String> {
        Ok(())
    }
}

pub mod browser {
    #[tauri::command]
    pub async fn browser_open() -> Result<(), String> {
        Err("the in-app browser window is not available on Android".into())
    }

    #[tauri::command]
    pub async fn browser_close() -> Result<(), String> {
        Ok(())
    }
}

/// Embedded libmpv needs a native window per platform; there is none for Android in this spike, so the probe says mpv is
/// missing (the Desktop already handles that case) and every other call is refused.
pub mod mpv {
    use serde::Serialize;
    use serde_json::Value;

    const UNAVAILABLE: &str = "libmpv is not available on Android in this build";

    pub struct MpvState;

    impl MpvState {
        pub fn new() -> Self {
            Self
        }
    }

    #[derive(Serialize)]
    pub struct MpvProbe {
        pub available: bool,
        pub binary: Option<String>,
        pub version: Option<String>,
        pub error: Option<String>,
    }

    #[tauri::command]
    pub async fn mpv_probe() -> MpvProbe {
        MpvProbe {
            available: false,
            binary: None,
            version: None,
            error: Some(UNAVAILABLE.into()),
        }
    }

    #[tauri::command]
    pub async fn mpv_audio_devices() -> Result<Vec<Value>, String> {
        Ok(Vec::new())
    }

    #[tauri::command]
    pub async fn mpv_start() -> Result<(), String> {
        Err(UNAVAILABLE.into())
    }

    #[tauri::command]
    pub async fn mpv_command() -> Result<(), String> {
        Err(UNAVAILABLE.into())
    }

    #[tauri::command]
    pub async fn mpv_set_property() -> Result<(), String> {
        Err(UNAVAILABLE.into())
    }

    #[tauri::command]
    pub async fn mpv_get_property() -> Result<Value, String> {
        Err(UNAVAILABLE.into())
    }

    #[tauri::command]
    pub async fn mpv_set_geometry() -> Result<(), String> {
        Ok(())
    }

    #[tauri::command]
    pub fn mpv_export_log() -> Result<String, String> {
        Err(UNAVAILABLE.into())
    }

    #[tauri::command]
    pub async fn mpv_force_below() -> Result<(), String> {
        Ok(())
    }

    #[tauri::command]
    pub async fn mpv_set_hdr_stage() -> Result<(), String> {
        Ok(())
    }

    #[tauri::command]
    pub async fn display_hdr_active() -> Result<bool, String> {
        Ok(false)
    }

    #[tauri::command]
    pub async fn mpv_save_screenshot() -> Result<String, String> {
        Err(UNAVAILABLE.into())
    }

    #[tauri::command]
    pub async fn mpv_gif_start() -> Result<(), String> {
        Err(UNAVAILABLE.into())
    }

    #[tauri::command]
    pub async fn mpv_gif_abort() -> Result<(), String> {
        Ok(())
    }

    #[tauri::command]
    pub async fn mpv_gif_stop() -> Result<Value, String> {
        Err(UNAVAILABLE.into())
    }

    #[tauri::command]
    pub async fn mpv_clip_save() -> Result<Value, String> {
        Err(UNAVAILABLE.into())
    }

    #[tauri::command]
    pub async fn mpv_screenshot_data_url() -> Result<String, String> {
        Err(UNAVAILABLE.into())
    }

    #[tauri::command]
    pub async fn mpv_on_pip_changed() -> Result<(), String> {
        Ok(())
    }

    #[tauri::command]
    pub async fn mpv_sub_add() -> Result<(), String> {
        Err(UNAVAILABLE.into())
    }

    #[tauri::command]
    pub async fn sub_download() -> Result<String, String> {
        Err(UNAVAILABLE.into())
    }

    #[tauri::command]
    pub async fn mpv_stop() -> Result<(), String> {
        Ok(())
    }
}
