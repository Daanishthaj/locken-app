//! The Shield on Windows: while a session runs, games, game launchers and social or chat apps are
//! closed as soon as they appear. It only closes what the signed-in Windows user started; it never
//! touches system processes, browsers, or Locken itself. Browser tabs are not closed yet (that needs
//! a browser extension).

use std::path::Path;
use std::collections::BTreeMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use serde::Serialize;
use sysinfo::{ProcessRefreshKind, ProcessesToUpdate, System, UpdateKind};
use tauri::{AppHandle, Emitter, State};

/// Executable names (lowercase) of social, chat and game-launcher apps.
const BLOCKED_EXES: &[(&str, &str)] = &[
    ("discord.exe", "Discord"),
    ("whatsapp.exe", "WhatsApp"),
    ("telegram.exe", "Telegram"),
    ("messenger.exe", "Messenger"),
    ("instagram.exe", "Instagram"),
    ("tiktok.exe", "TikTok"),
    ("steam.exe", "Steam"),
    ("steamwebhelper.exe", "Steam"),
    ("epicgameslauncher.exe", "Epic Games Launcher"),
    ("battle.net.exe", "Battle.net"),
    ("riotclientservices.exe", "Riot Client"),
    ("riotclientux.exe", "Riot Client"),
    ("leagueclient.exe", "League of Legends"),
    ("minecraftlauncher.exe", "Minecraft Launcher"),
    ("minecraft.windows.exe", "Minecraft"),
    ("robloxplayerbeta.exe", "Roblox"),
    ("robloxplayerlauncher.exe", "Roblox"),
    ("galaxyclient.exe", "GOG Galaxy"),
];

/// Never closed, even if someone adds them: Windows itself, browsers (Locken closes tabs, not browsers) and Locken.
const PROTECTED_EXES: &[&str] = &[
    "explorer.exe", "svchost.exe", "csrss.exe", "winlogon.exe", "dwm.exe", "taskmgr.exe", "searchhost.exe",
    "startmenuexperiencehost.exe", "shellexperiencehost.exe", "runtimebroker.exe", "systemsettings.exe",
    "chrome.exe", "msedge.exe", "firefox.exe", "brave.exe", "opera.exe", "arc.exe", "vivaldi.exe",
    "locken.exe", "msedgewebview2.exe",
];

/// Any program inside these game library folders is a game.
const GAME_FOLDERS: &[&str] = &["\\steamapps\\common\\", "\\epic games\\", "\\riot games\\", "\\gog galaxy\\games\\"];

/// The student's own choices, sent from the app each time a session starts: extra programs to close and
/// built-in apps to keep open.
#[derive(Default, Clone)]
pub struct Rules {
    extra: Vec<String>,
    allowed: Vec<String>,
}

#[derive(Default)]
pub struct Blocker {
    active: Arc<AtomicBool>,
    rules: Arc<Mutex<Rules>>,
}

#[derive(Clone, Serialize)]
struct Blocked {
    name: String,
}

fn verdict(exe_name: &str, exe_path: Option<&Path>, rules: &Rules) -> Option<String> {
    let name = exe_name.to_lowercase();
    if PROTECTED_EXES.contains(&name.as_str()) {
        return None;
    }
    if let Some((_, label)) = BLOCKED_EXES.iter().find(|(exe, _)| *exe == name) {
        if rules.allowed.iter().any(|kept| kept == label) {
            return None;
        }
        return Some((*label).to_string());
    }
    if rules.extra.iter().any(|extra| *extra == name) {
        let stem = Path::new(exe_name).file_stem().map(|s| s.to_string_lossy().into_owned());
        return Some(stem.unwrap_or_else(|| exe_name.to_string()));
    }
    let path = exe_path?.to_string_lossy().to_lowercase();
    if GAME_FOLDERS.iter().any(|folder| path.contains(folder)) {
        let stem = Path::new(exe_name).file_stem().map(|s| s.to_string_lossy().into_owned());
        return Some(stem.unwrap_or_else(|| "A game".into()));
    }
    None
}

