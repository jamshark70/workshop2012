// fixed (unchanging) impulse response
// cmd-. to stop

(
s.waitForBoot {
	var c = Condition.new, cleanfunc = { CmdPeriod.remove(cleanfunc); b.free };
	fork {
		b = Buffer.alloc(s, 2048, 1);
		CmdPeriod.add(cleanfunc);
		s.sync;
		a = {
			RecordBuf.ar(BrownNoise.ar * EnvGen.ar(Env(#[0, 1, 0], #[0.5, 0.5], \sin), timeScale: b.duration, doneAction: 2), b, loop: 0);
			0
		}.play;
		OSCpathResponder(s.addr, ['/n_end', a.nodeID], { |time, resp, msg|
			resp.remove;
			c.unhang;
		}).add;
		c.hang;
		a = {
			var freq = MouseX.kr(150, 450, warp: 1, lag: 0.1);
			LeakDC.ar(Convolution2.ar(Impulse.ar(freq * [1, 5/4]).sum, b, framesize: b.numFrames) * -40.dbamp) ! 2;
		}.play;
	};
};
)



// multiple impulse responses for timbre control
(
s.waitForBoot {
	var c = Condition.new, cleanfunc = { CmdPeriod.remove(cleanfunc); b.free };
	fork {
		b = Buffer.allocConsecutive(3, s, 2048, 1);
		CmdPeriod.add(cleanfunc);
		s.sync;
		a = {
			var sig = [BrownNoise.ar, PinkNoise.ar, WhiteNoise.ar];
			sig.do { |chan, i|
				RecordBuf.ar(chan * EnvGen.ar(Env(#[0, 1, 0], #[0.5, 0.5], \sin), timeScale: b[i].duration, doneAction: 2), b[i], loop: 0);
			};
		}.play;
		OSCpathResponder(s.addr, ['/n_end', a.nodeID], { |time, resp, msg|
			resp.remove;
			c.unhang;
		}).add;
		c.hang;
		a = {
			var freq = MouseX.kr(150, 450, warp: 1, lag: 0.1),
				index = MouseY.kr(0, 1.99, lag: 0.1),
				iWhole = index.trunc(2),
				iFrac = index - iWhole,
				iAdjust = iFrac >= 1.0,
				trig = Impulse.ar(freq),
				bufs = b[0].bufnum + [iWhole + (2 * iAdjust), iWhole + 1],
				convolvers = bufs.collect { |buf|
					Convolution2.ar(trig, buf, HPZ1.kr(buf).abs, framesize: b[0].numFrames)
				};
			(
				XFade2.ar(
					// Select.ar(iWhole + (2 * iAdjust), convolvers),
					// Select.ar(iWhole + 1, convolvers),
					convolvers[0], convolvers[1],
					iFrac.fold(0, 1) * 2 - 1
				) * -30.dbamp
			) ! 2;
		}.play;
	};
};
)



a.trace;

a.free;

LeakDC.ar(Convolution2.ar(Impulse.ar(freq), b, framesize: b.numFrames) * -35.dbamp) ! 2;



// "works" for pitch but we lose all guzheng color
// interesting that the attack gives a darker sound than the (noisier?) decay
// glisses sound like sliding on guitar strings, just a bit
// longer kernel?

f = SoundFile.openRead("/media/39ED-A99A/from-linux/xinghai/11-12-spring/max/GZ A.aif");
// f.seek(rrand(108802, 120000));
f.seek(rrand(1000, 15000));
f.readData(d = Signal.newClear(4096));
f.close;

d.plot

d = d * Env(#[0, 1, 0], 0.5 ! 2, \sin).discretize(d.size);

b.free;
b = Buffer.sendCollection(s, d, action: { "done".postln });

a = {
	var freq = MouseX.kr(150, 450, warp: 1, lag: 0.1);
	LeakDC.ar(Convolution2.ar(Impulse.ar(freq * [1, 5/4]).sum, b, framesize: b.numFrames) * -20.dbamp) ! 2;
}.play;


a.free;



// still can't hear gz quality
// buffer transitions are not smooth

b.free;

(
fork {
	var c = Condition.new, f, d,
	kernelsize = 4096,
	hann = Env(#[0, 1, 0], 0.5 ! 2, \sin).discretize(kernelsize);
	b = Buffer.allocConsecutive(5, s, kernelsize, 1);
	s.sync;

	f = SoundFile.openRead("/media/39ED-A99A/from-linux/xinghai/11-12-spring/max/GZ A.aif");
	if(f.notNil) {
		protect {
			b.do { |buf, i|
				f.seek(rrand(1000, 40000).debug(i));
				f.readData(d = Signal.newClear(kernelsize));
				fork {
					buf.sendCollection(d * hann, action: { c.unhang });
				};
				c.hang;
			};
			"buffers ready".postln;
		} { f.close };
	};
}
)

a = {
	var freq = MouseX.kr(150, 450, warp: 1, lag: 0.1),
	index = MouseY.kr(0, b.size - 1.001, lag: 0.1),
	iWhole = index.trunc(2),
	iFrac = index - iWhole,
	iAdjust = iFrac >= 1.0,
	trig = Impulse.ar(freq),
	bufs = b[0].bufnum + [iWhole + (2 * iAdjust), iWhole + 1],
	convolvers = bufs.collect { |buf|
		LeakDC.ar(Convolution2.ar(trig, buf, HPZ1.kr(buf).abs, framesize: b[0].numFrames))
	};
	(
		Limiter.ar(XFade2.ar(
			convolvers[0], convolvers[1],
			iFrac.fold(0, 1) * 2 - 1
		))
	) ! 2;
}.play;

a.free;