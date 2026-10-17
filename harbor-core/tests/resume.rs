use harbor_core::resume::{self, Document, Entry, Target};
use std::collections::BTreeMap;

fn target() -> Target {
    Target {
        id: "tt123".into(),
        season: None,
        episode: None,
        video_id: None,
    }
}

#[test]
fn desktop_movie_episode_and_special_keys_are_preserved() {
    let mut target = target();
    assert_eq!(resume::key(&target).unwrap(), "tt123");
    target.season = Some(0);
    target.episode = Some(2);
    assert_eq!(resume::key(&target).unwrap(), "tt123|s0e2");
    target.season = Some(1);
    assert_eq!(resume::key(&target).unwrap(), "tt123|s1e2");
}

#[test]
fn custom_video_ids_do_not_overwrite_another_episode() {
    let mut target = target();
    target.video_id = Some("addon:episode-one".into());
    let one = resume::key(&target).unwrap();
    target.video_id = Some("addon:episode-two".into());
    assert_ne!(one, resume::key(&target).unwrap());
    target.season = Some(1);
    target.episode = Some(3);
    assert_eq!(resume::key(&target).unwrap(), "tt123|s1e3");
}

#[test]
fn invalid_episode_coordinates_and_controls_return_only_safe_codes() {
    for (season, episode) in [(-1, 1), (0, 0), (1, -1)] {
        let mut target = target();
        target.season = Some(season);
        target.episode = Some(episode);
        assert_eq!(resume::key(&target).unwrap_err(), "invalid-resume-target");
    }
    let mut target = target();
    target.id = "private\0value".into();
    assert_eq!(resume::key(&target).unwrap_err(), "invalid-resume-target");
}

#[test]
fn autosave_boundaries_match_desktop_guard_rules() {
    let target = target();
    let run = |pos, duration| resume::checkpoint(&target, pos, duration, 1234, false).unwrap();
    assert!(run(4999.0, 200_000.0).is_none());
    assert!(run(5000.0, 149_999.0).is_none());
    assert!(run(5000.0, 150_000.0).is_some());
    assert!(run(5000.0, 0.0).is_some());
    let entry = run(12_345.5, 200_000.0).unwrap().entry;
    assert_eq!(
        entry,
        Entry {
            ms: 12_345.5,
            t: 1234
        }
    );
}

#[test]
fn exit_keeps_actual_positive_position_without_erasing_on_failed_start() {
    let target = target();
    assert!(resume::checkpoint(&target, 1.0, 1000.0, 1, true)
        .unwrap()
        .is_some());
    assert!(resume::checkpoint(&target, 0.0, 0.0, 1, true)
        .unwrap()
        .is_none());
    let mut live = target;
    live.id = "iptv:channel".into();
    assert!(resume::checkpoint(&live, 1000.0, 0.0, 1, true)
        .unwrap()
        .is_none());
}

#[test]
fn nonfinite_or_negative_player_numbers_never_reach_storage() {
    for number in [f64::NAN, f64::INFINITY, f64::NEG_INFINITY, -1.0] {
        assert_eq!(
            resume::checkpoint(&target(), number, 200_000.0, 1, true).unwrap_err(),
            "invalid-resume-position"
        );
        assert_eq!(
            resume::checkpoint(&target(), 6000.0, number, 1, true).unwrap_err(),
            "invalid-resume-position"
        );
    }
}

#[test]
fn resume_and_prompt_use_desktop_thresholds_and_settings() {
    let plan = |ms, duration, playback, prompt| {
        resume::start_plan(ms, duration, playback, prompt).unwrap()
    };
    assert_eq!(plan(5000.0, 0.0, true, false).ms, 0.0);
    assert_eq!(plan(5000.1, 0.0, true, false).ms, 5000.1);
    assert!(!plan(30_000.0, 0.0, true, true).prompt);
    assert!(plan(30_000.1, 0.0, true, true).prompt);
    assert!(!plan(50_000.0, 0.0, true, false).prompt);
    assert_eq!(plan(50_000.0, 0.0, false, true).ms, 0.0);
    assert_eq!(plan(80_000.0, 100_000.0, true, true).ms, 0.0);
    assert_eq!(plan(79_999.0, 100_000.0, true, false).ms, 79_999.0);
    assert!(resume::start_plan(f64::NAN, 0.0, true, true).is_err());
}

#[test]
fn unknown_schema_and_invalid_records_are_not_treated_as_empty() {
    let mut document = Document {
        version: 2,
        entries: BTreeMap::new(),
    };
    assert_eq!(
        resume::validate(&document),
        Err("unsupported-resume-version")
    );
    document.version = 1;
    document
        .entries
        .insert("tt123".into(), Entry { ms: -1.0, t: 1 });
    assert_eq!(resume::validate(&document), Err("invalid-resume-store"));
    document.entries.get_mut("tt123").unwrap().ms = 6000.0;
    assert_eq!(resume::validate(&document), Ok(()));
}
