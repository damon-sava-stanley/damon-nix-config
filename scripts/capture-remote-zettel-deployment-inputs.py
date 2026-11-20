import datetime, json, pathlib, sys
archive=json.loads(pathlib.Path(sys.argv[1]).read_text())
lock=json.loads((pathlib.Path(archive['path'])/'flake.lock').read_text())
paths={lock['root']:archive['path']}
def collect(name,arch):
 for key,value in lock['nodes'][name].get('inputs',{}).items():
  if not isinstance(value,str) or key not in arch.get('inputs',{}): continue
  child=arch['inputs'][key]; paths[value]=child['path']; collect(value,child)
collect(lock['root'],archive)
def nix(v):
 if isinstance(v,str): return json.dumps(v)
 if isinstance(v,bool): return 'true' if v else 'false'
 if isinstance(v,int): return str(v)
 if isinstance(v,list): return '[ '+' '.join(nix(x) for x in v)+' ]'
 if isinstance(v,dict): return '{ '+' '.join(nix(k)+' = '+nix(val)+';' for k,val in v.items())+' }'
 raise ValueError(v)
lines=['{','rootName = '+nix(lock['root'])+';','graph = {']
for name,node in lock['nodes'].items():
 source={'outPath':'__PATH__'}
 source.update({k:v for k,v in node.get('locked',{}).items() if k in ['narHash','rev','revCount','lastModified']})
 if 'rev' in source: source['shortRev']=source['rev'][:7]
 if 'lastModified' in source: source['lastModifiedDate']=datetime.datetime.fromtimestamp(source['lastModified'],datetime.timezone.utc).strftime('%Y%m%d%H%M%S')
 data={'sourceInfo':source,'inputs':node.get('inputs',{}),'flake':node.get('flake',True)}
 if name not in paths: raise ValueError('Missing captured source: '+name)
 entry=nix(data).replace('"__PATH__"','builtins.storePath '+nix(paths[name]))
 lines.append(nix(name)+' = '+entry+';')
lines+=['};','}']
pathlib.Path(sys.argv[2]).write_text('\n'.join(lines)+'\n')

# Explicit dependency list permits pure evaluation of the capture package.
pathlib.Path(sys.argv[2]).with_name("captured-sources.json").write_text(json.dumps(sorted(set(paths.values())), indent=2)+"\n")
