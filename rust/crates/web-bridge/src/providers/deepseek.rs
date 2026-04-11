use serde_json::{json, Value};

use crate::credential_store::{Cookie, WebCredential};
use crate::error::WebBridgeError;

use super::{ChatRequest, StreamDelta, WebModel, WebProvider};

const BASE_URL: &str = "https://chat.deepseek.com";
const CHAT_API: &str = "https://chat.deepseek.com/api/v0/chat/completions";

pub struct DeepSeekProvider;

impl DeepSeekProvider {
    pub fn new() -> Self {
        Self
    }

    /// Convert our standard ChatRequest to DeepSeek's web API format.
    fn build_request_body(request: &ChatRequest) -> Value {
        let messages: Vec<Value> = request
            .messages
            .iter()
            .map(|m| {
                json!({
                    "role": m.role,
                    "content": m.content,
                })
            })
            .collect();

        json!({
            "model": map_model_id(&request.model),
            "messages": messages,
            "stream": true,
            "temperature": request.temperature.unwrap_or(0.0),
        })
    }
}

/// Map our model IDs to DeepSeek's internal model names.
fn map_model_id(model: &str) -> &str {
    match model {
        "deepseek-chat" | "deepseek-v3" => "deepseek_chat",
        "deepseek-reasoner" | "deepseek-r1" => "deepseek_reasoner",
        "deepseek-coder" => "deepseek_code",
        _ => "deepseek_chat",
    }
}

#[async_trait::async_trait]
impl WebProvider for DeepSeekProvider {
    fn name(&self) -> &str {
        "deepseek"
    }

    fn display_name(&self) -> &str {
        "DeepSeek"
    }

    fn login_url(&self) -> &str {
        BASE_URL
    }

    fn credential_domains(&self) -> &[&str] {
        &["chat.deepseek.com"]
    }

    fn models(&self) -> Vec<WebModel> {
        vec![
            WebModel {
                id: "deepseek-chat".into(),
                name: "DeepSeek V3".into(),
                context_window: 64_000,
                max_output_tokens: 8_192,
            },
            WebModel {
                id: "deepseek-reasoner".into(),
                name: "DeepSeek R1".into(),
                context_window: 64_000,
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
                    Cookie::to_header_value(&credential.cookies).parse().unwrap(),
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
                provider: "deepseek".into(),
                status: status.as_u16(),
                message: text,
            });
        }

        let byte_stream = response.bytes_stream();

        // Track accumulated content for providers that send full content each time
        let stream = SseDecoderStream::new(byte_stream);

        Ok(Box::new(stream))
    }
}

/// Decodes SSE byte stream into `StreamDelta` items.
/// Handles DeepSeek's accumulated-content format by emitting only new deltas.
pub struct SseDecoderStream {
    inner: Box<dyn tokio_stream::Stream<Item = Result<bytes::Bytes, reqwest::Error>> + Send + Unpin>,
    buffer: String,
    accumulated_content: String,
    done: bool,
}

impl SseDecoderStream {
    fn new(
        inner: impl tokio_stream::Stream<Item = Result<bytes::Bytes, reqwest::Error>>
            + Send
            + Unpin
            + 'static,
    ) -> Self {
        Self {
            inner: Box::new(inner),
            buffer: String::new(),
            accumulated_content: String::new(),
            done: false,
        }
    }

    fn parse_sse_line(&mut self, line: &str) -> Option<Result<StreamDelta, WebBridgeError>> {
        let data = line.strip_prefix("data: ")?;

        if data.trim() == "[DONE]" {
            self.done = true;
            return Some(Ok(StreamDelta {
                content: None,
                role: None,
                finish_reason: Some("stop".into()),
            }));
        }

        let parsed: Value = match serde_json::from_str(data) {
            Ok(v) => v,
            Err(_) => return None,
        };

        let choice = parsed.get("choices")?.as_array()?.first()?;
        let delta = choice.get("delta")?;
        let finish_reason = choice
            .get("finish_reason")
            .and_then(Value::as_str)
            .map(String::from);

        let content = delta.get("content").and_then(Value::as_str);

        // Handle accumulated content: DeepSeek may send full content each time
        let delta_content = if let Some(content) = content {
            if content.len() > self.accumulated_content.len()
                && content.starts_with(&self.accumulated_content)
            {
                // Accumulated mode: extract only the new part
                let new_part = content[self.accumulated_content.len()..].to_string();
                self.accumulated_content = content.to_string();
                Some(new_part)
            } else {
                // Incremental mode: use as-is
                self.accumulated_content.push_str(content);
                Some(content.to_string())
            }
        } else {
            None
        };

        let role = delta
            .get("role")
            .and_then(Value::as_str)
            .map(String::from);

        Some(Ok(StreamDelta {
            content: delta_content,
            role,
            finish_reason,
        }))
    }
}

impl tokio_stream::Stream for SseDecoderStream {
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
            // First, try to parse a complete line from the buffer
            if let Some(newline_pos) = self.buffer.find('\n') {
                let line = self.buffer[..newline_pos].trim().to_string();
                self.buffer = self.buffer[newline_pos + 1..].to_string();

                if line.is_empty() {
                    continue;
                }

                if let Some(result) = self.parse_sse_line(&line) {
                    return Poll::Ready(Some(result));
                }
                continue;
            }

