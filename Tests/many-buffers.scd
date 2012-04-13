
~sampDir = HrVideoData.filenameSymbol.asString.dirname.dirname.dirname +/+ "samples";

~bufs = (~sampDir +/+ "Audio/*.wav").pathMatch.collect { |path|
	Buffer.read(s, path);
};


~dampBufs = ~bufs.select { |buf|
	buf.path.basename.asInteger <= 21
};

// then use this in a pattern
Pdefn(\dampingBufs, Prand(~dampBufs, inf));


h = Hadron.new;