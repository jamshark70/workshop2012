// support code
// reads visual analysis OSC messages from PD
// and forwards data to dependents

Proto({
	~num = 5;
	~color = Color.red;
	~predict_color = Color.blue;
	~magspec = #[0, 20, -6].asSpec;
	~maxmag = 0.2; // 783360;
	~magThresh = -1; // 7000;  // below this, ignore the new point
	~predicted = false;
	~prep = { |x_origin = 0, y_origin = 0, plotsize(Point(64, 48))|
		~x = 0 ! ~num;
		~y = 0 ! ~num;
		~mag = 0 ! ~num;
		~plotsize = plotsize;
		// these are fixed values used for the regression
		// calculate once, instead of every time
		~indices = (0 .. ~num-1);
		~i_avg = ~indices.mean;
		~i_minus = ~indices - ~i_avg;
		~i_minus_sqr_sum = ~i_minus.squared.sum;
		~x_origin = x_origin;
		~y_origin = y_origin;
		~color_.(~color);
		currentEnvironment
	};

	~xabs = { ~x.last + ~x_origin };
	~yabs = { ~y.last + ~y_origin };
	~ptabs = { Point(~xabs.(), ~yabs.()) };

	~addPoint = { |x, y, mag|
		var	x1, y1, mag1;
		if(x < 0 or: { mag < ~magThresh }) {
			x1 = ~x.last;
			y1 = ~y.last;
		} {
			x1 = x * ~plotsize.x;
			y1 = y * ~plotsize.y;
		};
		~x = ~x.rotate(-1).put(~num-1, x1);
		~y = ~y.rotate(-1).put(~num-1, y1);
		~mag = ~mag.rotate(-1).put(~num-1, max(0, mag));
		~predicted = false;
		currentEnvironment
	};
	// two linear regressions: x vs time index, y vs time index
	// this is much more accurate than regressing x vs time and y vs x
	~predict = {
		var y_avg = ~y.mean,
			x_avg = ~x.mean,
			x_slope = (~i_minus * (~x - x_avg)).sum / ~i_minus_sqr_sum,
			y_slope = (~i_minus * (~y - y_avg)).sum / ~i_minus_sqr_sum,
			x_intercept = x_avg - (x_slope * ~i_avg),
			y_intercept = y_avg - (y_slope * ~i_avg);
		~new_x = x_intercept + (x_slope * ~num);  // ~num = high 'i' + 1
		~new_y = y_intercept + (y_slope * ~num);
		~angle = atan2(~y.last - ~new_y, ~x.last - ~new_x);
		~radius = sqrt((~x.last - ~new_x).squared + (~y.last - ~new_y).squared);
		~predicted = true;
		currentEnvironment
	};
	// must call this only from a drawing function
	~plot = {
		var	mag = ~magspec.map(~mag.last / ~maxmag) * 0.5, mg,
			pt1 = Point(~x.last + ~x_origin, ~y.last + ~y_origin),
			pt2;
		~x.do { |x, i|
			mg = mag * i / ~num;
			Pen.color_(~colors[i])
			.fillOval(Rect.aboutPoint(Point(x + ~x_origin, ~y[i] + ~y_origin), mg, mg));
		};
		if(~predicted) {
			mag = mag * 0.5;
			pt2 = Point(~new_x + ~x_origin, ~new_y + ~y_origin);
			Pen.color_(~predict_color)
			.fillOval(Rect.aboutPoint(pt2, mag, mag))
			.moveTo(pt2).lineTo(pt1).stroke;
		};
	};
	~color_ = { |color|
		var	white = Color.white;
		~color = color;
		~colors = Array.fill(~num, { |i|
			color.blend(white, i / ~num);
		}).reverse;
	};
}, parentKeys: #[num, color, magspec, maxmag]) => PR(\regressionUnit);

Proto({
	~dim = 3;
	~ptNum = 5;
	~anglebufSize = 3;
	~maxmag = 1; // 3000000;
	~magThresh = -1; // 7000;
	~kmSize = 2;
	~imgSize = Point(320, 240);
	~prep = {
		~plotsize = ~imgSize / ~dim;
		~blobxy = Point(0.5, 0.5);
		~clients = IdentitySet.new;
		~points = Array(~dim.squared);
		~dim.do { |xi|
			~dim.do { |yi|
				~points.add(
					PR(\regressionUnit).copy
					.put(\num, ~ptNum)
					.put(\magThresh, ~magThresh)
					.prep(xi * ~plotsize.x, yi * ~plotsize.y, ~plotsize)
				);
			};
		};
		~makeResponder.();

		~xbuf = Array.fill(~anglebufSize, 0);
		~ybuf = Array.fill(~anglebufSize, 0);
		~bufIndex = 0;
		~xsum = 0;
		~ysum = 0;
		~prevXSum = 0;
		~prevYSum = 0;
		~clusterFuncs = ~clusterFuncs.collect { |func| e(func) };

		currentEnvironment
	};
	~freeCleanup = {
		~removeResponder.();
		BP(~collIndex).changed(\modelWasFreed);
	};
	~makeResponder = {
		if(~resp.notNil) { ~removeResponder.() };
		~resp = OSCresponderNode(nil, '/coord', e { |time, resp, msg|
			if(msg[4] == (~dim.squared + 1)) {
				~blobxy = Point(msg[1], msg[2]);
				~magsum = msg[3];
				~predict.();
				BP(~collIndex).changed(\allPtsReceived);
			} {
				~points[msg[4] - 1].addPoint(*msg[1..3]).predict;
				// if(msg[4] == ~dim.squared) {
				// };
			};
		}).add;
	};
	~removeResponder = { ~resp.remove; };
	// assumes a/ on AppClock b/ on a drawing func
	~updatePoints = {
		~points.do { |pt| pt.plot };
	};

	// rework: anglebuf is now the last few centroids
	// then calculate the slope from linear regression and get the angle from this
	~predict = {
		var /*sum = Point(0, 0),*/ temppt, centroidx = 0, centroidy = 0, magsum = 0,
			theta, insertIndex, magtemp;
		// lazy: these might be expensive and not always requested
		// this is one of the most unintentionally humorous lines I've written
		// in rather some time
		~clusterCalcs = ~clusterFuncs.collect { |func| Thunk(func) };

		~rawCentroid = ~blobxy * 2 - 1;
			
		// ~magsum = magsum;
		~normmag = magsum / ~maxmag;

		~prevXSum = ~xsum;
		~prevYSum = ~ysum;
		~xsum = ~xsum - ~xbuf[~bufIndex] + ~rawCentroid.x;
		~ysum = ~ysum - ~ybuf[~bufIndex] + ~rawCentroid.y;
		~xbuf[~bufIndex] = ~rawCentroid.x;
		~ybuf[~bufIndex] = ~rawCentroid.y;
		~bufIndex = (~bufIndex + 1) % ~anglebufSize;
		~anglePoint = Point(
			(~xsum - ~prevXSum) / ~anglebufSize,
			(~ysum - ~prevYSum) / ~anglebufSize
		);
		~centroid = Point(~xsum / ~anglebufSize, ~ysum / ~anglebufSize);

		currentEnvironment
	};

	~addClient = { |object|
		~clients.add(object);
		// why the difference?
		// the motion gui is a dependant, but not a client
		BP(~collIndex).addDependant(object);
		currentEnvironment
	};
	~removeClient = { |object|
		~clients.remove(object);
		// why the difference?
		// the motion gui is a dependant, but not a client
		BP(~collIndex).removeDependant(object);
		// return value: clients may do
		// if(ml.removeClient(this)) { ml.free }
		~clients.size <= 0
	};
	~clusterFuncs = (
		spreadX: {
			var coords;
			if(~kmeans.centroids.size > 0) {
				coords = ~kmeans.centroids.flop[0];
				coords.maxItem - coords.minItem
			} { 0 }
		},
		spreadY: {
			var coords;
			if(~kmeans.centroids.size > 0) {
				coords = ~kmeans.centroids.flop[1];
				coords.maxItem - coords.minItem
			} { 0 }
		},
		spread: {
			// since these are thunks, redundant calcs won't be done
			hypot(~clusterCalcs[\spreadX].value, ~clusterCalcs[\spreadY].value)
		} //,
		// orient: {
			
		// }
	);
}) => PR(\motionListener);

// let's do this right... don't fold gui into data-handling class
Proto({
	~gridColor = Color.gray(0.6);
	~pdAddr = NetAddr("127.0.0.1", 57122);
	~noiseReduction = 9; // 64;
	~autoSwitchOffCamera = true;
	~prep = { |model|
		~model ?? { ~model = model };
		~model.predict;  // need to fill some variables in the model
		~makeController.();
		~makeViews.();
		~pdHandshake.();
		currentEnvironment
	};
	~freeCleanup = {
		var win = ~win;
		~controller.remove;
		if(~autoSwitchOffCamera ? false) {
			~cameraPowerSwitch.(0);
		};
		defer { win.tryPerform(\close) };
	};
	~makeController = {
		var updateFunc = inEnvir { ~uview.refresh };
		~controller = SimpleController(~model)
		.put(\allPtsReceived, {
			defer(updateFunc)
		})
		.put(\modelWasFreed, e {
			BP(~collIndex).free;
		});
	};
	~makeViews = {
		var drawfunc = if(Window.implClass.findRespondingMethodFor(\drawFunc_).notNil)
		{ \drawFunc_ } { \drawHook_ };
		~win = Window(\test, Rect(500, 50, 320, 270));
		// grid background, don't redraw on every userview refresh
		~win.perform(drawfunc, e {
			Pen.color = ~gridColor;
			(~model.dim + 1).do { |i|
				Pen.moveTo(Point(0, i * ~model.plotsize.y))
				.lineTo(Point(320, i * ~model.plotsize.y))
				.moveTo(Point(i * ~model.plotsize.x, 0))
				.lineTo(Point(i * ~model.plotsize.x, 240));
			};
			Pen.stroke;
		});
		~uview = UserView(~win, Rect(0, 0, 320, 240));
		~uview.drawFunc_(e {
			~updateView.();
		});
		// 100 == (320 - 120) / 2
		~onoff = Button(~win, Rect(2, 245, 88, 20))
		.states_([["stopped"], ["running", Color.black, Color(0.6, 1.0, 0.6)]])
		.action_(e { |view|
			~cameraPowerSwitch.(view.value);
		});
		~noiseReduction = EZSlider.new(~win, Rect(92, 245, 318 - 92, 20), "nr", #[0, 127, \lin, 1], action: e { |view|
			~pdAddr.tryPerform(\sendMsg, \noiseReduction, view.value)
		}, initVal: ~noiseReduction, /*initAction: true,*/ labelWidth: 30);
		~win.front.refresh;
		~win.onClose = e { BP(~collIndex).free };
	};
	~updateView = {
		~model.updatePoints;
	};
	~cameraPowerSwitch = { |onoff = 0|
		~pdAddr.tryPerform(\sendMsg, \onOffSwitch, onoff);
		defer(e { ~onoff.value = (onoff > 0).binaryValue });
	};
	~pdHandshake = {
		~handshakeResp = OSCresponderNode(nil, '/handshakeReply', e {
			~handshakeResp = nil;
			~handshakeThread.stop;
			~handshakeThread = nil;
			~pdAddr.tryPerform(\sendMsg, \noiseReduction, ~noiseReduction.value);
			"Communication with pd is established.".postln;
			NotificationCenter.notify(PR(~collIndex), \handsShook);
		}).add.removeWhenDone;
		~handshakeThread = Task({
			loop {
				~pdAddr.tryPerform(\sendMsg, \handshake);
				0.5.wait;
			};
		}).play;
	};
}) => PR(\motionGui);

