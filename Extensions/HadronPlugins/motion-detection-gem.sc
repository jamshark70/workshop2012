// support code
// reads visual analysis OSC messages from PD
// and forwards data to dependents

HrVideoBlock {
	var <num = 5;
	var <color, <colors;
	var <predict_color;
	var <>magspec;
	var <>maxmag = 0.2; // 783360;
	var <>magThresh = -1; // 7000;  // below this, ignore the new point
	var predicted = false;
	var <x, <y, new_x, new_y, <mag, <plotsize, <angle, <radius;
	var indices, i_avg, i_minus, i_minus_sqr_sum;
	var <>x_origin, <>y_origin;

	*new { |num(5), x_origin = 0, y_origin = 0, plotsize(Point(64, 48))|
		^super.new.init(num, x_origin, y_origin, plotsize)
	}

	init { |argNum, argx_origin = 0, argy_origin = 0, argplotsize(Point(64, 48))|
		num = argNum;
		x = 0 ! num;
		y = 0 ! num;
		mag = 0 ! num;
		plotsize = argplotsize;
		// these are fixed values used for the regression
		// calculate once, instead of every time
		indices = (0 .. num-1);
		i_avg = indices.mean;
		i_minus = indices - i_avg;
		i_minus_sqr_sum = i_minus.squared.sum;
		x_origin = argx_origin;
		y_origin = argy_origin;
		this.color_(Color.red);
		predict_color = Color.blue;
		magspec = #[0, 20, -6].asSpec;
	}

	xabs { x.last + x_origin }
	yabs { y.last + y_origin }
	ptabs { Point(this.xabs, this.yabs) }

	addPoint { |argx, argy, argmag|
		var	x1, y1, mag1;
		if(argx < 0 or: { argmag < magThresh }) {
			x1 = x.last;
			y1 = y.last;
		} {
			x1 = argx * plotsize.x;
			y1 = argy * plotsize.y;
		};
		x = x.rotate(-1).put(num-1, x1);
		y = y.rotate(-1).put(num-1, y1);
		mag = mag.rotate(-1).put(num-1, max(0, argmag));
		predicted = false;
	}
	// two linear regressions: x vs time index, y vs time index
	// this is much more accurate than regressing x vs time and y vs x
	predict {
		var y_avg = y.mean,
			x_avg = x.mean,
			x_slope = (i_minus * (x - x_avg)).sum / i_minus_sqr_sum,
			y_slope = (i_minus * (y - y_avg)).sum / i_minus_sqr_sum,
			x_intercept = x_avg - (x_slope * i_avg),
			y_intercept = y_avg - (y_slope * i_avg);
		new_x = x_intercept + (x_slope * num);  // num = high 'i' + 1
		new_y = y_intercept + (y_slope * num);
		angle = atan2(y.last - new_y, x.last - new_x);
		radius = sqrt((x.last - new_x).squared + (y.last - new_y).squared);
		predicted = true;
	}
	// must call this only from a drawing function
	plot {
		var	mag1 = magspec.map(mag.last / maxmag) * 0.5, mg,
			pt1 = Point(x.last + x_origin, y.last + y_origin),
			pt2;
		x.do { |x, i|
			mg = mag1 * i / num;
			Pen.color_(colors[i])
			.fillOval(Rect.aboutPoint(Point(x + x_origin, y[i] + y_origin), mg, mg));
		};
		if(predicted) {
			mag1 = mag1 * 0.5;
			pt2 = Point(new_x + x_origin, new_y + y_origin);
			Pen.color_(predict_color)
			.fillOval(Rect.aboutPoint(pt2, mag1, mag1))
			.moveTo(pt2).lineTo(pt1).stroke;
		};
	}
	color_ { |color|
		var	white = Color.white;
		color = color;
		colors = Array.fill(num, { |i|
			color.blend(white, i / num);
		}).reverse;
	}
}

