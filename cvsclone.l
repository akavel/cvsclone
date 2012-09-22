/* cvsclone.l */

/*
 * Copyright (C) 2006  Peter Backes <rtc@gmx.de>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 * 
 * BUILDING
 *
 * flex cvsclone.l && gcc -Wall -O2 lex.yy.c -o cvsclone
 *
 * EXAMPLE
 *
 * *-------------------------------------------------------------------*
 * | Applying this tool to sourceforge.net or savannah.gnu.org is      |
 * | neither necessary nor recommended: With $1 being the project, you |
 * | can simply                                                        |
 * |      rsync -av rsync://$1.cvs.sourceforge.net/cvsroot/$1/ $1      |
 * | or                                                                |
 * |           rsync -av rsync://cvs.sv.gnu.org/sources/$1 $1          |
 * | respectively (try also 'web' instead of 'sources').               |
 * *-------------------------------------------------------------------*
 *
 * cvsclone -d :pserver:anonymous@cvs.example.org:/var/lib/cvs module
 *
 * DESCRIPTION
 * 
 * Utility to clone cvs repositories over the cvspserver interface.  Works
 * for anonymous access.
 * 
 * FEATURES
 *
 * - reads $HOME/.cvspass
 *
 * - can clone corrupt repositories: writes ,v files directly, does not
 *   need rcs.  (For example, ccvs module has archives that go backwards
 *   in time.)
 *
 * PROBLEMS
 *
 * - can't enable compression.
 *
 * - reading cvs password from $HOME/.cvspass uses CVSROOT in a 
 *   case sensitive way.
 *
 * - rlog format is ambiguous.  If the separators it uses are found inside 
 *   log messages, possibly followed by lines similar to what rlog
 *   outputs, things can go wrong horribly.
 *
 * - rcs 5.x rlog format does not contain the comment leader.  It is 
 *   guessed according to the extension as rcs and CVS do.
 *
 * - uses normal diff format since this is the easiest one that works.
 *   diff --rcs is problematic, since files without newline at the
 *   last line are not output correctly.  The major drawback about this
 *   is that deleted lines are transfered while they don't need to be.
 *   even rdiff has major problems with lines that contain \0, because
 *   of a bug in cvs.
 * 
 * - does not work incrementally.  That would be much more work if
 *   updating the trunk since the most recent revision had to be 
 *   reconstructed.  Also, the whole history probably had to be transfered 
 *   again, with all log messages.
 * 
 * - Horrible complexity.  A file with n deltas takes O(n^2) to transfer.
 *
 * - Makes the cvs server really work hard, taking up all processor time.
 *   It should really not be used on public cvs servers, especially
 *   not on a regular basis.  Perhaps it is useful for salvaging 
 *   archive files from projects where only access to anonymous cvs 
 *   is available.
 *
 *
 * Patches and comments are welcome.
 *
 */
%{
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>
#include <resolv.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>

#include <errno.h>
#include <ctype.h>
#include <assert.h>
#include <stdlib.h>
#include <time.h>
#include <stdio.h>
#include <string.h>
#ifdef _IO_getc_unlocked
#undef getc
#define getc _IO_getc_unlocked
#endif
%}
%s HDR0 HDR1 DESC ACCL0 TAGL0 TAGL1 LCKL0 LCKL1 REV0 REV1 REV2 ATR0 ATR1
%s REV3 REV4 RLST XREV FEND SRV0 SRVA SRVB SRV1 SRV2 SRV3 SRV4 SRV5 SRV6 PWF0
%s REVSKIP
%option noyywrap nounput
num     [0-9.]+
special [$,.:;@]
idchar  [^$,.:;@ \b\t\v\f\r\n]
ws      [ \b\t\v\f\r]
id      {num}?{idchar}({idchar}|{num})*
sym     [0-9]?{idchar}({idchar}|[0-9])*
xid     ({idchar}|{special}|{ws})+
yid     ({idchar}|{special})+
nws     (ws|\n)
date1   [0-9]+(-[0-9]{2}){2}\ [0-9]{2}(:[0-9]{2}){2}\ [-+][0-9]{4}
date2   [0-9]+(\/[0-9]{2}){2}\ [0-9]{2}(:[0-9]{2}){2}

	/*
	RCS file: x,v
	Working file: x
	head: 1.2
	branch: 1.1
	locks: [strict]
		rtc: 1.1
		rtc: 1.1.2.1
	access list:
		root
		rtc
	symbolic names:
		test: 1.1
	keyword substitution: kv
	total revisions: ; selected\ revisions:
	description: 

 
	file()		: trunk(Head) tree(Head)
			;
	trunk(p)	:
			| adelta(p) trunk(p->next)
			;
	tree(root)	:
			| tree(root->next) forest(root->branches)
			;
	forest(broot)	:
			| forest(broot->nextbranch) abranch(broot) tree(broot)
			;
	abranch(root)	:
			| abranch(root->next) adelta(root)
			;

	adelta	:
		"----------------------------\n"
		"revision %s" [ "\tlocked by: %s;" ] "\n"

		"date: %s;  author: %s;  state: %s; lines: +%ld -%ld"
		[ "; kopt: %s" ]
		[ "; commitid: %s" ]
		[ "; filename: %s" ]
		[ "; mergepoint:" ("  %s;")+ ]
		"\n"

		[ "branches:" ("  %s;")+ "\n" ]
		[ "included:" ("  %s;")+ ]
		[ "excluded:" ("  %s;")+ ]
		[ "ignored:" ("  %s;")+ ] "\n"  // '\n' if one of them is there
		[ "source: %s" [ "\t%s" ] "\n" ]

		<log>*"\n"
	 */
