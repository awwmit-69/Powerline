"""Package an existing Flutter release as a small Worker module; no secret inputs."""
import base64
import gzip
import json
import mimetypes
import pathlib
import sys

root=pathlib.Path(sys.argv[1]).resolve()
target=pathlib.Path(sys.argv[2]).resolve()
files={}
for path in root.rglob('*'):
    if not path.is_file():
        continue
    relative=path.relative_to(root).as_posix()
    # Flutter's loader already uses the engine-revision-pinned public renderer CDN.
    if relative.startswith('canvaskit/'):
        continue
    mime=mimetypes.guess_type(path.name)[0] or 'application/octet-stream'
    if path.suffix=='.js':
        mime='application/javascript'
    files['/'+relative]=[mime,base64.b64encode(gzip.compress(path.read_bytes(),mtime=0)).decode()]
source='const files='+json.dumps(files,separators=(',',':'))+';\n'
source+='''const cache=new Map();
export async function serveEmbedded(request){
  if(!['GET','HEAD'].includes(request.method))return new Response('Method not allowed',{status:405});
  let path=new URL(request.url).pathname;
  if(path==='/')path='/index.html';
  if(!files[path]){if(path.startsWith('/assets/')||path.includes('.'))return new Response('Not found',{status:404});path='/index.html';}
  const [mime,encoded]=files[path];
  if(!cache.has(path)){const zipped=Uint8Array.from(atob(encoded),c=>c.charCodeAt(0));cache.set(path,new Uint8Array(await new Response(new Blob([zipped]).stream().pipeThrough(new DecompressionStream('gzip'))).arrayBuffer()));}
  return new Response(request.method==='HEAD'?null:cache.get(path),{headers:{'Content-Type':mime,'Cache-Control':'private, no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer','X-Frame-Options':'DENY'}});
}
'''
target.parent.mkdir(parents=True,exist_ok=True)
target.write_text(source)
print(json.dumps({'asset_count':len(files),'module_bytes':len(source.encode()),'gzip_bytes':len(gzip.compress(source.encode()))}))
