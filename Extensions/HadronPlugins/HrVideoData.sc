HrVideoData : HrMultiCtlMod {
	classvar videoParams, videoIndices;
	var synthChannels, activeIndices;
	var videoListener, videoGui;
	var activeItems;

	*initClass
	{
		this.addHadronPlugin;
		videoParams = [
			'CentroidX': { |ml| ml.centroid.x * 0.5 + 0.5 },
			'CentroidY': { |ml| ml.centroid.y * 0.5 + 0.5 }
		];
		videoIndices = ('CentroidX': 0, 'CentroidY': 2);
		StartUp.add {
			(this.filenameSymbol.asString.dirname.dirname.dirname
				+/+ "common/motion-detection.scd")
			.debug("HrVideoData: loading motion-detection.scd").loadPath;
		};
	}
	*height { ^335 }

	*shouldWatch { |argExtraArgs|
		^argExtraArgs.size < 1 or: {
			argExtraArgs[0] != "0" and: { argExtraArgs[0] != "false" }
		}
	}

	init
	{
		loadSemaphore = Semaphore(1);

		window.background_(Color.gray(0.7));
		if(extraArgs.size >= 1 and: {
			extraArgs[1].size > 0 and: { extraArgs[1].asFloat > 0 }
		}) {
			pollRate = extraArgs[1].asFloat;
		} {
			pollRate = defaultPollRate;
		};
		helpString = "Choose video parameter data and map to other plugins.";
		
		numChannels = 0; // will change when synth is made
		isMapped = [];
		modControl = [];

		activeItems = [];
		postOpText = HrListSelector(window, Rect(10, 20, 430, 95))
		.allItems_(videoParams[0, 2..])
		.action_({ |view|
			var i, didChange = false;
			if(view.activeItems.size != activeItems.size) {
				activeItems = view.activeItems.copy;
				this.makeSynth;
			};
		});

		startButton = Button(window, Rect(10, 120, 80, 20)).states_([["Start"],["Stop"]])
		.value_(0)
		.action_
		({|btn|
			if(btn.value == 1) {
				isMapped = modControl.collect { |ctl, i| ctl.map(prOutBus.index + i) };
				synthInstance.set(\pollRate, pollRate * (watcher.notNil.binaryValue));
			} {
				modControl.do(_.unmap);
				isMapped = false ! numChannels;
				synthInstance.set(\pollRate, 0);
			};
		});

		if(this.shouldWatch) {
			pollRateView = HrEZSlider(window, Rect(10, 150, 430, 20),
				"update rate", [1, 25], { |view|
					pollRate = view.value;
					if(synthInstance.notNil) {
						synthInstance.set(\pollRate, pollRate * (watcher.notNil.binaryValue));
					};
				}, pollRate, labelWidth: 100, numberWidth: 45
			);
		};

		modCtlsScroll = ScrollView(window, Rect(5, 175, 440, 150))
		.background_(Color.gray(0.92))
		.hasHorizontalScroller_(false);

		videoListener = PR(\motionListener) => BP(("ml"++uniqueID).asSymbol);
		videoGui = PR(\motionAngleGui).chuck(
			BP(("mg"++uniqueID).asSymbol), nil, (model: videoListener)
		);
		videoListener.addDependant(this);

		this.makeSynth;

		saveGets =
			[
				{ postOpText.activeItems.collect(_.asSymbol).asCompileString },
				{ modControl.collect(_.getSaveValues); },
				{ startButton.value; },
				{ pollRate }
			];

		saveSets =
			[
				{ |argg|
					postOpText.activeItems = argg.interpret;
					fork {
						loadSemaphore.wait; // block others
						this.makeSynth;
						loadSemaphore.signal; // unblock others
					};
				},
				{ |argg|
					{
						loadSemaphore.wait;
						modControl.do { |ctl, i|
							ctl.putSaveValues(argg[i]).doWakeFromLoad
						};
						loadSemaphore.signal;
					}.fork(AppClock);
				},
				{ |argg|
					{
						loadSemaphore.wait;
						startButton.valueAction_(argg);
						loadSemaphore.signal;
					}.fork(AppClock);
				},
				{ |argg|
					{
						loadSemaphore.wait;
						if(argg.notNil) {
							pollRate = argg;
							pollRateView.tryPerform(\valueAction_, argg);
						};
						loadSemaphore.signal;
						loadSemaphore = nil;
					}.fork(AppClock);
				}
			];
	}

	makeSynthDef {
		synthChannels = max(1, postOpText.activeItems.size);
		replyID = UniqueID.next;
		SynthDef("HrVideoData"++uniqueID, { |prOutBus, pollRate = 1, t_trig = 1|
			var input = NamedControl.kr(\data, 0 ! synthChannels),
			envArray = Env([0, 1], [max(1, pollRate).reciprocal], \lin).asArray;
			input = input.asArray.collect { |chan|
				envArray.put(0, chan).put(4, chan);
				EnvGen.kr(envArray, t_trig);
			};
			ReplaceOut.kr(prOutBus, input);
		}).add;
		this.rebuildBus(synthChannels).rebuildTargets(postOpText.activeItems.size);
		numChannels = postOpText.activeItems.size;
		isMapped = isMapped.extend(numChannels, false);
	}

	update { |obj, what, argument, oldplug, oldparam|
		var data;
		if(what == \allPtsReceived and: { obj === videoListener }) {
			data = postOpText.activeItems.collect { |i|
				videoParams[videoIndices[i.asSymbol] + 1].value(videoListener)
			};
			if(synthInstance.notNil and: { data.size > 0 }) {
				synthInstance.set(\data, data, \t_trig, 1);
			};
			defer { modControl.do { |ctl, i| ctl.updateMappedGui(data[i]) } };
		} {
			super.update(obj, what, argument, oldplug, oldparam);
		}
	}

	cleanUp {
		videoListener.removeDependant(this);
		videoGui.free;
		videoListener.free;
	}
}