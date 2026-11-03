const {Worker,isMainThread,workerData}=require('node:worker_threads'); const fs=require('fs');
function mk(memory,state){
  const dec=new TextDecoder();
  const wasi=new Proxy({},{get:(_,k)=>{
    if(k==='fd_write') return (fd,iov,n,out)=>{const m=new DataView(memory.buffer);let tot=0,s='';for(let i=0;i<n;i++){const p=m.getUint32(iov+i*8,true),l=m.getUint32(iov+i*8+4,true);s+=dec.decode(new Uint8Array(memory.buffer.slice(p,p+l)));tot+=l}m.setUint32(out,tot,true);(fd===2?process.stderr:process.stdout).write(s);return 0};
    if(k==='proc_exit') return c=>{throw new Error('proc_exit '+c)};
    return ()=>0;}});
  return {env:{memory},wasi_snapshot_preview1:wasi,wasi:{'thread-spawn':(arg)=>{const tid=++state.n;new Worker(__filename,{workerData:{mod:state.mod,memory,tid,arg,n:state.n}});return tid;}}};
}
const mod=isMainThread?new WebAssembly.Module(fs.readFileSync(process.argv[2])):workerData.mod;
const memory=isMainThread?new WebAssembly.Memory({initial:300,maximum:1280,shared:true}):workerData.memory;
const state={mod,n:isMainThread?0:workerData.n};
const inst=new WebAssembly.Instance(mod,mk(memory,state));
if(isMainThread){ try{ inst.exports._start(); }catch(e){ console.error('main ended:',e.stack);} void 0;}
else { try{ inst.exports.wasi_thread_start(workerData.tid,workerData.arg);}catch(e){console.error('thread ended:',e.message)} }