%{
char *getstr(unsigned long n, char *s)
{
	s[n] = '\0';
	return s;
}
union revref;
struct rev {
	char *num;
	time_t date;
	char *author, *state, *comment, *commitid, *kopt;
	int ladd, ldel;
	/* mergepoint */
	/* branches */
	/* included */
	/* excluded */
	/* ignored */
	char *server,  /* originating server */
		*onum; /* original number */
	char *log;
	struct rev *next, *branch, *sub;
};
union revref {
	char *num;
	struct rev *r;
};
struct rpair {
	char *item;
	union revref rev;
};
struct rcsfile {
	char *source, *workfile;
	union revref head, branch;
	int strict;
	char *ksub, *leader;
	int tot, sel;
	char *descr;
	struct rpair *lckl, *lckt, *tagl, *tagt;
	char **accl, **acct; /* access list, access top */
	struct rev *revl, *revt;
} rfile;

void rcsinit(void)
{
	rfile.source = rfile.workfile = rfile.head.num
		= rfile.branch.num = rfile.ksub = rfile.leader
		= rfile.descr = NULL;
	rfile.strict = rfile.tot = rfile.sel = 0;
	rfile.lckl = rfile.lckt = rfile.tagl = rfile.tagt = NULL;
	rfile.revl = rfile.revt = NULL;
	rfile.accl = rfile.acct = NULL;
}

void addaccl(char *s)
{
	if (!rfile.accl)
		rfile.acct = rfile.accl = malloc(16 * sizeof *rfile.accl);
	else if (!((rfile.acct - rfile.accl) % 16)) {
		unsigned long n = rfile.acct - rfile.accl;
		rfile.accl = realloc(rfile.accl, (n+16) * sizeof *rfile.accl);
		rfile.acct = rfile.accl + n;
	}
	
	*rfile.acct++ = s;
}
void addtag(char *s)
{
	if (!rfile.tagl)
		rfile.tagt = rfile.tagl = malloc(16 * sizeof *rfile.tagl);
	else if (!((rfile.tagt - rfile.tagl) % 16)) {
		unsigned long n = rfile.tagt - rfile.tagl;
		rfile.tagl = realloc(rfile.tagl, (n+16) * sizeof *rfile.tagl);
		rfile.tagt = rfile.tagl + n;
	}
	
	rfile.tagt++->item = s;
}
void addlck(char *s)
{
	if (!rfile.lckl)
		rfile.lckt = rfile.lckl = malloc(16 * sizeof *rfile.lckl);
	else if (!((rfile.lckt - rfile.lckl) % 16)) {
		unsigned long n = rfile.lckt - rfile.lckl;
		rfile.lckl = realloc(rfile.lckl, (n+16) * sizeof *rfile.lckl);
		rfile.lckt = rfile.lckl + n;
	}
	
	rfile.lckt++->item = s;
}
void setdate(unsigned long n, char *s, char *t)
{
	char d;
	struct tm tm;
	sscanf(s, "%d%c%d%c%d %d:%d:%d", &tm.tm_year, &d, &tm.tm_mon, &d,
		&tm.tm_mday, &tm.tm_hour, &tm.tm_min, &tm.tm_sec);
	tm.tm_year -= 1900;
	tm.tm_mon--;
	if (t) {
		int z = atoi(t);
		if (z < 0)
			tm.tm_sec += -z / 100 * 3600 + -z % 100 * 60;
		else
			tm.tm_sec -= z / 100 * 3600 + z % 100 * 60;
	}
	rfile.revt->date = timegm(&tm);
#if 0
	printf("setdate: %.*s, %.5s --> %s", (int)n, s, t, 
		ctime(&rfile.revt->date));
#endif
	
}
void addrev(char *s)
{
	if (!rfile.revt)
		rfile.revt = rfile.revl;
	else 
		rfile.revt++;
	assert(rfile.revl && rfile.revt < rfile.revl + rfile.sel);
	/* assert(rfile.revt - rfile.revl < rfile.n) */
	rfile.revt->num = s;
	rfile.revt->author = rfile.revt->state
		= rfile.revt->comment = rfile.revt->commitid 
		= rfile.revt->kopt = rfile.revt->server
		= rfile.revt->onum = rfile.revt->log = NULL;
	rfile.revt->next = rfile.revt->branch = rfile.revt->sub = NULL;
	rfile.revt->ladd = rfile.revt->ldel = 0;
}
void addrl(char *s)
{
}
void initrev(int n)
{
	if ((rfile.sel = n))
		rfile.revl = malloc(n * sizeof *rfile.revl);
}
char *cvsroot, *cvspass, *cvsuser, *cvshost, *cvsdir;
int chkroot(char *s, size_t le, int s1)
{
	size_t l = strlen(cvsroot);
	
	if (s1) {
		char *x, *y;
#if 0
		fprintf(stderr, "cvsroot=%s, s=%s, s1=%d\n", cvsroot, s, s1);
#endif
		if (*s != ':' || !(x = strchr(s + 1, ':'))
		 || !(x = strchr(x + 1, ':'))
		 || strncmp(cvsroot, s, x - s + 1)
		 || !isdigit(*(x + 1)))
			return 0;
#if 0
		fprintf(stderr, "survived\n");
#endif
		y = cvsroot + (x - s) + 1;
		while (isdigit(*++x))
			continue;
		if (strncmp(y, x, l - (y - cvsroot)) 
		 || x[l - (y - cvsroot)] != ' ')
			return 0;
		l += x - s - (y - cvsroot);
#if 0
		fprintf(stderr, "l=%u(%d, %u), s=%s, cvsroot=%s, x=%s, y=%s\n", 
			l, x - s - (y - cvsroot), le,
			s, cvsroot, x, y);
#endif
	} else if (strncmp(cvsroot, s, l) || s[l] != ' ')
		return 0;
	
	cvsroot = strncpy(realloc(cvsroot, le + 1), s, le);
	cvsroot[l] = cvsroot[le+1] = '\0';
	cvspass = cvsroot + l + 1;
	return 1;
}
FILE *rcsfiop;
void rcsfwrite(char *s, size_t l, FILE *stream)
{
	for (; l--; putc(*s++, stream))
		if (*s == '@')
			putc(*s, stream);
}
void rcsrang(int d0, int d1, int a0, int a1)
{
	fprintf(rcsfiop, "d%d %d\na%d %d\n", d0, d1-d0+1, d1, a1-a0+1);
}
void rcsrang2(int d0, int d1, int a)
{
	fprintf(rcsfiop, "d%d %d\n", d0, d1-d0+1);
}
void rcsrang3(int d, int a0, int a1)
{
	fprintf(rcsfiop, "a%d %d\n", d, a1-a0+1);
}
char *queue, *que;
size_t queuel;
char *getq(size_t l)
{
	if (!queue)
		return queue = malloc(queuel = l);
	queuel += l;
	queue = realloc(queue, queuel);
	return queue + queuel - l;
}
void begin(char *s, size_t l)
{
	char *p = s + 10, *fi, *fi2;
	size_t l0 = strlen(cvsdir);
	s[l-1] = '\0';
	if (strncmp(cvsdir, p, l0) || p[l0] != '/') {
		fprintf(stderr, "path mismatch.\n");
		return;
	}
	fi = p + l0 + 1;
	while ((fi2 = strchr(fi, '/'))) {
		*fi2 = '\0';
		mkdir(p + l0 + 1, 0777);
		*fi2 = '/';
		fi = fi2 + 1;
	}
	strcpy(getq(strlen(p + l0 + 1) + 1), p + l0 + 1);
	if (!access(p + l0 + 1, R_OK)) {
		char buffer[1024];
		snprintf(buffer, sizeof(buffer), "%s.old", p + l0 + 1);
		rename(p + l0 + 1, buffer);
	}
	if (!(rcsfiop = fopen(p + l0 + 1, "w")))
		return;
	s[l-1] = '\n';
	fputs("\n", rcsfiop);
	fwrite(s, 1, l, rcsfiop);
}

%}

