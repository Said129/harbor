"""Retain the six approved anime checks while correcting only the UI selector."""
import argparse,hashlib,json,os,re,subprocess,urllib.error,urllib.request
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--source',required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
assert a.source=='cae4f81b2f387704d08eac3a1c165e0bcd5fba77'
subprocess.run(['git','fetch','--no-tags','--depth=1','origin',a.source],check=True)
assert not subprocess.check_output(['git','diff','--name-only',a.source,'HEAD','--','ios/Harbor','ios/project.yml','ios/HarborTests','ios/HarborIntegrationTests','harbor-core','harbor-ios-bridge']).strip(),'Do not change approved application/native/public code'
path='ios/HarborUITests/AnimeEpisodesNavigationTests.swift'
before=subprocess.check_output(['git','show',a.source+':'+path]).decode()
after=Path(path).read_text('utf-8')
assert after==before.replace("identifier == 'catalog-series'","identifier == 'catalog-media'",1),'Only repair the actual UI selector'
api='https://api.github.com/repos/'+os.environ['GITHUB_REPOSITORY'];headers={'Accept':'application/vnd.github+json','Authorization':'Bearer '+os.environ['GH_TOKEN'],'User-Agent':'Harbor-anime-ui-validation'}
def get(path):
 with urllib.request.urlopen(urllib.request.Request(api+path,headers=headers),timeout=45) as r:return json.load(r)
class NoRedirect(urllib.request.HTTPRedirectHandler):
 def redirect_request(self,*args):return None
run=get('/actions/runs/38816711339');assert run['head_sha']==a.source and run['status']=='completed' and run['conclusion']=='failure'
rows=[];failed=[]
for job in get('/actions/runs/38816711339/jobs?per_page=100')['jobs']:
 if job['conclusion']=='skipped':continue
 steps={s['name']:s['conclusion'] for s in job['steps']}
 for name in ['Run bridge and model tests on iPhone simulator','Run real addon services on iPhone simulator']:assert steps[name]=='success'
 request=urllib.request.Request(api+f'/actions/jobs/{job["id"]}/logs',headers=headers)
 try:response=urllib.request.build_opener(NoRedirect).open(request,timeout=45)
 except urllib.error.HTTPError as e:
  assert e.code==302 and e.headers['Location'].startswith('https://');response=urllib.request.urlopen(e.headers['Location'],timeout=60)
 with response:log=response.read(50*1024*1024).decode('utf-8')
 assert 'Unbalanced calls to begin/end appearance transitions' not in log
 for m in re.finditer(r"Test Case '-\[([^ ]+) ([^\]]+)\]' (passed|failed|skipped) \(([^)]+)\)",log):
  row=dict(case=m[1]+'/'+m[2],result=m[3],duration=m[4],run=38816711339,source=a.source,device='iPhone simulator')
  if m[3]=='passed':rows.append(row)
  else:failed.append(row)
assert len(rows)==6 and len(failed)==1 and failed[0]['case'].startswith('HarborUITests.AnimeEpisodesNavigationTests/')
assert sum(x['case'].startswith('HarborTests.AnimeEpisodeTests/') for x in rows)==5
assert sum(x['case'].startswith('HarborIntegrationTests.AnimeEpisodeLiveTests/') for x in rows)==1
guards={}
for path in subprocess.check_output(['git','ls-files','ios/Harbor','ios/project.yml','ios/HarborTests','ios/HarborIntegrationTests','harbor-core','harbor-ios-bridge'],text=True).splitlines():guards[path]=hashlib.sha256(Path(path).read_bytes()).hexdigest()
a.output.parent.mkdir(parents=True,exist_ok=True)
a.output.write_text(json.dumps(dict(source=os.environ['GITHUB_SHA'],previous_source=a.source,previous_run=38816711339,preserved_executions=rows,failed_observations=failed,identical_application_and_native_public_sha256=guards,scope='Only the ordinary iPhone anime-detail UI reruns after replacing an invalid catalog-series test selector with the actual catalog-media identifier. All production/native/public code is identical. Fresh ordinary guest preferences are prepared without repeating native tests.'),indent=2)+'\n','utf-8')
print('Retained five native checks and the actual public metadata/images case. Only the failed UI route remains.')
