use thiserror::Error;

#[derive(Debug, Error)]
pub enum WebBridgeError {
    #[error("HTTP error: {0}")]
    Http(String),

    #[error("Provider '{provider}' returned {status}: {message}")]
    ProviderError {
        provider: String,
        status: u16,
        message: String,
    },

    #[error("No credentials found for provider '{0}'. Run `claw web-login {0}` first.")]
    NoCredentials(String),

    #[error("Provider '{0}' not found. Available: deepseek, chatgpt, gemini, qwen, kimi")]
    UnknownProvider(String),

    #[error("Model '{0}' not found in any web provider")]
    UnknownModel(String),

    #[error("Browser error: {0}")]
    Browser(String),

    #[error("Gateway error: {0}")]
    Gateway(String),

    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),
}
