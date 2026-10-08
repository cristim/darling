#!/usr/bin/env python3
"""Build a pinned SwiftUI source closure in a private workspace; never install in the input runtime."""
import argparse, hashlib, json, os, pathlib, shlex, subprocess, sys, time
p=argparse.ArgumentParser()
p.add_argument('--inputs',required=True,type=pathlib.Path)
p.add_argument('--runtime-root',required=True,type=pathlib.Path)
p.add_argument('--workspace',required=True,type=pathlib.Path)
p.add_argument('--jobs',type=int,default=2,choices=[1,2])
p.add_argument('--lock',default='/tmp/agent-locks/darling-heavy-build.lock')
p.add_argument('--configure-only',action='store_true')
a=p.parse_args(); root=a.runtime_root.resolve();ws=a.workspace.resolve()
if ws==root or root in ws.parents or ws==pathlib.Path('/'):
 p.error('workspace must be separate from the read-only runtime root')
config=json.loads(a.inputs.read_text())
if config.get('schema_version')!=1 or config.get('architecture')!='arm64':p.error('schema 1 and architecture arm64 required; x86_64 unsupported')
ws.mkdir(parents=True,exist_ok=True)
def expand(s):return s.replace('{workspace}',str(ws)).replace('{runtime_root}',str(root))
def stable_write(path,text):
 if not path.exists() or path.read_text()!=text:path.write_text(text)
def q(s):return shlex.quote(s)
def esc(s):return s.replace('$','$$').replace(' ','$ ').replace(':','$:')
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
result={'schema_version':1,'architecture':'arm64','inputs_sha256':sha(a.inputs),'runtime_root':str(root),'workspace':str(ws),'status':'configured','source_provenance':[],'artifacts':[],'input_files':[],'actual_app_verified':False}
for source in config.get('sources',[]):
 path=pathlib.Path(source['path']);head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=path,text=True).strip()
 if head!=source['commit']:raise RuntimeError(f'pin mismatch: {path}')
 status=subprocess.check_output(['git','status','--porcelain'],cwd=path,text=True)
 result['source_provenance'].append({'path':str(path),'commit':head,'status':status})
 if status and not source.get('allow_recorded_changes',False):raise RuntimeError(f'dirty source: {path}')
ninja=['rule run\n  command = $command > $log 2>&1\n  description = $label\n'];alloutputs=[]
for target in config['targets']:
 name=target['name'];outputs=[expand(s) for s in target['outputs']];inputs=[expand(s) for s in target['inputs']]
 for f in outputs:pathlib.Path(f).parent.mkdir(parents=True,exist_ok=True)
 for filename in inputs:
  f=pathlib.Path(filename)
  if f.is_file():result['input_files'].append({'path':str(f),'sha256':sha(f),'bytes':f.stat().st_size})
 argv=[expand(s) for s in target['argv']];env=['env']+[k+'='+expand(v) for k,v in sorted(target.get('env',{}).items())]
 command=shlex.join(env+argv);signature=ws/(name+'.command');stable_write(signature,command+'\n')
 ninja.append('build '+' '.join(map(esc,outputs))+': run '+' '.join(map(esc,inputs+[str(signature)]))+f'\n  command = {command.replace(chr(36),chr(36)*2)}\n  log = {ws/name}.log\n  label = {name}\n');alloutputs+=outputs
ninja.append('default '+' '.join(map(esc,alloutputs))+'\n');stable_write(ws/'build.ninja','\n'.join(ninja))
if not a.configure_only:
 started=time.time();log=ws/'build.log'
 with log.open('w') as f:r=subprocess.run(['flock',a.lock,'ninja','-C',str(ws),'-j'+str(a.jobs)],stdout=f,stderr=subprocess.STDOUT)
 result.update(status='passed' if r.returncode==0 else 'failed',build_exit=r.returncode,elapsed_seconds=time.time()-started,build_log=str(log),incremental_no_work='no work to do' in log.read_text())
 for path in alloutputs:
  f=pathlib.Path(path)
  if f.is_file():result['artifacts'].append({'path':str(f),'sha256':sha(f),'bytes':f.stat().st_size})
else:r=None
(ws/'result.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'status':result['status'],'result':str(ws/'result.json')}))
sys.exit(r.returncode if r else 0)
