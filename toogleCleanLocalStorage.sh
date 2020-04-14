#!/bin/bash -e

FILE=~/Library/Containers/com.moneymoney-app.retail/Data/webCache/cleanLocalStorage

if [  -e "$FILE" ]; then
	rm "$FILE"
	echo "cleanLocalStorage off"
else
	touch "$FILE"
	echo "cleanLocalStorage on"
fi
