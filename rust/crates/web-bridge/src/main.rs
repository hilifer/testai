use std::process::ExitCode;

#[tokio::main]
async fn main() -> ExitCode {
    let port = std::env::var("WEB_BRIDGE_PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(web_bridge::DEFAULT_GATEWAY_PORT);

    eprintln!("[web-bridge] Starting gateway on port {port}...");

    match web_bridge::start_gateway(port).await {
        Ok(addr) => {
            eprintln!("[web-bridge] Gateway running at http://{addr}");
            eprintln!("[web-bridge] Press Ctrl+C to stop");
            // Keep running until killed
            tokio::signal::ctrl_c().await.ok();
            eprintln!("[web-bridge] Shutting down");
            ExitCode::SUCCESS
        }
        Err(e) => {
            eprintln!("[web-bridge] Failed to start: {e}");
            ExitCode::FAILURE
        }
    }
}