HrVideoListener {
	classvar <>defaultSize = 3;

	var <>dim;
	var ptNum = 5;
	var anglebufSize = 3;
	var maxmag = 1; // 3000000;
	var magThresh = -1; // 7000;
	var imgSize;
	var <plotsize;
	var <>blobxy;
	var clients, <points;
	var xbuf, ybuf, bufIndex, xsum, ysum, prevXSum, prevYSum;
	var <>clusterFuncs, <clusterCalcs;
	var resp;
	var <rawCentroid, <magsum = 0, <normmag, <anglePoint, <centroid;

	*new { |dim(defaultSize), ptNum(5), anglebufSize(3), imgSize(Point(320, 240))|
		^super.new.init(dim, ptNum, anglebufSize, imgSize)
	}

	init { |argDim, argPtNum, argBufSize, argImgSize|
		dim = argDim;
		ptNum = argPtNum;
		anglebufSize = argBufSize;
		imgSize = argImgSize;
		plotsize = imgSize / dim;
		blobxy = Point(0.5, 0.5);
		clients = IdentitySet.new;
		points = Array(dim.squared);
		dim.do { |xi|
			dim.do { |yi|
				points.add(
					HrVideoBlock(ptNum, xi * plotsize.x, yi * plotsize.y, plotsize)
				);
			};
		};
		this.makeResponder();

		xbuf = Array.fill(anglebufSize, 0);
		ybuf = Array.fill(anglebufSize, 0);
		bufIndex = 0;
		xsum = 0;
		ysum = 0;
		prevXSum = 0;
		prevYSum = 0;
		clusterFuncs = ();
	}
	free {
		this.removeResponder();
		this.changed(\modelWasFreed);
	}
	makeResponder {
		if(resp.notNil) { this.removeResponder() };
		resp = OSCresponderNode(nil, '/coord', { |time, resp, msg|
			if(msg[4] == (dim.squared + 1)) {
				blobxy = Point(msg[1], msg[2]);
				magsum = msg[3];
				this.predict();
				this.changed(\allPtsReceived);
			} {
				points[msg[4] - 1].addPoint(*msg[1..3]).predict;
			};
		}).add;
	}
	removeResponder { resp.remove; }
	// assumes a/ on AppClock b/ on a drawing func
	updatePoints {
		points.do { |pt| pt.plot };
	}

	// rework: anglebuf is now the last few centroids
	// then calculate the slope from linear regression and get the angle from this
	predict {
		var /*sum = Point(0, 0),*/ temppt, centroidx = 0, centroidy = 0,
			theta, insertIndex, magtemp;
		// lazy: these might be expensive and not always requested
		// this is one of the most unintentionally humorous lines I've written
		// in rather some time
		clusterCalcs = clusterFuncs.collect { |func| Thunk(func) };

		rawCentroid = blobxy * 2 - 1;
			
		// magsum = magsum;
		normmag = magsum / maxmag;

		prevXSum = xsum;
		prevYSum = ysum;
		xsum = xsum - xbuf[bufIndex] + rawCentroid.x;
		ysum = ysum - ybuf[bufIndex] + rawCentroid.y;
		xbuf[bufIndex] = rawCentroid.x;
		ybuf[bufIndex] = rawCentroid.y;
		bufIndex = (bufIndex + 1) % anglebufSize;
		anglePoint = Point(
			(xsum - prevXSum) / anglebufSize,
			(ysum - prevYSum) / anglebufSize
		);
		centroid = Point(xsum / anglebufSize, ysum / anglebufSize);

	}

	addClient { |object|
		clients.add(object);
		// why the difference?
		// the motion gui is a dependant, but not a client
		this.addDependant(object);
	}
	removeClient { |object|
		clients.remove(object);
		// why the difference?
		// the motion gui is a dependant, but not a client
		this.removeDependant(object);
		// return value: clients may do
		// if(ml.removeClient(this)) { ml.free }
		^clients.size <= 0
	}

}

