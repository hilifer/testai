//! Web provider — routes requests through the built-in web-bridge gateway.
//!
//! When a user specifies a web model (e.g. `deepseek/deepseek-chat`), this
//! provider auto-starts the web-bridge gateway and forwards requests to it
//! using the OpenAI-compatible wire format.

use crate::error::ApiError;
use crate::providers::openai_compat::{OpenAiCompatClient, OpenAiCompatConfig};

/// The OpenAI-compatible config that points to the local web-bridge gateway.
fn web_bridge_config() -> OpenAiCompatConfig {
    OpenAiCompatConfig {
        provider_name: "WebBridge",
        api_key_env: "WEB_BRIDGE_TOKEN",
        base_url_env: "WEB_BRIDGE_URL",
        default_base_url: "http://127.0.0.1:18899/v1",
    }
}

/// Create a client that connects to the web-bridge gateway.
/// If no WEB_BRIDGE_TOKEN is set, uses a dummy token since the local
/// gateway doesn't require authentication by default.
pub fn create_web_client() -> Result<OpenAiCompatClient, ApiError> {
    // Set a dummy API key if none is set — the local gateway doesn't require it
    if std::env::var_os("WEB_BRIDGE_TOKEN").is_none() {
        std::env::set_var("WEB_BRIDGE_TOKEN", "local");
    }
    OpenAiCompatClient::from_env(web_bridge_config())
}
