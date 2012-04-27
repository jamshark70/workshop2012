INSTALLING THESE EXTENSIONS

Windows:

- Remove older versions of these same extensions. If you have them, they'll be installed in one of these locations:

** C:\Documents and Settings\[your username]\SuperCollider\Extensions
** C:\Program Files\SuperCollider\SCClassLibrary\Extensions

- Copy these directories into C:\Documents and Settings\[your username]\SuperCollider\Extensions.

- Start SC.

- Check whether the new classes are there: run the line "MixerChannel" in SC. "Class not defined" means there's a problem.


OSX:

- Make a new directory: ~/Library/Application Support/SuperCollider/quarks -- in the Terminal, run the command.

mkdir ~/Library/Application Support/SuperCollider/quarks

- Copy the directories into this location.

- In SuperCollider, run these commands:

Quarks.install("ddwMixerChannel");
Quarks.install("ddwChucklib");
Quarks.install("ddwTimeline");
Quarks.install("ddwMIDI");

- In SuperCollider, recompile the class library: cmd-K.

- Check whether the new classes are there: run the line "MixerChannel" in SC. "Class not defined" means there's a problem.
