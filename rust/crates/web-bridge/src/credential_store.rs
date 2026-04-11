use std::collections::HashMap;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};

/// Stored credentials for a single web provider.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WebCredential {
    pub provider: String,
    pub cookies: Vec<Cookie>,
    #[serde(default)]
    pub bearer_token: Option<String>,
    #[serde(default)]
    pub user_agent: Option<String>,
    /// Unix timestamp (seconds) when these credentials were captured.
    #[serde(default)]
    pub captured_at: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Cookie {
    pub name: String,
    pub value: String,
    pub domain: String,
    #[serde(default)]
    pub path: Option<String>,
    #[serde(default)]
    pub expires: Option<f64>,
    #[serde(default)]
    pub http_only: bool,
    #[serde(default)]
    pub secure: bool,
}

/// All stored credentials, keyed by provider name.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct CredentialStore {
    pub credentials: HashMap<String, WebCredential>,
}

impl CredentialStore {
    /// Returns the path to the credential store file: `~/.claw/web-credentials.json`
    pub fn default_path() -> Option<PathBuf> {
        // Respect CLAW_CONFIG_HOME if set
        let base = std::env::var("CLAW_CONFIG_HOME")
            .map(PathBuf::from)
            .ok()
            .or_else(|| dirs::home_dir().map(|h| h.join(".claw")))?;
        Some(base.join("web-credentials.json"))
    }

    /// Load credentials from disk. Returns an empty store if the file doesn't exist.
    pub fn load() -> Self {
        let Some(path) = Self::default_path() else {
            return Self::default();
        };
        match std::fs::read_to_string(&path) {
            Ok(contents) => serde_json::from_str(&contents).unwrap_or_default(),
            Err(_) => Self::default(),
        }
    }

    /// Atomically save credentials to disk (write-then-rename).
    pub fn save(&self) -> Result<(), std::io::Error> {
        let Some(path) = Self::default_path() else {
            return Err(std::io::Error::new(
                std::io::ErrorKind::NotFound,
                "cannot determine config directory",
            ));
        };
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let tmp = path.with_extension("json.tmp");
        let json = serde_json::to_string_pretty(self)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))?;
        std::fs::write(&tmp, json)?;
        std::fs::rename(&tmp, &path)?;
        Ok(())
    }

    /// Get credentials for a specific provider.
    pub fn get(&self, provider: &str) -> Option<&WebCredential> {
        self.credentials.get(provider)
    }

    /// Insert or update credentials for a provider.
    pub fn set(&mut self, provider: String, credential: WebCredential) {
        self.credentials.insert(provider, credential);
    }

    /// List all configured providers.
    pub fn providers(&self) -> Vec<&str> {
        self.credentials.keys().map(String::as_str).collect()
    }
}

