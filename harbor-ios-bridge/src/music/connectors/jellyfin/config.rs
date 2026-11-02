use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JellyfinConfig {
    pub origin: String,
    pub user_id: String,
    pub user_name: String,
    pub token: String,
    pub device_id: String,
    pub server_name: String,
    pub library_id: Option<String>,
}

pub fn normalize_origin(value: &str) -> Result<String, String> {
    let url = reqwest::Url::parse(value.trim())
        .map_err(|_| "Enter the full Jellyfin server address".to_string())?;
    if !matches!(url.scheme(), "http" | "https") || url.host_str().is_none() {
        return Err("Enter the full Jellyfin server address".to_string());
    }
    if !url.username().is_empty() || url.password().is_some() {
        return Err("Leave the sign in details out of the server address".to_string());
    }
    let mut base = url;
    base.set_query(None);
    base.set_fragment(None);
    Ok(base.as_str().trim_end_matches('/').to_string())
}

impl JellyfinConfig {
    pub fn validated(mut self) -> Result<Self, String> {
        self.origin = normalize_origin(&self.origin)?;
        self.user_id = super::items::safe_item_id(&self.user_id)?;
        if let Some(id) = self.library_id.as_mut() {
            *id = super::items::safe_item_id(id)?;
        }
        validate_header_field(&self.device_id, 128)?;
        validate_header_field(&self.token, 16384)?;
        if self.user_name.len() > 512 || self.server_name.len() > 512 {
            return Err("Invalid Jellyfin account".into());
        }
        Ok(self)
    }
}
pub fn validate_header_field(value: &str, limit: usize) -> Result<(), String> {
    if value.is_empty()
        || value.len() > limit
        || value
            .bytes()
            .any(|v| v.is_ascii_control() || v == b'"' || v == b'\\')
    {
        return Err("Invalid Jellyfin authorization".into());
    }
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn proxy_origin_and_credentials_are_checked_before_io() {
        assert_eq!(
            normalize_origin(" https://media.example.test/jellyfin/?token=1#top").unwrap(),
            "https://media.example.test/jellyfin"
        );
        for value in [
            "ftp://media.example.test",
            "https://user:password@media.example.test",
            "media.example.test",
        ] {
            assert!(normalize_origin(value).is_err());
        }
        for value in ["", "token\nInjected: yes", "token\"other", "token\\other"] {
            assert!(validate_header_field(value, 100).is_err());
        }
        assert!(validate_header_field("token-123", 100).is_ok());
    }
}
