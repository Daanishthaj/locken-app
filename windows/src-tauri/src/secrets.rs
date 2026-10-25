//! The signed-in session, kept in Windows Credential Manager (the Keychain on macOS during development),
//! never in the web view's localStorage. Access and refresh tokens are stored as two items because
//! Credential Manager caps one secret at 2,560 bytes.

use keyring::Entry;
use serde::Serialize;

const SERVICE: &str = "app.locken.windows.session";

#[derive(Serialize)]
pub struct Session {
    access: String,
    refresh: String,
}

fn entry(name: &str) -> Result<Entry, String> {
    Entry::new(SERVICE, name).map_err(|_| "Couldn't open secure storage.".to_string())
}

fn valid_token(token: &str) -> bool {
    !token.is_empty() && token.len() <= 2048 && token.chars().all(|c| c.is_ascii_graphic())
}

#[tauri::command]
pub fn save_session(access: String, refresh: String) -> Result<(), String> {
    if !valid_token(&access) || !valid_token(&refresh) {
        return Err("Invalid session.".into());
    }
    entry("access")?.set_password(&access).map_err(|_| "Couldn't save your sign-in.".to_string())?;
    entry("refresh")?.set_password(&refresh).map_err(|_| "Couldn't save your sign-in.".to_string())
}

#[tauri::command]
pub fn load_session() -> Option<Session> {
    let access = entry("access").ok()?.get_password().ok()?;
    let refresh = entry("refresh").ok()?.get_password().ok()?;
    Some(Session { access, refresh })
}

#[tauri::command]
pub fn clear_session() {
    for name in ["access", "refresh"] {
        if let Ok(item) = entry(name) {
            let _ = item.delete_credential();
        }
    }
}
