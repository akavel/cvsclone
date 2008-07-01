all: cvsclone

cvsclone: lex.yy.c
	gcc -Wall -g lex.yy.c -o cvsclone

lex.yy.c: cvsclone.l
	flex cvsclone.l
