HrVideoData : HrMultiCtlMod {
	classvar <videoParams, <videoIndices;
	classvar <videoListener, <videoGui;  // only one of each! shared among instances

	var synthChannels, activeIndices;
	var activeItems;

	*initClass
	{
		this.addHadronPlugin;
		StartUp.add {
			videoParams = [
				'CentroidX': { |ml| ml.centroid.x * 0.5 + 0.5 },
				'CentroidY': { |ml| ml.centroid.y * 0.5 + 0.5 },
				'NormMag': { |ml| ml.normmag },
				'Angle': { |ml| ml.anglePoint.theta },
				'Radius': { |ml| ml.anglePoint.rho },
			];
			// if('KMeans'.asClass.notNil) {
			// 	// we'll just assume the default # of KMeans clusters
			// 	// this might need to change later
			// 	videoParams = videoParams.grow(6 + (PR(\motionListener).kmSize * 4));
			// 	videoParams.add(\ClusterSpreadX)
			// 	.add({ |ml| ml.clusterCalcs[\spreadX].value })
			// 	.add(\ClusterSpreadY)
			// 	.add({ |ml| ml.clusterCalcs[\spreadY].value })
			// 	.add(\ClusterSpread)
			// 	.add({ |ml| ml.clusterCalcs[\spread].value })
			// 	// .add(\ClusterOrient)
			// 	// .add({ |ml| ml.clusterOrient })
			// 	;
			// 	PR(\motionListener).kmSize.do { |i|
			// 		videoParams.add("Cluster%X".format(i).asSymbol)
			// 		.add({ |ml| ml.kmeans.centroids[i][0] })
			// 		.add("Cluster%Y".format(i).asSymbol)
			// 		.add({ |ml| ml.kmeans.centroids[i][1] });
			// 	};
			// };
			videoParams = videoParams.grow(HrVideoListener.defaultSize.squared * 2);
			HrVideoListener.defaultSize.do { |xi|
				HrVideoListener.defaultSize.do { |yi|
					videoParams.add("Mag@(%,%)".format(xi, yi).asSymbol)
					.add({ |ml|
						var pt = ml.points[xi * ml.dim + yi];
						pt.mag.last / pt.maxmag
					});
				};
			};
			videoIndices = IdentityDictionary.new;
			videoParams.pairsDo { |key, func, i|
				videoIndices.put(key, i);
			};
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
		loadConditions = Array.fill(5, { |i|
			Condition(false)
		});

		window.background_(Color.gray(0.7));
		if(extraArgs.size >= 1 and: {
			extraArgs[1].size > 0 and: { extraArgs[1].asFloat > 0 }
		}) {
			pollRate = extraArgs[1].asFloat;
		} {
			pollRate = 8;  // pd happens to spit out data about 8 frames/sec
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
				synthInstance.set(\pollRate, pollRate);
			} {
				modControl.do(_.unmap);
				isMapped = false ! numChannels;
				synthInstance.set(\pollRate, 0);
			};
		});

		if(this.shouldWatch) {
			pollRateView = HrEZSlider(window, Rect(10, 150, 430, 20),
				"update rate", [1, 25], { |view|
					this.pollRate = view.value;
					if(synthInstance.notNil) {
						synthInstance.set(\pollRate, pollRate);
					};
				}, pollRate, labelWidth: 100, numberWidth: 45
			);
		};

		modCtlsScroll = ScrollView(window, Rect(5, 175, 440, 150))
		.background_(Color.gray(0.92))
		.hasHorizontalScroller_(false);

		if(videoListener.isNil) {
			videoListener = HrVideoListener.new;
			videoGui = HrVideoAngleGui(videoListener);
		};
		videoListener.addClient(this);

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
						this.makeSynth;
						loadConditions[1].test_(true).signal; // unblock others
					};
				},
				{ |argg|
					{
						loadConditions[1].wait;
						modControl.do { |ctl, i|
							ctl.putSaveValues(argg[i]).doWakeFromLoad
						};
						loadConditions[2].test_(true).signal; // unblock others
					}.fork(AppClock);
				},
				{ |argg|
					{
						loadConditions[2].wait;
						startButton.valueAction_(argg);
						loadConditions[3].test_(true).signal; // unblock others
					}.fork(AppClock);
				},
				{ |argg|
					{
						loadConditions[3].wait;
						if(argg.notNil) {
							this.pollRate = argg;
							pollRateView.tryPerform(\valueAction_, argg);
						};
						loadConditions[4].test_(true).signal; // unblock others
					}.fork(AppClock);
				}
			];
	}

	makeSynthDef {
		synthChannels = max(1, postOpText.activeItems.size);
		replyID = UniqueID.next;
		SynthDef("HrVideoData"++uniqueID, { |prOutBus, outBus0, pollRate = 1, t_trig = 1|
			var input = NamedControl.kr(\data, 0 ! synthChannels),
			envArray = Env([0, 1], [max(1, pollRate).reciprocal], \lin).asArray;
			input = input.asArray.collect { |chan|
				envArray.put(0, chan).put(4, chan);
				EnvGen.kr(envArray, t_trig);
			};
			ReplaceOut.kr(prOutBus, input);
			Out.ar(outBus0, K2A.ar(input));
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
		if(videoListener.removeClient(this)) {
			videoGui.free;
			videoListener.free;
			videoGui = videoListener = nil;
		}
	}
}