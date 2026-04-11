use serde_json::{json, Value};

use crate::credential_store::{Cookie, WebCredential};
use crate::error::WebBridgeError;

use super::{ChatRequest, StreamDelta, WebModel, WebProvider};

const BASE_URL: &str = "https://chatgpt.com";
const CHAT_API: &str = "https://chatgpt.com/backend-api/conversation";

pub struct ChatGptProvider;

impl ChatGptProvider {
    pub fn new() -> Self {
        Self
    }

    fn build_request_body(request: &ChatRequest) -> Value {
        let messages: Vec<Value> = request
            .messages
            .iter()
            .map(|m| {
                json!({
                    "author": { "role": m.role },
                    "content": { "content_type": "text", "parts": [m.content] },
                })
            })
            .collect();

        json!({
            "action": "next",
            "messages": messages,
            "model": map_model_id(&request.model),
            "parent_message_id": uuid::Uuid::new_v4().to_string(),
        })
    }
}

fn map_model_id(model: &str) -> &str {
    match model {
        "gpt-4" | "gpt-4-web" => "gpt-4",
        "gpt-4o" | "gpt-4o-web" => "gpt-4o",
        "gpt-4o-mini" => "gpt-4o-mini",
        "o1" | "o1-web" => "o1",
        "o1-mini" => "o1-mini",
        "o3" | "o3-web" => "o3",
        "o3-mini" => "o3-mini",
        _ => "gpt-4o",
    }
}

#[async_trait::async_trait]
impl WebProvider for ChatGptProvider {
    fn name(&self) -> &str {
        "chatgpt"
    }

    fn display_name(&self) -> &str {
        "ChatGPT"
    }

    fn login_url(&self) -> &str {
        BASE_URL
    }

    fn credential_domains(&self) -> &[&str] {
        &["chatgpt.com", "chat.openai.com"]
    }

    fn models(&self) -> Vec<WebModel> {
        vec![
            WebModel {
                id: "gpt-4o".into(),
                name: "GPT-4o".into(),
                context_window: 128_000,
                max_output_tokens: 16_384,
            },
            WebModel {
                id: "gpt-4o-mini".into(),
                name: "GPT-4o Mini".into(),
                context_window: 128_000,
                max_output_tokens: 16_384,
            },
            WebModel {
                id: "o3".into(),
                name: "o3".into(),
                context_window: 200_000,
                max_output_tokens: 100_000,
            },
            WebModel {
                id: "o3-mini".into(),
                name: "o3 Mini".into(),
                context_window: 200_000,
                max_output_tokens: 100_000,
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
                headers.insert("Referer", format!("{BASE_URL}/").parse().unwrap());
                headers
            })
            .build()
            .map_err(|e| WebBridgeError::Http(e.to_string()))?;

        let body = Self::build_request_body(request);

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
                provider: "chatgpt".into(),
                status: status.as_u16(),
                message: text,
            });
        }

        // ChatGPT uses a similar SSE format, reuse the decoder
        let stream = ChatGptSseStream::new(response.bytes_stream());
        Ok(Box::new(stream))
    }
}

/// ChatGPT-specific SSE decoder.
/// ChatGPT's SSE format wraps content differently than standard OpenAI API.
struct ChatGptSseStream {
    inner: Box<dyn tokio_stream::Stream<Item = Result<bytes::Bytes, reqwest::Error>> + Send + Unpin>,
    buffer: String,
    done: bool,
}

impl ChatGptSseStream {
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

    fn parse_line(&mut self, line: &str) -> Option<Result<StreamDelta, WebBridgeError>> {
        let data = line.strip_prefix("data: ")?;

        if data.trim() == "[DONE]" {
            self.done = true;
            return Some(Ok(StreamDelta {
                content: None,
                role: None,
                finish_reason: Some("stop".into()),
            }));
        }

        let parsed: Value = serde_json::from_str(data).ok()?;

        // ChatGPT web format: message.content.parts[0]
        let message = parsed.get("message")?;
        let content = message
            .get("content")
            .and_then(|c| c.get("parts"))
            .and_then(Value::as_array)
            .and_then(|parts| parts.first())
            .and_then(Value::as_str)
            .map(String::from);

        let role = message
            .get("author")
            .and_then(|a| a.get("role"))
            .and_then(Value::as_str)
            .map(String::from);

        let finish = parsed
            .get("finish_details")
            .and_then(|f| f.get("type"))
            .and_then(Value::as_str)
            .map(String::from);

        Some(Ok(StreamDelta {
            content,
            role,
            finish_reason: finish,
        }))
    }
}

impl tokio_stream::Stream for ChatGptSseStream {
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
                if let Some(result) = self.parse_line(&line) {
                    return Poll::Ready(Some(result));
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
