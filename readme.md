# cvsclone

Utility to clone cvs repositories over the cvspserver interface.

As ```git cvsimport``` is pretty slow over the wire (and as [cvs2git](http://cvs2svn.tigris.org/cvs2git.html) can do a substantially better job if there are a lot of branches), it is often better to "clone" a whole CVS repository. Enter cvsclone!

## Features

- Works with anonymous access. Will read $HOME/.cvspass if needed
- Can clone corrupt repositories: writes ,v files directly, does not need rcs (For example, ccvs module has archives that go backwards in time).

## Building

You will need [Flex](http://flex.sourceforge.net/) installed to create cvsclone. You can normally find this in your package manager i.e:

```bash
> apt-get install flex
```

Use [Homebrew](http://brew.sh/) on OS X:
```bash
> brew install flex
```

Once installed, clone this repository and build using **make**:

```bash
> git clone
> cd cvsclone
> make
```

The **cvsclone** binary should be output into the same folder and ready to use.

## Using

Set up your $CVSROOT to point to your repository of choice. You will need to log into CVS first so that your credentials are on the machine:

```bash
> set $CVSROOT=:pserver:your.user@mycvsserver.com:/SomeRepo
> cvs login
```

To clone the repository, use ```./cvsclone -d <connect pserver string> <module>```. For example:

```bash
> ./cvsclone -d $CVSROOT mymodule
```

Your repository should be converted and placed in a folder with the modules name.

## History

Originally written by Peter Backes. Check the header in [cvsclone.i](./cvsclone.i) for more details.

Additional fixes by [Mateusz Czapliński](https://github.com/akavel/cvsclone) (which this version is based on) allowing to pipe the output of "cvs rlog" into a file, editing the file to fix errors (such as geniuses who put the cvs log of moved files into a commit message) and use that file as input instead.

## Known Issues

- Can't enable compression
- Reading CVS password from $HOME/.cvspass uses $CVSROOT in a case sensitive way
- rlog format is ambiguous. If the separators it uses are found inside log messages, possibly followed by lines similar to what rlog outputs, things can go wrong horribly
- rcs 5.x rlog format does not contain the comment leader. It is guessed according to the extension as rcs and CVS do
- Uses normal diff format since this is the easiest one that works. ```diff --rcs``` is problematic, since files without newline at the last line are not output correctly. The major drawback about this is that deleted lines are transferred while they don't need to be. Even rdiff has major problems with lines that contain \0, because of a bug in CVS
- does not work incrementally. That would be much more work if updating the trunk since the most recent revision had to be reconstructed.  Also, the whole history probably had to be transferred again, with all log messages
- Horrible complexity. A file with n deltas takes O(n^2) to transfer
- Makes the cvs server really work hard, taking up all processor time. It should really not be used on public cvs servers, especially not on a regular basis. Perhaps it is useful for salvaging archive files from projects where only access to anonymous cvs is available