%%
<HDR0>RCS\ file:\ {xid}\n rfile.source = getstr(yyleng-11, yytext+10);
<HDR0>Working\ file:\ {xid}\n rfile.workfile = getstr(yyleng-15, yytext+14);
<HDR0>head:\ {num}\n    rfile.head.num = getstr(yyleng-7, yytext+6);
<HDR0>head:\n           rfile.head.num = NULL;
<HDR0>branch:\n         rfile.branch.num = NULL;
<HDR0>branch:\ {num}\n  rfile.branch.num = getstr(yyleng-9, yytext+8);
<HDR0>locks:\ strict\n  BEGIN LCKL0; rfile.strict = 1; 
<HDR0>locks:\n          BEGIN LCKL0; rfile.strict = 0; 
<HDR0>access\ list:\n   BEGIN ACCL0;
<HDR0>symbolic\ names:\n BEGIN TAGL0;
<HDR0>keyword\ substitution:\ .*\n rfile.ksub = getstr(yyleng-23, yytext+22); 
<HDR0>comment\ leader:\ \".*\"\n rfile.leader = getstr(yyleng-19, yytext+17);
<HDR0>total\ revisions:\ [0-9]+;\t BEGIN HDR1; rfile.tot = atoi(yytext+17);
<HDR1>selected\ revisions:\ [0-9]+\n BEGIN HDR0; initrev(atoi(yytext+20));
<HDR0>description:\n    BEGIN DESC;
<HDR0>\n                /* EMPTY */
<DESC>={77}\n           BEGIN FEND; *yytext = '\0'; if (!rfile.descr) rfile.descr = yytext;
<DESC>-{28}\n           BEGIN REV0; *yytext = '\0'; if (!rfile.descr) rfile.descr = yytext;
<DESC>.*\n              if (!rfile.descr) rfile.descr = yytext;
<ACCL0>\t{id}\n         addaccl(getstr(yyleng-2, yytext+1));
<ACCL0>""/[^\t]         BEGIN HDR0;
<TAGL0>\t{sym}:\        BEGIN TAGL1; addtag(getstr(yyleng-3, yytext+1)); 
<TAGL0>""/[^\t]         BEGIN HDR0;
<TAGL1>{num}\n          BEGIN TAGL0; rfile.tagt[-1].rev.num = getstr(yyleng-1, yytext); 
<LCKL0>\t{id}:\         BEGIN LCKL1; addlck(getstr(yyleng-3, yytext+1)); 
<LCKL0>""/[^\t]         BEGIN HDR0;
<LCKL1>{num}\n          BEGIN LCKL0; rfile.lckt[-1].rev.num = getstr(yyleng-1, yytext);
<REV0>revision\ {num}\n BEGIN REV2; addrev(getstr(yyleng-10, yytext+9));
<REV0>revision\ {num}\t BEGIN REV1; addrev(getstr(yyleng-10, yytext+9));
<REV1>locked\ by:\ {id};\n BEGIN REV2; /* getstr(yyleng-13, yytext+11); */
<REV2>date:\ {date1};\ \  BEGIN ATR0; setdate(yyleng-15, yytext+6, yytext+yyleng-8);
<REV2>date:\ {date2};\ \  BEGIN ATR0; setdate(yyleng-9, yytext+6, NULL);
<ATR0>author:\ {id};\ \  rfile.revt->author = getstr(yyleng-11, yytext+8);
<ATR0>state:\ {id};\ \  rfile.revt->state = getstr(yyleng-10, yytext+7);
<ATR0>state:\ {id};\n   BEGIN REV3; rfile.revt->state = getstr(yyleng-9, yytext+7);
<ATR0>lines:\ \+[0-9]+\  BEGIN ATR1; rfile.revt->ladd = atoi(yytext+8);
<ATR1>-[0-9]+;?\n         BEGIN REV3; rfile.revt->ldel = atoi(yytext+1);
<ATR1>-[0-9]+;\ \       BEGIN ATR0; rfile.revt->ldel = atoi(yytext+1);
<ATR0>kopt:\ [^;\n]+;\n BEGIN REV3; rfile.revt->kopt = getstr(yyleng-8, yytext+6);
<ATR0>kopt:\ [^;\n]+;\ \  rfile.revt->kopt = getstr(yyleng-9, yytext+6);
<ATR0>commitid:\ [0-9a-f]{16};\ \  rfile.revt->commitid = getstr(16, yytext+10);
<ATR0>commitid:\ [0-9a-f]{16};\n BEGIN REV3; rfile.revt->commitid = getstr(16, yytext+10);
<ATR0>mergepoint:\ {num};\n BEGIN REV3; /* getstr(yyleng-14, yytext+12); */
<REV3>branches:/.*\n    BEGIN RLST;
<REV3,REV4>={77}\n      BEGIN FEND; *yytext = '\0'; if (!rfile.revt->log) rfile.revt->log = yytext; if (rfile.revt) rfile.revt++;
<REV3,REV4>-{28}\n      BEGIN REV0; *yytext = '\0'; if (!rfile.revt->log) rfile.revt->log = yytext;
<REV3>.*\n              BEGIN REV4; assert(!rfile.revt->log); rfile.revt->log = yytext;
<RLST>\ \ {num};        addrl(getstr(yyleng-3, yytext+2));
<RLST>\n                BEGIN REV3;
<REV4>The\ changelog\ prior\ to\ shifting.*\n BEGIN REVSKIP; *yytext = '\0'; if (!rfile.revt->log) rfile.revt->log = yytext;
<REVSKIP>={77}\n      BEGIN REV0; *yytext = '\0'; if (!rfile.revt->log) rfile.revt->log = yytext;
<REVSKIP>.*\n		*yytext = '\0'; /* do nothing */
<REV4>.*\n              if (!rfile.revt->log) rfile.revt->log = yytext;
<FEND><<EOF>>           return EOF;