// let's do this right... don't fold gui into data-handling class
HrVideoGui {
	var <>gridColor;
	var <>pdAddr;
	var <>noiseReduction = 9; // 64;
	var <>autoSwitchOffCamera = true;
	var <model, win, uview, onoff, noiseSl, controller;
	var handshakeResp, handshakeThread;

	*new { |model, noiseReduction(18), pdAddr(NetAddr("127.0.0.1", 57122))|
		^super.new.init(model, noiseReduction, pdAddr)
	}

	init { |argModel, argNr, argPdAddr|
		gridColor = Color.gray(0.6);
		pdAddr = argPdAddr;
		noiseReduction = argNr;

		model = argModel;
		model.predict;  // need to fill some variables in the model
		this.makeController();
		this.makeViews();
		this.pdHandshake();
	}
	free {
		controller.remove;
		handshakeThread.stop;
		handshakeResp.remove;
		if(autoSwitchOffCamera ? false) {
			this.cameraPowerSwitch(0);
		};
		defer { win.tryPerform(\close) };
	}
	makeController {
		var updateFunc = inEnvir { uview.refresh };
		controller = SimpleController(model)
		.put(\allPtsReceived, {
			defer(updateFunc)
		})
		.put(\modelWasFreed, {
			this.free;
		});
	}
	makeViews {
		var drawfunc = if(Window.implClass.findRespondingMethodFor(\drawFunc_).notNil)
		{ \drawFunc_ } { \drawHook_ };
		win = Window(\test, Rect(500, 50, 320, 270));
		// grid background, don't redraw on every userview refresh
		win.perform(drawfunc, {
			Pen.color = gridColor;
			(model.dim + 1).do { |i|
				Pen.moveTo(Point(0, i * model.plotsize.y))
				.lineTo(Point(320, i * model.plotsize.y))
				.moveTo(Point(i * model.plotsize.x, 0))
				.lineTo(Point(i * model.plotsize.x, 240));
			};
			Pen.stroke;
		});
		uview = UserView(win, Rect(0, 0, 320, 240));
		uview.drawFunc_({
			this.updateView();
		});
		// 100 == (320 - 120) / 2
		onoff = Button(win, Rect(2, 245, 88, 20))
		.states_([["stopped"], ["running", Color.black, Color(0.6, 1.0, 0.6)]])
		.action_({ |view|
			this.cameraPowerSwitch(view.value);
		});
		noiseSl = EZSlider.new(win, Rect(92, 245, 318 - 92, 20), "nr", #[0, 127, \lin, 1], action: { |view|
			pdAddr.tryPerform(\sendMsg, \noiseReduction, view.value)
		}, initVal: noiseReduction, /*initAction: true,*/ labelWidth: 30);
		win.front.refresh;
		win.onClose = { this.free };
	}
	updateView {
		model.updatePoints;
	}
	cameraPowerSwitch { |argonoff = 0|
		pdAddr.tryPerform(\sendMsg, \onOffSwitch, argonoff);
		defer({ onoff.value = (argonoff > 0).binaryValue });
	}
	pdHandshake {
		handshakeResp = OSCresponderNode(nil, '/handshakeReply', {
			handshakeResp = nil;
			handshakeThread.stop;
			handshakeThread = nil;
			pdAddr.tryPerform(\sendMsg, \noiseReduction, noiseSl.value);
			"Communication with pd is established.".postln;
			NotificationCenter.notify(this.class, \handsShook);
		}).add.removeWhenDone;
		handshakeThread = Task({
			loop {
				pdAddr.tryPerform(\sendMsg, \handshake);
				0.5.wait;
			};
		}).play;
	}
}

HrVideoAngleGui : HrVideoGui {
	var <>angleColor;

	init { |model, argNr, argPdAddr|
		var	colorTemp = [0.1, 0.1, 1.0];
		angleColor = Color.gray;
		super.init(model, argNr, argPdAddr);
	}
	updateView {
		var bounds = uview.bounds, ctr, pt, km;
		pt = model.anglePoint;
		ctr = model.centroid * 0.5 + 0.5 * Point(319, 239);
		Pen.color_(angleColor)
		.fillRect(Rect.aboutPoint(ctr, 6, 6))
		.width_(4)
		.line(ctr, ctr + Polar(bounds.height * 0.4 * model.normmag, atan2(pt.y, pt.x)).asPoint)
		.stroke.width_(1);
		model.updatePoints;
	}
}
