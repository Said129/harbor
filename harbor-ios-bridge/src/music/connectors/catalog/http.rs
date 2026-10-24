use std::sync::LazyLock;
use std::time::Duration;

const AGENT: &str = concat!(
    "Harbor/",
    "0.9.132",
    " ( https://github.com/harborstremio/harbor )"
);
const REQUEST_TIMEOUT: Duration = Duration::from_secs(6);

static CLIENT: LazyLock<reqwest::Client> = LazyLock::new(|| {
    reqwest::Client::builder()
        .user_agent(AGENT)
        .timeout(REQUEST_TIMEOUT)
        .build()
        .unwrap_or_default()
});

pub struct Payload {
    pub content_type: String,
    pub text: String,
}

pub async fn get(url: &str, provider: &str) -> Result<Payload, String> {
    let mut response = CLIENT
        .get(url)
        .send()
        .await
        .map_err(|error| format!("{provider} request failed: {error}"))?;
    let status = response.status();
    let content_type = response
        .headers()
        .get(reqwest::header::CONTENT_TYPE)
        .and_then(|value| value.to_str().ok())
        .unwrap_or_default()
        .to_string();
    const MAX_BODY: usize = 8 * 1024 * 1024;
    if response.content_length().is_some_and(|length| length > MAX_BODY as u64) {
        return Err(format!("{provider} response exceeded the native catalog limit"));
    }
    let mut bytes = Vec::new();
    while let Some(chunk) = response.chunk().await
        .map_err(|error| format!("{provider} response was unreadable: {error}"))? {
        if bytes.len().saturating_add(chunk.len()) > MAX_BODY {
            return Err(format!("{provider} response exceeded the native catalog limit"));
        }
        bytes.extend_from_slice(&chunk);
    }
    let text = String::from_utf8_lossy(&bytes).into_owned();
    if !status.is_success() {
        return Err(format!("{provider} returned HTTP {}", status.as_u16()));
    }
    Ok(Payload { content_type, text })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_user_agent_identifies_harbor_and_carries_a_contact() {
        assert!(AGENT.starts_with("Harbor/"));
        assert!(AGENT.contains("https://github.com/harborstremio/harbor"));
    }
}
