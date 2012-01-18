(
// in 3.5, you can 'add' a SynthDef before the server is booted!
// it will be sent automatically on boot - sweet!
SynthDef(\analog, { |outBus0, outBus1, freq = 440, dtune = 1.003, ffreq = 2000, rq = 0.1, amp = 0.1|
	var sig = Saw.ar(freq * [1, dtune], amp).sum;
	sig = RLPF.ar(sig, ffreq, rq);
	Out.ar([outBus0, outBus1], sig);
}, metadata: (
	specs: (
		freq: \freq.asSpec,
		dtune: [0.95, 0.95.reciprocal, \exp, 0, 1.003].asSpec,
		ffreq: \freq.asSpec,
		rq: [1, 0.05, \exp].asSpec,
		amp: \amp.asSpec
	)
)).add;

SynthDef(\kr2ar, { |outBus0, value|
	Out.ar(outBus0, K2A.ar(value));
}, metadata: (
	specs: (
		value: [0, 1].asSpec
	)
)).add;

h = Hadron.new;
)

// too lazy to open pd by hand every time
(
var dir = thisProcess.nowExecutingPath.dirname.dirname;

"ps x | grep 'pd-extended' | grep -v 'grep'".unixCmd(e { |result|
	if(result > 0) {
		// pd is not running; load the video patch
		"xdg-open %".format((dir +/+ "common/frame-diff5.pd").escapeChar($ )).unixCmd;
	};
}, postOutput: true);  // postOutput is required to avoid "broken pipe"
)

// File.exists((thisProcess.nowExecutingPath.dirname +/+ "../common/frame-diff5.pd").escapeChar($ ))

// save time in the video capture
HadronStateLoad(h).loadState("~/share/SC/hadron.git/TestPatches/analog1.hadron".standardizePath);


BP.freeAll;


// scratchpad for functions
{ |pctFast = 0|
	var notFast = (1 - pctFast) * 0.5,
	rhythm = Dstutter(2, Dwrand([0.1, 0.2, 0.4], [pctFast, notFast, notFast], inf)),
	trig = TDuty.kr(rhythm, 0, rhythm),
	dur = Latch.kr(trig, trig);
	[
		TExpRand.kr(130, 260, trig) * (0.4 / dur),
		Lag.kr(TExpRand.kr(500, 12000, trig), 0.02),
		Lag.kr(TExpRand.kr(0.05, 0.25, trig), 0.02),
		trig
	]
}