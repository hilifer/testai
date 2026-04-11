pub mod browser;
pub mod credential_store;
pub mod error;
pub mod gateway;
pub mod providers;

pub use credential_store::CredentialStore;
pub use error::WebBridgeError;
pub use gateway::start_gateway;
pub use providers::{ProviderRegistry, WebProvider};

/// Default port for the built-in web-bridge gateway.
pub const DEFAULT_GATEWAY_PORT: u16 = 18899;

/// Check if the web-bridge gateway is needed based on the model name.
/// Models prefixed with "web/" or ending with "-web" trigger the gateway.
pub fn is_web_model(model: &str) -> bool {
    model.starts_with("web/")
        || model.starts_with("deepseek/")
        || model.starts_with("chatgpt/")
        || model.starts_with("gemini/")
        || model.starts_with("qwen-web/")
        || model.starts_with("kimi/")
        || model.ends_with("-web")
}

/// Auto-start the gateway if needed, and return the OpenAI-compatible base URL.
/// This is called from the main CLI when a web model is detected.
#[allow(clippy::missing_errors_doc)]
pub async fn ensure_gateway_running() -> Result<String, WebBridgeError> {
    // Check if gateway is already running
    let health_url = format!("http://127.0.0.1:{DEFAULT_GATEWAY_PORT}/health");
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(2))
        .build()
        .map_err(|e| WebBridgeError::Http(e.to_string()))?;

    if let Ok(resp) = client.get(&health_url).send().await {
        if resp.status().is_success() {
            return Ok(format!("http://127.0.0.1:{DEFAULT_GATEWAY_PORT}/v1"));
        }
    }

    // Start the gateway
    let addr = start_gateway(DEFAULT_GATEWAY_PORT).await?;
    Ok(format!("http://{addr}/v1"))
}

#[cfg(test)]
mod tests {
    use super::*;

    // --- is_web_model tests ---

    #[test]
    fn web_prefix_detected() {
        assert!(is_web_model("web/deepseek-chat"));
        assert!(is_web_model("web/gpt-4o"));
        assert!(is_web_model("web/anything"));
    }

    #[test]
    fn provider_prefix_detected() {
        assert!(is_web_model("deepseek/deepseek-chat"));
        assert!(is_web_model("chatgpt/gpt-4o"));
        assert!(is_web_model("gemini/gemini-pro"));
        assert!(is_web_model("kimi/kimi-chat"));
        assert!(is_web_model("qwen-web/qwen-max"));
    }

    #[test]
    fn web_suffix_detected() {
        assert!(is_web_model("deepseek-web"));
        assert!(is_web_model("chatgpt-web"));
        assert!(is_web_model("anything-web"));
    }

    #[test]
    fn non_web_models_not_detected() {
        assert!(!is_web_model("claude-sonnet-4-6"));
        assert!(!is_web_model("gpt-4"));
        assert!(!is_web_model("grok-3"));
        assert!(!is_web_model("qwen-plus")); // qwen- without "web" suffix
        assert!(!is_web_model(""));
        assert!(!is_web_model("openai/gpt-4"));
    }

    #[test]
    fn default_gateway_port() {
        assert_eq!(DEFAULT_GATEWAY_PORT, 18899);
    }
}
