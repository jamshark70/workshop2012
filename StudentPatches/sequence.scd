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

	PR(\funcCmd).clone {
		~setDoneSignal = {
			~doneSignal = NotificationCenter.register(\midiGo, \go, currentEnvironment, e {
				~stop.();
			});
			{
				~window = Window("Advance", Rect(0, 40, 200, 120));
				~button = Button(~window, ~window.view.bounds.insetBy(2, 2))
				.states_([
					[~label ?? { "Click or hit MIDI button to advance" },
						Color.black, Color(1.0, 0.65, 0.65)]
				])
				.action_(e { ~stop.() });
				~window.front;
			}.fork(AppClock);
		};
		~clearDoneSignal = {
			~doneSignal.remove;
			defer(e { ~window.close });
		};
	} => PR(\waitCmd);

	if(thisProcess.platform.name == \windows) {
		~dir = HrVideoData.filenameSymbol.asString.dirname.dirname.dirname +/+ "StudentPatches";
	} {
		~dir = thisProcess.nowExecutingPath.dirname;
	};

	MIDIClient.init;
	MIDIIn.connectAll;

	topEnvironment[\goButton].remove;
	topEnvironment[\goButton] = CCResponder({ NotificationCenter.notify(\midiGo, \go) }, num: 13);
};
);

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
	{
		HrVideoData.videoGui.cameraPowerSwitch(1);
		2 // 10,
	},

	hadronCmd: (
		id: \conv,
		path: topEnvironment[\dir] +/+ "A-convolution.hadron"
	),
	\cmdSync,
	waitCmd: (label: "Click/MIDI to fade in convolution"),
	\cmdSync,
	{
		var p = Library.at(\hadronCmd, \conv).alivePlugs.detect { |plug| plug.ident == "fade" };
		defer { p.modSets[\modValue].value(1) };
		3
	},
	{ defer { Library.at(\hadronCmd, \delay).graceExit; Library.global.removeEmptyAt(\hadronCmd, \delay) }; 0 },
	waitCmd: (label: "Click/MIDI to raise pitch"),
	\cmdSync,
	{
		var p = Library.at(\hadronCmd, \conv).alivePlugs.select(_.isKindOf(HrRangeMap)).detect { |plug| plug.ident == "start" };
		defer { p.modSets[\modValue].value(1) };
		0
	},
	hadronCmd: (
		id: \scrape,
		path: topEnvironment[\dir] +/+ "A-scrape-transition.hadron"
	),
	\cmdSync,
	waitCmd: (label: "Click/MIDI to run transition"),
	\cmdSync,
	{
		var p = Library.at(\hadronCmd, \scrape).alivePlugs
		.select(_.isKindOf(HrRangeMap))
		.detect { |plug| plug.ident == "goctl" };
		defer { p.modSets[\modValue].value(1) };
		HrVideoData.videoGui.cameraPowerSwitch(1);
		10
	},

	// waitCmd: (label: "Click/MIDI to fade convolution"),
	// \cmdSync,
	[
		3,
		{
			var p = Library.at(\hadronCmd, \conv).alivePlugs
			.select(_.isKindOf(HrRangeMap))
			.detect { |plug| plug.ident == "fade" };
			defer { p.modSets[\modValue].value(-0.1) };
			12.5
		},
		{
			defer {
				if(Library.at(\hadronCmd, \conv).notNil) {
					Library.at(\hadronCmd, \conv).graceExit;
					Library.global.removeEmptyAt(\hadronCmd, \conv)
				};
			};
			0
		}
	],

	5,  // total 15 seconds wait, enough for bigscrape?
	
	///// SECTION B
	// starts with, "Pause electronics," so, discard all existing hadron patches
	// but do load the next one we'll need... (doesn't play automatically)
	hadronCmd: (
		id: \trem129,
		path: topEnvironment[\dir] +/+ "B-tremolo129.hadron"
	),
	\cmdSync,
	{
		defer {
			Library.at(\hadronCmd).keys.do { |key|
				if(#[trem129, scrape].includes(key).not) {
					Library.at(\hadronCmd, key).graceExit;
					Library.global.removeEmptyAt(\hadronCmd, key);
				};
			};
		};
		0
	},
	waitCmd: (label: "Click/MIDI to run 129"),
	\cmdSync,
	{
		var p = Library.at(\hadronCmd, \trem129).alivePlugs
		.detect(_.isKindOf(HrPolyPattern));
		defer { p.run(true) };
		8
	},

	{
		defer {
			Library.at(\hadronCmd, \scrape).graceExit;
			Library.global.removeEmptyAt(\hadronCmd, \scrape);
		};
		2
	},

	hadronCmd: (
		id: \contour,
		path: topEnvironment[\dir] +/+ "hjh-producing-some-pitch-contours2.hadron"
	),
	\cmdSync,
	{
		HrVideoData.videoGui.cameraPowerSwitch(1);
		2 // 10,
	},
	[
		12,
		{
			var p = Library.at(\hadronCmd, \trem129).alivePlugs
			.detect(_.isKindOf(HrPolyPattern));
			defer { p.run(false) };
			10
		},
		{
			defer {
				Library.at(\hadronCmd, \trem129).graceExit;
				Library.global.removeEmptyAt(\hadronCmd, \trem129);
			};
			0
		}
	],

	hadronCmd: (
		id: \bells,
		path: topEnvironment[\dir] +/+ "deep-note-bells.hadron"
	),
	\cmdSync,

	waitCmd: (label: "Click/MIDI for bells"),
	\cmdSync,
	{
		var p = Library.at(\hadronCmd, \bells).alivePlugs
		.detect(_.isKindOf(HrPolyPattern));
		defer { p.run(true) };
		4
	},
	// midi to fade in/out


	///// SECTION C

	hadronCmd: (
		id: \trem133,
		path: topEnvironment[\dir] +/+ "C-tremolo133.hadron"
	),
	\cmdSync,
	waitCmd: (label: "Click/MIDI for tremolo"),
	\cmdSync,
	{
		var func = { |key, bool|
			var p = Library.at(\hadronCmd, key).alivePlugs
			.select(_.isKindOf(HrPolyPattern));
			defer { p.do(_.run(bool)) };
		}, p;
		func.(\trem133, true);
		func.(\bells, false);

		// fade out contour
		p = Library.at(\hadronCmd, \contour)
		.alivePlugs.detect { |plug| plug.ident == "envgate" };
		if(p.notNil) { defer { p.modSets[\modValue].value(0) } };

		2
	},

	hadronCmd: (
		id: \ringz,
		path: topEnvironment[\dir] +/+ "xthird-part-1.hadron"
	),
	\cmdSync,

	// remove old patches: in subthread, won't affect cmdSync
	[
		1.5,
		{
			defer {
				Library.at(\hadronCmd).keys.do { |key|
					if(#[trem133, ringz].includes(key).not) {
						Library.at(\hadronCmd, key).graceExit;
						Library.global.removeEmptyAt(\hadronCmd, key);
					};
				};
			};
			0
		},
	],

	waitCmd: (label: "Click/MIDI for perc"),
	\cmdSync,
	{
		var p = Library.at(\hadronCmd, \ringz).alivePlugs
		.detect(_.isKindOf(HrPolyPattern));
		defer { p.run(true) };
		4
	},

	hadronCmd: (
		id: \deepnote,
		path: topEnvironment[\dir] +/+ "C-deep-note-converge.hadron"
	),
	\cmdSync,
	waitCmd: (label: "Click/MIDI for deep note"),
	\cmdSync,
	{
		var func = { |key, bool|
			var p = Library.at(\hadronCmd, key).alivePlugs
			.select(_.isKindOf(HrPolyPattern));
			defer { p.do(_.run(bool)) };
		};
		func.(\deepnote, true);
		6
	},

	{
		var func = { |key, bool|
			var p = Library.at(\hadronCmd, key).alivePlugs
			.select(_.isKindOf(HrPolyPattern));
			defer { p.do(_.run(bool)) };
		};
		func.(\trem133, false);
		func.(\ringz, false);
		0
	},

	funcCmd: (
		setDoneSignal: { ~doneSignal = true }
	)
]).play;

// clean up on stop -- ANY stop
upd = SimpleController(t).put(\done, {
	upd.remove;
	{
		Library.at(\hadronCmd).keys.do({ |key| Library.at(\hadronCmd, key).graceExit });
		topEnvironment[\gzkernel].free;
	}.fork(AppClock);
});
)