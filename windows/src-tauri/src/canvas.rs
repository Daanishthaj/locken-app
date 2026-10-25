//! Canvas assignments (the Windows side of the Mac app's CanvasAPIManager). A student links Canvas with their
//! school address and a personal access token, or with the Canvas calendar feed link. Either is kept in Windows
//! Credential Manager, per account, and only this file reads it: the token is sent to that one Canvas host and
//! nowhere else (pagination links to other hosts are not followed), and the web view never sees it.

use keyring::Entry;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::time::Duration;

const SERVICE: &str = "app.locken.windows.canvas";
/// Biggest response read (a page of JSON or a calendar feed).
const MAX_BODY: usize = 4 * 1024 * 1024;

#[derive(Serialize, Deserialize)]
#[serde(tag = "method", rename_all = "lowercase")]
enum Link {
    Token { host: String, token: String },
    Feed { url: String },
}

#[derive(Serialize, Clone, Debug, PartialEq)]
pub struct Assignment {
    id: String,
    title: String,
    course: String,
    /// ISO 8601 from the API (`2026-10-20T23:59:00Z`), or empty when there is none.
    due: String,
}

/// Assignments from the API, or the raw calendar feed (its dates and time zones are read in the app).
#[derive(Serialize)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum Loaded {
    Api { items: Vec<Assignment> },
    Feed { text: String },
}

#[derive(Serialize)]
pub struct Status {
    method: String,
    host: String,
}

fn entry(account: &str) -> Result<Entry, String> {
    if account.is_empty() || account.len() > 64 || !account.chars().all(|c| c.is_ascii_alphanumeric() || c == '-') {
        return Err("Sign in again to link Canvas.".into());
    }
    Entry::new(SERVICE, account).map_err(|_| "Couldn't open secure storage.".to_string())
}

fn stored(account: &str) -> Option<Link> {
    serde_json::from_str(&entry(account).ok()?.get_password().ok()?).ok()
}

fn save(account: &str, link: &Link) -> Result<(), String> {
    let text = serde_json::to_string(link).map_err(|_| "Couldn't save the Canvas link.".to_string())?;
    entry(account)?.set_password(&text).map_err(|_| "Couldn't save the Canvas link.".to_string())
}

#[tauri::command]
pub fn canvas_status(account: String) -> Option<Status> {
    match stored(&account)? {
        Link::Token { host, .. } => Some(Status { method: "token".into(), host }),
        Link::Feed { url } => Some(Status { method: "feed".into(), host: host_of(&url).unwrap_or_default() }),
    }
}

#[tauri::command]
pub async fn canvas_link_token(account: String, address: String, token: String) -> Result<Loaded, String> {
    let host = normalized_host(&address).ok_or("Enter your school's Canvas address, for example school.instructure.com.")?;
    let token = token.trim().to_string();
    if token.is_empty() || token.len() > 512 || !token.chars().all(|c| c.is_ascii_graphic()) {
        return Err("Paste your Canvas access token.".into());
    }
    let link = Link::Token { host, token };
    let loaded = load(&link).await?;
    save(&account, &link)?;
    Ok(loaded)
}

#[tauri::command]
pub async fn canvas_link_feed(account: String, url: String) -> Result<Loaded, String> {
    let url = normalized_feed_url(&url).ok_or("Paste the calendar feed link from Canvas (Calendar \u{2192} Calendar Feed).")?;
    let link = Link::Feed { url };
    let loaded = load(&link).await?;
    save(&account, &link)?;
    Ok(loaded)
}

#[tauri::command]
pub async fn canvas_refresh(account: String) -> Result<Loaded, String> {
    let link = stored(&account).ok_or("Canvas sign-in details are missing. Unlink and link Canvas again.")?;
    load(&link).await
}

#[tauri::command]
pub fn canvas_unlink(account: String) {
    if let Ok(item) = entry(&account) {
        let _ = item.delete_credential();
    }
}

// ---------- Input ----------

/// `https://School.Instructure.com/courses` → `school.instructure.com`; nil unless it looks like a host name.
fn normalized_host(input: &str) -> Option<String> {
    let mut text = input.trim().to_lowercase();
    for prefix in ["https://", "http://"] {
        if let Some(rest) = text.strip_prefix(prefix) {
            text = rest.to_string();
        }
    }
    let text = text.split('/').next().unwrap_or("").to_string();
    let ok = text.contains('.') && !text.starts_with('.') && !text.ends_with('.') && text.len() <= 253
        && text.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '.' || c == '-');
    ok.then_some(text)
}

/// Canvas offers the feed as webcal:// for calendar apps; it's the same resource over https. Only https is used.
fn normalized_feed_url(input: &str) -> Option<String> {
    let mut text = input.trim().to_string();
    for prefix in ["webcal://", "http://"] {
        if text.to_lowercase().starts_with(prefix) {
            text = format!("https://{}", &text[prefix.len()..]);
        }
    }
    let url = reqwest::Url::parse(&text).ok()?;
    (url.scheme() == "https" && url.host_str().is_some() && text.len() <= 2048).then_some(text)
}

