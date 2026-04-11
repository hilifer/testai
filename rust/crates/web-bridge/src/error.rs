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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn error_display_http() {
        let err = WebBridgeError::Http("timeout".into());
        assert_eq!(err.to_string(), "HTTP error: timeout");
    }

    #[test]
    fn error_display_provider() {
        let err = WebBridgeError::ProviderError {
            provider: "deepseek".into(),
            status: 429,
            message: "rate limited".into(),
        };
        assert!(err.to_string().contains("deepseek"));
        assert!(err.to_string().contains("429"));
        assert!(err.to_string().contains("rate limited"));
    }

    #[test]
    fn error_display_no_credentials() {
        let err = WebBridgeError::NoCredentials("chatgpt".into());
        assert!(err.to_string().contains("chatgpt"));
        assert!(err.to_string().contains("web-login"));
    }

    #[test]
    fn error_display_unknown_provider() {
        let err = WebBridgeError::UnknownProvider("foo".into());
        assert!(err.to_string().contains("foo"));
        assert!(err.to_string().contains("not found"));
    }

    #[test]
    fn error_from_io() {
        let io_err = std::io::Error::new(std::io::ErrorKind::NotFound, "missing");
        let err: WebBridgeError = io_err.into();
        assert!(err.to_string().contains("missing"));
    }

    #[test]
    fn error_from_json() {
        let json_err = serde_json::from_str::<serde_json::Value>("invalid").unwrap_err();
        let err: WebBridgeError = json_err.into();
        assert!(err.to_string().contains("JSON"));
    }
}
