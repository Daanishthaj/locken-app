//! What's playing, for the sidebar profile card (the Windows side of the Mac app's NowPlayingService).
//! Reads the system media controls (Spotify, a browser tab, Media Player, anything that shows in the volume
//! flyout), so it needs no permission and sends nothing off the PC. The artwork comes back as a data: URL,
//! so the page never loads a remote image.

use base64::Engine;
use serde::Serialize;

#[derive(Serialize, Clone, Debug, PartialEq)]
pub struct Track {
    pub title: String,
    pub artist: String,
    pub playing: bool,
    /// `data:image/...;base64,...`, or empty when the player gives no artwork.
    pub cover: String,
}

#[cfg_attr(not(windows), allow(dead_code))]
/// Artwork larger than this is skipped (the card shows a music note instead).
const MAX_COVER_BYTES: usize = 512 * 1024;

#[tauri::command]
pub async fn now_playing() -> Option<Track> {
    tauri::async_runtime::spawn_blocking(platform::now_playing).await.ok().flatten()
}

#[tauri::command]
pub async fn media_play_pause() {
    let _ = tauri::async_runtime::spawn_blocking(platform::play_pause).await;
}

#[cfg_attr(not(windows), allow(dead_code))]
fn data_url(content_type: &str, bytes: &[u8]) -> String {
    let kind = if content_type.starts_with("image/") && content_type.len() < 40 && !content_type.contains([';', ',', '"']) {
        content_type
    } else {
        "image/png"
    };
    format!("data:{kind};base64,{}", base64::engine::general_purpose::STANDARD.encode(bytes))
}

#[cfg(windows)]
mod platform {
    use super::{data_url, Track, MAX_COVER_BYTES};
    use std::sync::Mutex;
    use windows::Media::Control::{
        GlobalSystemMediaTransportControlsSessionManager as Manager,
        GlobalSystemMediaTransportControlsSessionPlaybackStatus as Status,
    };
    use windows::Storage::Streams::DataReader;

    /// The last artwork read, keyed by title and artist, so it isn't re-read on every poll.
    static COVER: Mutex<Option<(String, String)>> = Mutex::new(None);

    pub fn now_playing() -> Option<Track> {
        let session = Manager::RequestAsync().ok()?.join().ok()?.GetCurrentSession().ok()?;
        let props = session.TryGetMediaPropertiesAsync().ok()?.join().ok()?;
        let title = props.Title().ok()?.to_string_lossy().chars().take(200).collect::<String>();
        if title.trim().is_empty() {
            return None;
        }
        let artist = props.Artist().map(|a| a.to_string_lossy()).unwrap_or_default().chars().take(200).collect::<String>();
        let playing = session
            .GetPlaybackInfo()
            .and_then(|info| info.PlaybackStatus())
            .map(|status| status == Status::Playing)
            .unwrap_or(false);
        let key = format!("{title}\u{1f}{artist}");
        let cached = COVER.lock().ok().and_then(|c| c.clone()).filter(|(k, _)| *k == key).map(|(_, url)| url);
        let cover = match cached {
            Some(url) => url,
            None => {
                let url = read_cover(&props).unwrap_or_default();
                // Players often send the artwork a moment after the title, so "no artwork yet" is not remembered.
                if !url.is_empty() {
                    if let Ok(mut c) = COVER.lock() {
                        *c = Some((key, url.clone()));
                    }
                }
                url
            }
        };
        Some(Track { title, artist, playing, cover })
    }

    fn read_cover(props: &windows::Media::Control::GlobalSystemMediaTransportControlsSessionMediaProperties) -> Option<String> {
        let stream = props.Thumbnail().ok()?.OpenReadAsync().ok()?.join().ok()?;
        let size = usize::try_from(stream.Size().ok()?).ok()?;
        if size == 0 || size > MAX_COVER_BYTES {
            return None;
        }
        let content_type = stream.ContentType().map(|t| t.to_string_lossy()).unwrap_or_default();
        let reader = DataReader::CreateDataReader(&stream).ok()?;
        reader.LoadAsync(size as u32).ok()?.join().ok()?;
        let mut bytes = vec![0u8; size];
        reader.ReadBytes(&mut bytes).ok()?;
        Some(data_url(&content_type, &bytes))
    }

    pub fn play_pause() {
        if let Some(session) = Manager::RequestAsync().ok().and_then(|op| op.join().ok()).and_then(|m| m.GetCurrentSession().ok()) {
            if let Ok(op) = session.TryTogglePlayPauseAsync() {
                let _ = op.join();
            }
        }
    }
}

#[cfg(not(windows))]
mod platform {
    use super::Track;
    pub fn now_playing() -> Option<Track> {
        None
    }
    pub fn play_pause() {}
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cover_type_is_an_image_or_png() {
        assert!(data_url("image/jpeg", b"x").starts_with("data:image/jpeg;base64,"));
        assert!(data_url("text/html", b"x").starts_with("data:image/png;base64,"));
        assert!(data_url("image/png;x=\"", b"x").starts_with("data:image/png;base64,"));
    }
}