<SRV0>M\ \n             BEGIN SRVA;
<SRVA>M\ RCS\ file:\ {xid}\n BEGIN SRVB; begin(yytext+2, yyleng-2);
<SRVB>M\ ={77}\n	BEGIN SRV0; fwrite(yytext+2, 1, yyleng-2, rcsfiop); fclose(rcsfiop);
<SRVB>M\ .*\n           fwrite(yytext+2, 1, yyleng-2, rcsfiop);
<SRV0,SRV1,SRV2,SRV3,SRV4,SRV5,SRV6>E\ .*\n fwrite(yytext+2, 1, yyleng-2, stderr);
<SRV0>I\ LOVE\ YOU\n    fprintf(stderr, "%s", yytext);
<SRV0>error\ [^ \n]*\ .*\n return 1;
<SRV0>ok\n              return 0;
<SRV0><<EOF>>           return EOF;
<SRV1>M\ <\ .*\n        BEGIN SRV2; rcsfwrite(yytext+4, yyleng-5, rcsfiop);
<SRV2>M\ <\ .*\n        yytext[3] = '\n'; rcsfwrite(yytext+3, yyleng-4, rcsfiop);
<SRV2>M\ \\\ .*\n       BEGIN SRV3;
<SRV2,SRV5>ok\n         putc('\n', rcsfiop); return 0;
<SRV2,SRV5>error\ [^ \n]*\ .*\n putc('\n', rcsfiop); return 1;
<SRV3,SRV1,SRV4,SRV6>ok\n return 0;
<SRV3,SRV1,SRV4,SRV6>error\ [^ \n]*\ .*\n return 1;
<SRV4>M\ [0-9]+,[0-9]+c[0-9]+,[0-9]+\n rcsrang(atoi(yytext+2), atoi(strchr(yytext, ',')+1), atoi(strchr(yytext, 'c')+1), atoi(strrchr(yytext, ',')+1));
<SRV4>M\ [0-9]+c[0-9]+,[0-9]+\n rcsrang(atoi(yytext+2), atoi(yytext+2), atoi(strchr(yytext, 'c')+1), atoi(strrchr(yytext, ',')+1));
<SRV4>M\ [0-9]+,[0-9]+c[0-9]+\n rcsrang(atoi(yytext+2), atoi(strchr(yytext, ',')+1), atoi(strchr(yytext, 'c')+1), atoi(strchr(yytext, 'c')+1));
<SRV4>M\ [0-9]+c[0-9]+\n   rcsrang(atoi(yytext+2), atoi(yytext+2), atoi(strchr(yytext, 'c')+1), atoi(strchr(yytext, 'c')+1));
<SRV4>M\ [0-9]+,[0-9]+d[0-9]+\n rcsrang2(atoi(yytext+2), atoi(strchr(yytext, ',')+1), atoi(strchr(yytext, 'd')+1));
<SRV4>M\ [0-9]+d[0-9]+\n   rcsrang2(atoi(yytext+2), atoi(yytext+2), atoi(strchr(yytext, 'd')+1));
<SRV4>M\ [0-9]+a[0-9]+,[0-9]+\n rcsrang3(atoi(yytext+2), atoi(strchr(yytext, 'a')+1), atoi(strchr(yytext, ',')+1));
<SRV4>M\ [0-9]+a[0-9]+\n   rcsrang3(atoi(yytext+2), atoi(strrchr(yytext, 'a')+1), atoi(strchr(yytext, 'a')+1));
<SRV4>M\ >\ .*\n        BEGIN SRV5; rcsfwrite(yytext+4, yyleng-5, rcsfiop);
<SRV5>M\ >\ .*\n        yytext[3] = '\n'; rcsfwrite(yytext+3, yyleng-4, rcsfiop);
<SRV5>""/M\ [0-9]       BEGIN SRV4; putc('\n', rcsfiop);
<SRV5>M\ \\\ .*\n       BEGIN SRV6;
<SRV1,SRV4>M\ RCS\ file:.*\n |
<SRV1,SRV4>M\ ========.*\n |
<SRV1,SRV4>M\ retrieving.*\n |
<SRV1,SRV4>M\ diff.*\n  |
<SRV1,SRV4>M\ Index:.*\n |
<SRV1>M\ [0-9]+(,[0-9]+)?d[0-9]+\n |
<SRV4>M\ \\\ .*\n       |
<SRV4>M\ (<\ .*|---)\n  /* ignore */
<SRV5>([^M\n]|M([^ \n]|\ [^0-9\n])).*\n? |
<SRV5>M\ ?\n?           |
<SRV0,SRV1,SRV2,SRV3,SRV4,SRV6>.*\n? fwrite(yytext, 1, yyleng, stderr);

<PWF0>\/1\ [^ \n]+\ .*\n if (chkroot(yytext+3, yyleng-4, 1)) return 0;
<PWF0>[^ \n]+\ .*\n     if (chkroot(yytext, yyleng-1, 0)) return 0;
<PWF0>.*\n?             /* ignore unknown lines */
<PWF0><<EOF>>           return EOF;

