#!/bin/sh
ls -li ~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application\ Support/MoneyMoney/Extensions/amazon-orders.lua amazon-orders.lua

rm ~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application\ Support/MoneyMoney/Extensions/amazon-orders.lua 
ln amazon-orders.lua ~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application\ Support/MoneyMoney/Extensions/amazon-orders.lua 

ls -li ~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application\ Support/MoneyMoney/Extensions/amazon-orders.lua amazon-orders.lua

