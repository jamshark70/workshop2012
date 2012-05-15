(
s.waitForBoot {
	var midiIndex;
	PR(\funcCmd).clone {
		~setDoneSignal = {
			~doneSignal = true;
		};
		~func = {
			~preload.();
			~hadron = Hadron.new;
			HadronStateLoad(~hadron).addFunc(e { ~stop.() }).loadState(~path);
			Library.put(\hadronCmd, ~id, ~hadron)
		};
		// optionally may be called in ~done
		~findMixerPlug = { |ident|
			~hadron.alivePlugs.detect { |plug|
				plug.isKindOf(HrMixerCh) and: { ident.isNil or: { plug.ident == ident } }
			};
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

	Proto {
		~recordEnabled = false;
		~isRecording = false;
		~prep = {
			defer(e {
				~recWindow = Window("Record switch",
					Rect(Window.screenBounds.width - 200, 50, 200, 100));
				~recButton = Button(~recWindow, Rect(2, 2, 196, 40))
				.states_([
					["Recording disabled"],
					["Recording enabled", Color.black, Color(0.8, 1.0, 0.8)],
					["Recording active", Color.black, Color(1.0, 0.8, 0.8)]
				])
				.action_(e { |view|
					if(view.value == 2) {
						view.valueAction = 0;
					} {
						~recordEnabled = view.value > 0;
						if(view.value == 0 and: { ~isRecording }) {
							~stopRecord.();
						};
					};
				});
				~stopButton = Button(~recWindow, Rect(2, 46, 196, 40))
				.states_([["Stop all"]])
				.action_(e { ~stopAll.(); });
				~recWindow.front.onClose_(e { ~recWindow = nil });
			});
			currentEnvironment
		};
		~freeCleanup = {
			defer(e {
				if(~recWindow.notNil) { ~recWindow.close };
			});
		};
		~startRecord = {
			var e = topEnvironment;
			fork {
				e[\guzheng].prepareRecord;
				e[\electr].prepareRecord;
				Server.default.sync;
				// ensure sample sync between files
				Server.default.makeBundle(nil, {
					e[\guzheng].startRecord;
					e[\electr].startRecord;
				});
				~isRecording = true;
				defer(e { ~recButton.value = 2 });
			};
			currentEnvironment
		};
		~stopRecord = {
			var e = topEnvironment;
			e[\guzheng].stopRecord;
			e[\electr].stopRecord;
			defer(e { ~recButton.value = ~recordEnabled.binaryValue });
			~isRecording = false;
			currentEnvironment
		};
		~stopAll = {
			// ~stopRecord.();
			t.stop;  // will stopRecord too
			currentEnvironment
		};
		~runRecIfNeeded = {
			if(~recordEnabled and: { ~isRecording.not }) {
				~startRecord.();
			};
			currentEnvironment
		};
		~stopRecIfNeeded = {
			if(~isRecording) {
				"~isRecording is true; stopping record".debug;
				~stopRecord.();
			};
			currentEnvironment
		};
	} => PR(\recorder);

	if(thisProcess.platform.name == \windows) {
		~dir = HrVideoData.filenameSymbol.asString.dirname.dirname.dirname +/+ "FinalPatches";
	} {
		~dir = thisProcess.nowExecutingPath.dirname;
	};

	MIDIClient.init;
	MIDIIn.connectAll;

	midiIndex = MIDIClient.sources.detectIndex { |src| src.name.contains("ReMOTE") };
	MIDIPort.init(midiIndex.asArray);

	topEnvironment[\goButton].remove;
	topEnvironment[\goButton] = CCResponder({ NotificationCenter.notify(\midiGo, \go) }, num: 13);

	if(MixingBoard.boards.size < 1) { 'makeEmptyMixer8'.eval };
	if(thisProcess.platform.name == \linux) {
		{ "wmctrl -r 'Mixer' -b add,above".unixCmd }.defer(0.6);
	};
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
				SynthDef(\bufGrainPan, { |start, gate = 1, bufnum, pan, rate = 0, amp = 1,
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
						rate: #[0, 2, \lin] // #[0.1, 10, \exp]
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
					attack = 0.1, decay = 0.15, susLevel = 0.5, release = 0.25, pan = 0|
					var sig = Blip.ar(freq * [1, det], trunc(topFreq / freq)).sum * db.dbamp,
					eg = EnvGen.kr(Env.adsr(attack, decay, susLevel, release), gate, doneAction: 2);
					Out.ar(outBus0, Pan2.ar(sig, pan, eg));
				}, metadata: (
					numOutputs: 2,
					specs: (
						freq: \freq.asSpec,
						topFreq: \freq.asSpec,
						det: [-0.5.midiratio, 0.5.midiratio, \exp].asSpec,
						db: #[-120, 0],
						pan: \bipolar.asSpec,
						attack: #[0.002, 5, \exp],
						decay: #[0.002, 5, \exp],
						susLevel: #[0, 1, \amp],
						release: #[0.002, 5, \exp]
					)
				)).add;

				SynthDef("deepnote", { |freq1 = 440, freq2 = 440, detune, amp = 0.1, keyscale = 0.05,
					m0_coarse = 1, m0_fine = 7, m0_level = 3.75, m0_mul = 1, m0_pan,
					m1_coarse = 1, m1_fine = 0, m1_level = 2.11, m1_mul = 1, m1_pan,
					bufs = #[0, 0, 0], outBus0, timescale = 1, doneAction = 2, slideTime = 0.001|

					var basefreq = 220, freq, freqs, mods, cars, env, eg, gate = 1;

					slideTime = slideTime * timescale;
					freq = XLine.kr(freq1, freq2, slideTime);
					m0_level = m0_level * basefreq / ((keyscale * freq) + (basefreq * (1 - keyscale)));
					m1_level = m1_level * basefreq / ((keyscale * freq) + (basefreq * (1 - keyscale)));

					env = Env([ 0.0, 1.0, 0.48837210619172, 0.0 ], [ 0.057812497019768, 0.058854147791862, 0.88333335518837 ], [ -2.6971080662741, -3.5960966826931, -3.8909896224546 ]);
					eg = EnvGen.kr(env, timeScale: timescale, doneAction: 2);

					freqs = freq * [1, (detune * 0.01).midiratio];
					mods = [
						[m0_coarse, m0_fine, m0_level, m0_mul],
						[m1_coarse, m1_fine, m1_level, m1_mul]
					].collect { |row, i|
						var ratio = row[0] * (row[1] * 0.01).midiratio;
						Osc.ar(bufs[i+1], freqs[i] * ratio, 0, row[2] * row[3], 1)
					};
					cars = Osc.ar(bufs[0], freqs * mods, 0);
					Out.ar(outBus0, Pan2.ar(cars, [m0_pan, m1_pan], amp * eg).sum)
				}, metadata: (
					numOutputs: 2,
					specs: (
						freq1: \freq,
						freq2: \freq,
						amp: \amp,
						timescale: #[0.01, 10, \exp],
						slideTime: #[0, 1],
						m0_level: #[0.01, 50, \exp],
						m1_level: #[0.01, 50, \exp]
					)
				)).add;

				topEnvironment.use {
					if(~master.isNil or: { ~master.active.not }) {
						~master = MixerChannel(\master, s, 2, 2, level: 1).debug("made");
					};
					if(~guzheng.isNil or: { ~guzheng.active.not }) {
						~guzheng = MixerChannel(\guzheng, s, 2, 2, level: 1, outbus: ~master).debug("made");
					};
					if(~electr.isNil or: { ~electr.active.not }) {
						~electr = MixerChannel(\electr, s, 2, 2, level: 1, outbus: ~master).debug("made");
					};
				};

				defer {
					topEnvironment.use {
						~guzheng => MCG(6);
						~electr => MCG(7);
					};
				};

				PR(\recorder) => BP(\rec);

				topEnvironment.use {
					~sinebuf.free; ~mod1buf.free;
					~sinebuf = Buffer.alloc(s, 2048, 1, completionMessage: { |buf|
						buf.sine1Msg([1]);
					});
					~mod1buf = Buffer.alloc(s, 2048, 1, completionMessage: { |buf|
						buf.sine1Msg([1.00, 0.00, 0.00, 0.00, 0.33, 0.00, 0.00, 0.47]);
					});

					Pdefn(\fmbufs, [[~sinebuf, ~mod1buf, ~sinebuf]]);
				};

				if(topEnvironment[\gzkernel].isKindOf(Buffer)) { topEnvironment[\gzkernel].free };
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

				Server.default.latency = 0.08;
			}
		}
	),
	\cmdSync,


	///// SECTION A


	hadronCmd: (
		id: \delay,
		path: topEnvironment[\dir] +/+ "A-delays3.hadron",
		done: {
			var mixer = ~findMixerPlug.();
			if(mixer.notNil) { mixer.mixer.outbus = topEnvironment[\electr].debug("topE[\\electr]") };
		}
	),
	\cmdSync,
	waitCmd: (label: "Click/MIDI to start"),
	\cmdSync,
	{
		BP(\rec).runRecIfNeeded;
		HrVideoData.videoGui.cameraPowerSwitch(1);
		2 // 10,
	},

	hadronCmd: (
		id: \conv,
		path: topEnvironment[\dir] +/+ "A-convolution.hadron",
		done: {
			var mixer = ~findMixerPlug.();
			if(mixer.notNil) { mixer.mixer.outbus = topEnvironment[\electr] };
		}
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
		path: topEnvironment[\dir] +/+ "A-scrape-transition.hadron",
		done: {
			var mixer = ~findMixerPlug.();
			if(mixer.notNil) { mixer.mixer.outbus = topEnvironment[\electr] };
		}
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
		0
	},

	// waitCmd: (label: "Click/MIDI to fade convolution"),
	// \cmdSync,
	[
		// 3,
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

	15,  // total 15 seconds wait, enough for bigscrape?
	
	///// SECTION B
	// starts with, "Pause electronics," so, discard all existing hadron patches
	// but do load the next one we'll need... (doesn't play automatically)
	hadronCmd: (
		id: \trem129,
		path: topEnvironment[\dir] +/+ "B-tremolo129.hadron",
		done: {
			var mixer = ~findMixerPlug.();
			if(mixer.notNil) { mixer.mixer.outbus = topEnvironment[\electr] };
		}
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
		path: topEnvironment[\dir] +/+ "hjh-producing-some-pitch-contours2.hadron",
		done: {
			var mixer = ~findMixerPlug.();
			if(mixer.notNil) { mixer.mixer.outbus = topEnvironment[\electr] };
		}
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
		path: topEnvironment[\dir] +/+ "deep-note-bells.hadron",
		done: {
			var mixer = ~findMixerPlug.();
			if(mixer.notNil) { mixer.mixer.outbus = topEnvironment[\electr] };
		}
	),
	\cmdSync,

	waitCmd: (label: "Click/MIDI for bells"),
	\cmdSync,
	{
		var p = Library.at(\hadronCmd, \bells).alivePlugs
		.detect({ |plug| plug.ident == "start" });
		defer { p.modSets[\modValue].value(1) };
		4
	},
	// midi to fade in/out


	///// SECTION C

	hadronCmd: (
		id: \trem133,
		path: topEnvironment[\dir] +/+ "C-tremolo133.hadron",
		done: {
			var mixer = ~findMixerPlug.();
			if(mixer.notNil) { mixer.mixer.outbus = topEnvironment[\electr] };
		}
	),
	\cmdSync,
	waitCmd: (label: "Click/MIDI for tremolo"),
	\cmdSync,
	{
		var func = { |key, bool|
			var p = Library.at(\hadronCmd, key).alivePlugs
			.select(_.isKindOf(HrPolyPattern));
			defer { p.do(_.run(bool)) };
		}, startplug, gateplug;
		func.(\trem133, true);
		// func.(\bells, false);

		startplug = Library.at(\hadronCmd, \bells).alivePlugs
		.detect({ |plug| plug.ident == "start" });
		defer { startplug.modSets[\modValue].value(0) };

		// fade out contour
		gateplug = Library.at(\hadronCmd, \contour).alivePlugs
		.detect { |plug| plug.ident == "envgate" };
		if(gateplug.notNil) { defer { gateplug.modSets[\modValue].value(0) } };

		2
	},

	hadronCmd: (
		id: \ringz,
		path: topEnvironment[\dir] +/+ "xthird-part-1.hadron",
		done: {
			var mixer = ~findMixerPlug.();
			if(mixer.notNil) { mixer.mixer.outbus = topEnvironment[\electr] };
		}
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
		path: topEnvironment[\dir] +/+ "C-deep-note-converge.hadron",
		done: {
			var mixer = ~findMixerPlug.();
			if(mixer.notNil) { mixer.mixer.outbus = topEnvironment[\electr] };
		}
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

	waitCmd: (label: "Click/MIDI to stop deep note"),
	\cmdSync,
	{
		var p = Library.at(\hadronCmd, \deepnote).alivePlugs
		.detect(_.isKindOf(HrPolyPattern));
		if(p.notNil) { defer { p.run(false) } };
		0
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

	waitCmd: (label: "Click/MIDI to close"),
	\cmdSync
]).play;

// clean up on stop -- ANY stop
upd = SimpleController(t).put(\done, {
	upd.remove;
	{
		BP(\rec).stopRecIfNeeded;
		BP(\rec).free;
		Library.at(\hadronCmd).keys.do({ |key| Library.at(\hadronCmd, key).graceExit });
		topEnvironment[\gzkernel].free;
	}.fork(AppClock);
});
)
