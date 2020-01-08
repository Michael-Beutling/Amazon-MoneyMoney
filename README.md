# Amazon Plugin for MoneyMoney
## Installation
copy *amazon-orders.lua* script in the *~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application\ Support/MoneyMoney/Extensions* Folder or run the *link_ext.sh* script in a shell.

## Config
Only for unsigned version:
For **.de** users it's already configured. For another sites please edit the JSON file in the *~/Library/Containers/com.moneymoney-app.retail/Data/* folder and hope the best ;) 

The plugin generate the JSON file after the first loading via MoneyMoney.

## Performance
The script cache same data, but the first time it's scraped your whole order history. In facts  ~10 years shopping with about 230 orders with 340 positions take 12 minutes in the first run! The second run needs 2 minutes. After then all data cached so a normally run needs 20-30 seconds.   

## Warranty
Nope, no warrenty! When the script order 10 tons of dog food every day, it's your problem!     

