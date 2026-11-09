import sys,subprocess,os,signal,time
sys.path.insert(0,'.')
import miracast_source as m, wfd
src=sys.argv[1]; extra=sys.argv[2:]
a=m.build_parser().parse_args(["--source",src,"--pattern","smpte"]+extra)
cmd=m.build_pipeline(a,wfd.mode_of(7),2,8,"127.0.0.1",1028,5000,audio_on=True)
i=cmd.index("rtpmp2tpay"); cmd=cmd[:i-1]+["!","filesink","location=/tmp/claude-1000/-home-joelsgc--nixos/b6e04066-60de-469a-bb21-243fc4c21d1b/scratchpad/so3.ts"]; cmd.insert(2,"-e")
env=dict(os.environ, PATH="/nix/store/kl4czq458fzrjzkbcq506bgiq658zwy8-gstreamer-1.26.11-bin/bin:"+os.environ["PATH"], GST_PLUGIN_SYSTEM_PATH_1_0=open("/tmp/claude-1000/-home-joelsgc--nixos/b6e04066-60de-469a-bb21-243fc4c21d1b/scratchpad/gstpath2.txt").read().strip())
p=subprocess.Popen(cmd,env=env,stderr=subprocess.DEVNULL); time.sleep(6); p.send_signal(signal.SIGINT); p.wait(timeout=15)
d=open("/tmp/claude-1000/-home-joelsgc--nixos/b6e04066-60de-469a-bb21-243fc4c21d1b/scratchpad/so3.ts",'rb').read()
first={}; cnt={0x1011:0,0x1100:0}; order=[]
for i in range(0,len(d)-188,188):
    p=d[i:i+188]; pid=((p[1]&0x1f)<<8)|p[2]; afc=(p[3]>>4)&3; off=4
    if afc&2: off=5+p[4]
    if pid in cnt and (p[1]&0x40) and (afc&1) and p[off:off+3]==b'\x00\x00\x01' and p[off+7]&0x80:
        q=p[off+9:off+14]
        pts=(((q[0]>>1)&7)<<30)|(q[1]<<22)|((q[2]>>1)<<15)|(q[3]<<7)|(q[4]>>1)
        cnt[pid]+=1
        if pid not in first: first[pid]=pts/90000
        if len(order)<8: order.append('V' if pid==0x1011 else 'A')
print("%-8s %-45s video-first minus audio-first PTS = %+4.0f ms | first PES order %s | video PES %d audio PES %d"%(src," ".join(extra)[:45],1000*(first[0x1011]-first[0x1100]),''.join(order),cnt[0x1011],cnt[0x1100]))
