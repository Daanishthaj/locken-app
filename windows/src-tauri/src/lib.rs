mod ai;
mod blocker;
mod canvas;
mod media;
mod secrets;
mod tray;
mod workspace;

use tauri::{AppHandle, Manager, PhysicalPosition, PhysicalSize, WebviewUrl, WebviewWindowBuilder, WindowEvent};

const CHECKIN_WIDTH: f64 = 480.0;
const CHECKIN_HEIGHT: f64 = 196.0;
/// How far down the screen the check-in's glow reaches.
const AURORA_HEIGHT: f64 = 340.0;

/// The Windows account name, shown under the name on the sidebar profile card (the Mac shows its user name).
#[tauri::command]
fn user_name() -> String {
    std::env::var("USERNAME").or_else(|_| std::env::var("USER")).unwrap_or_default().chars().take(64).collect()
}

/// A soft aurora along the top of the screen while the check-in is open (the Mac app's check-in glow): a transparent
/// window across the screen that ignores the mouse and never takes focus, so nothing beneath it stops working.
fn open_aurora(app: &AppHandle) {
    if app.get_webview_window("checkin-aurora").is_some() {
        return;
    }
    let Ok(window) = WebviewWindowBuilder::new(app, "checkin-aurora", WebviewUrl::App("aurora.html".into()))
        .title("Locken check-in glow")
        .inner_size(1200.0, AURORA_HEIGHT)
        .resizable(false)
        .decorations(false)
        .transparent(true)
        .shadow(false)
        .always_on_top(true)
        .skip_taskbar(true)
        .focused(false)
        .build()
    else {
        return;
    };
    let _ = window.set_ignore_cursor_events(true);
    if let Ok(Some(monitor)) = window.current_monitor() {
        let scale = monitor.scale_factor();
        let _ = window.set_size(PhysicalSize::new(monitor.size().width, (AURORA_HEIGHT * scale) as u32));
        let _ = window.set_position(PhysicalPosition::new(monitor.position().x, monitor.position().y));
    }
}

/// Shows the check-in prompt at the top centre of the screen, above every other window, and gives
/// it keyboard focus so the student types their status straight away.
#[tauri::command]
fn open_checkin(app: AppHandle) -> Result<(), String> {
    if let Some(existing) = app.get_webview_window("checkin") {
        let _ = existing.set_focus();
        return Ok(());
    }
    // The glow first, so the check-in window opens above it.
    open_aurora(&app);
    let window = WebviewWindowBuilder::new(&app, "checkin", WebviewUrl::App("checkin.html".into()))
        .title("Locken check-in")
        .inner_size(CHECKIN_WIDTH, CHECKIN_HEIGHT)
        .resizable(false)
        .decorations(false)
        .always_on_top(true)
        .skip_taskbar(true)
        .focused(true)
        .build()
        .map_err(|_| "Couldn't open the check-in.".to_string())?;
    if let Ok(Some(monitor)) = window.current_monitor() {
        let scale = monitor.scale_factor();
        let x = monitor.position().x + ((monitor.size().width as f64 - CHECKIN_WIDTH * scale) / 2.0) as i32;
        let y = monitor.position().y + (14.0 * scale) as i32;
        let _ = window.set_position(PhysicalPosition::new(x, y));
    }
    let _ = window.set_focus();
    // However the check-in closes (its answer, the session ending), its glow goes with it.
    let handle = app.clone();
    window.on_window_event(move |event| {
        if let WindowEvent::Destroyed = event {
            if let Some(aurora) = handle.get_webview_window("checkin-aurora") {
                let _ = aurora.close();
            }
        }
    });
    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        // First: a second copy (started by a locken:// link from Google sign-in) hands the link to this one and
        // quits, so only one Locken runs and the sign-in finishes in the window that started it.
        .plugin(tauri_plugin_single_instance::init(|app, _argv, _cwd| {
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.unminimize();
                let _ = window.set_focus();
            }
        }))
        .plugin(tauri_plugin_deep_link::init())
        .plugin(tauri_plugin_opener::init())
        .manage(blocker::Blocker::default())
        .setup(|app| {
            // Make sure locken:// opens this app (the installer registers it too; this covers older installs).
            #[cfg(windows)]
            {
                use tauri_plugin_deep_link::DeepLinkExt;
                let _ = app.deep_link().register_all();
            }
            let handle = app.handle().clone();
            blocker::spawn(handle, &app.state::<blocker::Blocker>());
            tray::create(app.handle())?;
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            open_checkin,
            blocker::start_blocking,
            blocker::stop_blocking,
            blocker::default_blocked_apps,
            blocker::running_apps,
            workspace::open_workspace_app,
            secrets::save_session,
            secrets::load_session,
            secrets::clear_session,
            media::now_playing,
            media::media_play_pause,
            user_name,
            ai::ai_key_status,
            ai::ai_save_key,
            ai::ai_remove_key,
            ai::ai_rephrase,
            ai::ai_milestones,
            ai::ai_week_digest,
            canvas::canvas_status,
            canvas::canvas_link_token,
            canvas::canvas_link_feed,
            canvas::canvas_refresh,
            canvas::canvas_unlink,
            tray::tray_status,
        ])
        .run(tauri::generate_context!())
        .expect("error while running Locken");
}
