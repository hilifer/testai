pub mod deepseek;
pub mod chatgpt;
pub mod gemini;
pub mod qwen;
pub mod kimi;

use serde::{Deserialize, Serialize};

use crate::credential_store::WebCredential;
use crate::error::WebBridgeError;

/// A chat message in the standard format.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatMessage {
    pub role: String,
    pub content: String,
}

/// A chat completion request in OpenAI-compatible format.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatRequest {
    pub model: String,
    pub messages: Vec<ChatMessage>,
    #[serde(default)]
    pub stream: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub temperature: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub max_tokens: Option<u32>,
}

/// A streaming delta chunk.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StreamDelta {
    pub content: Option<String>,
    pub role: Option<String>,
    pub finish_reason: Option<String>,
}

/// Trait that all web providers must implement.
#[async_trait::async_trait]
pub trait WebProvider: Send + Sync {
    /// Provider identifier (e.g. "deepseek", "chatgpt").
    fn name(&self) -> &str;

    /// Display name for the user.
    fn display_name(&self) -> &str;

    /// The web login URL the user needs to visit.
    fn login_url(&self) -> &str;

    /// Domains to intercept credentials from.
    fn credential_domains(&self) -> &[&str];

    /// Available model IDs for this provider.
    fn models(&self) -> Vec<WebModel>;

    /// Send a chat request and return a streaming response.
    /// Each item in the stream is an SSE line (e.g., `data: {...}`).
    async fn chat_stream(
        &self,
        credential: &WebCredential,
        request: &ChatRequest,
    ) -> Result<Box<dyn tokio_stream::Stream<Item = Result<StreamDelta, WebBridgeError>> + Send + Unpin>, WebBridgeError>;
}

/// Metadata about a model available through a web provider.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WebModel {
    pub id: String,
    pub name: String,
    pub context_window: u32,
    pub max_output_tokens: u32,
}

/// Registry of all available web providers.
pub struct ProviderRegistry {
    providers: Vec<Box<dyn WebProvider>>,
}

impl ProviderRegistry {
    pub fn new() -> Self {
        let providers: Vec<Box<dyn WebProvider>> = vec![
            Box::new(deepseek::DeepSeekProvider::new()),
            Box::new(chatgpt::ChatGptProvider::new()),
            Box::new(gemini::GeminiProvider::new()),
            Box::new(qwen::QwenProvider::new()),
            Box::new(kimi::KimiProvider::new()),
        ];
        Self { providers }
    }

    /// Find a provider by name.
    pub fn get(&self, name: &str) -> Option<&dyn WebProvider> {
        self.providers
            .iter()
            .find(|p| p.name() == name)
            .map(|p| p.as_ref())
    }

    /// Find a provider by model ID (checks all providers).
    pub fn find_by_model(&self, model: &str) -> Option<(&dyn WebProvider, &str)> {
        // model format: "web/deepseek-chat" or "deepseek-web/deepseek-chat"
        let stripped = model
            .strip_prefix("web/")
            .or_else(|| {
                // Try "provider-web/model" format
                model.split_once('/').and_then(|(prefix, rest)| {
                    let provider_name = prefix.strip_suffix("-web")?;
                    self.get(provider_name)?;
                    Some(rest)
                })
            });

        if let Some(model_id) = stripped {
            // Search all providers for this model
            for provider in &self.providers {
                if provider.models().iter().any(|m| m.id == model_id) {
                    return Some((provider.as_ref(), model_id));
                }
            }
        }

        // Also try direct provider name match: "deepseek/deepseek-chat"
        if let Some((provider_name, model_id)) = model.split_once('/') {
            if let Some(provider) = self.get(provider_name) {
                return Some((provider, model_id));
            }
        }

        None
    }

    /// List all providers.
    pub fn list(&self) -> &[Box<dyn WebProvider>] {
        &self.providers
    }
}

impl Default for ProviderRegistry {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn registry_has_all_providers() {
        let reg = ProviderRegistry::new();
        let providers = reg.list();
        assert_eq!(providers.len(), 5);

        assert!(reg.get("deepseek").is_some());
        assert!(reg.get("chatgpt").is_some());
        assert!(reg.get("gemini").is_some());
        assert!(reg.get("qwen").is_some());
        assert!(reg.get("kimi").is_some());
    }

    #[test]
    fn registry_unknown_provider_returns_none() {
        let reg = ProviderRegistry::new();
        assert!(reg.get("nonexistent").is_none());
        assert!(reg.get("").is_none());
    }

    #[test]
    fn provider_names_are_unique() {
        let reg = ProviderRegistry::new();
        let mut names: Vec<&str> = reg.list().iter().map(|p| p.name()).collect();
        let original_len = names.len();
        names.sort();
        names.dedup();
        assert_eq!(names.len(), original_len, "provider names must be unique");
    }

    #[test]
    fn each_provider_has_models() {
        let reg = ProviderRegistry::new();
        for provider in reg.list() {
            let models = provider.models();
            assert!(
                !models.is_empty(),
                "provider '{}' should have at least one model",
                provider.name()
            );
            for model in &models {
                assert!(!model.id.is_empty(), "model ID must not be empty");
                assert!(!model.name.is_empty(), "model name must not be empty");
                assert!(model.context_window > 0, "context_window must be > 0");
                assert!(model.max_output_tokens > 0, "max_output_tokens must be > 0");
            }
        }
    }

