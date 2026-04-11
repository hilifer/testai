use serde_json::{json, Value};

use crate::credential_store::{Cookie, WebCredential};
use crate::error::WebBridgeError;

use super::{ChatRequest, StreamDelta, WebModel, WebProvider};

const BASE_URL: &str = "https://gemini.google.com";
const CHAT_API: &str = "https://gemini.google.com/api/generate";

pub struct GeminiProvider;

impl GeminiProvider {
    pub fn new() -> Self {
        Self
    }
}

#[async_trait::async_trait]
impl WebProvider for GeminiProvider {
    fn name(&self) -> &str {
        "gemini"
    }

    fn display_name(&self) -> &str {
        "Google Gemini"
    }

    fn login_url(&self) -> &str {
        BASE_URL
    }

    fn credential_domains(&self) -> &[&str] {
        &["gemini.google.com"]
    }

    fn models(&self) -> Vec<WebModel> {
        vec![
            WebModel {
                id: "gemini-pro".into(),
                name: "Gemini Pro".into(),
                context_window: 128_000,
                max_output_tokens: 8_192,
            },
            WebModel {
                id: "gemini-ultra".into(),
                name: "Gemini Ultra".into(),
                context_window: 128_000,
                max_output_tokens: 8_192,
            },
        ]
    }

    async fn chat_stream(
        &self,
        credential: &WebCredential,
        request: &ChatRequest,
    ) -> Result<
        Box<dyn tokio_stream::Stream<Item = Result<StreamDelta, WebBridgeError>> + Send + Unpin>,
        WebBridgeError,
    > {
        let client = reqwest::Client::builder()
            .default_headers({
                let mut headers = reqwest::header::HeaderMap::new();
                headers.insert("Content-Type", "application/json".parse().unwrap());
                headers.insert(
                    "Cookie",
                    Cookie::to_header_value(&credential.cookies)
                        .parse()
                        .unwrap(),
                );
                if let Some(ref ua) = credential.user_agent {
                    headers.insert("User-Agent", ua.parse().unwrap());
                }
                headers.insert("Origin", BASE_URL.parse().unwrap());
                headers.insert("Referer", format!("{BASE_URL}/").parse().unwrap());
                headers
            })
            .build()
            .map_err(|e| WebBridgeError::Http(e.to_string()))?;

        // Gemini web uses a different request format
        let last_message = request
            .messages
            .last()
            .map(|m| m.content.clone())
            .unwrap_or_default();

        let body = json!({
            "prompt": last_message,
            "model": request.model,
        });

        let response = client
            .post(CHAT_API)
            .json(&body)
            .send()
            .await
            .map_err(|e| WebBridgeError::Http(e.to_string()))?;

        if !response.status().is_success() {
            let status = response.status();
            let text = response.text().await.unwrap_or_default();
            return Err(WebBridgeError::ProviderError {
                provider: "gemini".into(),
                status: status.as_u16(),
                message: text,
            });
        }

        // Gemini returns a streaming response; parse it
        let stream = GeminiSseStream::new(response.bytes_stream());
        Ok(Box::new(stream))
    }
}

struct GeminiSseStream {
    inner: Box<dyn tokio_stream::Stream<Item = Result<bytes::Bytes, reqwest::Error>> + Send + Unpin>,
    buffer: String,
    done: bool,
}

impl GeminiSseStream {
    fn new(
        inner: impl tokio_stream::Stream<Item = Result<bytes::Bytes, reqwest::Error>>
            + Send
            + Unpin
            + 'static,
    ) -> Self {
        Self {
            inner: Box::new(inner),
            buffer: String::new(),
            done: false,
        }
    }
}

impl tokio_stream::Stream for GeminiSseStream {
    type Item = Result<StreamDelta, WebBridgeError>;

    fn poll_next(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<Option<Self::Item>> {
        use std::task::Poll;

        if self.done {
            return Poll::Ready(None);
        }

        loop {
            if let Some(newline_pos) = self.buffer.find('\n') {
                let line = self.buffer[..newline_pos].trim().to_string();
                self.buffer = self.buffer[newline_pos + 1..].to_string();
                if line.is_empty() {
                    continue;
                }
                if let Some(data) = line.strip_prefix("data: ") {
                    if data.trim() == "[DONE]" {
                        self.done = true;
                        return Poll::Ready(Some(Ok(StreamDelta {
                            content: None,
                            role: None,
                            finish_reason: Some("stop".into()),
                        })));
                    }
                    if let Ok(parsed) = serde_json::from_str::<Value>(data) {
                        let content = parsed
                            .get("candidates")
                            .and_then(Value::as_array)
                            .and_then(|a| a.first())
                            .and_then(|c| c.get("content"))
                            .and_then(|c| c.get("parts"))
                            .and_then(Value::as_array)
                            .and_then(|p| p.first())
                            .and_then(|p| p.get("text"))
                            .and_then(Value::as_str)
                            .map(String::from);

                        return Poll::Ready(Some(Ok(StreamDelta {
                            content,
                            role: Some("assistant".into()),
                            finish_reason: None,
                        })));
                    }
                }
                continue;
            }

            let inner = &mut self.inner;
            match std::pin::Pin::new(inner).poll_next(cx) {
                Poll::Ready(Some(Ok(bytes))) => {
                    self.buffer.push_str(&String::from_utf8_lossy(&bytes));
                }
                Poll::Ready(Some(Err(e))) => {
                    return Poll::Ready(Some(Err(WebBridgeError::Http(e.to_string()))));
                }
                Poll::Ready(None) => return Poll::Ready(None),
                Poll::Pending => return Poll::Pending,
            }
        }
    }
}