impl Cookie {
    /// Format cookies as a Cookie header value.
    pub fn to_header_value(cookies: &[Cookie]) -> String {
        cookies
            .iter()
            .map(|c| format!("{}={}", c.name, c.value))
            .collect::<Vec<_>>()
            .join("; ")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_cookie(name: &str, value: &str, domain: &str) -> Cookie {
        Cookie {
            name: name.into(),
            value: value.into(),
            domain: domain.into(),
            path: Some("/".into()),
            expires: None,
            http_only: false,
            secure: true,
        }
    }

    fn sample_credential(provider: &str) -> WebCredential {
        WebCredential {
            provider: provider.into(),
            cookies: vec![
                sample_cookie("session", "abc123", "example.com"),
                sample_cookie("token", "xyz789", "example.com"),
            ],
            bearer_token: Some("bearer-test-token".into()),
            user_agent: Some("TestAgent/1.0".into()),
            captured_at: 1700000000,
        }
    }

    #[test]
    fn cookie_header_value_single() {
        let cookies = vec![sample_cookie("sid", "val1", "example.com")];
        assert_eq!(Cookie::to_header_value(&cookies), "sid=val1");
    }

    #[test]
    fn cookie_header_value_multiple() {
        let cookies = vec![
            sample_cookie("a", "1", "x.com"),
            sample_cookie("b", "2", "x.com"),
            sample_cookie("c", "3", "x.com"),
        ];
        assert_eq!(Cookie::to_header_value(&cookies), "a=1; b=2; c=3");
    }

    #[test]
    fn cookie_header_value_empty() {
        let cookies: Vec<Cookie> = vec![];
        assert_eq!(Cookie::to_header_value(&cookies), "");
    }

    #[test]
    fn credential_serialize_deserialize() {
        let cred = sample_credential("deepseek");
        let json = serde_json::to_string(&cred).unwrap();
        let parsed: WebCredential = serde_json::from_str(&json).unwrap();

        assert_eq!(parsed.provider, "deepseek");
        assert_eq!(parsed.cookies.len(), 2);
        assert_eq!(parsed.cookies[0].name, "session");
        assert_eq!(parsed.cookies[0].value, "abc123");
        assert_eq!(parsed.bearer_token, Some("bearer-test-token".into()));
        assert_eq!(parsed.user_agent, Some("TestAgent/1.0".into()));
        assert_eq!(parsed.captured_at, 1700000000);
    }

    #[test]
    fn credential_deserialize_missing_optional_fields() {
        let json = r#"{
            "provider": "test",
            "cookies": [],
            "captured_at": 0
        }"#;
        let cred: WebCredential = serde_json::from_str(json).unwrap();
        assert_eq!(cred.provider, "test");
        assert!(cred.bearer_token.is_none());
        assert!(cred.user_agent.is_none());
        assert!(cred.cookies.is_empty());
    }

    #[test]
    fn store_set_and_get() {
        let mut store = CredentialStore::default();
        assert!(store.get("deepseek").is_none());

        store.set("deepseek".into(), sample_credential("deepseek"));
        assert!(store.get("deepseek").is_some());
        assert_eq!(store.get("deepseek").unwrap().provider, "deepseek");
    }

    #[test]
    fn store_overwrite() {
        let mut store = CredentialStore::default();
        let mut cred1 = sample_credential("deepseek");
        cred1.captured_at = 100;
        store.set("deepseek".into(), cred1);

        let mut cred2 = sample_credential("deepseek");
        cred2.captured_at = 200;
        store.set("deepseek".into(), cred2);

        assert_eq!(store.get("deepseek").unwrap().captured_at, 200);
    }

    #[test]
    fn store_multiple_providers() {
        let mut store = CredentialStore::default();
        store.set("deepseek".into(), sample_credential("deepseek"));
        store.set("chatgpt".into(), sample_credential("chatgpt"));
        store.set("kimi".into(), sample_credential("kimi"));

        assert_eq!(store.providers().len(), 3);
        assert!(store.get("deepseek").is_some());
        assert!(store.get("chatgpt").is_some());
        assert!(store.get("kimi").is_some());
        assert!(store.get("gemini").is_none());
    }

    #[test]
    fn store_serialize_deserialize_roundtrip() {
        let mut store = CredentialStore::default();
        store.set("deepseek".into(), sample_credential("deepseek"));
        store.set("chatgpt".into(), sample_credential("chatgpt"));

        let json = serde_json::to_string_pretty(&store).unwrap();
        let parsed: CredentialStore = serde_json::from_str(&json).unwrap();

        assert_eq!(parsed.providers().len(), 2);
        assert_eq!(
            parsed.get("deepseek").unwrap().cookies.len(),
            store.get("deepseek").unwrap().cookies.len()
        );
    }

    #[test]
    fn store_save_and_load_to_temp_dir() {
        // Use a temp dir to avoid polluting the real config
        let tmp = std::env::temp_dir().join("claw-test-cred-store");
        let _ = std::fs::remove_dir_all(&tmp);
        std::env::set_var("CLAW_CONFIG_HOME", tmp.to_str().unwrap());

        let mut store = CredentialStore::default();
        store.set("deepseek".into(), sample_credential("deepseek"));
        store.save().unwrap();

        let loaded = CredentialStore::load();
        assert!(loaded.get("deepseek").is_some());
        assert_eq!(loaded.get("deepseek").unwrap().cookies.len(), 2);

        // Cleanup
        let _ = std::fs::remove_dir_all(&tmp);
        std::env::remove_var("CLAW_CONFIG_HOME");
    }
}