    #[test]
    fn each_provider_has_login_url() {
        let reg = ProviderRegistry::new();
        for provider in reg.list() {
            let url = provider.login_url();
            assert!(
                url.starts_with("https://"),
                "provider '{}' login URL should be https, got: {url}",
                provider.name()
            );
        }
    }

    #[test]
    fn each_provider_has_credential_domains() {
        let reg = ProviderRegistry::new();
        for provider in reg.list() {
            let domains = provider.credential_domains();
            assert!(
                !domains.is_empty(),
                "provider '{}' should have at least one credential domain",
                provider.name()
            );
            for domain in domains {
                assert!(
                    !domain.is_empty(),
                    "credential domain must not be empty for provider '{}'",
                    provider.name()
                );
            }
        }
    }

    #[test]
    fn find_by_model_direct_format() {
        let reg = ProviderRegistry::new();

        // "deepseek/deepseek-chat" format
        let result = reg.find_by_model("deepseek/deepseek-chat");
        assert!(result.is_some(), "should find deepseek/deepseek-chat");
        let (provider, model_id) = result.unwrap();
        assert_eq!(provider.name(), "deepseek");
        assert_eq!(model_id, "deepseek-chat");
    }

    #[test]
    fn find_by_model_chatgpt() {
        let reg = ProviderRegistry::new();
        let result = reg.find_by_model("chatgpt/gpt-4o");
        assert!(result.is_some());
        let (provider, model_id) = result.unwrap();
        assert_eq!(provider.name(), "chatgpt");
        assert_eq!(model_id, "gpt-4o");
    }

    #[test]
    fn find_by_model_gemini() {
        let reg = ProviderRegistry::new();
        let result = reg.find_by_model("gemini/gemini-pro");
        assert!(result.is_some());
        assert_eq!(result.unwrap().0.name(), "gemini");
    }

    #[test]
    fn find_by_model_qwen() {
        let reg = ProviderRegistry::new();
        let result = reg.find_by_model("qwen/qwen-max");
        assert!(result.is_some());
        assert_eq!(result.unwrap().0.name(), "qwen");
    }

    #[test]
    fn find_by_model_kimi() {
        let reg = ProviderRegistry::new();
        let result = reg.find_by_model("kimi/kimi-chat");
        assert!(result.is_some());
        assert_eq!(result.unwrap().0.name(), "kimi");
    }

    #[test]
    fn find_by_model_web_prefix() {
        let reg = ProviderRegistry::new();
        // "web/deepseek-chat" should find deepseek provider
        let result = reg.find_by_model("web/deepseek-chat");
        assert!(result.is_some(), "should find web/deepseek-chat");
        assert_eq!(result.unwrap().0.name(), "deepseek");
    }

    #[test]
    fn find_by_model_unknown_returns_none() {
        let reg = ProviderRegistry::new();
        assert!(reg.find_by_model("unknown/model").is_none());
        assert!(reg.find_by_model("").is_none());
    }

    #[test]
    fn find_by_model_provider_web_suffix_format() {
        let reg = ProviderRegistry::new();
        // "deepseek-web/deepseek-chat" format
        let result = reg.find_by_model("deepseek-web/deepseek-chat");
        assert!(result.is_some(), "should find deepseek-web/deepseek-chat");
        assert_eq!(result.unwrap().0.name(), "deepseek");
    }

    // --- ChatMessage / ChatRequest serialization ---

    #[test]
    fn chat_message_serialize() {
        let msg = ChatMessage {
            role: "user".into(),
            content: "Hello".into(),
        };
        let json = serde_json::to_value(&msg).unwrap();
        assert_eq!(json["role"], "user");
        assert_eq!(json["content"], "Hello");
    }

    #[test]
    fn chat_request_serialize_minimal() {
        let req = ChatRequest {
            model: "deepseek-chat".into(),
            messages: vec![ChatMessage {
                role: "user".into(),
                content: "Hi".into(),
            }],
            stream: false,
            temperature: None,
            max_tokens: None,
        };
        let json = serde_json::to_value(&req).unwrap();
        assert_eq!(json["model"], "deepseek-chat");
        assert_eq!(json["stream"], false);
        // Optional fields should be absent
        assert!(json.get("temperature").is_none());
        assert!(json.get("max_tokens").is_none());
    }

    #[test]
    fn chat_request_serialize_full() {
        let req = ChatRequest {
            model: "gpt-4o".into(),
            messages: vec![],
            stream: true,
            temperature: Some(0.7),
            max_tokens: Some(4096),
        };
        let json = serde_json::to_value(&req).unwrap();
        assert_eq!(json["stream"], true);
        assert_eq!(json["temperature"], 0.7);
        assert_eq!(json["max_tokens"], 4096);
    }

    #[test]
    fn stream_delta_fields() {
        let delta = StreamDelta {
            content: Some("Hello".into()),
            role: Some("assistant".into()),
            finish_reason: None,
        };
        assert_eq!(delta.content.as_deref(), Some("Hello"));
        assert_eq!(delta.role.as_deref(), Some("assistant"));
        assert!(delta.finish_reason.is_none());
    }
}
