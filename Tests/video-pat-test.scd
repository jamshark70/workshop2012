(
var dir = thisProcess.nowExecutingPath.dirname.dirname;

"ps x | grep 'pd-extended' | grep -v 'grep'".unixCmd(e { |result|
	if(result > 0) {
		// pd is not running; load the video patch
		"xdg-open %".format((dir +/+ "common/frame-diff5.pd").escapeChar($ )).unixCmd;
	};
}, postOutput: true);  // postOutput is required to avoid "broken pipe"

// need outBus1 argument, though not used, to determine # of outputs
// that's annoying
SynthDef(\analog, { |outBus0, outBus1, freq = 440, dtune = 1.003, ffreq = 2000, rq = 0.1, amp = 0.1, pan = 0, gate = 1|
	var sig = Saw.ar(freq * [1, dtune]).sum * amp,
	eg = EnvGen.kr(Env.adsr(0.01, 0.1, 0.6, 0.25), gate, doneAction: 2);
	sig = RLPF.ar(sig, ffreq, rq);
	Out.ar(outBus0, Pan2.ar(sig, pan, eg));
}, metadata: (
	specs: (
		freq: \freq.asSpec,
		dtune: [0.95, 0.95.reciprocal, \exp, 0, 1.003].asSpec,
		ffreq: \freq.asSpec,
		rq: [1, 0.05, \exp].asSpec,
		amp: \amp.asSpec,
		pan: \bipolar.asSpec
	)
)).add;
)

h = Hadron.new;

HrPbindef(\tl).quant = 0;

// fine, more fucking crap that's not working
~saveAddr = s.addr;
~debugAddr = DebugNetAddr("127.0.0.1", 57110);

s.addr = ~debugAddr;
s.addr = ~saveAddr;

s.audioBusAllocator.debug;


p = h.alivePlugs[1];
p.modMapSets[\run].postcs.def.dumpByteCodes

p.insp

p = h.alivePlugs[4];
p.pollRate
p.synthInstance

o.free;
o = OSCFunc({ |msg| if(msg[1] == p.synthInstance.nodeID) { msg.postln } }, '/modValue', s.addr);