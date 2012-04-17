h = Hadron.new;

{ |input| var verbs = GVerb.ar(input, 100); Balance2.ar(verbs, #[-0.75, 0.75]).sum }

GVerb.ar(SinOsc.ar([440, 550]), 100).inspect

SynthDef(\percussive, { |outBus0 = 0, freq = 440, index = 0, /*gate = 1,*/ amp = 0.5, pan = 0, attack = 0.1, release = 0.1, ringtime = 1|
	var eg = EnvGen.kr(Env.perc(attack, release), /*gate,*/ doneAction: 2),
	sig = Pan2.ar(
		Ringz.ar(
			PinkNoise.ar(mul: Rand(0, 0.5)) +
			WhiteNoise.ar(mul: Rand(0, 0.25)) +
			BrownNoise.ar(mul: Rand(0, 0.1)),
			freq, ringtime  // Line.kr(440, 880, 5)
		),
		pan,
		eg * amp
	);
	Out.ar(outBus0, sig);
}, metadata: (
	numOutputs: 2,
	specs: (
		freq: \freq.asSpec,
		index: \index.asSpec,
		amp: \amp.asSpec,
		pan: \pan.asSpec,
		attack: [0.01, 1, \exp],
		release: [0.01, 1, \exp],
		ringtime: [0.01, 15, \exp]
	)
)).add;


s.queryAllNodes

s.sendMsg(\n_trace, 1359)





SynthDef(\bufGrainPan, { |start, gate = 1, bufnum, pan, rate = 1, amp = 1,
		attack = 0.001, decay = 0.02, outBus0|
	var sig;
	sig = PlayBuf.ar(1, bufnum, rate * BufRateScale.kr(bufnum), 1, start * BufFrames.kr(bufnum), 0)
		* EnvGen.kr(Env.asr(attack, 1, decay), gate, doneAction:2);
	Out.ar(outBus0, Pan2.ar(sig, pan, amp));
}, metadata: (
	numOutputs: 2,
	specs: (
		start: #[0, 1],
		time: #[0.01, 10],
		bufnum: #[0, 128],
		pan: #[-1, 1],
		amp: \amp,
		attack: #[0.001, 1.0, \exp],
		decay: #[0.001, 1.0, \exp],
		rate: #[0.1, 10, \exp]
	)
)).add;


