ORIGINAL README FROM BASE git REPO BY Johannes Schindelin @ http://repo.or.cz/w/cvsclone.git:

As git cvsimport is pretty slow over the wire (and as cvs2git can do a substantially better job if there are a lot of branches), it is often better to "clone" a whole CVS repository. Enter cvsclone, written by Peter Backes.

You can find a few touchups by yours truly here, allowing to pipe the output of "cvs rlog" into a file, editing the file to fix errors (such as geniuses who put the cvs log of moved files into a commit message) and use that file as input instead. 