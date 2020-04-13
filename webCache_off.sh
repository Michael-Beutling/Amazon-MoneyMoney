#!/bin/bash -e

DIR=~/Library/Containers/com.moneymoney-app.retail

if [ -e "$DIR/Data/webCache" ]; then
	mv "$DIR/Data/webCache" "$DIR/Data/webCacheOff" 
fi
echo webCache off