PR(\motionGui).clone({
	~angleColor = Color.gray;
	~superPrep = ~prep;
	~prep = {
		var	colorTemp = [0.1, 0.1, 1.0];
		~superPrep.();
		~kmeansColors = Array.fill(~model.kmSize, {
			colorTemp = colorTemp.rotate(1);
			Color(*(colorTemp ++ #[0.4]))
		});
		currentEnvironment
	};
	~updateView = {
		var bounds = ~uview.bounds, ctr, pt, km;
		pt = ~model.anglePoint;
		ctr = ~model.centroid * 0.5 + 0.5 * Point(319, 239);
		Pen.color_(~angleColor)
		.fillRect(Rect.aboutPoint(ctr, 6, 6))
		.width_(4)
		.line(ctr, ctr + Polar(bounds.height * 0.4 * ~model.normmag, atan2(pt.y, pt.x)).asPoint)
		.stroke.width_(1);
		if((km = ~model.v[\kmeans]).notNil) {
			km.centroids.do { |pair, i|
				pair = pair * 0.5 + 0.5 * #[319, 319];
				Pen.color_(~kmeansColors[i])
				.fillOval(Rect.aboutPoint(Point(*pair), 16, 16));
			};
		};
		~model.updatePoints;
	};
}) => PR(\motionAngleGui);

Proto({
	~channels = 3;
	~chunkFrames = 1024;
	~model_ = { |newModel|
		~removeResponder.();
		~model = newModel;
		if(~soundfile.notNil) { ~makeResponder.() };
		currentEnvironment
	};
	~startLog = { |filename|
		var dir = ~dir ?? { thisProcess.nowExecutingPath.dirname },
			path = dir +/+ (filename ?? { "datalog%.aiff".format(Date.getDate.stamp) });
		if(~soundfile.isNil) {
			path = path.standardizePath;
			~soundfile = SoundFile(path).headerFormat_("AIFF").sampleFormat_("float")
			.numChannels_(~channels);
			if(~soundfile.openWrite.not) {
				~soundfile.close;
				~soundfile = nil;
				"couldn't open % for writing".format(path).error;
			} {
				~bufsize = ~channels * ~chunkFrames;
				~dataBuf = FloatArray.new(~bufsize);
				~makeResponder.();
			};
		} {
			"Already logging.".warn;
		};
		currentEnvironment
	};
	~stopLog = {
		if(~soundfile.notNil) {
			~removeResponder.();
			~soundfile.writeData(~dataBuf);
			~soundfile.close;
			~soundfile = nil;
		};
		currentEnvironment
	};
	~makeResponder = {
		if(~resp.isNil) {
			~resp = SimpleController(~model)
			.put(\allPtsReceived, e { ~addData.(); })
		};
	};
	~removeResponder = {
		if(~resp.notNil) { ~resp.remove; ~resp = nil; };
	};
	~addData = {
		~model.points.do { |pt|
			~dataBuf.add(pt.x.last).add(pt.y.last).add(pt.mag.last);
			if(~dataBuf.size == ~bufsize) {
				~soundfile.writeData(~dataBuf);
				~dataBuf = FloatArray.new(~bufsize);
			};
		};
	};
	~freeCleanup = {
		~stopLog.();
		~removeResponder.();
	};
}) => PR(\soundFileLogger);

Proto({
	~dir = thisProcess.nowExecutingPath.dirname;
	~file = "datalog110921_185859.aiff";
	~channels = 3;
	~frameRate = 50;
	~loop = 0;
	~alwaysReset = true;
	~prep = { |model|
		~buf = Buffer.readAndQuery(s, (~dir +/+ ~file).standardizePath);
		if(model.notNil) { ~model = model };
		~makeSynthDef.();
		~makeResponder.();
		currentEnvironment
	};
	~makeSynthDef = {
		var size = ~model.points.size;
		~def = SynthDef("logread%x%".format(size, ~channels).asSymbol,
			{ |bufnum, frameRate, loop = 0|
				var	t = Impulse.kr(frameRate),
				frames = BufFrames.kr(bufnum) / size,
				framePlus = (0 .. size - 1),
				frameCount = Demand.kr(t, 0, Dseq([Dseries(0, 1, frames)], inf)),
				xymags = BufRd.kr(~channels, bufnum,
					frameCount * size + framePlus,
					loop: 0, interpolation: 1);
				FreeSelf.kr((loop <= 0) * (frameCount >= (frames-1)));
				xymags.do { |point, i|
					SendReply.kr(t, '/coordlog', point, i);
				};
			}
		).add;
	};
	~makeResponder = {
		~resp = OSCresponderNode(s.addr, '/coordlog', e { |time, resp, msg|
			~model.points[msg[2]].addPoint(*msg[3..]).predict;
			if(msg[2] + 1 == ~model.dim.squared) {
				~model.predict;
				~model.changed(\allPtsReceived);
			};
		}).add;
	};
	~freeCleanup = {
		~buf.free;
		~resp.remove;
	};
	~asPattern = {
		Prout({
			var thisbp = BP(~collIndex);
			if(~synth.isNil) {
				if(~endResp.notNil) { ~endResp.free };
				~synth = Synth(~def.name, [bufnum: ~buf, frameRate: ~frameRate, loop: ~loop]);
				~endResp = OSCpathResponder(s.addr, ['/n_end', ~synth.nodeID], e {
					~synth = nil; thisbp.stop(0)
				}).add;
			};
			loop { 10.wait };
		});
	};
	~stopCleanup = {
		if(~synth.notNil) { ~synth.free; ~synth = nil };
		~endResp.remove;
	};
}) => PR(\soundFileReader);
