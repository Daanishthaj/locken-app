fn main() {
    // Declaring the app's own commands makes Tauri deny them by default; capabilities/ then grants each window
    // only the ones it needs (the check-in popup gets none).
    tauri_build::try_build(tauri_build::Attributes::new().app_manifest(
        tauri_build::AppManifest::new().commands(&[
            "open_checkin",
            "start_blocking",
            "stop_blocking",
            "default_blocked_apps",
            "running_apps",
            "open_workspace_app",
            "save_session",
            "load_session",
            "clear_session",
            "now_playing",
            "media_play_pause",
            "user_name",
            "ai_key_status",
            "ai_save_key",
            "ai_remove_key",
            "ai_rephrase",
            "ai_milestones",
            "ai_week_digest",
            "ai_assistant",
            "voice_key_status",
            "voice_save_key",
            "voice_list",
            "voice_remove_key",
            "voice_speech",
            "canvas_status",
            "canvas_link_token",
            "canvas_link_feed",
            "canvas_refresh",
            "canvas_unlink",
            "tray_status",
        ]),
    ))
    .expect("failed to run tauri-build");
}
