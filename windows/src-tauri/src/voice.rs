//! ElevenLabs voices for the Assistant (the Mac app's `ElevenLabsVoice`). The student can pick one of Locken's four
//! voice clones with their own ElevenLabs API key. The key lives in Windows Credential Manager, per account, and every
//! request is made here in Rust, so the key never reaches the web view. Only the reply text is sent, to be spoken.

use base64::Engine;
use keyring::Entry;
use serde::Serialize;
use std::time::Duration;

const SERVICE: &str = "app.locken.windows.elevenlabs";
const API: &str = "https://api.elevenlabs.io/v1";
/// Locken's voice clones (same IDs as the Mac app).
const CLONE_IDS: [&str; 4] = ["6i4Eb1eUSagmAhMPqhYS", "rFtEb2MlDt7EXDbMtvop", "jQsSjEc5AqgeKVNnZAUe", "igSE0ESt9o1f4gv4QCL2"];
/// The fast model, so the first words come quickly (same as the Mac app).
const MODEL: &str = "eleven_flash_v2_5";
const MAX_TEXT: usize = 1000;

#[derive(Serialize)]
pub struct Voice {
    id: String,
    name: String,
}

/// One Credential Manager item per Locken account, so one account's key is never used by another on the same PC.
fn entry(account: &str) -> Result<Entry, String> {
    if account.is_empty() || account.len() > 64 || !account.chars().all(|c| c.is_ascii_alphanumeric() || c == '-') {
        return Err("Sign in again to use ElevenLabs voices.".into());
    }
    Entry::new(SERVICE, account).map_err(|_| "Couldn't open secure storage.".to_string())
}

fn stored_key(account: &str) -> Option<String> {
    entry(account).ok()?.get_password().ok()
}

fn valid_key(key: &str) -> bool {
    (20..=200).contains(&key.len()) && key.chars().all(|c| c.is_ascii_graphic())
}

fn client() -> Result<reqwest::Client, String> {
    reqwest::Client::builder()
        .timeout(Duration::from_secs(20))
        .https_only(true)
        .build()
        .map_err(|_| "Couldn't reach ElevenLabs.".to_string())
}

/// The voices this key can use, by name. Err when ElevenLabs refuses the key itself.
async fn voices(key: &str) -> Result<Vec<Voice>, String> {
    let client = client()?;
    let mut found = Vec::new();
    for id in CLONE_IDS {
        let response = client
            .get(format!("{API}/voices/{id}"))
            .header("xi-api-key", key)
            .send()
            .await
            .map_err(|_| "Couldn't reach ElevenLabs. Check your internet connection.".to_string())?;
        match response.status().as_u16() {
            200 => {
                let json: serde_json::Value = response.json().await.unwrap_or_default();
                let name: String = json["name"].as_str().unwrap_or("").chars().take(24).collect();
                found.push(Voice { id: id.to_string(), name });
            }
            401 => return Err("ElevenLabs didn't accept that key.".into()),
            _ => {}
        }
    }
    Ok(found)
}

#[tauri::command]
pub fn voice_key_status(account: String) -> bool {
    stored_key(&account).is_some()
}

/// Checks the key with ElevenLabs before keeping it, and returns the voices it can use.
#[tauri::command]
pub async fn voice_save_key(account: String, key: String) -> Result<Vec<Voice>, String> {
    let key = key.trim().to_string();
    if !valid_key(&key) {
        return Err("That doesn't look like an ElevenLabs API key.".into());
    }
    let found = voices(&key).await?;
    if found.is_empty() {
        return Err("That key can't use any of Locken's voices.".into());
    }
    entry(&account)?.set_password(&key).map_err(|_| "Couldn't save the key.".to_string())?;
    Ok(found)
}

#[tauri::command]
pub async fn voice_list(account: String) -> Result<Vec<Voice>, String> {
    let key = stored_key(&account).ok_or("Add an ElevenLabs key first.")?;
    voices(&key).await
}

#[tauri::command]
pub fn voice_remove_key(account: String) {
    if let Ok(item) = entry(&account) {
        let _ = item.delete_credential();
    }
}

/// The reply spoken by one of Locken's voices, as base64 MP3 for the page to play.
#[tauri::command]
pub async fn voice_speech(account: String, voice_id: String, text: String) -> Result<String, String> {
    if !CLONE_IDS.contains(&voice_id.as_str()) {
        return Err("Pick one of Locken's voices in Settings.".into());
    }
    let text: String = text.trim().chars().take(MAX_TEXT).collect();
    if text.is_empty() {
        return Err("Nothing to say.".into());
    }
    let key = stored_key(&account).ok_or("Add an ElevenLabs key in Settings.")?;
    let response = client()?
        .post(format!("{API}/text-to-speech/{voice_id}?output_format=mp3_44100_64"))
        .header("xi-api-key", key)
        .header("Accept", "audio/mpeg")
        .json(&serde_json::json!({ "text": text, "model_id": MODEL }))
        .send()
        .await
        .map_err(|_| "Couldn't reach ElevenLabs.".to_string())?;
    match response.status().as_u16() {
        200 => {}
        401 => return Err("ElevenLabs didn't accept your key. Check it in Settings.".into()),
        429 => return Err("ElevenLabs is busy or your plan's characters ran out.".into()),
        _ => return Err("ElevenLabs couldn't speak that. Try again.".into()),
    }
    let audio = response.bytes().await.map_err(|_| "Couldn't reach ElevenLabs.".to_string())?;
    Ok(base64::engine::general_purpose::STANDARD.encode(audio))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn checks_keys_and_accounts() {
        assert!(valid_key("sk_0123456789abcdef0123456789abcdef"));
        assert!(!valid_key("short"));
        assert!(!valid_key("has spaces in it 0123456789"));
        assert!(entry("").is_err());
        assert!(entry("../other").is_err());
    }
}
