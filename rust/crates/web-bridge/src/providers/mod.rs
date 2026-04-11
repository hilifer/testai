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
