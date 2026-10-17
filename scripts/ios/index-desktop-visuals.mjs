import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const reference = resolve(process.argv[2]);
const output = resolve(process.argv[3] ?? join(root, "docs/ios/desktop-visuals-0.9.132.json"));
assert.equal(JSON.parse(readFileSync(join(reference, "package.json"), "utf8")).version, "0.9.132");
const digest = (bytes) => createHash("sha256").update(bytes).digest("hex");
const portable = (base, file) => relative(base, file).replaceAll("\\", "/");
function files(folder) {
  return readdirSync(folder, { withFileTypes: true })
    .flatMap((entry) => {
      const file = join(folder, entry.name);
      return entry.isDirectory() ? files(file) : entry.isFile() ? [file] : [];
    })
    .sort();
}

const animations = [];
for (const file of files(join(reference, "src")).filter((item) => item.endsWith(".css"))) {
  const source = readFileSync(file, "utf8");
  for (const match of source.matchAll(/@keyframes\s+([A-Za-z0-9_-]+)\s*\{/g)) {
    let depth = 1;
    let end = match.index + match[0].length;
    for (; depth > 0 && end < source.length; end += 1) {
      if (source[end] === "{") depth += 1;
      if (source[end] === "}") depth -= 1;
    }
    assert.equal(depth, 0, `Unbalanced animation in ${file}`);
    animations.push({
      name: match[1],
      source: portable(reference, file),
      line: source.slice(0, match.index).split("\n").length,
      definitionSha256: digest(source.slice(match.index, end)),
      status: "pending_native_and_visual_review",
    });
  }
}
const vectors = files(join(reference, "src/assets"))
  .filter((file) => {
    const name = portable(reference, file);
    return (
      file.endsWith(".json") && (name.includes("/lottie/") || name.endsWith("/harbor-lottie.json"))
    );
  })
  .map((file) => ({
    source: portable(reference, file),
    bytes: statSync(file).size,
    sha256: digest(readFileSync(file)),
    status: "pending_native_and_visual_review",
  }));
const native = {
  home: "HomeView",
  discover: "DiscoverView",
  catalogs: "CatalogsView",
  plugins: null,
  movies: "ContentPageView",
  shows: "ContentPageView",
  music: "MusicView",
  kids: "ContentPageView",
  anime: "ContentPageView",
  manga: "MangaView",
  ebook: "EBooksView",
  live: "LiveTVView",
  sports: "SportsView",
  vod: "VODView",
  calendar: "CalendarView",
  library: "LibraryView",
  collections: "CollectionsView",
  downloads: "DownloadsView",
  addons: "AddonsView",
  settings: "SettingsView",
};
const sections = Object.entries(native).map(([id, name]) => {
  const path = name ? `ios/Harbor/Views/${name}.swift` : null;
  if (path) assert.ok(statSync(join(root, path)).isFile());
  return {
    id,
    nativeEntry: path,
    status: "pending_complete_reference_comparison",
    requiredStates: [
      "normal",
      "loading",
      "empty",
      "error",
      "touch",
      "iPad_layout",
      "Reduce_Motion",
    ],
    review: {
      desktopReference: null,
      phoneCapture: null,
      tabletCapture: null,
      animationEvidence: null,
    },
  };
});
const report = {
  schema: 1,
  reference: "0834340cec5531650bfe78cd628628702e636987",
  version: "0.9.132",
  authority:
    "Owner explicitly requires all compatible interfaces, animations, transitions and sections.",
  countedAsCompletion: false,
  note: "This reproducible index is a review checklist, not proof of visual or functional parity. Existing native views and imported vectors still need complete flow and motion comparison on iPhone/iPad. Exclusions require a concrete PC dependency, not implementation difficulty.",
  excludedSections: ["games"],
  sections,
  crossCuttingInterfaces: [
    {
      id: "navigation",
      desktop: ["src/chrome/nav-items.tsx", "src/components/icons/nav-lottie.tsx"],
      native: [
        "ios/Harbor/Views/HarborShell.swift",
        "ios/Harbor/Views/SidebarNavigationIcon.swift",
        "ios/Harbor/Views/InterfaceSettingsView.swift",
      ],
      status: "pending_complete_reference_comparison",
    },
    {
      id: "onboarding",
      desktop: ["src/components/onboarding.tsx"],
      native: ["ios/Harbor/Views/AppWalkthroughView.swift"],
      status: "partial_native_walkthrough_requires_the_desktop_configuration_steps",
    },
    {
      id: "account_and_profiles",
      desktop: ["src/views/profile"],
      native: ["ios/Harbor/Views/AccountView.swift"],
      status: "pending_complete_reference_comparison",
    },
    {
      id: "player",
      desktop: ["src/views/player"],
      native: ["ios/Harbor/Player/PlayerView.swift"],
      status: "pending_complete_reference_comparison",
    },
    {
      id: "details",
      desktop: ["src/views/detail"],
      native: ["ios/Harbor/Views/DetailView.swift"],
      status: "pending_complete_reference_comparison",
    },
  ],
  cssAnimations: animations,
  vectorAnimations: vectors,
};
for (const entry of report.crossCuttingInterfaces) {
  for (const path of entry.desktop) assert.ok(statSync(join(reference, path)));
  for (const path of entry.native) assert.ok(statSync(join(root, path)).isFile());
}
writeFileSync(output, `${JSON.stringify(report, null, 2)}\n`);
process.stdout.write(
  `Indexed compatible section review targets and original CSS/vector animation definitions. No completion percentage is inferred.\n`,
);
