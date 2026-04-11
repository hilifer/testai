use serde_json::{json, Value};

use crate::credential_store::{Cookie, WebCredential};
use crate::error::WebBridgeError;

use super::{ChatRequest, StreamDelta, WebModel, WebProvider};

const BASE_URL: &str = "https://tongyi.aliyun.com";
const CHAT_API: &str = "https://tongyi.aliyun.com/qianwen/api/chat";

pub struct QwenProvider;

impl QwenProvider {
    pub fn new() -> Self {
        Self
    }
}

#[async_trait::async_trait]
impl WebProvider for QwenProvider {
    fn name(&self) -> &str {
        "qwen"
    }

    fn display_name(&self) -> &str {
        "Qwen (通义千问)"
    }

    fn login_url(&self) -> &str {
        BASE_URL
    }

    fn credential_domains(&self) -> &[&str] {
        &["tongyi.aliyun.com", "qianwen.aliyun.com"]
    }

    fn models(&self) -> Vec<WebModel> {
        vec![
            WebModel {
                id: "qwen-max".into(),
                name: "Qwen Max".into(),
                context_window: 128_000,
                max_output_tokens: 8_192,
            },
            WebModel {
                id: "qwen-plus".into(),
                name: "Qwen Plus".into(),
                context_window: 128_000,
                max_output_tokens: 8_192,
            },
            WebModel {
                id: "qwen-turbo".into(),
                name: "Qwen Turbo".into(),
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
                if let Some(ref token) = credential.bearer_token {
                    headers.insert(
                        "Authorization",
                        format!("Bearer {token}").parse().unwrap(),
                    );
                }
                if let Some(ref ua) = credential.user_agent {
                    headers.insert("User-Agent", ua.parse().unwrap());
                }
                headers.insert("Accept", "text/event-stream".parse().unwrap());
                headers.insert("Origin", BASE_URL.parse().unwrap());
                headers
            })
            .build()
            .map_err(|e| WebBridgeError::Http(e.to_string()))?;

        let last_message = request
            .messages
            .last()
            .map(|m| m.content.clone())
            .unwrap_or_default();

        let body = json!({
            "model": request.model,
            "input": { "prompt": last_message },
            "parameters": {
                "incremental_output": true,
            },
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
                provider: "qwen".into(),
                status: status.as_u16(),
                message: text,
            });
        }

        // Qwen CN sends accumulated content — need delta tracking
        let stream = QwenSseStream::new(response.bytes_stream());
        Ok(Box::new(stream))
    }
}

struct QwenSseStream {
    inner: Box<dyn tokio_stream::Stream<Item = Result<bytes::Bytes, reqwest::Error>> + Send + Unpin>,
    buffer: String,
    accumulated: String,
    done: bool,
}

impl QwenSseStream {
    fn new(
        inner: impl tokio_stream::Stream<Item = Result<bytes::Bytes, reqwest::Error>>
            + Send
            + Unpin
            + 'static,
    ) -> Self {
        Self {
            inner: Box::new(inner),
            buffer: String::new(),
            accumulated: String::new(),
            done: false,
        }
    }
}

impl tokio_stream::Stream for QwenSseStream {
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
                if let Some(data) = line.strip_prefix("data:") {
                    let data = data.trim();
                    if data == "[DONE]" {
                        self.done = true;
                        return Poll::Ready(Some(Ok(StreamDelta {
                            content: None,
                            role: None,
                            finish_reason: Some("stop".into()),
                        })));
                    }
                    if let Ok(parsed) = serde_json::from_str::<Value>(data) {
                        // Qwen sends accumulated content
                        let content = parsed
                            .get("output")
                            .and_then(|o| o.get("text"))
                            .and_then(Value::as_str)
                            .unwrap_or("");

                        let delta = if content.len() > self.accumulated.len()
                            && content.starts_with(&self.accumulated)
                        {
                            let new_part = content[self.accumulated.len()..].to_string();
                            self.accumulated = content.to_string();
                            new_part
                        } else if !content.is_empty() {
                            self.accumulated.push_str(content);
                            content.to_string()
                        } else {
                            continue;
                        };

                        return Poll::Ready(Some(Ok(StreamDelta {
                            content: Some(delta),
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