<HDR0>[^t\n].*\n?       |
<HDR0>t[^\t\n]*         |
<TAGL0,LCKL0>\t[^:\n]*:?\n? |
<TAGL0,LCKL0>\t[^:\n]*:[^ ].*\n? |
<TAGL0,LCKL0>\t[^:\n]*:\  |
<ACCL0>\t.*\n?          |
<REV0>[^\t\n]*[\t\n]?   |
<REV2>[^;\n]*(""|;\ ?)  |
<ATR0>[^l\n][^;\n]*     |
<ATR0>[^l\n][^;\n]*;\ ? |
<ATR0>(\n|l[^ \n]*)     |
<ATR0>lines:\ [^ \n]*   |
<ATR1,RLST>[^;\n]*      |
<ATR1>[^;\n]*;\ ?       |
<HDR1,DESC,TAGL1>.*\n?  |
<LCKL1,REV1,REV3>.*\n?  |
<REV4,XREV,SRVA>.*\n?   |
<SRVB>.*\n?             |
(.|\n)                  printf("Unmached: <%.*s>\n", yyleng, yytext);
%%

static YY_BUFFER_STATE yybuf;
/* Read rlog to buffer */
size_t rlread(char *ptr, size_t nmemb, FILE *stream)
{
	char *top = ptr;
	static int state;
	while (nmemb--) {
		register int c = getc(stream);

		if (c == EOF) {
			state = 0;
			return ptr - top;
		}
		*ptr++ = c;
		if (c == '\n') {
			if (state == 77) {
				state = 0;
				return ptr - top;
			}
			state = 0;
		} else if (state < 78) {
			if (c == '=')
				state++;
			else
				state = 78;
		}
	}
	return ptr - top;
}

void *ftobuf(FILE *stream, unsigned long *s)
{
	unsigned long siz = 0;
	void *buf = NULL;
	do {
		buf = realloc(buf, siz + BUFSIZ + 2);
		siz += fread(buf + siz, 1, BUFSIZ, stream);
		/*siz += rlread(buf + siz, BUFSIZ, stream);*/
	} while (siz && !(siz % BUFSIZ));
	*s = siz += 2;

	if (*s == 2) {
		free(buf);
		return NULL;
	}
	return realloc(buf, siz);
}

char *strfix(char *s)
{
	unsigned long l = strlen(s);
	if (!l)
	       return s;
	if (s[l-1] == '\n')
		s[l-1] = '\0';
	return s;	
}
FILE *srv, *rlog_input;

FILE *srvopen(void)
{
#ifndef XTEST
	struct hostent *host;
	struct servent *serv;
	struct sockaddr_in sin;
	int fd;
#endif
	char *cvsport = NULL;
	if (strncmp(cvsroot, ":pserver:", 9)
	 || !(cvsdir = strchr(cvsuser = cvsroot + 9, ':'))
	 || !(cvshost = strchr(cvsuser, '@')) || cvshost > cvsdir)
		return NULL;
	*cvshost++ = *cvsdir++ = '\0';
	if (isdigit(*cvsdir)) {
		cvsport = cvsdir;
		while (isdigit(*++cvsdir))
			continue;
	}
#ifndef XTEST
	memset(&sin, '\0', sizeof sin);
	if (cvsport)
		sin.sin_port = htons(atoi(cvsport));
	else if (!(serv = getservbyname("cvspserver", "tcp")))
		return NULL;
	else
		sin.sin_port = serv->s_port;
	if (!(host = gethostbyname(cvshost))
	 || (fd = socket(PF_INET, SOCK_STREAM, 0)) == -1)
		return NULL;
	sin.sin_family = AF_INET;
	memcpy(&sin.sin_addr, host->h_addr, host->h_length);
	if (connect(fd, (struct sockaddr *)&sin, sizeof sin) == -1) {
		close(fd);
		return NULL;
	}
	return fdopen(fd, "w+");
#else
	return NULL;
#endif
}
char *getpar(char *s)
{
	char *p = NULL, *q = NULL;
	while (*s)
		if (*s == '.')
			p = q, q = s++;
		else
			s++;
	return p;
}

struct rev *range(struct rev *begin)
{
	char *brb, *bre;
	if (begin >= rfile.revt)
		return NULL;
	brb = begin->num;
	bre = strrchr(brb, '.');
	if (!bre || bre == strchr(brb, '.'))
		bre = brb;
	else
		bre++;
	/*fprintf(stderr, "brb: %s, n: %u\n", brb, bre - brb);*/
	while (begin < rfile.revt 
	    && (bre - brb ? !strncmp(begin->num, brb, bre - brb)
	          && !strchr(begin->num + (bre - brb), '.')
	        : strchr(begin->num, '.') == strrchr(begin->num, '.')))
	          /* works fine even if no '.' present */
		begin++;
	return begin;
}

/*
 :
1.4
 |  
1.3 | next
 |  v
1.2   branch
 |   ------>      
1.1--1.1.1.1--1.1.1.1.1.1 - -
        |   
     1.1.2.1 | sub
        |    v
     1.1.3.1
        :


next            branch          sub              T
v               -                                /1.2
*               | -                              |1.1*
                : :                              : F B
        *       | |             ->               | / <1.1.2.1*
                : :             :                : : 
        *       | |       -     |                | | /1.1.1.2
        ^       | ->    - |     -                | | |1.1.1.1*
                :       : :                      : : : F B 
        *       |       | |                      | | | / /1.1.1.2.1.2
        ^       |       | ->                     | | | \ \1.1.1.2.1.1*
                :       :                        : : : F B
        *       |       |                        | | | / /1.1.1.1.1.2
        ^       |       ->                       | \ \ \ \1.1.1.1.1.1*
                :                                :   B
        *       |                                | / /1.2.1.2
        ^       ->                               \ \ \1.2.1.1*

*/
int prefix(const char *rev, const char *subrev)
{
	size_t l = strlen(rev);
	return !strncmp(rev, subrev, l) && subrev[l] == '.';
}

/* parse forest belonging to revision x */
struct rev *forest(struct rev *x, struct rev **b)
{
	struct rev *z = NULL;
	do {
		struct rev *branch(struct rev **b);
		struct rev *y = branch(b);
		y->sub = z;
		z = y;
	} while (*b < rfile.revt && prefix(x->num, (*b)->num));
	return z;
}
/* parse branch */
struct rev *branch(struct rev **b)
{
	struct rev *e = range(*b), *x, *y = *b;
	(*b)->next = NULL;
	for (x = *b; x < e - 1; x++)
		x[1].next = x;
	/* As for the trunk, for each branch revision, a forest can follow.
	 * However here the forests in decreasing order match the order 
	 * of the branch revisions.
	 */
	while (e < rfile.revt) {
		while (y <= x && !prefix(y->num, e->num))
			y++->branch = NULL;
		if (y > x)
			break;
		y->branch = forest(y, &e);
		y++;
	}
	*b = e;
	return x;
}

