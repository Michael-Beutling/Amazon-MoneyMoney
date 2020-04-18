# Amazon Plugin for MoneyMoney
## Installation
copy *amazon-orders.lua* script in the *~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application\ Support/MoneyMoney/Extensions* Folder or run the *link_ext.sh* script in a shell.

**Look out:** MoneyMoney only runs unsigned plugins in the **beta version** and you need to **disable signature check** in the extentsion settings.
After installation go to *add new account* - *others* - *Amazon Orders*.
Normal will list your spendings like a normal account.
Inverted will have your spendings with positive values.
Mixed will show a positive booking for every position, so the total adds up to Zero.

## Config
Only for unsigned version:
For **.de** users it's already configured. For other sites please edit the JSON file in the *~/Library/Containers/com.moneymoney-app.retail/Data/* folder and hope the best ;)

The plugin generate the JSON file after the first loading via MoneyMoney.

## Performance
The script cache some data, but the first time it's scraped your whole order history. In facts  ~10 years shopping with about 230 orders with 340 positions take 12 minutes in the first run! The second run needs 2 minutes. After that all data is cached so a normal run needs 20-30 seconds.

## Warranty
Nope, no warrenty! When the script order 10 tons of dog food every day, it's your problem!     

## Beta-Version
You found the Beta-Version here [amazon-orders.lua](https://raw.githubusercontent.com/Michael-Beutling/Amazon-MoneyMoney/beta/amazon-orders.lua).