fn host_of(url: &str) -> Option<String> {
    reqwest::Url::parse(url).ok()?.host_str().map(str::to_lowercase)
}

// ---------- Fetching ----------

fn client() -> Result<reqwest::Client, String> {
    reqwest::Client::builder()
        .timeout(Duration::from_secs(15))
        .https_only(true)
        // Redirects could carry the token elsewhere; Canvas API and feeds answer directly.
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .map_err(|_| "Couldn't reach Canvas. Try again.".to_string())
}

fn status_message(status: u16, feed: bool) -> String {
    match (status, feed) {
        (401, _) => "Canvas rejected the access token. Create a new one in Canvas \u{2192} Account \u{2192} Settings.".into(),
        (403, _) => "Canvas refused access. Your school may not allow access tokens \u{2014} try the calendar feed instead.".into(),
        (404, true) => "Canvas couldn't find that calendar feed. Copy the link again from Calendar \u{2192} Calendar Feed.".into(),
        (404, false) => "No Canvas site found at that address. Check your school's Canvas URL.".into(),
        (429, _) => "Canvas is busy right now. Try again in a minute.".into(),
        (500..=599, _) => "Your school's Canvas is having problems right now. Try again later.".into(),
        _ => "Couldn't load your assignments from Canvas. Try again later.".into(),
    }
}

fn network_message(error: &reqwest::Error) -> String {
    if error.is_timeout() {
        "Canvas took too long to answer. Try again in a moment.".into()
    } else if error.is_connect() {
        "Couldn't find that Canvas address, or you're offline. Check the address and your connection.".into()
    } else {
        "Couldn't reach Canvas. Try again.".into()
    }
}

async fn read_body(response: reqwest::Response) -> Result<Vec<u8>, String> {
    if response.content_length().is_some_and(|n| n as usize > MAX_BODY) {
        return Err("Canvas sent more than Locken can read.".into());
    }
    let bytes = response.bytes().await.map_err(|e| network_message(&e))?;
    if bytes.len() > MAX_BODY {
        return Err("Canvas sent more than Locken can read.".into());
    }
    Ok(bytes.to_vec())
}

async fn load(link: &Link) -> Result<Loaded, String> {
    let client = client()?;
    match link {
        Link::Feed { url } => {
            let response = client.get(url).send().await.map_err(|e| network_message(&e))?;
            let status = response.status().as_u16();
            if status != 200 {
                return Err(status_message(status, true));
            }
            let text = String::from_utf8(read_body(response).await?).map_err(|_| "That link didn't return a Canvas calendar feed.".to_string())?;
            if !text.contains("BEGIN:VCALENDAR") {
                return Err("That link didn't return a Canvas calendar feed.".into());
            }
            Ok(Loaded::Feed { text })
        }
        Link::Token { host, token } => Ok(Loaded::Api { items: fetch_pending(&client, host, token).await? }),
    }
}

/// Authenticated GETs against one Canvas host, following `Link: <…>; rel="next"` on that same host only.
async fn get_pages(client: &reqwest::Client, host: &str, token: &str, path_and_query: &str, max_pages: usize) -> Result<Vec<Value>, String> {
    let mut next = format!("https://{host}{path_and_query}");
    let mut pages = Vec::new();
    for _ in 0..max_pages {
        let response = client
            .get(&next)
            .bearer_auth(token)
            .header("Accept", "application/json")
            .send()
            .await
            .map_err(|e| network_message(&e))?;
        let status = response.status().as_u16();
        if status != 200 {
            return Err(status_message(status, false));
        }
        let link = response.headers().get("link").and_then(|v| v.to_str().ok()).map(str::to_string);
        let body = read_body(response).await?;
        pages.push(serde_json::from_slice(&body).map_err(|_| "Canvas sent a response Locken couldn't read.".to_string())?);
        match link.as_deref().and_then(next_page_url) {
            Some(url) if host_of(&url).as_deref() == Some(host) => next = url,
            _ => break,
        }
    }
    Ok(pages)
}

fn next_page_url(header: &str) -> Option<String> {
    header.split(',').find(|part| part.contains("rel=\"next\"")).and_then(|part| {
        let open = part.find('<')?;
        let close = part.find('>')?;
        (open < close).then(|| part[open + 1..close].to_string())
    })
}

