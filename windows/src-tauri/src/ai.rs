//! Intelligent Rephrase and session steps (the Windows side of the Mac app's AITaskFormatter).
//! Uses the student's own Claude (`sk-ant-…`), ChatGPT (OpenAI `sk-…`) or Gemini (Google AI Studio) key. The key lives in Windows
//! Credential Manager, per account, and every request is made here in Rust, so the key never reaches the web
//! view. Only the goal, session length and workspace app are sent, after emails, links and phone numbers are
//! replaced with placeholders. The age (18+) and on/off checks happen in the app before these are called.

use keyring::Entry;
use regex::Regex;
use serde_json::{json, Value};
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

const SERVICE: &str = "app.locken.windows.ai";
/// Same model as the Mac app.
const CLAUDE_MODEL: &str = "claude-sonnet-5";
/// Plain chat models, best first (same as the Mac app); the next one is tried when a key has no access to one.
const OPENAI_MODELS: [&str; 2] = ["gpt-4.1-mini", "gpt-4o-mini"];
const FALLBACK_GEMINI_MODELS: [&str; 7] = [
    "gemini-3.5-flash", "gemini-3.6-flash", "gemini-3.7-flash", "gemini-3.8-flash",
    "gemini-3.5-flash-lite", "gemini-3.1-flash-lite", "gemini-2.5-flash",
];

/// Gemini models this key can use, best first; looked up once per key.
static GEMINI_MODELS: Mutex<Option<Vec<String>>> = Mutex::new(None);

#[derive(Clone, Copy, PartialEq, Debug)]
enum Provider {
    Claude,
    OpenAi,
    Gemini,
}

impl Provider {
    fn name(self) -> &'static str {
        match self {
            Provider::Claude => "Claude",
            Provider::OpenAi => "ChatGPT",
            Provider::Gemini => "Gemini",
        }
    }

    /// Claude keys start with `sk-ant-` and OpenAI's with `sk-` (`sk-proj-…`). Any other key is treated as Gemini, since
    /// AI Studio's newer key format isn't documented (same rule as the Mac app).
    fn detect(key: &str) -> Option<Provider> {
        if key.starts_with("sk-ant-") {
            return Some(Provider::Claude);
        }
        if key.chars().count() < 20 || key.chars().any(char::is_whitespace) {
            return None;
        }
        Some(if key.starts_with("sk-") { Provider::OpenAi } else { Provider::Gemini })
    }
}

/// One Credential Manager item per Locken account, so one account's key is never used by another on the same PC.
fn entry(account: &str) -> Result<Entry, String> {
    if account.is_empty() || account.len() > 64 || !account.chars().all(|c| c.is_ascii_alphanumeric() || c == '-') {
        return Err("Sign in again to use AI features.".into());
    }
    Entry::new(SERVICE, account).map_err(|_| "Couldn't open secure storage.".to_string())
}

fn stored_key(account: &str) -> Option<String> {
    entry(account).ok()?.get_password().ok()
}

#[tauri::command]
pub fn ai_key_status(account: String) -> Option<String> {
    stored_key(&account).and_then(|key| Provider::detect(&key)).map(|p| p.name().to_string())
}

#[tauri::command]
pub fn ai_save_key(account: String, key: String) -> Result<String, String> {
    let key = key.trim();
    let provider = Provider::detect(key)
        .filter(|_| key.len() <= 512 && key.chars().all(|c| c.is_ascii_graphic()))
        .ok_or("That doesn't look like a Claude (sk-ant-…), ChatGPT (sk-…) or Gemini (Google AI Studio) key.")?;
    entry(&account)?.set_password(key).map_err(|_| "Couldn't save the key.".to_string())?;
    *GEMINI_MODELS.lock().unwrap_or_else(|e| e.into_inner()) = None;
    Ok(provider.name().to_string())
}

#[tauri::command]
pub fn ai_remove_key(account: String) {
    if let Ok(item) = entry(&account) {
        let _ = item.delete_credential();
    }
    *GEMINI_MODELS.lock().unwrap_or_else(|e| e.into_inner()) = None;
}

