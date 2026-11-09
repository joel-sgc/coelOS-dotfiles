import sys,subprocess,os,signal,time
sys.path.insert(0,'.')
import miracast_source as m, wfd
src=sys.argv[1]; extra=sys.argv[2:]
a=m.build_parser().parse_args(["--source",src,"--pattern","smpte"]+extra)
cmd=m.build_pipeline(a,wfd.mode_of(7),2,8,"127.0.0.1",1028,5000,audio_on=True)
i=cmd.index("rtpmp2tpay"); cmd=cmd[:i-1]+["!","filesink","location=/tmp/claude-1000/-home-joelsgc--nixos/b6e04066-60de-469a-bb21-243fc4c21d1b/scratchpad/so.ts"]; cmd.insert(2,"-e")
env=dict(os.environ, PATH="/nix/store/kl4czq458fzrjzkbcq506bgiq658zwy8-gstreamer-1.26.11-bin/bin:"+os.environ["PATH"], GST_PLUGIN_SYSTEM_PATH_1_0=open("/tmp/claude-1000/-home-joelsgc--nixos/b6e04066-60de-469a-bb21-243fc4c21d1b/scratchpad/gstpath2.txt").read().strip())
p=subprocess.Popen(cmd,env=env,stderr=subprocess.DEVNULL); time.sleep(3); p.send_signal(signal.SIGINT); p.wait(timeout=15)
out=subprocess.run(["/nix/store/rr1fzxzzv5pnz5wm6yfcxinnwid64x71-ffmpeg-8.1.2-bin/bin/ffprobe","-v","quiet","-show_entries","packet=stream_index,pts_time","-of","csv=p=0","/tmp/claude-1000/-home-joelsgc--nixos/b6e04066-60de-469a-bb21-243fc4c21d1b/scratchpad/so.ts"],capture_output=True,text=True).stdout
first={}
for l in out.splitlines():
    si,t=l.strip().strip(',').split(',')[:2]
    first.setdefault(si,float(t))
print(src,extra[:2],"video first %.3f audio first %.3f -> video-audio = %+.0f ms"%(first['1'],first['0'],1000*(first['1']-first['0'])))
