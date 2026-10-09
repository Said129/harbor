//! Transport-independent Stremio addon protocol, mapped from src/lib/addons.ts.
//! Networking and credential persistence belong to the host, never the views.
use percent_encoding::{utf8_percent_encode, NON_ALPHANUMERIC};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeMap;
use url::Url;

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Addon {
    pub manifest: Manifest,
    pub transport_url: String,
    #[serde(default = "enabled_by_default")]
    pub enabled: bool,
}
fn enabled_by_default() -> bool {
    true
}

// Optional Stremio fields can be absent or explicitly null in cloud manifests.
// Normalize only the native projection; account.rs retains the original records.
fn null_default<'de, D, T>(deserializer: D) -> Result<T, D::Error>
where
    D: serde::Deserializer<'de>,
    T: Deserialize<'de> + Default,
{
    Ok(Option::<T>::deserialize(deserializer)?.unwrap_or_default())
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Manifest {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub types: Vec<String>,
    #[serde(default, deserialize_with = "null_default")]
    pub id_prefixes: Vec<String>,
    #[serde(default)]
    pub resources: Vec<Resource>,
    #[serde(default)]
    pub catalogs: Vec<Catalog>,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(untagged)]
pub enum Resource {
    Name(String),
    Specific {
        name: String,
        #[serde(default, deserialize_with = "null_default")]
        types: Vec<String>,
        #[serde(rename = "idPrefixes", default, deserialize_with = "null_default")]
        id_prefixes: Vec<String>,
    },
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Catalog {
    pub id: String,
    #[serde(rename = "type")]
    pub kind: String,
    #[serde(default, deserialize_with = "null_default")]
    pub name: String,
    #[serde(default)]
    pub extra: Vec<CatalogExtra>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CatalogExtra {
    pub name: String,
    #[serde(default)]
    pub is_required: bool,
    #[serde(default, deserialize_with = "null_default")]
    pub options: Vec<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RequestPlan {
    pub key: String,
    pub url: String,
    pub title: String,
    pub kind: String,
    pub addon: Addon,
    pub addon_priority: u32,
    pub timeout_ms: u32,
    pub catalog: Option<Catalog>,
}

impl Addon {
    /// Specific resource declarations take precedence, matching Desktop.
    pub fn accepts(&self, resource: &str, kind: &str, id: &str) -> bool {
        if !self.enabled {
            return false;
        }
        let specific: Vec<_> = self
            .manifest
            .resources
            .iter()
            .filter_map(|r| match r {
                Resource::Specific {
                    name,
                    types,
                    id_prefixes,
                } if name == resource => Some((types, id_prefixes)),
                _ => None,
            })
            .collect();
        let prefix_ok =
            |prefixes: &[String]| prefixes.is_empty() || prefixes.iter().any(|p| id.starts_with(p));
        if !specific.is_empty() {
            return specific
                .iter()
                .any(|(types, prefixes)| types.iter().any(|t| t == kind) && prefix_ok(prefixes));
        }
        self.manifest
            .resources
            .iter()
            .any(|r| matches!(r, Resource::Name(n) if n == resource))
            && self.manifest.types.iter().any(|t| t == kind)
            && prefix_ok(&self.manifest.id_prefixes)
    }
}

/// URLs can carry credentials. Errors deliberately never include their input.
pub fn normalize_manifest_url(raw: &str) -> Result<String, &'static str> {
    let value = raw.trim();
    let value = value
        .strip_prefix("stremio://")
        .map(|v| format!("https://{v}"))
        .unwrap_or_else(|| value.to_owned());
    let mut url = Url::parse(&value).map_err(|_| "invalid-addon-url")?;
    if !matches!(url.scheme(), "https" | "http")
        || url.host_str().is_none()
        || !url.username().is_empty()
        || url.password().is_some()
    {
        return Err("invalid-addon-url");
    }
    url.set_fragment(None);
    if !url.path().ends_with("/manifest.json") {
        if url.path().ends_with("/configure") {
            let path = format!(
                "{}/manifest.json",
                url.path().trim_end_matches("/configure")
            );
            url.set_path(&path);
        } else {
            url.set_path(&format!(
                "{}/manifest.json",
                url.path().trim_end_matches('/')
            ));
        }
    }
    Ok(url.into())
}

fn component(value: &str) -> String {
    const COMPONENT: &percent_encoding::AsciiSet = &NON_ALPHANUMERIC
        .remove(b'-')
        .remove(b'_')
        .remove(b'.')
        .remove(b'~');
    utf8_percent_encode(value, COMPONENT).to_string()
}

pub fn resource_url(
    addon: &Addon,
    resource: &str,
    kind: &str,
    id: &str,
    extras: &BTreeMap<String, String>,
) -> Result<String, &'static str> {
    let normalized = normalize_manifest_url(&addon.transport_url)?;
    let mut url = Url::parse(&normalized).map_err(|_| "invalid-addon-url")?;
    let base = url
        .path()
        .strip_suffix("/manifest.json")
        .ok_or("invalid-addon-url")?;
    let extra_path = if extras.is_empty() {
        String::new()
    } else {
        format!(
            "/{}",
            extras
                .iter()
                .map(|(k, v)| format!("{}={}", component(k), component(v)))
                .collect::<Vec<_>>()
                .join("&")
        )
    };
    url.set_path(&format!(
        "{base}/{}/{}/{}{extra_path}.json",
        component(resource),
        component(kind),
        component(id)
    ));
    Ok(url.into())
}

pub fn catalog_plans(
    addons: &[Addon],
    search: Option<&str>,
    genre: Option<&str>,
    skip: u32,
) -> Result<Vec<RequestPlan>, &'static str> {
    let mut plans = Vec::new();
    for (priority, addon) in addons.iter().enumerate().filter(|(_, a)| a.enabled) {
        for catalog in &addon.manifest.catalogs {
            let supports = |name: &str| catalog.extra.iter().any(|e| e.name == name);
            if search.is_some() && !supports("search") {
                continue;
            }
            let mut extras = BTreeMap::new();
            if let Some(value) = search {
                extras.insert("search".into(), value.into());
            }
            if let Some(value) = genre {
                if supports("genre") {
                    extras.insert("genre".into(), value.into());
                }
            }
            if skip > 0 {
                if !supports("skip") {
                    continue;
                }
                extras.insert("skip".into(), skip.to_string());
            }
            if catalog
                .extra
                .iter()
                .any(|e| e.is_required && !extras.contains_key(&e.name))
            {
                continue;
            }
            plans.push(RequestPlan {
                key: format!("{}:{}:{}", priority, catalog.kind, catalog.id),
                url: resource_url(addon, "catalog", &catalog.kind, &catalog.id, &extras)?,
                title: if catalog.name.is_empty() {
                    addon.manifest.name.clone()
                } else {
                    catalog.name.clone()
                },
                kind: catalog.kind.clone(),
                addon: addon.clone(),
                addon_priority: priority as u32,
                timeout_ms: 8000,
                catalog: Some(catalog.clone()),
            });
        }
    }
    Ok(plans)
}

pub fn resource_plans(
    addons: &[Addon],
    resource: &str,
    kind: &str,
    id: &str,
) -> Result<Vec<RequestPlan>, &'static str> {
    if !matches!(resource, "meta" | "stream" | "subtitles") {
        return Err("invalid-resource");
    }
    addons
        .iter()
        .enumerate()
        .filter(|(_, a)| a.accepts(resource, kind, id))
        .map(|(priority, addon)| {
            let slow = [
                "mediafusion",
                "comet",
                "torrentio",
                "knightcrawler",
                "aiostreams",
                "jackettio",
                "torbox",
            ]
            .iter()
            .any(|p| {
                format!(
                    "{} {} {}",
                    addon.manifest.id, addon.manifest.name, addon.transport_url
                )
                .to_lowercase()
                .contains(p)
            });
            Ok(RequestPlan {
                key: format!("{priority}:{resource}:{kind}:{id}"),
                url: resource_url(addon, resource, kind, id, &BTreeMap::new())?,
                title: addon.manifest.name.clone(),
                kind: kind.to_owned(),
                addon: addon.clone(),
                addon_priority: priority as u32,
                timeout_ms: if slow { 22000 } else { 8000 },
                catalog: None,
            })
        })
        .collect()
}

pub fn map_streams(
    plan: &RequestPlan,
    response: Value,
) -> Result<Vec<crate::Stream>, &'static str> {
    let list = response
        .get("streams")
        .and_then(Value::as_array)
        .ok_or("invalid-stream-response")?;
    list.iter()
        .enumerate()
        .map(|(index, raw)| {
            let mut raw = raw.clone();
            let object = raw.as_object_mut().ok_or("invalid-stream-response")?;
            object.insert(
                "addonId".into(),
                Value::String(plan.addon.manifest.id.clone()),
            );
            object.insert(
                "addonName".into(),
                Value::String(plan.addon.manifest.name.clone()),
            );
            object.insert("addonPriority".into(), plan.addon_priority.into());
            object.insert("addonReturnIdx".into(), (index as u32).into());
            let mut stream: crate::Stream =
                serde_json::from_value(raw).map_err(|_| "invalid-stream-response")?;
            if let Some(hash) = stream.info_hash.as_mut() {
                *hash = hash.to_lowercase();
            }
            Ok(stream)
        })
        .collect()
}
