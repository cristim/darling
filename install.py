#!/usr/bin/env python3
import argparse,json,pathlib,shutil,subprocess
p=argparse.ArgumentParser();p.add_argument('--artifacts',required=True,type=pathlib.Path);p.add_argument('--image',required=True,type=pathlib.Path);a=p.parse_args();image=a.image.resolve()
for item in json.loads(a.artifacts.read_text()):
 source=pathlib.Path(item['source']);target=image/item['path']
 if not target.resolve().is_relative_to(image):raise RuntimeError('install artifact escapes private image')
 if item.get('kind','binary')=='binary':
  r=subprocess.run(['llvm-lipo','-archs',str(source)],capture_output=True,text=True,check=True)
  if 'arm64' not in r.stdout.split():raise RuntimeError('installation requires arm64')
 elif item['kind']!='swiftmodule':raise RuntimeError('unknown install artifact kind')
 target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
 if '.framework/' in item['path']:
  parts=target.parts;index=next(i for i,s in enumerate(parts) if s.endswith('.framework'));framework=pathlib.Path(*parts[:index+1]);name=framework.stem
  for path,to in [(framework/'Versions/Current','A'),(framework/name,'Versions/Current/'+name),(framework/'Modules','Versions/Current/Modules')]:
   if not path.exists() and not path.is_symlink():path.symlink_to(to)