/* parse trunk */
struct rev *trunk(struct rev *b)
{
	struct rev *e = b ? range(b) : NULL, *x, *y = e;
	if (!e)
		return NULL;
	for (x = b; x < e - 1; x++)
		x->next = x + 1;
	x->next = NULL;
	/* For each trunk revision, a forest can follow.
	 * The forests are in increasing order, in contrast to the 
	 * trunk revisions, which are in decreasing order.
	 */
	while (e < rfile.revt) {
		/* search the trunk revision this forest belongs to */
		while (y > b && !prefix((--y)->num, e->num))
			y->branch = NULL;
		assert(y > b || prefix(y->num, e->num));
		/* parse the forest, set branch of the trunk revision */
		y->branch = forest(y, &e);
	}
	return b;
}

struct {
	int ndeltas, nfiles, nbranches;
} stats;

void rcsfputs(const char *s, FILE *stream)
{
	for (putc('@', stream); *s; putc(*s++, stream))
		if (*s == '@')
			putc(*s, stream);
	putc('@', stream);
}
void puttree(struct rev *x, FILE *stream)
{
	struct rev *y, *z;
	void putforest(struct rev *x, FILE *stream);
	for (y = x; y; y = y->next) {
		struct tm *tm;
		tm = gmtime(&y->date);
		fprintf(stream, "%s\n", y->num);
		fprintf(stream, "date\t%d.%02d.%02d.%02d.%02d.%02d;"
			"\tauthor %s;\tstate %s;\n", 
			tm->tm_year > 99 ? tm->tm_year + 1900 : tm->tm_year,
			tm->tm_mon + 1, tm->tm_mday, tm->tm_hour, tm->tm_min,
			tm->tm_sec, y->author, y->state);
		fprintf(stream, "branches");
		for (z = y->branch; z; z = z->sub)
			fprintf(stream, "\n\t%s", z->num);
			
		fprintf(stream, ";\n");
		fprintf(stream, "next\t%s;\n", y->next ? y->next->num : "");
		fprintf(stream, "\n");
	}
	putforest(x, stream);
}
void putforest(struct rev *x, FILE *stream)
{
	struct rev *z;
	if (!x)
		return;
	putforest(x->next, stream);
	for (z = x->branch; z; z = z->sub)
		puttree(z, stream);
}
void unqueue(void)
{
	ssize_t s;
	if (que == queue + queuel)
		return;
	fcntl(fileno(srv), F_SETFL, O_NONBLOCK);
	if ((s = write(fileno(srv), que, queue + queuel - que)) != -1)
		que += s;
	fcntl(fileno(srv), F_SETFL, 0L);
}
char *fi, *fi2;
void puttree2(struct rev *z, struct rev *x)
{
	struct rev *y;
	for (y = x; y; y = y->next) {
		void putfor2(struct rev *z, struct rev *x);
		
		if (!z) {
			for (z = y; z && !strcmp(z->state, "dead"); z = z->next)
				continue;
			if (z) {
				sprintf(getq(10*4+5+2+3+2+strlen(z->num)
					+ (fi2 - strrchr(fi, '/')) - 1), 
					"Argument -r%s\n"
					"Argument -aN\n"
					"Argument --\n"
					"Argument %.*s\n"
					"diff", z->num, 
					(int)(fi2 - strrchr(fi, '/') - 1),
					strrchr(fi, '/') + 1);
				queue[queuel-1] = '\n';
			} else
				/* file was initially added on branch */
				z = y;
		} else if (strcmp(y->state, "dead") && z != y) {
			sprintf(getq(10*5+5+2+2+2+2+strlen(z->num)
				+ strlen(y->num)
				+ (fi2 - strrchr(fi, '/'))), 
				"Argument -r%s\n"
				"Argument -r%s\n"
				"Argument -aN\n"
				"Argument --\n"
				"Argument %.*s\n"
				"diff", z->num, y->num, 
				(int)(fi2 - strrchr(fi, '/') - 1),
				strrchr(fi, '/') + 1);
			queue[queuel-1] = '\n';
			z = y;
		}
		putfor2(z, y->branch);
	}
}
void putfor2(struct rev *z, struct rev *x)
{
	if (!x)
		return;
	putfor2(z, x->sub);
	puttree2(z, x);
}
void puttree3(struct rev *z, struct rev *x)
{
	struct rev *y;
	for (y = x; y; y = y->next) {
		void putfor3(struct rev *z, struct rev *x);
		fprintf(stderr, "%s ", y->num);
		
		stats.ndeltas++;
		fprintf(rcsfiop, "\n\n%s\nlog\n", y->num);
		rcsfputs(y->log, rcsfiop);
		fprintf(rcsfiop, "\ntext\n@");
		
		if (!z) {
			for (z = y; z && !strcmp(z->state, "dead"); z = z->next)
				continue;
			if (z) {
				unqueue();
				BEGIN SRV1;
				yylex();
			} else
				/* file was initially added on branch */
				z = y;
		} else if (strcmp(y->state, "dead") && z != y) {
			unqueue();
			BEGIN SRV4;
			yylex();
			z = y;
		}
		fprintf(rcsfiop, "@\n");
		putfor3(z, y->branch);
	}
}
void putfor3(struct rev *z, struct rev *x)
{
	if (!x)
		return;
	stats.nbranches++;
	putfor3(z, x->sub);
	puttree3(z, x);
}

