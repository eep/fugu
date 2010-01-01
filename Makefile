# Copyright (c) 2005 Regents of the University of Michigan
# All Rights Reserved. See COPYRIGHT.

SHELL = /bin/sh

srcdir = .

FUGU=		Fugu.app
TARGETS=	fugu
BUILDER=	/usr/bin/xcodebuild

all : ${TARGETS}

run : all
	open build/${FUGU}

install : all
	ditto --rsrc build/${FUGU} /Applications/${FUGU}
	
fugu :
	${BUILDER} -alltargets 

version=`cat VERSION`
DISTDIR=../fugu-${version}

dist : distclean
	mkdir ${DISTDIR}
	tar -cf - -X EXCLUDE ${srcdir} | tar xpf - -C ${DISTDIR}

clean :
	${BUILDER} -alltargets clean

distclean : clean
	rm -f Fugu.pbproj/*.pbxuser Fugu.pbproj/*.mode1
