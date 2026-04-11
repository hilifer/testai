use serde_json::{json, Value};

/// Find an available port for testing.
async fn get_free_port() -> u16 {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    listener.local_addr().unwrap().port()
}

#[tokio::test]
async fn health_endpoint() {
    let port = get_free_port().await;
    let addr = web_bridge::start_gateway(port).await.unwrap();
    let url = format!("http://{addr}/health");

    let client = reqwest::Client::new();
    let resp = client.get(&url).send().await.unwrap();

    assert_eq!(resp.status(), 200);
    assert_eq!(resp.text().await.unwrap(), "ok");
}

#[tokio::test]
async fn models_endpoint_returns_list() {
    let port = get_free_port().await;
    let addr = web_bridge::start_gateway(port).await.unwrap();
    let url = format!("http://{addr}/v1/models");

    let client = reqwest::Client::new();
    let resp = client.get(&url).send().await.unwrap();

    assert_eq!(resp.status(), 200);
    let body: Value = resp.json().await.unwrap();

    assert_eq!(body["object"], "list");
    let data = body["data"].as_array().unwrap();
    assert!(!data.is_empty(), "should have at least one model");

    // Check that each model has required fields
    for model in data {
        assert!(model["id"].is_string(), "model should have id");
        assert!(model["object"].is_string());
        assert!(model["owned_by"].is_string());
        assert!(model["name"].is_string());
        assert!(model["context_window"].is_number());
        assert!(model["max_output_tokens"].is_number());
    }
}

#[tokio::test]
async fn models_endpoint_contains_all_providers() {
    let port = get_free_port().await;
    let addr = web_bridge::start_gateway(port).await.unwrap();
    let url = format!("http://{addr}/v1/models");

    let client = reqwest::Client::new();
    let body: Value = client.get(&url).send().await.unwrap().json().await.unwrap();
    let data = body["data"].as_array().unwrap();

    let owners: Vec<&str> = data
        .iter()
        .filter_map(|m| m["owned_by"].as_str())
        .collect();

    assert!(owners.contains(&"deepseek"), "should have deepseek models");
    assert!(owners.contains(&"chatgpt"), "should have chatgpt models");
    assert!(owners.contains(&"gemini"), "should have gemini models");
    assert!(owners.contains(&"qwen"), "should have qwen models");
    assert!(owners.contains(&"kimi"), "should have kimi models");
}

#[tokio::test]
async fn models_show_not_ready_without_credentials() {
    let port = get_free_port().await;
    let addr = web_bridge::start_gateway(port).await.unwrap();
    let url = format!("http://{addr}/v1/models");

    let client = reqwest::Client::new();
    let body: Value = client.get(&url).send().await.unwrap().json().await.unwrap();
    let data = body["data"].as_array().unwrap();

    // Without any credentials configured, all models should show ready=false
    for model in data {
        assert_eq!(
            model["ready"], false,
            "model {} should not be ready without credentials",
            model["id"]
        );
    }
}

#[tokio::test]
async fn chat_completions_unknown_model_returns_400() {
    let port = get_free_port().await;
    let addr = web_bridge::start_gateway(port).await.unwrap();
    let url = format!("http://{addr}/v1/chat/completions");

    let client = reqwest::Client::new();
    let body = json!({
        "model": "unknown/nonexistent",
        "messages": [{"role": "user", "content": "Hi"}],
        "stream": false,
    });

    let resp = client.post(&url).json(&body).send().await.unwrap();
    assert_eq!(resp.status(), 400);

    let error: Value = resp.json().await.unwrap();
    assert!(error["error"]["message"].is_string());
    assert!(
        error["error"]["message"]
            .as_str()
            .unwrap()
            .contains("Unknown model")
    );
}

#[tokio::test]
async fn chat_completions_no_credentials_returns_401() {
    let port = get_free_port().await;
    let addr = web_bridge::start_gateway(port).await.unwrap();
    let url = format!("http://{addr}/v1/chat/completions");

    let client = reqwest::Client::new();
    let body = json!({
        "model": "deepseek/deepseek-chat",
        "messages": [{"role": "user", "content": "Hi"}],
        "stream": false,
    });

    let resp = client.post(&url).json(&body).send().await.unwrap();
    assert_eq!(resp.status(), 401);

    let error: Value = resp.json().await.unwrap();
    assert!(error["error"]["message"]
        .as_str()
        .unwrap()
        .contains("No credentials"));
}

#[tokio::test]
async fn multiple_gateways_on_different_ports() {
    let port1 = get_free_port().await;
    let port2 = get_free_port().await;

    let addr1 = web_bridge::start_gateway(port1).await.unwrap();
    let addr2 = web_bridge::start_gateway(port2).await.unwrap();

    assert_ne!(addr1, addr2);

    let client = reqwest::Client::new();

    let resp1 = client
        .get(format!("http://{addr1}/health"))
        .send()
        .await
        .unwrap();
    let resp2 = client
        .get(format!("http://{addr2}/health"))
        .send()
        .await
        .unwrap();

    assert_eq!(resp1.status(), 200);
    assert_eq!(resp2.status(), 200);
}
