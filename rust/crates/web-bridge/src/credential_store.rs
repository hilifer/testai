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