            // Need more data from the inner stream
            let inner = &mut self.inner;
            match std::pin::Pin::new(inner).poll_next(cx) {
                Poll::Ready(Some(Ok(bytes))) => {
                    let text = String::from_utf8_lossy(&bytes);
                    self.buffer.push_str(&text);
                }
                Poll::Ready(Some(Err(e))) => {
                    return Poll::Ready(Some(Err(WebBridgeError::Http(e.to_string()))));
                }
                Poll::Ready(None) => {
                    if self.buffer.is_empty() {
                        return Poll::Ready(None);
                    }
                    // Process remaining buffer
                    let remaining = std::mem::take(&mut self.buffer);
                    for line in remaining.lines() {
                        let line = line.trim();
                        if line.is_empty() {
                            continue;
                        }
                        if let Some(result) = self.parse_sse_line(line) {
                            return Poll::Ready(Some(result));
                        }
                    }
                    return Poll::Ready(None);
                }
                Poll::Pending => return Poll::Pending,
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio_stream::StreamExt;

    // --- SSE line parsing tests (unit tests for parse_sse_line) ---

    fn make_decoder() -> SseDecoderStream {
        // Create a decoder with an empty stream (we'll test parse_sse_line directly)
        let empty_stream = tokio_stream::empty::<Result<bytes::Bytes, reqwest::Error>>();
        SseDecoderStream::new(empty_stream)
    }

    #[test]
    fn parse_done_marker() {
        let mut decoder = make_decoder();
        let result = decoder.parse_sse_line("data: [DONE]");
        assert!(result.is_some());
        let delta = result.unwrap().unwrap();
        assert!(delta.content.is_none());
        assert_eq!(delta.finish_reason, Some("stop".into()));
        assert!(decoder.done);
    }

    #[test]
    fn parse_non_sse_line_returns_none() {
        let mut decoder = make_decoder();
        assert!(decoder.parse_sse_line("not an sse line").is_none());
        assert!(decoder.parse_sse_line("").is_none());
        assert!(decoder.parse_sse_line("event: message").is_none());
    }

    #[test]
    fn parse_invalid_json_returns_none() {
        let mut decoder = make_decoder();
        assert!(decoder.parse_sse_line("data: {invalid json}").is_none());
    }

    #[test]
    fn parse_incremental_delta() {
        let mut decoder = make_decoder();
        let line = r#"data: {"choices":[{"delta":{"content":"Hello"},"finish_reason":null}]}"#;
        let result = decoder.parse_sse_line(line);
        assert!(result.is_some());
        let delta = result.unwrap().unwrap();
        assert_eq!(delta.content, Some("Hello".into()));
        assert!(delta.finish_reason.is_none());
    }

    #[test]
    fn parse_incremental_sequence() {
        let mut decoder = make_decoder();

        let line1 = r#"data: {"choices":[{"delta":{"content":"Hi"},"finish_reason":null}]}"#;
        let d1 = decoder.parse_sse_line(line1).unwrap().unwrap();
        assert_eq!(d1.content, Some("Hi".into()));

        let line2 = r#"data: {"choices":[{"delta":{"content":" there"},"finish_reason":null}]}"#;
        let d2 = decoder.parse_sse_line(line2).unwrap().unwrap();
        assert_eq!(d2.content, Some(" there".into()));
    }

    #[test]
    fn parse_accumulated_content_extracts_delta() {
        let mut decoder = make_decoder();

        // Simulates accumulated mode: each chunk contains the full content so far
        let line1 = r#"data: {"choices":[{"delta":{"content":"Hello"},"finish_reason":null}]}"#;
        let d1 = decoder.parse_sse_line(line1).unwrap().unwrap();
        assert_eq!(d1.content, Some("Hello".into()));

        // Next chunk has "Hello world" (accumulated) — should emit only " world"
        let line2 =
            r#"data: {"choices":[{"delta":{"content":"Hello world"},"finish_reason":null}]}"#;
        let d2 = decoder.parse_sse_line(line2).unwrap().unwrap();
        assert_eq!(d2.content, Some(" world".into()));

        // Next: "Hello world!" — should emit only "!"
        let line3 =
            r#"data: {"choices":[{"delta":{"content":"Hello world!"},"finish_reason":null}]}"#;
        let d3 = decoder.parse_sse_line(line3).unwrap().unwrap();
        assert_eq!(d3.content, Some("!".into()));
    }

    #[test]
    fn parse_role_field() {
        let mut decoder = make_decoder();
        let line =
            r#"data: {"choices":[{"delta":{"role":"assistant","content":""},"finish_reason":null}]}"#;
        let d = decoder.parse_sse_line(line).unwrap().unwrap();
        assert_eq!(d.role, Some("assistant".into()));
    }

    #[test]
    fn parse_finish_reason() {
        let mut decoder = make_decoder();
        let line =
            r#"data: {"choices":[{"delta":{"content":""},"finish_reason":"stop"}]}"#;
        let d = decoder.parse_sse_line(line).unwrap().unwrap();
        assert_eq!(d.finish_reason, Some("stop".into()));
    }

    #[test]
    fn parse_missing_choices_returns_none() {
        let mut decoder = make_decoder();
        let line = r#"data: {"id":"123","model":"deepseek"}"#;
        assert!(decoder.parse_sse_line(line).is_none());
    }

    #[test]
    fn parse_empty_choices_returns_none() {
        let mut decoder = make_decoder();
        let line = r#"data: {"choices":[]}"#;
        assert!(decoder.parse_sse_line(line).is_none());
    }

    // --- Stream-level tests (async) ---

    #[tokio::test]
    async fn stream_from_bytes() {
        let data = "data: {\"choices\":[{\"delta\":{\"content\":\"Hi\"},\"finish_reason\":null}]}\n\ndata: [DONE]\n\n";
        let bytes_stream =
            tokio_stream::iter(vec![Ok::<_, reqwest::Error>(bytes::Bytes::from(data))]);

        let mut decoder = SseDecoderStream::new(bytes_stream);

        let first = decoder.next().await;
        assert!(first.is_some());
        assert_eq!(first.unwrap().unwrap().content, Some("Hi".into()));

        let second = decoder.next().await;
        assert!(second.is_some());
        assert_eq!(second.unwrap().unwrap().finish_reason, Some("stop".into()));

        // Stream should end
        assert!(decoder.next().await.is_none());
    }

    #[tokio::test]
    async fn stream_split_across_chunks() {
        // Data split across two byte chunks — the SSE line spans both
        let chunk1 = r#"data: {"choices":[{"delta":{"#;
        let chunk2 = r#""content":"split"},"finish_reason":null}]}
data: [DONE]
"#;
        let bytes_stream = tokio_stream::iter(vec![
            Ok::<_, reqwest::Error>(bytes::Bytes::from(chunk1)),
            Ok(bytes::Bytes::from(chunk2)),
        ]);

        let mut decoder = SseDecoderStream::new(bytes_stream);

        let first = decoder.next().await.unwrap().unwrap();
        assert_eq!(first.content, Some("split".into()));

        let second = decoder.next().await.unwrap().unwrap();
        assert_eq!(second.finish_reason, Some("stop".into()));
    }

    #[tokio::test]
    async fn stream_multiple_deltas() {
        let data = concat!(
            "data: {\"choices\":[{\"delta\":{\"content\":\"A\"},\"finish_reason\":null}]}\n\n",
            "data: {\"choices\":[{\"delta\":{\"content\":\"B\"},\"finish_reason\":null}]}\n\n",
            "data: {\"choices\":[{\"delta\":{\"content\":\"C\"},\"finish_reason\":null}]}\n\n",
            "data: [DONE]\n\n",
        );
        let bytes_stream =
            tokio_stream::iter(vec![Ok::<_, reqwest::Error>(bytes::Bytes::from(data))]);
        let mut decoder = SseDecoderStream::new(bytes_stream);

        let mut collected = String::new();
        while let Some(Ok(delta)) = decoder.next().await {
            if let Some(content) = delta.content {
                collected.push_str(&content);
            }
        }
        assert_eq!(collected, "ABC");
    }

    // --- Model mapping tests ---

    #[test]
    fn model_id_mapping() {
        assert_eq!(map_model_id("deepseek-chat"), "deepseek_chat");
        assert_eq!(map_model_id("deepseek-v3"), "deepseek_chat");
        assert_eq!(map_model_id("deepseek-reasoner"), "deepseek_reasoner");
        assert_eq!(map_model_id("deepseek-r1"), "deepseek_reasoner");
        assert_eq!(map_model_id("deepseek-coder"), "deepseek_code");
        assert_eq!(map_model_id("unknown-model"), "deepseek_chat");
    }

    // --- Provider metadata tests ---

    #[test]
    fn deepseek_provider_metadata() {
        let provider = DeepSeekProvider::new();
        assert_eq!(provider.name(), "deepseek");
        assert_eq!(provider.display_name(), "DeepSeek");
        assert_eq!(provider.login_url(), "https://chat.deepseek.com");
        assert!(provider.credential_domains().contains(&"chat.deepseek.com"));
        assert_eq!(provider.models().len(), 2);
    }

    #[test]
    fn deepseek_build_request_body() {
        let request = ChatRequest {
            model: "deepseek-chat".into(),
            messages: vec![super::super::ChatMessage {
                role: "user".into(),
                content: "Hello".into(),
            }],
            stream: true,
            temperature: Some(0.5),
            max_tokens: None,
        };
        let body = DeepSeekProvider::build_request_body(&request);
        assert_eq!(body["model"], "deepseek_chat");
        assert_eq!(body["stream"], true);
        assert_eq!(body["temperature"], 0.5);
        assert_eq!(body["messages"][0]["role"], "user");
        assert_eq!(body["messages"][0]["content"], "Hello");
    }
}
