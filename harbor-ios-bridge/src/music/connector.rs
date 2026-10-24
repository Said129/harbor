use serde::Serialize;
use std::sync::atomic::{AtomicU8, Ordering};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum ConnectorHealth {
    Unknown,
    Healthy,
    Degraded,
    Offline,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ConnectorHealthInfo {
    pub id: String,
    pub name: String,
    pub health: ConnectorHealth,
    pub searchable: bool,
    pub playable: bool,
    pub scrobbler: bool,
}

pub struct HealthCell(AtomicU8);

impl HealthCell {
    pub fn new() -> Self {
        Self(AtomicU8::new(0))
    }

    pub fn get(&self) -> ConnectorHealth {
        match self.0.load(Ordering::Relaxed) {
            1 => ConnectorHealth::Healthy,
            2 => ConnectorHealth::Degraded,
            3 => ConnectorHealth::Offline,
            _ => ConnectorHealth::Unknown,
        }
    }

    pub fn set(&self, health: ConnectorHealth) {
        self.0.store(
            match health {
                ConnectorHealth::Unknown => 0,
                ConnectorHealth::Healthy => 1,
                ConnectorHealth::Degraded => 2,
                ConnectorHealth::Offline => 3,
            },
            Ordering::Relaxed,
        );
    }
}

impl Default for HealthCell {
    fn default() -> Self {
        Self::new()
    }
}

