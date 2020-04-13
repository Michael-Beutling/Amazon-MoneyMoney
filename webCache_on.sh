#!/bin/bash -e

DIR=~/Library/Containers/com.moneymoney-app.retail

if [ ! -e "$DIR/Data/webCache" ]; then
	if [ -e "$DIR/Data/webCacheOff" ]; then
		mv "$DIR/Data/webCacheOff" "$DIR/Data/webCache"
	else
		mkdir "$DIR/Data/webCache"
	fi 
fi
echo webCache on
