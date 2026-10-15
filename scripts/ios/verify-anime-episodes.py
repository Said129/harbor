"""Limit the anime correction to the affected code and retain unrelated build 90 evidence."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import urllib.request

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--source',required=True)
p.add_argument('--output',type=Path,required=True)
a=p.parse_args()
assert a.source=='1593af9c24fbad3513fbd192f7aa0e053be3e9ba'
subprocess.run(['git','fetch','--no-tags','--depth=1','origin',a.source],check=True)
changed=set(subprocess.check_output(['git','diff','--name-only',a.source,'HEAD','--','ios/Harbor','ios/project.yml','harbor-core','harbor-ios-bridge'],text=True).splitlines())
allowed={'ios/Harbor/Services/AnimeEpisodeService.swift','ios/Harbor/Models/Media.swift','ios/Harbor/ViewModels/DetailModel.swift','ios/Harbor/Views/DetailView.swift','ios/Harbor/Views/EpisodeList.swift','ios/Harbor/Views/PlayerEpisodesView.swift','ios/project.yml'}
assert changed==allowed,'Reassess any changes outside anime episode metadata/presentation'
guards={}
for path in subprocess.check_output(['git','ls-tree','-r','--name-only',a.source,'--','ios/HarborTests','ios/HarborIntegrationTests','ios/HarborUITests'],text=True).splitlines():
 before=subprocess.check_output(['git','show',a.source+':'+path])
 after=Path(path).read_bytes().replace(b'\r\n',b'\n')
 assert before==after,'Previously approved test changed: '+path
 guards[path]=hashlib.sha256(after).hexdigest()
for path in ['ios/Harbor/Services/HarborService.swift','ios/Harbor/Services/StreamRequestPolicy.swift','ios/Harbor/Player/EpisodeSequence.swift','ios/Harbor/Models/Library.swift','ios/Harbor/Models/LibrarySnapshot.swift','ios/Harbor/Services/MediaMetadataStore.swift','ios/Harbor/Services/HTTPClient.swift']:
 before=subprocess.check_output(['git','show',a.source+':'+path]); after=Path(path).read_bytes().replace(b'\r\n',b'\n')
 assert before==after,'Playback/account/metadata lookup behavior must remain intact: '+path
 guards[path]=hashlib.sha256(after).hexdigest()
before=subprocess.check_output(['git','show',a.source+':ios/Harbor/Models/Media.swift']).decode()
after=Path('ios/Harbor/Models/Media.swift').read_text('utf-8')
addition='    var displaySeason: Int?\n    var displayEpisode: Int?\n    var listedSeason: Int? { displaySeason ?? season }\n    var listedEpisode: Int? { displayEpisode ?? episode }\n'
assert after.replace(addition,'',1)==before,'Only backward-compatible presentation fields may change in the model'
project=subprocess.check_output(['git','show',a.source+':ios/project.yml']).decode()
assert Path('ios/project.yml').read_text('utf-8')==project.replace('CFBundleVersion: "90"','CFBundleVersion: "91"',1)
api='https://api.github.com/repos/'+os.environ['GITHUB_REPOSITORY']
headers={'Accept':'application/vnd.github+json','Authorization':'Bearer '+os.environ['GH_TOKEN'],'User-Agent':'Harbor-anime-episode-validation'}
def get(path):
 with urllib.request.urlopen(urllib.request.Request(api+path,headers=headers),timeout=45) as r:return json.load(r)
run=get('/actions/runs/38755836388')
assert run['head_sha']==a.source and run['status']=='completed' and run['conclusion']=='success'
jobs=get('/actions/runs/38755836388/jobs?per_page=100')['jobs']
assert any(j['conclusion']=='success' and any(s['name']=='Package and verify unsigned iPhone IPA' and s['conclusion']=='success' for s in j['steps']) for j in jobs)
a.output.parent.mkdir(parents=True,exist_ok=True)
a.output.write_text(json.dumps(dict(source=os.environ['GITHUB_SHA'],previous_source=a.source,previous_run=38755836388,unchanged_guards_sha256=guards,scope='Unrelated build 90 functionality retains its recorded validation. This is not a new approval of changed episode presentation. Only AnimeEpisodeTests, actual Super metadata/images and ordinary anime-detail UI execute; full historical suites do not repeat.',affected='Continuous display order, episode stills, safe partial mappings, old Codable compatibility, raw streams/watched/resume/adjacency preservation, detail/player episode presentation.'),indent=2)+'\n','utf-8')
print('Prior release and unchanged underlying services/test files verified. Only affected anime checks execute.')
