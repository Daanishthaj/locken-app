//! The timer in the Windows system tray (the Windows side of the Mac app's menu bar timer). The tray icon is
//! always there; while a session runs its tooltip shows the time left and the goal. Clicking it, or "Open
//! Locken" in its menu, brings the window back. There is no Quit item, so a session can't be dropped from here.

use tauri::menu::{Menu, MenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Manager};

const TRAY_ID: &str = "locken";

fn show_main(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.unminimize();
        let _ = window.show();
        let _ = window.set_focus();
    }
}

pub fn create(app: &AppHandle) -> tauri::Result<()> {
    let open = MenuItem::with_id(app, "open", "Open Locken", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&open])?;
    let mut builder = TrayIconBuilder::with_id(TRAY_ID)
        .tooltip("Locken")
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| {
            if event.id() == "open" {
                show_main(app);
            }
        })
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click { button: MouseButton::Left, button_state: MouseButtonState::Up, .. } = event {
                show_main(tray.app_handle());
            }
        });
    if let Some(icon) = app.default_window_icon() {
        builder = builder.icon(icon.clone());
    }
    builder.build(app)?;
    Ok(())
}

/// What the tray shows: "Locken" when idle, or "18:42 left · Write the intro" while a session runs.
#[tauri::command]
pub fn tray_status(app: AppHandle, text: String) {
    let text: String = text.chars().filter(|c| !c.is_control()).take(120).collect();
    if let Some(tray) = app.tray_by_id(TRAY_ID) {
        let _ = tray.set_tooltip(Some(if text.is_empty() { "Locken".to_string() } else { text }));
    }
}
