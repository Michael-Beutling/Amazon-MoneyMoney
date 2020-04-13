#!/bin/bash -e

DIR=~/Library/Containers/com.moneymoney-app.retail/Data/webCache

if [ -e $DIR ] ; then
	rm -rvf $DIR
	mkdir -p $DIR
fi

