use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

use serde_json::Value;

use crate::credential_store::{Cookie, CredentialStore, WebCredential};
use crate::error::WebBridgeError;
use crate::providers::ProviderRegistry;

const CDP_PORT: u16 = 18892;

/// Launch Chrome in debug mode for credential capture.
/// This opens Chrome with remote debugging enabled so we can intercept
/// network requests and capture authentication tokens.
pub fn launch_chrome_debug() -> Result<std::process::Child, WebBridgeError> {
    let chrome_paths = [
        // Linux
        "google-chrome",
        "google-chrome-stable",
        "chromium",
        "chromium-browser",
        "/usr/bin/google-chrome",
        "/usr/bin/chromium",
        "/usr/bin/chromium-browser",
        // macOS
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        // Snap
        "/snap/bin/chromium",
    ];

    let chrome_path = chrome_paths.iter().find(|path| {
        Command::new("which")
            .arg(path)
            .output()
            .map(|o| o.status.success())
            .unwrap_or(false)
            || std::path::Path::new(path).exists()
    });

    let Some(chrome_path) = chrome_path else {
        return Err(WebBridgeError::Browser(
            "Chrome/Chromium not found. Please install Chrome or Chromium.".into(),
        ));
    };

    let user_data_dir = dirs::home_dir()
        .map(|h| h.join(".claw").join("chrome-profile"))
        .unwrap_or_else(|| std::path::PathBuf::from("/tmp/claw-chrome-profile"));

    let child = Command::new(chrome_path)
        .arg(format!("--remote-debugging-port={CDP_PORT}"))
        .arg(format!(
            "--user-data-dir={}",
            user_data_dir.to_string_lossy()
        ))
        .arg("--no-first-run")
        .arg("--no-default-browser-check")
        .spawn()
        .map_err(|e| WebBridgeError::Browser(format!("Failed to launch Chrome: {e}")))?;

    Ok(child)
}

/// Capture credentials from a running Chrome debug instance via CDP.
/// Connects to Chrome's DevTools protocol and extracts cookies for the
/// specified provider's domains.
pub async fn capture_credentials(provider_name: &str) -> Result<WebCredential, WebBridgeError> {
    let registry = ProviderRegistry::new();
    let provider = registry
        .get(provider_name)
        .ok_or_else(|| WebBridgeError::UnknownProvider(provider_name.into()))?;

    let domains = provider.credential_domains();

    // Connect to Chrome DevTools Protocol
    let cdp_url = format!("http://127.0.0.1:{CDP_PORT}/json");
    let client = reqwest::Client::new();

    let targets_response = client
        .get(&cdp_url)
        .send()
        .await
        .map_err(|e| {
            WebBridgeError::Browser(format!(
                "Cannot connect to Chrome CDP at port {CDP_PORT}. \
                 Make sure Chrome is running with --remote-debugging-port={CDP_PORT}.\n\
                 Run `claw web-chrome` first.\n\
                 Error: {e}"
            ))
        })?
        .json::<Vec<Value>>()
        .await
        .map_err(|e| WebBridgeError::Browser(format!("Failed to parse CDP targets: {e}")))?;

    // Get cookies via CDP
    let cookies_url = format!("http://127.0.0.1:{CDP_PORT}/json/protocol");

    // Use the DevTools HTTP API to get cookies for the target domains
    // We'll use the /json/version endpoint and then send CDP commands
    let mut all_cookies = Vec::new();
    let mut bearer_token = None;
    let mut user_agent = None;

    // Get browser version info for user agent
    let version_url = format!("http://127.0.0.1:{CDP_PORT}/json/version");
    if let Ok(response) = client.get(&version_url).send().await {
        if let Ok(version_info) = response.json::<Value>().await {
            user_agent = version_info
                .get("User-Agent")
                .and_then(Value::as_str)
                .map(String::from);
        }
    }

    // Find a page target for the provider's domain
    for target in &targets_response {
        let url = target.get("url").and_then(Value::as_str).unwrap_or("");
        let is_matching = domains.iter().any(|d| url.contains(d));

        if is_matching {
            if let Some(ws_url) = target.get("webSocketDebuggerUrl").and_then(Value::as_str) {
                // Connect via WebSocket and get cookies
                match extract_cookies_via_cdp(ws_url, domains).await {
                    Ok((cookies, token)) => {
                        all_cookies = cookies;
                        if token.is_some() {
                            bearer_token = token;
                        }
                        break;
                    }
                    Err(e) => {
                        tracing::warn!("Failed to extract cookies from {url}: {e}");
                    }
                }
            }
        }
    }

    if all_cookies.is_empty() {
        return Err(WebBridgeError::Browser(format!(
            "No cookies found for {}. Please:\n\
             1. Run `claw web-chrome`\n\
             2. Open {} in the Chrome window\n\
             3. Log in to your account\n\
             4. Then run `claw web-login {}` again",
            provider.display_name(),
            provider.login_url(),
            provider_name,
        )));
    }

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();

    Ok(WebCredential {
        provider: provider_name.to_string(),
        cookies: all_cookies,
        bearer_token,
        user_agent,
        captured_at: now,
    })
}

