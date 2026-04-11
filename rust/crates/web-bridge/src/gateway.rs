use std::net::SocketAddr;
use std::sync::Arc;

use axum::extract::State;
use axum::http::StatusCode;
use axum::response::sse::{Event, Sse};
use axum::response::IntoResponse;
use axum::routing::{get, post};
use axum::{Json, Router};
use serde_json::{json, Value};
use tokio::sync::RwLock;
use tokio_stream::StreamExt;

use crate::credential_store::CredentialStore;
use crate::error::WebBridgeError;
use crate::providers::{ChatMessage, ChatRequest, ProviderRegistry};

/// Shared state for the gateway.
struct GatewayState {
    registry: ProviderRegistry,
    credentials: RwLock<CredentialStore>,
}

/// Start the built-in OpenAI-compatible gateway server.
/// Returns the bound address so the caller knows which port was used.
pub async fn start_gateway(port: u16) -> Result<SocketAddr, WebBridgeError> {
    let state = Arc::new(GatewayState {
        registry: ProviderRegistry::new(),
        credentials: RwLock::new(CredentialStore::load()),
    });

    let app = Router::new()
        .route("/v1/chat/completions", post(chat_completions))
        .route("/v1/models", get(list_models))
        .route("/health", get(health))
        .with_state(state);

    let addr = SocketAddr::from(([127, 0, 0, 1], port));
    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .map_err(|e| WebBridgeError::Gateway(format!("failed to bind to {addr}: {e}")))?;

    let bound_addr = listener
        .local_addr()
        .map_err(|e| WebBridgeError::Gateway(e.to_string()))?;

    tracing::info!("web-bridge gateway listening on http://{bound_addr}");

    tokio::spawn(async move {
        axum::serve(listener, app).await.ok();
    });

    Ok(bound_addr)
}

/// POST /v1/chat/completions — OpenAI-compatible endpoint.
async fn chat_completions(
    State(state): State<Arc<GatewayState>>,
    Json(body): Json<Value>,
) -> impl IntoResponse {
    let model = body
        .get("model")
        .and_then(Value::as_str)
        .unwrap_or("deepseek/deepseek-chat")
        .to_string();

    let messages: Vec<ChatMessage> = body
        .get("messages")
        .and_then(Value::as_array)
        .map(|msgs| {
            msgs.iter()
                .filter_map(|m| {
                    Some(ChatMessage {
                        role: m.get("role")?.as_str()?.to_string(),
                        content: m.get("content")?.as_str()?.to_string(),
                    })
                })
                .collect()
        })
        .unwrap_or_default();

    let stream = body
        .get("stream")
        .and_then(Value::as_bool)
        .unwrap_or(false);

    let temperature = body.get("temperature").and_then(Value::as_f64);
    let max_tokens = body
        .get("max_tokens")
        .and_then(Value::as_u64)
        .map(|v| v as u32);

    // Find the provider
    // Resolve provider and model - collect owned data to avoid lifetime issues
    let (provider_name, actual_model) = {
        let Some((provider, actual_model)) = state.registry.find_by_model(&model) else {
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({
                    "error": {
                        "message": format!("Unknown model: {model}. Use format: provider/model (e.g., deepseek/deepseek-chat)"),
                        "type": "invalid_request_error",
                    }
                })),
            )
                .into_response();
        };
        (provider.name().to_string(), actual_model.to_string())
    };

    let credentials = state.credentials.read().await;
    let Some(credential) = credentials.get(&provider_name) else {
        let provider = state.registry.get(&provider_name).unwrap();
        return (
            StatusCode::UNAUTHORIZED,
            Json(json!({
                "error": {
                    "message": format!(
                        "No credentials for {}. Run `claw web-login {}` first.",
                        provider.display_name(),
                        provider_name
                    ),
                    "type": "authentication_error",
                }
            })),
        )
            .into_response();
    };

    let chat_request = ChatRequest {
        model: actual_model,
        messages,
        stream,
        temperature,
        max_tokens,
    };

    let credential = credential.clone();
    let provider = state.registry.get(&provider_name).unwrap();

    if stream {
        // Streaming response as SSE
        match provider.chat_stream(&credential, &chat_request).await {
            Ok(mut delta_stream) => {
                let sse_stream = async_stream::stream! {
                    let id = uuid::Uuid::new_v4().to_string();
                    while let Some(result) = delta_stream.next().await {
                        match result {
                            Ok(delta) => {
                                let chunk = json!({
                                    "id": format!("chatcmpl-{id}"),
                                    "object": "chat.completion.chunk",
                                    "model": model,
                                    "choices": [{
                                        "index": 0,
                                        "delta": {
                                            "content": delta.content,
                                            "role": delta.role,
                                        },
                                        "finish_reason": delta.finish_reason,
                                    }],
                                });
                                yield Ok::<Event, std::convert::Infallible>(
                                    Event::default().data(chunk.to_string())
                                );
                            }
                            Err(e) => {
                                let err_chunk = json!({
                                    "error": {"message": e.to_string()}
                                });
                                yield Ok(Event::default().data(err_chunk.to_string()));
                                break;
                            }
                        }
                    }
                    yield Ok(Event::default().data("[DONE]".to_string()));
                };

                Sse::new(sse_stream).into_response()
            }
            Err(e) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({
                    "error": {"message": e.to_string(), "type": "server_error"}
                })),
            )
                .into_response(),
        }
    } else {
        // Non-streaming: collect all deltas into one response
        match provider.chat_stream(&credential, &chat_request).await {
            Ok(mut delta_stream) => {
                let mut full_content = String::new();
                while let Some(Ok(delta)) = delta_stream.next().await {
                    if let Some(content) = delta.content {
                        full_content.push_str(&content);
                    }
                }

                Json(json!({
                    "id": format!("chatcmpl-{}", uuid::Uuid::new_v4()),
                    "object": "chat.completion",
                    "model": model,
                    "choices": [{
                        "index": 0,
                        "message": {
                            "role": "assistant",
                            "content": full_content,
                        },
                        "finish_reason": "stop",
                    }],
                    "usage": {
                        "prompt_tokens": 0,
                        "completion_tokens": 0,
                        "total_tokens": 0,
                    },
                }))
                .into_response()
            }
            Err(e) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({
                    "error": {"message": e.to_string(), "type": "server_error"}
                })),
            )
                .into_response(),
        }
    }
}

/// GET /v1/models — list all available web models.
async fn list_models(State(state): State<Arc<GatewayState>>) -> Json<Value> {
    let credentials = state.credentials.read().await;

    let models: Vec<Value> = state
        .registry
        .list()
        .iter()
        .flat_map(|provider| {
            let has_creds = credentials.get(provider.name()).is_some();
            provider.models().into_iter().map(move |model| {
                json!({
                    "id": format!("{}/{}", provider.name(), model.id),
                    "object": "model",
                    "owned_by": provider.name(),
                    "name": model.name,
                    "context_window": model.context_window,
                    "max_output_tokens": model.max_output_tokens,
                    "ready": has_creds,
                })
            })
        })
        .collect();

    Json(json!({
        "object": "list",
        "data": models,
    }))
}

/// GET /health
async fn health() -> &'static str {
    "ok"
}
