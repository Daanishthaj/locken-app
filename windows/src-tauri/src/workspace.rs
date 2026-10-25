//! "Where you'll work": opens the app the student picked when a session starts (as the Mac app does).
//! Only names from this fixed list can be opened; nothing the page sends is ever run as a command.

/// The app names the session setup shows, and what Windows's `start` command opens for each.
const APPS: &[(&str, &str)] = &[
    ("Google Chrome", "chrome"),
    ("Microsoft Edge", "msedge"),
    ("Comet", "comet"),
    ("VS Code", "code"),
    ("Cursor", "cursor"),
    ("Word", "winword"),
    ("Firefox", "firefox"),
    ("Brave", "brave"),
    // Notion and Obsidian install per user without an App Paths entry, so they open through their own links.
    ("Notion", "notion:"),
    ("Obsidian", "obsidian:"),
];

fn target(app: &str) -> Option<&'static str> {
    APPS.iter().find(|(name, _)| *name == app).map(|(_, target)| *target)
}

/// Opens the chosen app. Unknown names are ignored. Failing to open (the app isn't installed) is fine: the
/// session still starts.
#[tauri::command]
pub fn open_workspace_app(app: String) {
    let Some(target) = target(&app) else { return };
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        const CREATE_NO_WINDOW: u32 = 0x0800_0000;
        let _ = std::process::Command::new("cmd")
            .args(["/C", "start", "", target])
            .creation_flags(CREATE_NO_WINDOW)
            .spawn();
    }
    #[cfg(not(windows))]
    let _ = target;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_listed_apps_open() {
        assert_eq!(target("Google Chrome"), Some("chrome"));
        assert_eq!(target("Word"), Some("winword"));
        assert_eq!(target("Notion"), Some("notion:"));
        assert_eq!(target("calc & del C:\\"), None);
        assert_eq!(target(""), None);
    }
}