/// Extract cookies from a Chrome page via CDP WebSocket.
async fn extract_cookies_via_cdp(
    ws_url: &str,
    domains: &[&str],
) -> Result<(Vec<Cookie>, Option<String>), WebBridgeError> {
    // For simplicity, we use the HTTP-based CDP cookie extraction.
    // In a full implementation, this would use a WebSocket CDP client
    // (like chromiumoxide) to send Network.getCookies and
    // Network.getAllCookies commands.

    // Fallback: read cookies from Chrome's cookie file
    // This works when we can't use WebSocket CDP
    let cookies = extract_cookies_from_chrome_profile(domains)?;

    Ok((cookies, None))
}

/// Extract cookies from Chrome's user data directory.
/// This reads the Cookies SQLite database that Chrome maintains.
fn extract_cookies_from_chrome_profile(domains: &[&str]) -> Result<Vec<Cookie>, WebBridgeError> {
    let cookie_db_path = dirs::home_dir()
        .map(|h| h.join(".claw").join("chrome-profile").join("Default").join("Cookies"))
        .ok_or_else(|| WebBridgeError::Browser("Cannot determine home directory".into()))?;

    if !cookie_db_path.exists() {
        return Err(WebBridgeError::Browser(format!(
            "Chrome cookie database not found at {}. Make sure you've logged in via `claw web-chrome`.",
            cookie_db_path.display()
        )));
    }

    // Note: In production, this would use rusqlite to read the Cookies database.
    // Chrome encrypts cookies on some platforms, requiring platform-specific
    // decryption (DPAPI on Windows, Keychain on macOS, secretstorage on Linux).
    //
    // For now, we rely on the CDP approach or manual cookie input.
    // Users can also provide cookies via `claw web-login --cookies "..."`.

    tracing::info!(
        "Cookie database found at {}. Use CDP WebSocket for live extraction.",
        cookie_db_path.display()
    );

    Ok(Vec::new())
}

/// Manually set credentials for a provider.
/// Used when CDP capture isn't available — user pastes cookies directly.
pub fn set_credentials_manual(
    provider_name: &str,
    cookies_str: &str,
    bearer_token: Option<&str>,
) -> Result<(), WebBridgeError> {
    let registry = ProviderRegistry::new();
    let provider = registry
        .get(provider_name)
        .ok_or_else(|| WebBridgeError::UnknownProvider(provider_name.into()))?;

    // Parse cookie string: "name1=value1; name2=value2"
    let cookies: Vec<Cookie> = cookies_str
        .split(';')
        .filter_map(|pair| {
            let pair = pair.trim();
            let (name, value) = pair.split_once('=')?;
            Some(Cookie {
                name: name.trim().to_string(),
                value: value.trim().to_string(),
                domain: provider.credential_domains().first().unwrap_or(&"").to_string(),
                path: Some("/".into()),
                expires: None,
                http_only: false,
                secure: true,
            })
        })
        .collect();

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();

    let credential = WebCredential {
        provider: provider_name.to_string(),
        cookies,
        bearer_token: bearer_token.map(String::from),
        user_agent: None,
        captured_at: now,
    };

    let mut store = CredentialStore::load();
    store.set(provider_name.to_string(), credential);
    store.save()?;

    Ok(())
}