/// The to-do list is required (it also proves the token works); per-course lists are best-effort, since some
/// courses restrict their assignment list for students.
async fn fetch_pending(client: &reqwest::Client, host: &str, token: &str) -> Result<Vec<Assignment>, String> {
    let mut items: Vec<Assignment> = Vec::new();
    for page in get_pages(client, host, token, "/api/v1/users/self/todo?per_page=50", 10).await? {
        let list = parse_todo(&page).ok_or("Canvas sent a response Locken couldn't read.")?;
        for item in list {
            if !items.iter().any(|i| i.id == item.id) {
                items.push(item);
            }
        }
    }
    let Ok(course_pages) = get_pages(client, host, token, "/api/v1/courses?enrollment_state=active&per_page=100", 10).await else {
        return Ok(items);
    };
    let courses: Vec<(i64, String)> = course_pages.iter().flat_map(parse_courses).collect();
    let fetches = courses.iter().take(40).map(|(id, name)| async move {
        let path = format!("/api/v1/courses/{id}/assignments?bucket=future&include[]=submission&order_by=due_at&per_page=100");
        get_pages(client, host, token, &path, 5).await.unwrap_or_default().iter().flat_map(|p| parse_course_assignments(p, name)).collect::<Vec<_>>()
    });
    for list in futures_util::future::join_all(fetches).await {
        for item in list {
            if !items.iter().any(|i| i.id == item.id) {
                items.push(item);
            }
        }
    }
    Ok(items)
}

fn text(value: &Value, cap: usize) -> String {
    value.as_str().unwrap_or("").chars().take(cap).collect()
}

fn parse_todo(page: &Value) -> Option<Vec<Assignment>> {
    Some(
        page.as_array()?
            .iter()
            .filter_map(|item| {
                let a = item.get("assignment")?;
                Some(Assignment {
                    id: format!("api-{}", a.get("id")?.as_i64()?),
                    title: text(&a["name"], 300),
                    course: text(&item["context_name"], 200),
                    due: text(&a["due_at"], 40),
                })
            })
            .collect(),
    )
}

/// Skips courses whose details are hidden (access restricted by date).
fn parse_courses(page: &Value) -> Vec<(i64, String)> {
    page.as_array()
        .map(|courses| {
            courses
                .iter()
                .filter_map(|c| {
                    let name = c["name"].as_str().or_else(|| c["course_code"].as_str())?;
                    Some((c["id"].as_i64()?, name.chars().take(200).collect()))
                })
                .collect()
        })
        .unwrap_or_default()
}

/// Dated assignments the student hasn't submitted yet.
fn parse_course_assignments(page: &Value, course: &str) -> Vec<Assignment> {
    page.as_array()
        .map(|list| {
            list.iter()
                .filter_map(|a| {
                    let due = a["due_at"].as_str()?;
                    if let Some(sub) = a.get("submission").filter(|s| s.is_object()) {
                        let unsubmitted = sub["submitted_at"].is_null() && sub["workflow_state"].as_str().unwrap_or("unsubmitted") == "unsubmitted";
                        if !unsubmitted {
                            return None;
                        }
                    }
                    Some(Assignment {
                        id: format!("api-{}", a["id"].as_i64()?),
                        title: text(&a["name"], 300),
                        course: course.to_string(),
                        due: due.chars().take(40).collect(),
                    })
                })
                .collect()
        })
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn normalizes_canvas_addresses() {
        assert_eq!(normalized_host(" https://School.Instructure.com/courses/1 ").as_deref(), Some("school.instructure.com"));
        assert_eq!(normalized_host("localhost"), None);
        assert_eq!(normalized_host("evil.com@x"), None);
        assert_eq!(normalized_feed_url("webcal://school.instructure.com/feeds/calendars/user_abc.ics").as_deref(), Some("https://school.instructure.com/feeds/calendars/user_abc.ics"));
        assert_eq!(normalized_feed_url("ftp://x.com/a"), None);
    }

    #[test]
    fn follows_next_links_on_the_same_host_only() {
        let header = r#"<https://s.instructure.com/api/v1/x?page=2>; rel="next", <https://s.instructure.com/api/v1/x?page=9>; rel="last""#;
        assert_eq!(next_page_url(header).as_deref(), Some("https://s.instructure.com/api/v1/x?page=2"));
        assert_eq!(host_of("https://other.com/x").as_deref(), Some("other.com"));
    }

    #[test]
    fn parses_todo_and_course_assignments() {
        let todo = json!([{ "context_name": "Biology", "assignment": { "id": 7, "name": "Lab report", "due_at": "2026-10-20T23:59:00Z" } }, { "type": "grading" }]);
        assert_eq!(parse_todo(&todo).unwrap(), vec![Assignment { id: "api-7".into(), title: "Lab report".into(), course: "Biology".into(), due: "2026-10-20T23:59:00Z".into() }]);
        let course = json!([
            { "id": 1, "name": "Done", "due_at": "2026-10-21T10:00:00Z", "submission": { "workflow_state": "submitted", "submitted_at": "x" } },
            { "id": 2, "name": "Open", "due_at": "2026-10-22T10:00:00Z", "submission": { "workflow_state": "unsubmitted", "submitted_at": null } },
            { "id": 3, "name": "Undated" }
        ]);
        let parsed = parse_course_assignments(&course, "Math");
        assert_eq!(parsed.len(), 1);
        assert_eq!(parsed[0].title, "Open");
    }
}
