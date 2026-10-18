//! Stremio account contracts from Desktop's stremio.ts and addons.ts.
//! The host supplies HTTPS transport and secure persistence. Errors never echo
//! server messages, credentials or configured addon URLs.
use crate::addons::{self, Addon};
use serde_json::{json, Value};

pub fn request(action: &str, fields: &Value) -> Result<Value, &'static str> {
    let key = || -> Result<&str, &'static str> {
        fields["authKey"]
            .as_str()
            .filter(|s| !s.is_empty() && s.len() <= 16384)
            .ok_or("invalid-account-request")
    };
    let (path, body) = match action {
        "login" => {
            let email = fields["email"].as_str().unwrap_or("").trim();
            let password = fields["password"].as_str().unwrap_or("");
            if email.is_empty() || email.len() > 320 || password.is_empty() || password.len() > 4096
            {
                return Err("invalid-account-request");
            }
            (
                "login",
                json!({"email":email,"password":password,"facebook":false}),
            )
        }
        "user" => ("getUser", json!({"authKey":key()?})),
        "addons" => (
            "addonCollectionGet",
            json!({"authKey":key()?,"type":"user","update":false}),
        ),
        "setAddons" => {
            let list = fields["addons"]
                .as_array()
                .ok_or("invalid-account-request")?;
            validate_addons(list)?;
            (
                "addonCollectionSet",
                json!({"authKey":key()?,"type":"user","addons":list}),
            )
        }
        _ => return Err("invalid-account-request"),
    };
    Ok(json!({"url":format!("https://api.strem.io/api/{path}"),"body":body}))
}

pub fn response(action: &str, value: &Value) -> Result<Value, &'static str> {
    if !value["error"].is_null() {
        return Err("account-rejected");
    }
    let result = value
        .get("result")
        .filter(|v| !v.is_null())
        .ok_or("invalid-account-response")?;
    match action {
        "login" => {
            let token = result["authKey"]
                .as_str()
                .filter(|s| !s.is_empty() && s.len() <= 16384)
                .ok_or("invalid-account-response")?;
            validate_user(&result["user"])?;
            Ok(json!({"authKey":token,"user":result["user"]}))
        }
        "user" => {
            validate_user(result)?;
            Ok(result.clone())
        }
        "addons" => {
            let list = result["addons"]
                .as_array()
                .ok_or("invalid-account-response")?;
            let addons = validate_addons(list)?;
            // Keep original transport/flags for a later explicit collection edit.
            Ok(json!({"addons":addons,"records":list}))
        }
        "setAddons" if result.is_object() && result["success"] != false => {
            Ok(json!({"saved":true}))
        }
        _ => Err("invalid-account-response"),
    }
}

fn validate_user(user: &Value) -> Result<(), &'static str> {
    if !user["_id"]
        .as_str()
        .is_some_and(|id| !id.is_empty() && id.len() <= 512)
    {
        return Err("invalid-account-response");
    }
    Ok(())
}

fn validate_addons(list: &[Value]) -> Result<Vec<Addon>, &'static str> {
    if list.len() > 1000 {
        return Err("invalid-account-response");
    }
    list.iter()
        .map(|record| {
            let mut addon: Addon =
                serde_json::from_value(record.clone()).map_err(|_| "invalid-account-response")?;
            if addon.manifest.id.trim().is_empty() || addon.manifest.name.trim().is_empty() {
                return Err("invalid-account-response");
            }
            addon.transport_url = addons::normalize_manifest_url(&addon.transport_url)
                .map_err(|_| "invalid-account-response")?;
            Ok(addon)
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn errors_do_not_echo_secrets_or_turn_failed_sync_into_empty_addons() {
        let rejected = json!({"error":{"message":"private token and URL"}});
        assert_eq!(response("login", &rejected), Err("account-rejected"));
        assert_eq!(
            response("addons", &json!({"result":{}})),
            Err("invalid-account-response")
        );
        assert_eq!(
            response("setAddons", &json!({"result":{"success":false}})),
            Err("invalid-account-response")
        );
        assert_eq!(request("user", &json!({})), Err("invalid-account-request"));
    }
    #[test]
    fn collection_retains_configured_instances_order_flags_and_intentional_empty_list() {
        let records = json!([
            {"transportUrl":"https://example.org/config-a/manifest.json","manifest":{"id":"same","name":"A"},"flags":{"protected":true}},
            {"transportUrl":"https://example.org/config-b/manifest.json","manifest":{"id":"same","name":"B"}}
        ]);
        let decoded = response("addons", &json!({"result":{"addons":records}})).unwrap();
        assert_eq!(decoded["records"], records);
        assert_eq!(decoded["addons"][0]["manifest"]["name"], "A");
        assert_eq!(decoded["addons"][1]["manifest"]["name"], "B");
        assert_eq!(
            response("addons", &json!({"result":{"addons":[]}})).unwrap()["addons"],
            json!([])
        );
        let plan = request("setAddons", &json!({"authKey":"test","addons":records})).unwrap();
        assert_eq!(plan["body"]["addons"], records);
    }

    #[test]
    fn collection_accepts_nullable_stremio_manifest_fields_without_rewriting_cloud_records() {
        // Stremio serializes optional manifest fields as null in account collections.
        let records = json!([{
            "transportUrl":"https://example.org/configured/manifest.json",
            "flags":{"protected":true},
            "manifest":{
                "id":"nullable-contract", "name":"Configured addon", "version":"1.0.0",
                "types":["movie"], "idPrefixes":null,
                "resources":["meta", {"name":"stream","types":["movie"],"idPrefixes":null},
                    {"name":"subtitles","types":null,"idPrefixes":null}],
                "catalogs":[{"id":"popular","type":"movie","name":null,
                    "extra":[{"name":"genre","options":null}]}]
            }
        }]);
        let decoded = response("addons", &json!({"result":{"addons":records}})).unwrap();
        let addons: Vec<Addon> = serde_json::from_value(decoded["addons"].clone()).unwrap();
        assert_eq!(decoded["records"], records);
        assert!(addons[0].accepts("meta", "movie", "tt123"));
        assert!(addons[0].accepts("stream", "movie", "custom123"));
        assert!(!addons[0].accepts("subtitles", "movie", "tt123"));
        let plans = addons::catalog_plans(&addons, None, None, 0).unwrap();
        assert_eq!(plans.len(), 1);
        assert_eq!(plans[0].title, "Configured addon");
        assert!(plans[0].catalog.as_ref().unwrap().extra[0]
            .options
            .is_empty());
        let saved = request("setAddons", &json!({"authKey":"test","addons":records})).unwrap();
        assert_eq!(saved["body"]["addons"], records);
    }
}
