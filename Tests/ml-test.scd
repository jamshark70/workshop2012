

BP.freeAll;

PR(\motionListener) => BP(\ml);
PR(\motionAngleGui).chuck(
	BP(\mg), nil, (model: BP(\ml))
);

BP(\ml).centroid

BP(\ml).rawCentroid

BP(\ml).points[0].listVars
BP(\ml).dim

Point(320, 240) / BP(\ml).dim

BP(\ml).maxmag = 0.01;

BP(\ml).normmag

BP(\ml).magsum / BP(\ml).maxmag

BP(\ml).listVars

o.free;
o = OSCFunc({ |msg| msg.postln }, '/coord');

o.free;

o = OSCFunc({ |msg|
	if(msg.last == 10) { msg.postln };
}, '/coord');


BP(\ml).rawCentroid

(
BP(\ml).predict = {
	var /*sum = Point(0, 0),*/ temppt, centroidx = 0, centroidy = 0, magsum = 0,
	theta, insertIndex, magtemp;
	~kmeans = 'KMeans'.asClass.tryPerform(\new, ~kmSize);
	~points.do { |p|
		magtemp = p.mag.last * 10000;
		temppt = [p.xabs.linlin(0, 319, -1, 1), p.yabs.linlin(0, 239, -1, 1)];
		centroidx = centroidx + (temppt[0] * magtemp);
		centroidy = centroidy + (temppt[1] * magtemp);
		magsum = magsum + magtemp;
		// if(p.predicted) {
		// 	sum = sum + (Point(p.new_x - p.x.last, p.new_y - p.y.last) * p.mag.last);
		// };
		// 0.75 = y-extent / x-extent
		// preserve the same aspect ratio in kmeans
		if(p.mag.last >= ~magThresh) { ~kmeans.add(temppt * #[1, 0.75]) };
	};
	~rawCentroid = Point(
		(centroidx / max(magsum, 1)), // .linlin(-1, 1, 0, 319),
		(centroidy / max(magsum, 1)) // .linlin(-1, 1, 0, 239)
	);
	~kmeans.update;
	// lazy: these might be expensive and not always requested
	// this is one of the most unintentionally humorous lines I've written
	// in rather some time
	~clusterCalcs = ~clusterFuncs.collect { |func| Thunk(func) };
	
	~magsum = magsum;
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
)

106 /% 80




(
BP(\ml).points[4].addPoint = { |y, x, mag|
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
[x1, y1, mag].postln;
		currentEnvironment
	};
)