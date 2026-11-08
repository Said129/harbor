use harbor_core::addons::*;
use serde_json::json;
use std::collections::BTreeMap;

fn addon() -> Addon {
    serde_json::from_value(json!({
        "transportUrl":"https://example.com/config%2Fsecret/manifest.json?token=private",
        "manifest":{"id":"test","name":"Test","types":["movie","series"],"idPrefixes":["tt"],
            "resources":["meta","stream"],"catalogs":[{"id":"top","type":"movie","extra":[{"name":"search"},{"name":"skip"},{"name":"genre"}]}]}
    })).unwrap()
}

#[test]
fn encodes_path_extras_without_exposing_tokens_or_losing_config() {
    let plans = catalog_plans(&[addon()], Some("one / two & español"), None, 100).unwrap();
    assert_eq!(plans[0].url, "https://example.com/config%2Fsecret/catalog/movie/top/search=one%20%2F%20two%20%26%20espa%C3%B1ol&skip=100.json?token=private");
}

#[test]
fn simple_and_specific_resource_matching_follows_desktop() {
    let mut a = addon();
    assert!(a.accepts("stream", "movie", "tt123"));
    assert!(!a.accepts("stream", "anime", "tt123"));
    assert!(!a.accepts("stream", "movie", "kitsu:123"));
    a.manifest.resources.push(Resource::Specific {
        name: "stream".into(),
        types: Some(vec!["anime".into()]),
        id_prefixes: Some(vec!["kitsu:".into()]),
    });
    assert!(!a.accepts("stream", "movie", "tt123"));
    assert!(a.accepts("stream", "anime", "kitsu:123"));
    a.enabled = false;
    assert!(!a.accepts("stream", "anime", "kitsu:123"));
}

#[test]
fn skips_required_extras_and_unsearchable_catalogs() {
    let mut a = addon();
    a.manifest.catalogs[0].extra = vec![CatalogExtra {
        name: "search".into(),
        is_required: true,
        options: vec![],
    }];
    assert!(catalog_plans(&[a.clone()], None, None, 0)
        .unwrap()
        .is_empty());
    assert_eq!(
        catalog_plans(&[a.clone()], Some("film"), None, 0)
            .unwrap()
            .len(),
        1
    );
    a.manifest.catalogs[0].extra.clear();
    assert!(catalog_plans(&[a], Some("film"), None, 0)
        .unwrap()
        .is_empty());
}

#[test]
fn metadata_and_subtitle_resources_inherit_only_absent_constraints() {
    let mut a = addon();
    a.manifest.resources = serde_json::from_value(json!([
        {"name": "meta", "types": null},
        {"name": "subtitles", "types": ["series"], "idPrefixes": []},
        {"name": "stream"}
    ]))
    .unwrap();
    let projected = serde_json::to_value(a).unwrap();
    assert!(projected["manifest"]["resources"][0].get("types").is_none());
    let a: Addon = serde_json::from_value(projected).unwrap();
    assert!(a.accepts("meta", "movie", "tt123"));
    assert!(!a.accepts("meta", "movie", "kitsu:123"));
    assert!(!a.accepts("meta", "anime", "tt123"));
    assert!(a.accepts("subtitles", "series", "kitsu:123"));
    assert!(!a.accepts("subtitles", "movie", "tt123"));
    assert!(!a.accepts("stream", "movie", "tt123"));
}

#[test]
fn legacy_catalog_extras_survive_install_projection_and_plan_search_pages() {
    let mut a = addon();
    a.manifest.catalogs[0] = serde_json::from_value(json!({
        "id": "legacy",
        "type": "movie",
        "extra": null,
        "extraSupported": ["search", null, "skip", 3]
    }))
    .unwrap();
    let addon = serde_json::from_value(serde_json::to_value(a).unwrap()).unwrap();
    let plans = catalog_plans(&[addon], Some("one / two"), None, 12).unwrap();
    assert_eq!(plans.len(), 1);
    assert!(plans[0]
        .url
        .ends_with("/catalog/movie/legacy/search=one%20%2F%20two&skip=12.json?token=private"));
    assert_eq!(
        serde_json::to_value(&plans[0]).unwrap()["catalog"]["extraSupported"],
        json!(["search", "skip"])
    );
}

#[test]
fn required_catalog_extras_use_the_first_option_until_explicitly_overridden() {
    let mut a = addon();
    a.manifest.catalogs[0].extra[2].is_required = true;
    a.manifest.catalogs[0].extra[2].options = vec!["Sci-Fi".into(), "Drama".into()];

    let default = catalog_plans(std::slice::from_ref(&a), None, None, 0).unwrap();
    assert!(default[0].url.ends_with("/genre=Sci-Fi.json?token=private"));
    let filtered = catalog_plans(std::slice::from_ref(&a), None, Some("Drama"), 24).unwrap();
    assert!(filtered[0]
        .url
        .ends_with("/genre=Drama&skip=24.json?token=private"));

    a.manifest.catalogs[0].extra[2].options.clear();
    assert!(catalog_plans(&[a], None, None, 0).unwrap().is_empty());
}

#[test]
fn normalizes_stremio_and_configure_urls_and_rejects_unsafe_schemes() {
    assert_eq!(
        normalize_manifest_url("stremio://example.com/token/configure").unwrap(),
        "https://example.com/token/manifest.json"
    );
    assert_eq!(
        normalize_manifest_url("https://example.com").unwrap(),
        "https://example.com/manifest.json"
    );
    for input in [
        "file:///tmp/manifest.json",
        "javascript:alert(1)",
        "https://user:secret@example.com/manifest.json",
    ] {
        assert_eq!(normalize_manifest_url(input), Err("invalid-addon-url"));
    }
}

#[test]
fn maps_identity_order_and_preserves_unknown_stream_fields() {
    let plan = resource_plans(&[addon()], "stream", "series", "tt123:1:2")
        .unwrap()
        .remove(0);
    let mapped = map_streams(&plan, json!({"streams":[{"infoHash":"ABCDEF","fileIdx":2,"sources":["tracker:udp://example.com:80"],"subtitles":[{"url":"https://example.com/a.ass","lang":"spa"}],"behaviorHints":{"proxyHeaders":{"request":{"Authorization":"secret"}}},"futureField":true}]})).unwrap();
    assert_eq!(mapped[0].addon_id, "test");
    assert_eq!(mapped[0].info_hash.as_deref(), Some("abcdef"));
    assert_eq!(mapped[0].addon_return_idx, Some(0));
    assert_eq!(mapped[0].extra["futureField"], true);
    assert!(
        serde_json::to_value(&mapped[0]).unwrap()["behaviorHints"]["proxyHeaders"]["request"]
            ["Authorization"]
            .is_string()
    );
}

#[test]
fn rejects_invalid_stream_response_instead_of_silently_empty_results() {
    let plan = resource_plans(&[addon()], "stream", "movie", "tt123")
        .unwrap()
        .remove(0);
    assert!(map_streams(&plan, json!({"streams":"bad"})).is_err());
    assert!(
        resource_url(&addon(), "meta", "movie", "../private", &BTreeMap::new())
            .unwrap()
            .contains("..%2Fprivate")
    );
}