#[tauri::command]
pub async fn ai_rephrase(account: String, goal: String, minutes: u32, app: Option<String>) -> Result<String, String> {
    let raw = ask(&account, &system_prompt(minutes), &user_message(&goal, minutes, app.as_deref()), 400).await?;
    let text = cleaned(&raw);
    if text.is_empty() {
        return Err(EMPTY.into());
    }
    if text.to_uppercase().starts_with("UNCLEAR") {
        return Err("Couldn't tell what that goal is about. Add the subject or task, like \u{201C}math homework\u{201D} or \u{201C}history essay\u{201D}.".into());
    }
    Ok(text.chars().take(200).collect())
}

#[tauri::command]
pub async fn ai_milestones(account: String, goal: String, minutes: u32, app: Option<String>) -> Result<Vec<String>, String> {
    let raw = ask(&account, &milestones_prompt(minutes), &user_message(&goal, minutes, app.as_deref()), 400).await?;
    let steps = steps(&raw);
    if steps.is_empty() {
        return Err("The AI didn't send back any steps.".into());
    }
    Ok(steps)
}

/// A plan for the next 7 days from Canvas due dates (the Mac's week digest, without Apple Calendar events).
/// `lines` are the app's own "- [Canvas] Tue, Oct 20, due 11:59 PM: Title (Course)" lines; only those are sent.
#[tauri::command]
pub async fn ai_week_digest(account: String, today: String, lines: Vec<String>) -> Result<String, String> {
    let today: String = today.chars().take(80).collect();
    let lines: Vec<String> = lines.iter().take(80).map(|l| l.chars().take(300).collect()).collect();
    let message = if lines.is_empty() { "Nothing is scheduled or due in the next 7 days.".to_string() } else { format!("My next 7 days:\n{}", lines.join("\n")) };
    let text = ask(&account, &week_digest_prompt(&today), &message, 900).await?;
    let text = text.trim().to_string();
    if text.is_empty() {
        return Err("The AI didn't send back a plan. Try again.".into());
    }
    Ok(text.chars().take(6000).collect())
}

