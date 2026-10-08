#!/usr/bin/env python3
"""Recover the verified private commands into a full strict build/install manifest."""
from pathlib import Path
import json,shlex,subprocess
base=Path('/home/cristi/tmp-opencode/az120-swiftui-inputs'); diag=Path('/home/cristi/tmp-opencode/az120-swiftui-appzapper-diagnostic');runtime='/home/cristi/tmp-opencode/az120-app-image/usr/local/libexec/darling'
replacements=[(str(diag),'{workspace}/swiftui'),(str(base/'dependency-build'),'{workspace}/deps'),(str(base/'native-build'),'{workspace}/native'),(str(base/'shim-build'),'{workspace}/shim'),(str(base/'linked'),'{workspace}/linked'),(runtime,'{runtime_root}')]
def subst(s):
 for old,new in replacements:s=s.replace(old,new)
 return s
def args(p):return [subst(s) for s in shlex.split(p.read_text())]
tool='/home/cristi/src/swift-darling/toolchain-linux/swift-6.3.3-RELEASE-ubuntu24.04-aarch64/usr/bin/'
env={'LD_LIBRARY_PATH':'/home/cristi/src/swift-darling/toolchain-linux/compat-lib','SWIFT_BACKTRACE':'enable=no'}
targets=[];generated=[]
for item in json.loads((base/'dependency-build/source-build-manifest.json').read_text()):
 a=args(Path(item['response']));name=item['module'];target={'name':name+'-source','argv':[tool+'swiftc',*a],'env':env,'inputs':item['sources'],'outputs':['{workspace}/deps/objects/'+name+'.o','{workspace}/deps/modules/'+name+'.swiftmodule']}
 if name.endswith('Shims') and name!='OpenCoreGraphicsShims':target['inputs'].append('{workspace}/deps/modules/'+name.removesuffix('Shims')+'.swiftmodule')
 targets.append(target)
for folder in ['native-build','shim-build']:
 for rsp in sorted((base/folder).glob('*.args')):
  a=args(rsp);obj=a[a.index('-o')+1];source=a[a.index('-c')+1];targets.append({'name':folder+'-'+rsp.stem,'argv':[tool+'clang',*a],'env':env,'inputs':[source],'outputs':[obj],'depfile':obj+'.d'})
config=base/'native-build/generated/swift/Runtime/CMakeConfig.h';generated.append({'path':'{workspace}/native/generated/swift/Runtime/CMakeConfig.h','contents':config.read_text()})
# The driver reads the output file map by name; generate it in the new workspace.
generated.append({'path':'{workspace}/swiftui/output-file-map.json','contents':subst((diag/'output-file-map.json').read_text())})
a=args(diag/'compile-source-backend.args');sources=[s for s in a if s.endswith('.swift')];objects=[subst(v['object']) for v in json.loads((diag/'output-file-map.json').read_text()).values()]
depmodules=[f'{{workspace}}/deps/modules/{m["module"]}.swiftmodule' for m in json.loads((base/'dependency-build/source-build-manifest.json').read_text())]
targets.append({'name':'SwiftUI-source','argv':[tool+'swiftc',*a],'env':env,'inputs':sources+depmodules,'outputs':objects+['{workspace}/swiftui/modules/SwiftUI.swiftmodule']})
links=[]
for name in ['Symbols','AttributeGraph','RenderBox','CombineFoundation','Logging','OpenObservation','OpenCoreGraphicsShims','SwiftUI']:
 command=[subst(s) for s in json.loads((base/'linked'/f'{name}-link-command.json').read_text())];output=command[command.index('-o')+1];inputs=[s for s in command if s.endswith(('.o','.dylib','.a')) and s!=output and ':' not in s and (s.startswith('/home/') or s.startswith('{workspace}') or s.startswith('{runtime_root}'))]
 targets.append({'name':name+'-link','argv':command,'inputs':inputs,'outputs':[output]});links.append(name+'-link')
artifacts=[]
for r in json.loads((base/'linked/link-results.json').read_text()):artifacts.append({'source':subst(r['output']),'path':r['install_name'].lstrip('/')})
# Install compiler modules with the linked runtime; clients need these imports.
for item in json.loads((base/'dependency-build/source-build-manifest.json').read_text()):
 name=item['module']
 destination=('System/Library/Frameworks/Symbols.framework/Versions/A/Modules' if name=='Symbols' else 'usr/lib/swift')
 artifacts.append({'source':'{workspace}/deps/modules/'+name+'.swiftmodule','path':destination+'/'+name+'.swiftmodule/arm64-apple-macos.swiftmodule','kind':'swiftmodule'})
artifacts.append({'source':'{workspace}/swiftui/modules/SwiftUI.swiftmodule','path':'System/Library/Frameworks/SwiftUI.framework/Versions/A/Modules/SwiftUI.swiftmodule/arm64-apple-macos.swiftmodule','kind':'swiftmodule'})
generated.append({'path':'{workspace}/install-artifacts.json','contents':json.dumps(artifacts,indent=2)})
targets.append({'name':'SwiftUI-install','argv':['python3',str(Path(__file__).with_name('install.py')),'--artifacts','{workspace}/install-artifacts.json','--image','{workspace}/image'],'inputs':[a['source'] for a in artifacts]+[str(Path(__file__).with_name('install.py'))], 'outputs':['{workspace}/image/'+a['path'] for a in artifacts]})
sources=[]
for repo in ['az120-swiftui-appzapper-source','az120-openattributegraph-source','az120-openrenderbox-source','az120-openobservation-source','az120-opencoregraphics-source','az120-swift-log-source','az120-symbols-source']:
 path=Path('/home/cristi/tmp-opencode')/repo;head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=path,text=True).strip();sources.append({'path':str(path),'commit':head})
manifest={'schema_version':1,'architecture':'arm64','integration':{'link_targets':links,'install_targets':['SwiftUI-install'],'required_framework':'System/Library/Frameworks/SwiftUI.framework/Versions/A/SwiftUI','runtime_ready':False},'sources':sources,'generated_inputs':generated,'targets':targets,'note':'Strict linking currently fails on absent runtime APIs; compile-only success is not full integration success.'}
Path(__file__).with_name('full-source-inputs.json').write_text(json.dumps(manifest,indent=2)+'\n');print('Prepared full strict manifest:',len(targets),'targets')
