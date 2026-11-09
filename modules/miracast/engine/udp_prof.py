import sys,subprocess,os,signal,time,socket,threading,statistics
sys.path.insert(0,'.')
import miracast_source as m, wfd
src=sys.argv[1]; extra=sys.argv[2:]
s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.bind(("127.0.0.1",19444)); s.settimeout(0.5)
a=m.build_parser().parse_args(["--source",src,"--pattern","smpte"]+extra)
cmd=m.build_pipeline(a,wfd.mode_of(7),2,8,"127.0.0.1",19444,5001,audio_on=True)
env=dict(os.environ, PATH="/nix/store/kl4czq458fzrjzkbcq506bgiq658zwy8-gstreamer-1.26.11-bin/bin:"+os.environ["PATH"], GST_PLUGIN_SYSTEM_PATH_1_0=open("/tmp/claude-1000/-home-joelsgc--nixos/b6e04066-60de-469a-bb21-243fc4c21d1b/scratchpad/gstpath2.txt").read().strip())
t0=time.time(); p=subprocess.Popen(cmd,env=env,stderr=subprocess.DEVNULL)
ev=[]; vfirst=[]; vidx=[]; rtp=[]
while time.time()-t0<9:
    try:
        d=s.recv(2000); ev.append((time.time()-t0,len(d))); rtp.append((int.from_bytes(d[2:4],"big"),int.from_bytes(d[4:8],"big"),d[1],int.from_bytes(d[8:12],"big")))
        for k in range(12,len(d)-187,188):
            pid=((d[k+1]&0x1f)<<8)|d[k+2]
            if pid==0x1011 and not vfirst: vfirst.append(time.time()-t0)
            if pid==0x1011 and (d[k+1]&0x40) and len(vidx)<1 and d[k+3]&0x20: pass
    except socket.timeout: pass
p.send_signal(signal.SIGINT); p.wait(timeout=15)
print(src,extra,"packets",len(ev),"first at %.2fs"%ev[0][0],"first VIDEO ts-packet at %.2fs"%(vfirst[0] if vfirst else -1))
bins={}
for t,n in ev: bins[int(t*10)]=bins.get(int(t*10),0)+n
vals=[bins.get(i,0)/1000 for i in range(int(ev[0][0]*10)+5,90)]
gaps=[b[0]-a[0] for a,b in zip(ev,ev[1:])]
print("  KB per 100ms window: median %.1f p95 %.1f max %.1f min %.1f"%(statistics.median(vals),sorted(vals)[int(len(vals)*.95)],max(vals),min(vals)),"| max packet gap %.0f ms"%(1000*max(gaps)))

seqs=[r[0] for r in rtp]; tss=[r[1] for r in rtp]
gaps_seq=sum(1 for a,b in zip(seqs,seqs[1:]) if (b-a)%65536!=1)
back=sum(1 for a,b in zip(tss,tss[1:]) if ((b-a)%2**32)>2**31)
print("  RTP: PT",set(r[2]&0x7f for r in rtp),"marker-bit set on",sum(1 for r in rtp if r[2]&0x80),"pkts | seq gaps",gaps_seq,"| ts going backwards",back,"| ts first %d last %d (span %.2fs @90k)"%(tss[0],tss[-1],((tss[-1]-tss[0])%2**32)/90000),"| distinct ssrc",len(set(r[3] for r in rtp)))
