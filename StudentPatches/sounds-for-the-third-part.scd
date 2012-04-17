h = Hadron.new;

{ |input| var verbs = GVerb.ar(input, 100); Balance2.ar(verbs, #[-0.75, 0.75]).sum }

GVerb.ar(SinOsc.ar([440, 550]), 100).inspect

SynthDef(\percussive, { |outBus0 = 0, freq = 440, index = 0, /*gate = 1,*/ amp = 0.5, pan = 0, attack = 0.1, release = 0.1, ringtime = 1|
	var eg = EnvGen.kr(Env.perc(attack, release), /*gate,*/ doneAction: 2),
	sig = Pan2.ar(
		Ringz.ar(
			PinkNoise.ar(mul: { 0.5.rand }) +
			WhiteNoise.ar(mul: { 0.25.rand }) +
			BrownNoise.ar(mul: { 0.1.rand }),
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
		ringtime: [0.01, 5, \exp]
	)
)).add;


s.queryAllNodes

s.sendMsg(\n_trace, 1359)