fn week_digest_prompt(today: &str) -> String {
    format!("You turn a student's next 7 days of Canvas assignments into a short weekly plan.
Today is {today}.

Reply in Markdown with these sections, each starting with a level-3 heading (###):
### Due this week
Bullets in date order: the assignment, its course, and its due day and time. Start the bullet with **Soon:** when it's due within 48 hours. If nothing is due, write one line saying so.
### Busy days
1 to 3 bullets naming the days with the most deadlines, and why.
### Plan
3 to 5 bullets suggesting when to work on which assignment, for example \"Tuesday after school: 45 minutes on Unit 1 Review\".

Use only the items given. Never invent assignments, courses or times. No emojis, no introduction or sign-off.")
}

// ---------- Prompts (same text as the Mac app) ----------

fn system_prompt(minutes: u32) -> String {
    format!("You turn a student's rough focus-session goal into one clear goal they can finish in this session.

Students often type vague, lazy goals like \"do math\" or \"read book\". Rewrite the goal so it is:
- Specific: name the exact task, the material and an amount (problems, pages, sections, paragraphs).
- Actionable: start with a concrete verb such as Complete, Draft, Read and annotate, Solve, Outline, Review.
- Achievable in about {minutes} minutes: scale the amount to the session length.
- Motivating but plain: no hype, emojis or exclamation marks.

Keep the student's intent and subject. Never change the subject to something they didn't mention.

If the goal doesn't say what the work is (random words, a name, a joke, gibberish, or something like \"lock in\" or \"work\"), don't guess. Reply with exactly: UNCLEAR

Examples:
do math -> Complete 15 practice problems for Calculus Chapter 4
read book -> Read and annotate Chapter 3 of the Biology textbook
essay -> Draft the introduction and first body paragraph of the history essay
locken lockin -> UNCLEAR
asdf -> UNCLEAR

Reply with the goal only (or UNCLEAR): one sentence, at most 110 characters, no quotation marks, no preamble.")
}

fn step_count(minutes: u32) -> u32 {
    match minutes {
        0..=19 => 3,
        20..=49 => 4,
        _ => 5,
    }
}

fn milestones_prompt(minutes: u32) -> String {
    format!("You break a student's focus-session goal into {} small milestones they will tick off, in order, during a {minutes}-minute session.

Each milestone:
- Is one concrete step toward the goal, specific to its subject and material.
- Starts with a verb such as Read, Outline, Solve, Draft, Check or Review.
- Is sized so all of them together fit in about {minutes} minutes.
- Is at most 60 characters, plain, with no emojis.

Reply with the milestones only, one per line, no numbering, bullets or other text.", step_count(minutes))
}

fn user_message(goal: &str, minutes: u32, app: Option<&str>) -> String {
    let goal: String = goal.chars().take(200).collect();
    let mut lines = vec![format!("Goal: {goal}"), format!("Session length: {minutes} minutes")];
    if let Some(app) = app.filter(|a| !a.is_empty()) {
        lines.push(format!("Working in: {}", app.chars().take(40).collect::<String>()));
    }
    lines.join("\n")
}

/// First line only, without quotes or a "Goal:" label the model might add anyway.
fn cleaned(raw: &str) -> String {
    let mut text = raw.trim().lines().next().unwrap_or("").to_string();
    for label in ["goal:", "rephrased goal:", "rewritten goal:"] {
        if text.to_lowercase().starts_with(label) {
            text = text[label.len()..].to_string();
        }
    }
    text.trim_matches(|c: char| c.is_whitespace() || "\"'\u{201C}\u{201D}\u{2018}\u{2019}`*".contains(c)).to_string()
}

/// One step per line, without the numbering or bullets a model may add anyway; at most six.
fn steps(raw: &str) -> Vec<String> {
    raw.lines()
        .map(|line| {
            let line = line.replace("**", "");
            let trimmed = line.trim().trim_start_matches(|c: char| c.is_ascii_digit() || "-*\u{2022}\u{2013}\u{00B7}.) ".contains(c));
            cleaned(trimmed)
        })
        .filter(|s| !s.is_empty())
        .take(6)
        .map(|s| s.chars().take(120).collect())
        .collect()
}

/// Replaces email addresses, links and phone numbers with placeholders before anything is sent.
fn scrub(text: &str) -> String {
    static RULES: OnceLock<Vec<(Regex, &'static str)>> = OnceLock::new();
    let rules = RULES.get_or_init(|| {
        vec![
            (Regex::new(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}").unwrap(), "[email]"),
            (Regex::new(r#"(?:https?://|www\.)[^\s<>"']+"#).unwrap(), "[link]"),
            (Regex::new(r"(?:\+?\d{1,3}[\s.-]?)?(?:\(\d{3}\)|\b\d{3})[\s.-]?\d{3}[\s.-]?\d{4}\b").unwrap(), "[phone]"),
        ]
    });
    rules.iter().fold(text.to_string(), |acc, (re, placeholder)| re.replace_all(&acc, *placeholder).into_owned())
}

// ---------- Providers ----------

fn client() -> Result<reqwest::Client, String> {
    reqwest::Client::builder()
        .timeout(Duration::from_secs(30))
        .https_only(true)
        .build()
        .map_err(|_| "Couldn't reach the AI service.".to_string())
}

async fn ask(account: &str, system: &str, user: &str, max_tokens: u32) -> Result<String, String> {
    let key = stored_key(account).ok_or("Add a Claude, ChatGPT or Gemini API key in Settings to use Intelligent Rephrase.")?;
    let provider = Provider::detect(&key).ok_or("That doesn't look like a Claude (sk-ant-…), ChatGPT (sk-…) or Gemini (Google AI Studio) key.")?;
    let user = scrub(user);
    let client = client()?;
    let answer = match provider {
        Provider::Claude => retry_once(|| ask_claude(&client, &key, system, &user, max_tokens)).await,
        Provider::OpenAi => retry_once(|| ask_openai(&client, &key, system, &user, max_tokens)).await,
        Provider::Gemini => ask_gemini(&client, &key, system, &user, max_tokens).await,
    };
    answer.map_err(|(message, _)| message)
}

/// What the student is told, and whether trying again straight away usually works (a dropped connection, a busy server,
/// a rate limit, a blank answer). The Mac's `FormatterError.isTransient`.
type Failure = (String, bool);

const EMPTY: &str = "The AI sent back an empty answer. Try again.";

/// Claude and ChatGPT get one more try after a second before the student sees an error; Gemini has its own fallback across models.
async fn retry_once<F, Fut>(work: F) -> Result<String, Failure>
where
    F: Fn() -> Fut,
    Fut: std::future::Future<Output = Result<String, Failure>>,
{
    match work().await {
        Err((_, true)) => {
            let _ = tauri::async_runtime::spawn_blocking(|| std::thread::sleep(Duration::from_secs(1))).await;
            work().await
        }
        other => other,
    }
}

async fn send(request: reqwest::RequestBuilder) -> Result<(u16, Value), Failure> {
    let response = request.send().await.map_err(|_| ("Couldn't reach the AI service. Check your internet connection.".to_string(), true))?;
    let status = response.status().as_u16();
    let body = response.json::<Value>().await.unwrap_or(Value::Null);
    Ok((status, body))
}

/// A blank answer is a failure, so the next try or model gets its turn.
fn non_blank(text: String) -> Result<String, Failure> {
    if text.trim().is_empty() { Err((EMPTY.to_string(), true)) } else { Ok(text) }
}

fn busy_or_problem(provider: Provider, status: u16) -> Failure {
    let retry = status == 408 || (500..=599).contains(&status);
    if [502, 503, 504, 529].contains(&status) {
        (format!("{} is busy right now (error {status}). Try again in a moment.", provider.name()), retry)
    } else {
        // The provider's own message stays out of the UI; the status is enough to report a problem.
        (format!("{} had a problem (error {status}). Try again in a moment.", provider.name()), retry)
    }
}

async fn ask_claude(client: &reqwest::Client, key: &str, system: &str, user: &str, max_tokens: u32) -> Result<String, Failure> {
    let request = client
        .post("https://api.anthropic.com/v1/messages")
        .header("x-api-key", key)
        .header("anthropic-version", "2023-06-01")
        .json(&json!({
            "model": CLAUDE_MODEL,
            "max_tokens": max_tokens,
            "system": system,
            "messages": [{ "role": "user", "content": user }],
        }));
    let (status, body) = send(request).await?;
    match status {
        200 => non_blank(
            body["content"]
                .as_array()
                .map(|blocks| blocks.iter().filter(|b| b["type"] == "text").filter_map(|b| b["text"].as_str()).collect::<String>())
                .unwrap_or_default(),
        ),
        401 | 403 => Err(("Claude rejected the API key. Check it in Settings.".into(), false)),
        429 => Err(("Claude is limiting requests right now. Try again in a minute.".into(), true)),
        _ => Err(busy_or_problem(Provider::Claude, status)),
    }
}

/// Tries the plain chat models in turn, skipping one the key has no access to.
async fn ask_openai(client: &reqwest::Client, key: &str, system: &str, user: &str, max_tokens: u32) -> Result<String, Failure> {
    for (index, model) in OPENAI_MODELS.iter().enumerate() {
        let last = index == OPENAI_MODELS.len() - 1;
        let request = client
            .post("https://api.openai.com/v1/chat/completions")
            .bearer_auth(key)
            .json(&json!({
                "model": model,
                "max_completion_tokens": max_tokens,
                "messages": [{ "role": "system", "content": system }, { "role": "user", "content": user }],
            }));
        let (status, body) = send(request).await?;
        match status {
            200 => return non_blank(body["choices"][0]["message"]["content"].as_str().unwrap_or_default().to_string()),
            401 => return Err(("ChatGPT rejected the API key. Check it in Settings.".into(), false)),
            403 | 404 if !last => continue,
            403 => return Err(("ChatGPT didn't allow this key to use a model Locken can use. Check the key's project and permissions at platform.openai.com, or create a new key there.".into(), false)),
            404 => return Err(("ChatGPT has no model Locken can use for this key. Check the key's project at platform.openai.com, or create a new key there.".into(), false)),
            // A key with no credit left also answers 429; it needs billing, not waiting.
            429 if body["error"]["code"] == "insufficient_quota" => {
                return Err(("This ChatGPT key has no credit left. Add credit at platform.openai.com/settings/organization/billing, or paste a different key. A ChatGPT Plus subscription doesn't include API credit.".into(), false))
            }
            429 => return Err(("ChatGPT is limiting requests right now. Try again in a minute.".into(), true)),
            _ => return Err(busy_or_problem(Provider::OpenAi, status)),
        }
    }
    Err((EMPTY.into(), true))
}

/// Tries the key's best Flash models in turn, skipping ones that are out of quota, not offered to it, or overloaded.
async fn ask_gemini(client: &reqwest::Client, key: &str, system: &str, user: &str, max_tokens: u32) -> Result<String, Failure> {
    let cached = GEMINI_MODELS.lock().unwrap_or_else(|e| e.into_inner()).clone();
    let models = match cached {
        Some(models) => models,
        None => {
            let models = available_gemini_models(client, key).await;
            *GEMINI_MODELS.lock().unwrap_or_else(|e| e.into_inner()) = Some(models.clone());
            models
        }
    };
    let mut last: Failure = (EMPTY.to_string(), true);
    for model in models.iter().take(4) {
        let request = client
            .post(format!("https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"))
            .header("x-goog-api-key", key)
            .json(&json!({
                "systemInstruction": { "parts": [{ "text": system }] },
                "contents": [{ "role": "user", "parts": [{ "text": user }] }],
                // Roomy limit: newer Gemini models spend part of it thinking before they answer.
                "generationConfig": { "maxOutputTokens": (max_tokens * 2).max(1024) },
            }));
        // A dropped connection says nothing lasting about the model: the next one gets its turn.
        let (status, body) = match send(request).await {
            Ok(answer) => answer,
            Err(failure) => {
                last = failure;
                continue;
            }
        };
        if status == 200 {
            let parts = body["candidates"][0]["content"]["parts"].as_array().cloned().unwrap_or_default();
            let text: String = parts.iter().filter(|p| p["thought"] != true).filter_map(|p| p["text"].as_str()).collect();
            // A blank answer (blocked, or all of the limit spent thinking) isn't an answer: try the next model.
            if text.trim().is_empty() {
                last = (EMPTY.to_string(), true);
                continue;
            }
            return Ok(text);
        }
        let (message, try_next) = gemini_error(status, &body);
        if !try_next {
            return Err((message, false));
        }
        if let Ok(mut cache) = GEMINI_MODELS.lock() {
            if let Some(list) = cache.as_mut() {
                list.retain(|m| m != model);
            }
        }
        last = (message, true);
    }
    Err(last)
}

/// What the student should do about Google's error, and whether the next model is worth trying.
fn gemini_error(status: u16, body: &Value) -> (String, bool) {
    let message = body["error"]["message"].as_str().unwrap_or("").to_lowercase();
    let reasons: Vec<&str> = body["error"]["details"].as_array().map(|d| d.iter().filter_map(|x| x["reason"].as_str()).collect()).unwrap_or_default();
    let has = |r: &str| reasons.contains(&r);
    let fix = "Create a new key at aistudio.google.com/apikey and paste it in Settings, or change this key in Google Cloud Console \u{203A} APIs & Services \u{203A} Credentials.";
    if has("API_KEY_INVALID") || (status == 400 && message.contains("api key not valid")) || status == 401 {
        return ("Gemini rejected the API key. Check it in Settings.".into(), false);
    }
    if has("SERVICE_DISABLED") {
        return ("The Gemini API is turned off for this key's Google Cloud project. Create a key in Google AI Studio, or turn on the Generative Language API for that project.".into(), false);
    }
    if has("API_KEY_SERVICE_BLOCKED") {
        return (format!("This key isn't allowed to use the Gemini API: its API restrictions leave out the Generative Language API. {fix}"), false);
    }
    if reasons.iter().any(|r| r.starts_with("API_KEY_") && r.ends_with("_BLOCKED")) {
        return (format!("This key only works in certain places, so a PC app can't use it. {fix} Set Application restrictions to None."), false);
    }
    if status == 400 && message.contains("location is not supported") {
        return ("Gemini isn't available where you are, so Google refused the request.".into(), false);
    }
    match status {
        403 => ("Gemini didn't allow this key to use any of its models. Check the key in Google AI Studio, or create a new one there.".into(), true),
        429 => ("Gemini is limiting requests right now. Try again in a minute.".into(), true),
        404 | 500..=599 => (busy_or_problem(Provider::Gemini, status).0, true),
        _ => (busy_or_problem(Provider::Gemini, status).0, false),
    }
}

async fn available_gemini_models(client: &reqwest::Client, key: &str) -> Vec<String> {
    let fallback = || FALLBACK_GEMINI_MODELS.iter().map(|m| m.to_string()).collect::<Vec<_>>();
    let request = client.get("https://generativelanguage.googleapis.com/v1beta/models?pageSize=200").header("x-goog-api-key", key);
    let Ok((200, body)) = send(request).await else { return fallback() };
    let names: Vec<String> = body["models"]
        .as_array()
        .map(|models| {
            models
                .iter()
                .filter(|m| m["supportedGenerationMethods"].as_array().is_some_and(|s| s.iter().any(|x| x == "generateContent")))
                .filter_map(|m| m["name"].as_str())
                .map(|n| n.trim_start_matches("models/").to_string())
                .collect()
        })
        .unwrap_or_default();
    let ranked = ranked_gemini_models(names);
    if ranked.is_empty() { fallback() } else { ranked }
}

/// Flash models only, stable before preview, full-size before lite, newest first.
fn ranked_gemini_models(names: Vec<String>) -> Vec<String> {
    const EXCLUDED: [&str; 9] = ["image", "tts", "audio", "live", "embed", "computer-use", "robotics", "aqa", "learnlm"];
    let version = |n: &str| n.trim_start_matches("gemini-").chars().take_while(|c| c.is_ascii_digit() || *c == '.').collect::<String>().parse::<f64>().unwrap_or(0.0);
    let unstable = |n: &str| n.contains("preview") || n.contains("exp");
    let mut models: Vec<String> = names
        .into_iter()
        .filter(|n| n.starts_with("gemini-") && n.contains("flash") && !EXCLUDED.iter().any(|x| n.contains(x)))
        .collect();
    models.sort_by(|a, b| {
        unstable(a).cmp(&unstable(b))
            .then(a.contains("lite").cmp(&b.contains("lite")))
            .then(version(b).partial_cmp(&version(a)).unwrap_or(std::cmp::Ordering::Equal))
    });
    models
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_the_provider_like_the_mac() {
        assert_eq!(Provider::detect("sk-ant-api03-abc"), Some(Provider::Claude));
        assert_eq!(Provider::detect("sk-proj-0123456789012345678901"), Some(Provider::OpenAi));
        assert_eq!(Provider::detect("sk-short"), None);
        assert_eq!(Provider::detect("AIzaSyA0123456789012345678901"), Some(Provider::Gemini));
        assert_eq!(Provider::detect("short"), None);
        assert_eq!(Provider::detect("has a space in it but long enough"), None);
    }

    #[test]
    fn scrubs_contact_details_before_sending() {
        let out = scrub("email me at kid@school.org or call 555-123-4567, see https://x.com/a");
        assert_eq!(out, "email me at [email] or call [phone], see [link]");
        assert_eq!(scrub("Read chapter 3 pages 10-20"), "Read chapter 3 pages 10-20");
    }

    #[test]
    fn cleans_goal_and_steps() {
        assert_eq!(cleaned("Goal: \"Complete 15 problems\"\nextra"), "Complete 15 problems");
        assert_eq!(steps("1. Read pages 1-5\n- **Outline** the essay\n\n• Check work"), vec!["Read pages 1-5", "Outline the essay", "Check work"]);
    }

    #[test]
    fn blank_answers_are_failures_worth_retrying() {
        assert_eq!(non_blank("  \n".into()), Err((EMPTY.to_string(), true)));
        assert_eq!(non_blank("Read chapter 3".into()), Ok("Read chapter 3".to_string()));
    }

    #[test]
    fn retries_once_for_a_failure_that_usually_clears() {
        use std::sync::atomic::{AtomicU32, Ordering};
        let calls = AtomicU32::new(0);
        let result = tauri::async_runtime::block_on(retry_once(|| async {
            if calls.fetch_add(1, Ordering::SeqCst) == 0 { Err(("busy".to_string(), true)) } else { Ok("done".to_string()) }
        }));
        assert_eq!(result, Ok("done".to_string()));
        assert_eq!(calls.load(Ordering::SeqCst), 2);

        // A rejected key isn't retried, and a second failure is reported as it is.
        let calls = AtomicU32::new(0);
        let result = tauri::async_runtime::block_on(retry_once(|| async {
            calls.fetch_add(1, Ordering::SeqCst);
            Err::<String, Failure>(("Claude rejected the API key. Check it in Settings.".to_string(), false))
        }));
        assert_eq!(result, Err(("Claude rejected the API key. Check it in Settings.".to_string(), false)));
        assert_eq!(calls.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn ranks_gemini_models_like_the_mac() {
        let ranked = ranked_gemini_models(vec![
            "gemini-2.5-flash".into(), "gemini-3.5-flash-lite".into(), "gemini-3.5-flash".into(),
            "gemini-3.6-flash-preview".into(), "gemini-3.5-pro".into(), "gemini-3.5-flash-image".into(),
        ]);
        assert_eq!(ranked, vec!["gemini-3.5-flash", "gemini-2.5-flash", "gemini-3.5-flash-lite", "gemini-3.6-flash-preview"]);
    }
}
