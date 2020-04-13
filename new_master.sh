#!/bin/bash -e

DIR=~/Library/Containers/com.moneymoney-app.retail

for i in normal inverse mix ;do 
	if [ -f $DIR/Data/$i\_transactions.json ]; then
		echo copy \'$i\'
		cp $DIR/Data/$i\_transactions.json $DIR/Data/$i\_transactions_master.json
	else
		echo create \'$i\'
		touch $DIR/Data/$i\_transactions_master.json 
	fi
done
