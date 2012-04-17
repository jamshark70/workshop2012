(
s.waitForBoot {
	PR(\funcCmd).clone {
		~setDoneSignal = {
			~doneSignal = true;
		};
		~func = {
			~hadron = Hadron.new;
			HadronStateLoad(~hadron).addFunc(e { ~stop.() }).loadState(~path);
			Library.put(\hadronCmd, ~id, ~hadron)
		};
	} => PR(\hadronCmd);

	if(thisProcess.platform.name == \windows) {
		~dir = HrVideoData.filenameSymbol.asString.dirname.dirname.dirname +/+ "StudentPatches";
	} {
		~dir = thisProcess.nowExecutingPath.dirname;
	};

	MIDIClient.init;
	MIDIIn.connectAll;
};
)

(
var upd;

t.stop;

t = TLSequenceIterator([
	// load synths, convolution IR buffer
	funcCmd: (
		setDoneSignal: { ~doneSignal = true },
		func: {
			var bufLoadFailed = true, cond = Condition.new;
			fork {
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

				SynthDef(\impulses, { |outBus0, freq = 440, det = 1.003, topFreq = 12000,
					gate = 1, db = -60,
					attack = 0.1, decay = 0.15, susLevel = 0.5, release = 0.25|
					var sig = Blip.ar(freq * [1, det], trunc(topFreq / freq)).sum * db.dbamp,
					eg = EnvGen.kr(Env.adsr(attack, decay, susLevel, release), gate, doneAction: 2);
					Out.ar(outBus0, sig * eg);
				}, metadata: (
					numOutputs: 1,
					specs: (
						freq: \freq.asSpec,
						topFreq: \freq.asSpec,
						det: [-0.5.midiratio, 0.5.midiratio, \exp].asSpec,
						db: #[-120, 0],
						attack: #[0.002, 5, \exp],
						decay: #[0.002, 5, \exp],
						susLevel: #[0, 1, \amp],
						release: #[0.002, 5, \exp]
					)
				)).add;

				// if(topEnvironment[\gzkernel].isKindOf(Buffer)) { topEnvironment[\gzkernel].free };
				topEnvironment[\gzkernel] = Buffer.read(s, topEnvironment[\dir] +/+ "../samples/partconv-ir-trim.wav", action: {
					bufLoadFailed = false;
					cond.unhang;
				});
				cond.hang;
				if(bufLoadFailed.not) { ~stop.() };

				AppClock.sched(2, e {
					if(bufLoadFailed) {
						"Could not load % from disk. Stopped."
						.format(topEnvironment[\dir] +/+ "../samples/partconv-ir-trim.wav").warn;
						~iterator.stop;
					};
					nil
				});
			}
		}
	),
	\cmdSync,


	///// SECTION A


	hadronCmd: (
		id: \delay,
		path: topEnvironment[\dir] +/+ "A-delays3.hadron"
	),
	\cmdSync,

	funcCmd: (
		setDoneSignal: { ~doneSignal = true }
	)
]).play;

// clean up on stop -- ANY stop
upd = SimpleController(t).put(\done, {
	upd.remove;
	{
		Library.at(\hadronCmd).do(_.graceExit);
		topEnvironment[\gzkernel].free;
	}.fork(AppClock);
});
)