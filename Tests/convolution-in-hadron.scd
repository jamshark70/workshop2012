var dir, bufLoadFailed = true, cond = Condition.new;

if(thisProcess.platform.name == \windows) {
	dir = HrVideoData.filenameSymbol.asString.dirname.dirname.dirname +/+ "Tests";
} {
	dir = thisProcess.nowExecutingPath.dirname;
};

s.waitForBoot {
	{
		if(~gzkernel.isKindOf(Buffer)) { ~gzkernel.free };
		~gzkernel = Buffer.read(s, dir +/+ "../samples/partconv-ir-trim.wav", action: {
			bufLoadFailed = false;
			cond.unhang;
		});
		cond.hang;

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
		s.sync;

		h = Hadron.new;
		HadronStateLoad(h).loadState(dir +/+ "convolution-in-hadron5.hadron");

		AppClock.sched(2, {
			if(bufLoadFailed) {
				"Could not load % from disk. Stopped."
				.format(dir +/+ "../samples/partconv-ir-trim.wav").warn;
			};
			nil
		});
	}.fork(AppClock);
};