/// Starts the background watcher once, at launch. It sleeps unless a session is active.
pub fn spawn(app: AppHandle, blocker: &Blocker) {
    let active = blocker.active.clone();
    let rules = blocker.rules.clone();
    thread::spawn(move || {
        let own_pid = sysinfo::get_current_pid().ok();
        let mut system = System::new();
        let refresh = ProcessRefreshKind::nothing().with_exe(UpdateKind::OnlyIfNotSet);
        loop {
            thread::sleep(Duration::from_millis(1200));
            if !active.load(Ordering::Relaxed) {
                continue;
            }
            system.refresh_processes_specifics(ProcessesToUpdate::All, true, refresh);
            let current = rules.lock().map(|r| r.clone()).unwrap_or_default();
            for (pid, process) in system.processes() {
                if Some(*pid) == own_pid {
                    continue;
                }
                let exe_name = process.name().to_string_lossy();
                if let Some(label) = verdict(&exe_name, process.exe(), &current) {
                    if process.kill() {
                        let _ = app.emit_to("main", "app-blocked", Blocked { name: label });
                    }
                }
            }
        }
    });
}

/// Program names only (like "spotify.exe"), lowercase, at most 100 of each and 64 characters long.
fn clean_names(names: Option<Vec<String>>) -> Vec<String> {
    names
        .unwrap_or_default()
        .into_iter()
        .map(|n| n.trim().to_lowercase())
        .filter(|n| !n.is_empty() && n.len() <= 64 && !n.contains(['/', '\\', ':']))
        .take(100)
        .collect()
}

#[tauri::command]
pub fn start_blocking(blocker: State<'_, Blocker>, extra: Option<Vec<String>>, allowed: Option<Vec<String>>) {
    let allowed = allowed.unwrap_or_default().into_iter().map(|a| a.trim().to_string()).filter(|a| a.len() <= 64).take(100).collect();
    if let Ok(mut rules) = blocker.rules.lock() {
        *rules = Rules { extra: clean_names(extra), allowed };
    }
    blocker.active.store(true, Ordering::Relaxed);
}

#[derive(Serialize)]
pub struct AppChoice {
    exe: String,
    name: String,
}

/// The built-in blocked apps, for the Settings card.
#[tauri::command]
pub fn default_blocked_apps() -> Vec<String> {
    let mut names: Vec<String> = BLOCKED_EXES.iter().map(|(_, label)| (*label).to_string()).collect();
    names.dedup();
    names
}

/// Programs the signed-in user is running now (not Windows itself, browsers or Locken), to pick one to block.
#[tauri::command]
pub fn running_apps() -> Vec<AppChoice> {
    let mut system = System::new();
    system.refresh_processes_specifics(ProcessesToUpdate::All, true, ProcessRefreshKind::nothing().with_exe(UpdateKind::OnlyIfNotSet));
    let mut found: BTreeMap<String, String> = BTreeMap::new();
    for process in system.processes().values() {
        let exe = process.name().to_string_lossy().to_lowercase();
        let in_windows = process.exe().map(|p| p.to_string_lossy().to_lowercase().starts_with("c:\\windows")).unwrap_or(true);
        if !exe.ends_with(".exe") || in_windows || PROTECTED_EXES.contains(&exe.as_str()) {
            continue;
        }
        let name = Path::new(&exe).file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_else(|| exe.clone());
        found.entry(exe).or_insert(name);
    }
    found.into_iter().take(200).map(|(exe, name)| AppChoice { exe, name }).collect()
}

#[tauri::command]
pub fn stop_blocking(blocker: State<'_, Blocker>) {
    blocker.active.store(false, Ordering::Relaxed);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn blocks_known_apps_and_games() {
        let rules = Rules::default();
        assert_eq!(verdict("Discord.exe", None, &rules).as_deref(), Some("Discord"));
        let game = Path::new("C:\\Program Files (x86)\\Steam\\steamapps\\common\\Portal 2\\portal2.exe");
        assert_eq!(verdict("portal2.exe", Some(game), &rules).as_deref(), Some("portal2"));
    }

    #[test]
    fn leaves_work_apps_alone() {
        let rules = Rules::default();
        assert_eq!(verdict("chrome.exe", Some(Path::new("C:\\Program Files\\Google\\Chrome\\chrome.exe")), &rules), None);
        assert_eq!(verdict("WINWORD.EXE", None, &rules), None);
        assert_eq!(verdict("explorer.exe", Some(Path::new("C:\\Windows\\explorer.exe")), &rules), None);
    }

    #[test]
    fn follows_the_students_choices() {
        let rules = Rules { extra: vec!["spotify.exe".into(), "chrome.exe".into()], allowed: vec!["Discord".into()] };
        assert_eq!(verdict("Spotify.exe", None, &rules).as_deref(), Some("Spotify"));
        assert_eq!(verdict("Discord.exe", None, &rules), None);
        // Browsers stay protected even if someone adds one.
        assert_eq!(verdict("chrome.exe", None, &rules), None);
    }
}
