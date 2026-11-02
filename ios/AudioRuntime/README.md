This is the verified candidate Libavfilter component for the missing Desktop
music effects. The default app project still uses its original MPVKit package.

- Package source: MPVKit f82e06d4f5ef4fc4aa9faba3782a462dbbef870c.
- Matching release builder: 288527dffbc6d3e63cce147fc7b520c64a791603.
- FFmpeg 8.1.2: 38b88335f99e76ed89ff3c93f877fdefce736c13.
- Archive SHA-256: b3d8406c8ebf61018709e18fac526e13910e032b870ff9fe35ac4a1ef2f6934a.

runtime.json records the build configuration, architecture slices and source
inputs. Both source patches and license notices are retained here. The
upstream license bytes are excluded from formatting and newline conversion.
The
VideoToolbox patch belongs to the upstream full FFmpeg build; this candidate
replaces only Libavfilter. The deployed libavcodec and libmpv archives do not
change.

Rebuild with scripts/ios/music-dsp-runtime.py and the pinned SDK builder as
shown in .github/workflows/ios-music-runtime.yml. Prepare a native validation
project with python3 scripts/ios/prepare-music-runtime.py. That command verifies
the archive, extracts its generated framework and writes a separate project
specification. It does not edit ios/project.yml.

Successful component compilation does not establish application integration.
The selected native audio and playback cases must pass before adopting this
package for delivery.

Native run 41544752262 on source 0c4a1202 executed the extended filters and
effects, audio transport/source changes and Community-style subtitles
successfully. Its separate unindexed/tiny-cache HTTP case failed exactly as
with the baseline library. package-inputs.json records all four passing
executions and that remaining failure. The default package remains unchanged;
the indexed HTTP journey, new editor and device application build have their
own outstanding gates.