/* table of comment leader pairs, merged from RCS and CVS */
static const struct clpair {
	char *suffix, *comlead;
} cltbl[] = {
	{ "a"   , "-- " },      /* Ada */
	{ "ada" , "-- " },      
	{ "adb" , "-- " },      
	{ "ads" , "-- " },      
	{ "asm" , ";; " },      /* assembler (MS-DOS) */
	{ "bas" , "' "  },      /* Visual Basic code */
	{ "bat" , ":: " },      /* batch (MS-DOS) */
	{ "body", "-- " },      /* Ada */
	{ "c"   , " * " },      /* C */
	{ "c++" , "// " },      /* C++ in all its infinite guises */
	{ "cc"  , "// " },      
	{ "cpp" , "// " },      
	{ "cxx" , "// " },      
	{ "cl"  , ";;; "},      /* Common Lisp */
	{ "cmd" , ":: " },      /* command (OS/2) */
	{ "cmf" , "c "  },      /* CM Fortran */
	{ "cs"  , " * " },      /* C* */
	{ "csh" , "# "  },      /* shell */
	{ "dlg" , " * " },      /* MS Windows dialog file */
	{ "e"   , "# "  },      /* efl */
	{ "epsf", "% "  },      /* encapsulated postscript */
	{ "epsi", "% "  },      /* encapsulated postscript */
	{ "el"  , "; "  },      /* Emacs Lisp */
	{ "f"   , "c "  },      /* Fortran */
	{ "for" , "c "  },      
	{ "frm" , "' "  },      /* Visual Basic form */
	{ "h"   , " * " },      /* C-header */
	{ "hh"  , "// " },      
	{ "hpp" , "// " },      /* C++ header */
	{ "hxx" , "// " },      
	{ "in"  , "# "  },      /* for Makefile.in */
	{ "l"   , " * " },      /* lex (NOTE: franzlisp disagrees) */
	{ "lisp", ";;; "},      /* Lucid Lisp */
	{ "lsp" , ";; " },      /* Microsoft Lisp */
	{ "m"   , "// " },      /* Objective C */
	{ "mac" , ";; " },      /* macro (DEC-10, MS-DOS, PDP-11, VMS, etc) */
	{ "mak" , "# "  },      /* makefile, e.g. Visual C++ */
	{ "me"  , ".\\\" "},    /* troff -me */
	{ "ml"  , "; "  },      /* mocklisp */
	{ "mm"  , ".\\\" "},    /* troff -mm */
	{ "ms"  , ".\\\" "},    /* troff -ms */
	{ "man" , ".\\\" "},    /* man-macros   t/nroff */
	{ "1"   , ".\\\" "},    /* feeble attempt at man pages... */
	{ "2"   , ".\\\" "},    
	{ "3"   , ".\\\" "},    
	{ "4"   , ".\\\" "},    
	{ "5"   , ".\\\" "},    
	{ "6"   , ".\\\" "},    
	{ "7"   , ".\\\" "},    
	{ "8"   , ".\\\" "},    
	{ "9"   , ".\\\" "},    
	{ "p"   , " * " },      /* Pascal */
	{ "pas" , " * " },      
	{ "pl"  , "# "  },      /* perl (conflict with Prolog) */
	{ "ps"  , "% "  },      /* PostScript */
	{ "psw" , "% "  },      /* postscript wrap */
	{ "pswm", "% "  },      /* postscript wrap */
	{ "r"   , "# "  },      /* ratfor */
	{ "rc"  , " * " },      /* Microsoft Windows resource file */
	{ "red" , "% "  },      /* psl/rlisp */
#ifdef sparc
	{ "s"   , "! "  },      /* assembler */
#endif
#ifdef mc68000
	{ "s"   , "| "  },      /* assembler */
#endif
#ifdef pdp11
	{ "s"   , "/ "  },      /* assembler */
#endif
#ifdef vax
	{ "s"   , "# "  },      /* assembler */
#endif
#ifdef __ksr__
	{ "s"   , "# "  },      /* assembler */
	{ "S"   , "# "  },      /* Macro assembler */
#endif
	{ "sh"  , "# "  },      /* shell */
	{ "sl"  , "% "  },      /* psl */
	{ "spec", "-- " },      /* Ada */
	{ "sty" , "% "  },      /* LaTeX style */
	{ "tex" , "% "  },      /* TeX */
	{ "y"   , " * " },      /* yacc */
	{ "ye"  , " * " },      /* yacc-efl */
	{ "yr"  , " * " },      /* yacc-ratfor */
	{ ""    , "# "  },      /* default for empty suffix */
	{ 0     , "# "  }       /* default for unknown suffix; must be last */
};

static int is_version_number(const char *line)
{
	if (*line < '0' || *line > '9')
		return 0;
	for (; *line; line++)
		if (*line != '\n' && *line != '.' &&
				(*line < '0' || *line > '9'))
			return 0;
	return 1;
}

static int is_done(const char *filename)
{
	char buffer[1024], line[1024];
	FILE *orig;
	int remaining = rfile.sel;

	snprintf(buffer, sizeof(buffer), "%s.old", filename);
	orig = fopen(buffer, "rb");
	if (!orig)
		return 0;

	if (!fgets(line, sizeof(line), orig) || strncmp(line, "head\t", 5)) {
		fclose(orig);
		return 0;
	}

	while (!feof(orig) && fgets(line, sizeof(line), orig)) {
		if (!strcmp(line, "desc\n"))
			break;
		if (is_version_number(line))
			remaining--;
	}

	fclose(orig);
	if (!remaining)
		rename(buffer, filename);
	else
		unlink(buffer);
	return !remaining;
}

static const char *current_file;
static void unlink_current_file(int dummy)
{
	if (current_file)
		unlink(current_file);
	exit(1);
}

