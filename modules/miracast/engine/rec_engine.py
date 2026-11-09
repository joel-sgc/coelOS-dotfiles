import sys,subprocess,os,signal,time
sys.path.insert(0,'.')
import miracast_source as m, wfd
src,out=sys.argv[1],sys.argv[2]
extra=sys.argv[3:]
a=m.build_parser().parse_args(["--source",src,"--pattern","smpte"]+extra)
cmd=m.build_pipeline(a,wfd.mode_of(7),2,8,"127.0.0.1",1028,5000,audio_on=True)
i=cmd.index("rtpmp2tpay"); cmd=cmd[:i-1]+["!","filesink","location=/tmp/claude-1000/-home-joelsgc--nixos/b6e04066-60de-469a-bb21-243fc4c21d1b/scratchpad/"+out]; cmd.insert(2,"-e")
env=dict(os.environ, PATH="/nix/store/kl4czq458fzrjzkbcq506bgiq658zwy8-gstreamer-1.26.11-bin/bin:"+os.environ["PATH"], GST_PLUGIN_SYSTEM_PATH_1_0=open("/tmp/claude-1000/-home-joelsgc--nixos/b6e04066-60de-469a-bb21-243fc4c21d1b/scratchpad/gstpath2.txt").read().strip())
p=subprocess.Popen(cmd,env=env,stderr=subprocess.PIPE); time.sleep(6); p.send_signal(signal.SIGINT); p.communicate(timeout=20)
