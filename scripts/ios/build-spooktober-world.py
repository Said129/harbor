"""Package the pinned original seasonal world, without remote code or restricted fonts."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile

p=argparse.ArgumentParser();p.add_argument("--reference",type=Path,required=True);a=p.parse_args()
repo=Path(__file__).resolve().parents[2];reference=a.reference.resolve()
assert json.loads((reference/"package.json").read_text("utf-8"))["version"]=="0.9.132"
original=reference/"public/spooktober"
revision="0834340cec5531650bfe78cd628628702e636987"
manifest_data=subprocess.check_output(["git","show",revision+":public/spooktober/runtime-manifest.json"],cwd=repo)
manifest=json.loads(manifest_data)
assert manifest["fileCount"]==131 and manifest["totalBytes"]==4593083
inputs={};input_data={};normalized=[];stale=[]
requests="\n".join(revision+":public/spooktober/"+entry["path"] for entry in manifest["files"])+"\n"
objects=subprocess.check_output(["git","cat-file","--batch"],input=requests.encode(),cwd=repo)
cursor=0
for entry in manifest["files"]:
    path=Path(entry["path"])
    assert not path.is_absolute() and ".." not in path.parts
    end=objects.index(b"\n",cursor);header=objects[cursor:end].split()
    assert len(header)==3 and header[1]==b"blob"
    size=int(header[2]);cursor=end+1;data=objects[cursor:cursor+size];cursor+=size+1
    checkout=(original/path).read_bytes()
    if checkout!=data:
        assert path.suffix in {".json",".js",".css",".html",".svg"} and checkout.replace(b"\r\n",b"\n")==data,entry["path"]
        normalized.append(entry["path"])
    digest=hashlib.sha256(data).hexdigest()
    if digest!=entry["sha256"] or len(data)!=entry["bytes"]:stale.append(entry["path"])
    inputs[entry["path"]]=digest;input_data[entry["path"]]=data
assert cursor==len(objects)
files={}
roots={"native-entry.js","native-environment.js","native-runtime.js","native-layout.html","native-styles.css","credits.html"}
for entry in manifest["files"]:
    path=entry["path"]
    if path in roots or path.endswith(".json") or path.startswith("assets/") and not path.startswith("assets/fonts/"):
        files["spooktober/"+path]=input_data[path]
# Keep the two original family names, using fonts already redistributed by iOS.
# The original Nightmare metadata says personal use only. No original font is copied.
files["spooktober/native-fonts.json"]=(json.dumps([
    dict(family="SpookJakarta",source="url('/native-fonts/Inter.ttf')",descriptors=dict(weight="100 900",style="normal",display="swap")),
    dict(family="SpookNightmare",source="url('/native-fonts/Fraunces.ttf')",descriptors=dict(weight="100 900",display="swap"))
],indent=2)+"\n").encode()
for name in ["SpooktoberWorldHost.html","SpooktoberWorldHost.js"]:
    files[name.replace("SpooktoberWorldHost","index")]=(repo/"scripts/ios"/name).read_bytes()
archive=repo/"ios/Harbor/SpooktoberWorld.zip"
with zipfile.ZipFile(archive,"w",compression=zipfile.ZIP_DEFLATED,compresslevel=9) as package:
    for path,data in sorted(files.items()):
        info=zipfile.ZipInfo(path,date_time=(2026,10,3,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED;info.external_attr=0o100644<<16
        package.writestr(info,data)
output=dict(schema=1,reference="0834340cec5531650bfe78cd628628702e636987",
    original_manifest_sha256=hashlib.sha256(manifest_data).hexdigest(),
    original_files_verified=131,original_inputs=inputs,normalized_checkout_text_paths=normalized,
    upstream_manifest_differs_from_committed_blobs=stale,original_runtime_and_layout_preserved=True,
    original_fonts_copied=False,exact_original_typography=False,remote_code_updates=False,
    files={path:dict(bytes=len(data),sha256=hashlib.sha256(data).hexdigest()) for path,data in sorted(files.items())},
    zip_sha256=hashlib.sha256(archive.read_bytes()).hexdigest(),zip_bytes=archive.stat().st_size)
(repo/"ios/Harbor/SpooktoberWorldAssets.json").write_text(json.dumps(output,indent=2)+"\n","utf-8")
print(json.dumps(dict(files=len(files),bytes=sum(map(len,files.values())),zip_bytes=output["zip_bytes"],zip_sha256=output["zip_sha256"],original_fonts_copied=False)))