void gen()
{
	size_t l = strlen(cvsdir);
	char **i, suffix[6] = "";
	struct rpair *j;
	fprintf(stderr, "%s\n", rfile.source);
	fi = strrchr(rfile.source, '/');
	sprintf(getq(12 + (fi - rfile.source) + 1), 
		"Directory .\n%.*s", 
		(int)(fi - rfile.source), rfile.source);
	queue[queuel-1] = '\n';
	fi2 = strrchr(fi, ',');
	fi = strrchr(fi, '.');
	assert(fi2 && (!fi || fi < fi2));
	if (fi) {
		fi++;
		/* If the suffix length is greater than four characters,
		 * it cannot match, since it copies five of them.
		 */
		strncpy(suffix, fi, fi2 - fi < sizeof suffix - 1 
			? fi2 - fi : sizeof suffix - 1);
	}
	fi = rfile.source + l + 1;
	if (is_done(fi))
		return;
	current_file = fi;
	rcsfiop = fopen(fi, "w");

	fprintf(rcsfiop, "head\t%s;\n", rfile.head.num ? rfile.head.num : "");
	if (rfile.branch.num)
		fprintf(rcsfiop, "branch\t%s;\n", rfile.branch.num);
	fprintf(rcsfiop, "access");
	for (i = rfile.accl; i < rfile.acct; i++)
		fprintf(rcsfiop, "\n\t%s", *i);
	fprintf(rcsfiop, ";\n");
	fprintf(rcsfiop, "symbols");
	for (j = rfile.tagl; j < rfile.tagt; j++)
		fprintf(rcsfiop, "\n\t%s:%s", j->item, j->rev.num);
	fprintf(rcsfiop, ";\n");
	fprintf(rcsfiop, "locks");
	for (j = rfile.lckl; j < rfile.lckt; j++)
		fprintf(rcsfiop, "\n\t%s:%s", j->item, j->rev.num);
	fprintf(rcsfiop, ";%s\n", rfile.strict ? " strict;" : "");
	fprintf(rcsfiop, "comment\t");
	if (rfile.leader)
		rcsfputs(rfile.leader, rcsfiop);
	else {
		const struct clpair *curr;
		for (curr = cltbl; curr->suffix; curr++)
			if (!strcmp(curr->suffix, suffix))
				break;
		rcsfputs(curr->comlead, rcsfiop);
	}
	fprintf(rcsfiop, ";\n");
	if (rfile.ksub && strcmp(rfile.ksub, "kv")) {
		fprintf(rcsfiop, "expand\t");
		rcsfputs(rfile.ksub, rcsfiop);
		fprintf(rcsfiop, ";\n");
	}
	fprintf(rcsfiop, "\n\n");
	trunk(rfile.revl);
	stats.nfiles++;
	puttree(rfile.revl, rcsfiop);
	fprintf(rcsfiop, "\ndesc\n");
	rcsfputs(rfile.descr, rcsfiop);
	fprintf(rcsfiop, "\n");
	puttree2(NULL, rfile.revl);
	que = queue;
	puttree3(NULL, rfile.revl);
	if (queue)
		free(queue);
	queue = NULL;
	fprintf(stderr, "\n");
	fclose(rcsfiop);
	current_file = NULL;
}
char *home;
int main(int argc, char *argv[])
{
	unsigned long siz;
	char *buf, *passfile, *fn0, *fn1, *fn2;

	if (argc == 5 || argc == 3)
		if (!(rlog_input = fopen(argv[--argc], "rb"))) {
			fprintf(stderr, "Invalid rlog file\n");
			return EXIT_FAILURE;
		}

	if (argc == 4 && !strcmp(argv[1], "-d")) {
		argc -= 2;
		cvsroot = argv[2];
		argv[1] = argv[3];
	} else if (argc != 2) {
		fprintf(stderr, "Argument count.\n");
		return EXIT_FAILURE;
	} else
		cvsroot = getenv("CVSROOT");

	if (!cvsroot) {
		fprintf(stderr, "No CVSROOT.\n");
		return EXIT_FAILURE;
	}
	cvsroot = strdup(cvsroot);
	passfile = (home = getenv("HOME")) 
		? strcat(strcpy(malloc(strlen(home) 
			+ sizeof "/.cvspass"), home), "/.cvspass")
		: strcpy(malloc(sizeof ".cvspass"), ".cvspass");
	BEGIN PWF0;
	if (!(yyin = fopen(passfile, "r")) || yylex() == EOF) {
		size_t l = strlen(cvsroot);
		cvsroot = realloc(cvsroot, l + 2);
		cvspass = strcpy(cvsroot + l + 1, "A");
	}
	if (yyin)
		fclose(yyin);
	fprintf(stderr, "password file: %s\n"
		"cvsroot: %s\n"
		"pass: %.1s\n", passfile,
		cvsroot, cvspass);

	signal(SIGINT, unlink_current_file);
	if (!(srv = srvopen())) {
		fprintf(stderr, "server connection failed or bad cvsroot\n");
#ifndef XTEST
		return EXIT_FAILURE;
#endif
	}
#ifndef XTEST
	fprintf(srv, "BEGIN AUTH REQUEST\n"
		"%s\n"
		"%s\n"
		"%s\n"
		"END AUTH REQUEST\n", cvsdir, cvsuser, cvspass);
	fprintf(srv, "Root %s\n", cvsdir);
	/*fprintf(srv, "Argument micq/m4\n");*/
	fprintf(srv, "Argument %s\n", argv[1]);
	if (rlog_input)
		yyrestart(rlog_input);
	else
	{
		yyrestart(srv);
		fprintf(srv, "rlog\n");
		fflush(srv);
	}
	BEGIN SRV0;
	yy_set_interactive(1);
	fprintf(stderr, "exit: %d\n", yylex());
	fn2 = fn0 = queue;
	fn1 = queue + queuel;
	queue = NULL;
#else
	fn2 = fn0 = malloc(strlen(argv[1]) + 3);
	fn1 = strlen(argv[1]) + 3 + strcpy(fn0, argv[1]);
	strcat(fn0, ",v");
#endif
	while (fn0 < fn1 && (buf = ftobuf(rcsfiop = fopen(fn0, "r"), &siz))) {
		fclose(rcsfiop);
		fn0 += strlen(fn0) + 1;
		buf[siz - 2] = YY_END_OF_BUFFER_CHAR;
		buf[siz - 1] = YY_END_OF_BUFFER_CHAR;
		/* fprintf(stderr, "<<%s>>\n", buf); */
		yybuf = YY_CURRENT_BUFFER;
		yy_scan_buffer(buf, siz);
		yy_set_interactive(0);
		BEGIN HDR0;
		rcsinit();
		yylex();
		assert(YY_CURRENT_BUFFER);
		yy_delete_buffer(YY_CURRENT_BUFFER);
		yy_switch_to_buffer(yybuf);
		gen();
		if (rfile.lckl)
			free(rfile.lckl);
		if (rfile.tagl)
			free(rfile.tagl);
		if (rfile.accl)
			free(rfile.accl);
		if (rfile.revl)
			free(rfile.revl);
		
		free(buf);
	}
	if (fn2)
		free(fn2);
	fprintf(stderr, "%s clone successful: %d files, "
		"%d branches, %d deltas\n",
		argv[0], stats.nfiles, stats.nbranches, stats.ndeltas);
#ifndef XTEST
	fclose(srv);
#endif
	return EXIT_SUCCESS;
}

