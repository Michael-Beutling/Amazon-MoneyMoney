#!/bin/bash -e

DIR=~/Library/Containers/com.moneymoney-app.retail
NORM=$DIR.normal
DBG=$DIR.debug

if [ -e "$NORM" ]; then
	if [ -e "$DIR" ]; then
		mv "$DIR" "$DBG"
	fi
	mv "$NORM" "$DIR" 
	echo switch to normal
else
	if [ -e "$DIR" ]; then
		mv "$DIR" "$NORM"
		if [ -e "$DBG" ]; then
			mv "$DBG" "$DIR"
		fi
		echo switch to debug
	fi

fi

