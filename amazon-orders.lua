-- Amazon Plugin for https://moneymoney-app.com
--
-- Copyright 2019 Michael Beutling

-- Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files
-- (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify,
-- merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:

-- The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
-- OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
-- BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT
-- OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

local connection=nil
local secPassword
local secUsername
local captcha1run
local mfa1run
local aName
local html
local configDirty=false
local cleanCache=false
local webCache=false
local webCacheFolder='webCache'
local webCacheHit=false
local webCacheState='start'

local config={
  str2date = {
    Januar=1,
    Februar=2,
    ["März"]=3,
    April=4,
    Mai=5,
    Juni=6,
    Juli=7,
    August=8,
    September=9,
    Oktober=10,
    November=11,
    Dezember=12
  },
  domain='.amazon.de',
  configOk=true,
  services    = {"Amazon Orders"},
  description = "Give you a overview about your amazon orders.",
  contra="Amazon contra ",
  reallyLogout=true,
  maxOrdersToRead=250,
  cleanCookies=false,
  cleanOrdersCache=false,
  cleanFilterCache=false,
  debug=false,
}

function mergeConfig(default,read)
  for k,v in pairs(default) do
    if type(v) == 'table' then
      if type(read[k]) ~= 'table' then
        read[k] = {}
      end
      mergeConfig(v,read[k])
    else
      if type(read[k]) ~= 'nil'then
        if default[k]~=read[k] then
          default[k]=read[k]
          --print(k,'=',read[k])
        end
      else
        configDirty=true
      end
    end
  end
end


local configFileName='amazon_orders.json'

-- run every time which plug in is loaded
local configFile=io.open(configFileName,"rb")

if configFile~=nil then
  local configJson=configFile:read('*all')
  --print(configJson)
  local configTemp=JSON(configJson):dictionary()
  if configTemp['configOk'] then
    configDirty=false
    mergeConfig(config,configTemp)
    print('config read...')
  end
  io.close(configFile)
else
  configDirty=true
end


if LocalStorage ~=nil then
  if config['cleanOrdersCache'] and LocalStorage ~=nil then
    config['cleanOrdersCache']=false
    configDirty=true
    print("clean orders cache...")
    LocalStorage.OrderCache={}
  end

  if config['cleanFilterCache']  then
    config['cleanFilterCache']=false
    configDirty=true
    print("clean filter cache...")
    LocalStorage.orderFilterCache={}
  end

  if config['cleanCookies']  then
    config['cleanCookies']=false
    configDirty=true
    print("clean cookies...")
    LocalStorage.cookies=nil
  end

end
if configDirty then
  print('write config...')
  configFile=io.open(configFileName,"wb")
  configFile:write(JSON():set(config):json())
  io.close(configFile)
end

print(config['services'][1],"plugin loaded...")
if config['debug'] then print('debugging...') end

local baseurl='https://www'..config['domain']

WebBanking{version  = 1.05,
  url         = baseurl,
  services    = config['services'],
  description = config['description']}


function connectShop(method, url, postContent, postContentType, headers)
  return HTML(connectShopRaw(method, url, postContent, postContentType, headers))
end

function connectShopRaw(method, url, postContent, postContentType, headers)
  -- postContentType=postContentType or "application/json"

  if headers == nil then
    headers={
      --["DNT"]="1",
      --["Upgrade-Insecure-Requests"]="1",
      --["Connection"]="close",
      --["Accept"]="text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      }
  end

  if method == 'POST' then
    if config['debug'] then
      for i in string.gmatch(postContent, "([^&]+)") do
        print("post='"..i.."'")
      end
    end
  end

  if connection == nil then
    connection = Connection()
    --connection.useragent="Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:66.0) Gecko/20100101 Firefox/66.0"

    local status,err = pcall( function()
      for i in string.gmatch(LocalStorage.cookies, '([^; ]+)') do
        if  i:sub(1, #'ap-fid=') ~= 'ap-fid=' and i:sub(-#'=deleted') ~= '=deleted' then
          -- print("keep cookie:"..i)
          connection:setCookie(i..'; Domain='..config['domain']..'; Expires=Tue, 01-Jan-2036 08:00:01 GMT; Path=/')
        else
        -- print("suppress cockie:"..i)
        end
      end
    end) --pcall
  end

  local cached=false
  local content, charset, mimeType, filename, headers
  local id
  if webCache then
    id=MM.md5(tostring(method)..tostring(url)..tostring(postContent)..tostring(postContentType)..tostring(headers)..webCacheState)
    local webFile=io.open(webCacheFolder..'/'..id..'.json','rb')
    if webFile then
      local metaJSON=webFile:read('*all')
      local meta=JSON(metaJSON):dictionary()
      webFile:close()
      webFile=io.open(webCacheFolder..'/'..id..'.html','rb')
      if webFile then
        content=webFile:read('*all')
        webFile:close()
        charset=meta['charset']
        mimeType=meta['mimeType']
        filename=meta['filename']
        headers=meta['headers']
        cached=true
        print("webCache id="..id.." read.")
        webCacheHit=true
      end
    end
    if not cached and webCacheHit then
      error('webCache error!')
    end

  end

  if not cached then
    content, charset, mimeType, filename, headers = connection:request(method, url, postContent, postContentType, headers)
    if webCache then
      local webFile=io.open(webCacheFolder..'/'..id..'.json',"wb")
      webFile:write(JSON():set({
        charset=charset,
        mimeType=mimeType,
        filename=filename,
        headers=headers,
        request={
          method=method,
          url=url,
          postContent=postContent,
          postContentType=postContentType,
          headers=headers,
        },
        webCacheState=webCacheState,
      }):json())
      webFile:close()
      webFile=io.open(webCacheFolder..'/'..id..'.html',"wb")
      webFile:write(content)
      webFile:close()
      print("webCache id="..id.." written.")
    end
  end

  if not cached and baseurl == connection:getBaseURL():lower():sub(1,#baseurl)  then
    -- work around for deleted cookies, prevent captcha
    connection:setCookie('a-ogbcbff=; Domain='..config['domain']..'; Expires=Thu, 01-Jan-1970 00:00:10 GMT; Path=/')
    connection:setCookie('ap-fid=; Domain='..config['domain']..'; Expires=Thu, 01-Jan-1970 00:00:10 GMT; Path=/ap/; Secure')

    if config['debug'] then
      if LocalStorage.cookies~=connection:getCookies() then
        print("store cookies=",connection:getCookies())
      end
    end

    for i in string.gmatch(connection:getCookies(), '([^; ]+)') do
      if  i:sub(1, #'ap-fid=') == 'ap-fid=' or i:sub(-#'=deleted') == '=deleted' then
        error("unwanted cockie:"..i)
      end
    end
    LocalStorage.cookies=connection:getCookies()
  else
    if config['debug'] then print("skip cookie saving") end
  end

  return content,charset
end


function SupportsBank (protocol, bankCode)
  return protocol == ProtocolWebBanking and "Amazon Orders" == bankCode:sub(1,#"Amazon Orders")
end

function enterCredentials(state)
  webCacheState=state
  local xpform='//*[@name="signIn"]'
  if html:xpath(xpform):attr("name") ~= '' then
    print("enter username/password")
    html:xpath('//*[@name="email"]'):attr("value", secUsername)
    html:xpath('//*[@name="password"]'):attr("value",secPassword)
    html= connectShop(html:xpath(xpform):submit())
    if html:xpath('//a[@id="ap-account-fixup-phone-skip-link"]'):attr('id') ~= '' then
      print("skip phone dialog...")
      html= connectShop(html:xpath('//a[@id="nav-orders"]'):click())
    end
  end
end

function InitializeSession2 (protocol, bankCode, step, credentials, interactive)
  -- Login.
  if step==1 then
    if LocalStorage.getOrders == nil then
      LocalStorage.getOrders={}
    end
    secUsername=credentials[1]
    secPassword=credentials[2]
    captcha1run=true
    mfa1run=true
    aName=nil
    if config['debug'] then
      webCache=os.rename(webCacheFolder,webCacheFolder) and true or false
      if webCache then
        print("webcache on")
        LocalStorage.OrderCache={}
        LocalStorage.orderFilterCache={}
      end
    end
    html = connectShop("GET",baseurl)
    html= connectShop(html:xpath('//a[@id="nav-orders"]'):click())

    enterCredentials('1.login')
  end

  -- Captcha
  --
  local captcha=html:xpath('//img[@id="auth-captcha-image"]'):attr('src')
  --div id="image-captcha-section"
  if captcha ~= "" then
    if config['debug'] then print("login captcha") end
    if captcha1run then
      local pic=connectShopRaw("GET",captcha)
      captcha1run=false
      return {
        title=html:xpath('//li'):text(),
        challenge=pic,
        label=html:xpath('//form//h4'):text()
      }
    else
      html:xpath('//*[@name="guess"]'):attr("value",credentials[1])
      -- checkbox
      html:xpath('//*[@name="rememberMe"]'):attr('checked','checked')
      enterCredentials('captcha')
      captcha1run=true
    end
  end

  enterCredentials('after captcha')

  -- passcode

  if html:xpath('//form[@name="claimspicker"]'):text() ~= ''  then
    local text=''
    local number=0
    local passcode1run=true
    if config['debug'] then print("passcode 1. part") end
    html:xpath('//input[@type="radio"]'):each(function (index,element)
      text=text..index..". "..element:xpath('..'):text().."\n"
      number=index
      if  tonumber(index) == tonumber(credentials[1]) then
        element:attr('checked','checked')
        if config['debug'] then print("select",element:xpath('..'):text()) end
        passcode1run=false
      else
        element:attr('checked','')
      end
      --print(index,element:xpath('..'):text(),element:attr('checked'))
    end)
    if number == 0 then
      -- no selectable options
      html= connectShop(html:xpath('//form[@name="claimspicker"]'):submit())
      if html:xpath('//form[@action="verify"]'):text() ~= '' then
        return {
          title=html:xpath('//form[@action="verify"]//div[1]//div[1]'):text(),
          challenge=html:xpath('//form[@action="verify"]//div[1]//div[2]'):text(),
          label='Code'
        }
      end
    else
      if passcode1run then
        passcode1run=false
        -- ask for passcode methode, feature request select field when return value a table?
        return {
          title=html:xpath('//form[@action="claimspicker"]//div[1]'):text(),
          challenge=text,
          label='Please select 1-'..number
        }
      else
        html= connectShop(html:xpath('//form[@name="claimspicker"]'):submit())
        if html:xpath('//form[@action="verify"]'):text() ~= '' then
          return {
            title=html:xpath('//form[@action="verify"]//div[1]//div[1]'):text(),
            challenge=html:xpath('//form[@action="verify"]//div[1]//div[2]'):text(),
            label='Code'
          }
        end
      end
    end
  end

  -- passcode part 2
  if html:xpath('//form[@action="verify"]'):text() ~= '' then
    if config['debug'] then print("passcode 2. part") end
    html:xpath('//*[@name="code"]'):attr("value",credentials[1])
    html= connectShop(html:xpath('//form[@action="verify"]'):submit())
  end

  -- 2.FA
  local mfatext=html:xpath('//form[@id="auth-mfa-form"]//p'):text()
  if mfatext ~= "" then
    if config['debug'] then print("login mfa") end
    if mfa1run then
      -- print("mfa="..mfatext)
      mfa1run=false
      return {
        title='Two-factor authentication',
        challenge=mfatext,
        label='Code'
      }
    else
      html:xpath('//*[@name="otpCode"]'):attr("value",credentials[1])
      -- checkbox
      html:xpath('//*[@name="rememberDevice"]'):attr('checked','checked')
      html= connectShop(html:xpath('//*[@id="auth-mfa-form"]'):submit())
      mfa1run=true
    end
  end
  enterCredentials('after passcode')

  if html:xpath('//*[@id="timePeriodForm"]'):attr('id') == 'timePeriodForm' then
    aName=html:xpath('//span[@class="nav-line-3"]'):text()
    if aName == "" then
      aName="Unkown"
      -- print("can't get username, new layout?")
    else
    -- print("name="..aName)
    end
  else
    LocalStorage.cookies=nil
    return LoginFailed
  end

  return nil
end

function ListAccounts (knownAccounts)
  -- Return array of accounts.
  local name=aName
  if aName == nil or aName== "" then
    name=secUsername
  end
  LocalStorage.getOrders['mix']=false
  LocalStorage.getOrders['normal']=false
  LocalStorage.getOrders['inverse']=false
  return {[1]={
    name = "Amazon "..name,
    owner = secUsername,
    accountNumber="mix",
    type = AccountTypeOther
  },[2]={
    name = "Amazon "..name,
    owner = secUsername,
    accountNumber="normal",
    type = AccountTypeOther
  },[3]={
    name = "Amazon "..name,
    owner = secUsername,
    accountNumber="inverse",
    type = AccountTypeOther
  }}
end

function RefreshAccount (account, since)
  local mixed=false
  webCacheState='RefreshAccount'

  local divisor=-100
  if account.accountNumber == "inverse" then
    divisor=100
  end

  if account.accountNumber == "mix" then
    mixed=true
  end
  print("Refresh ",account.accountNumber)
  if LocalStorage.getOrders[account.accountNumber] == false or LocalStorage.getOrders[account.accountNumber] == nil then
    LocalStorage.getOrders[account.accountNumber]=true

    return {balance=0, transactions={[1]=
      {
        name="Please reload!",
        amount = 0,
        bookingDate = 1,
        purpose = "... and drink a coffee :)",
        booked = false,
      }
    }}
  end

  html=connectShop("GET",baseurl)

  -- Bestellungen
  html= connectShop(html:xpath('//a[@id="nav-orders"]'):click())

  if LocalStorage.OrderCache == nil then
    LocalStorage.OrderCache={}
  end

  if LocalStorage.orderFilterCache == nil then
    LocalStorage.orderFilterCache={}
  end
  --LocalStorage.orderFilterCache={}

  local orders={}
  local numOfOrders=0
  local orderFilterSelect=html:xpath('//select[@name="orderFilter"]'):children()
  orderFilterSelect:each(function(index,element)
    local orderFilterVal=element:attr('value')
    local foundOrders=true
    local foundNewOrders=false
    if LocalStorage.orderFilterCache[orderFilterVal] == nil then
      --print(orderFilterVal)
      html:xpath('//*[@name="orderFilter"]'):select(orderFilterVal)
      html=connectShop(html:xpath('//*[@id="timePeriodForm"]'):submit())
      local foundEnd=false
      repeat
        html:xpath('//a[contains(@href,"order-details")]'):each(function(index,orderLink)
          local url=orderLink:attr('href')
          local orderCode=string.match(url,'orderID=([%d-]+)')
          if orderCode ~= "" then
            if  LocalStorage.OrderCache[orderCode] == nil and orders[orderCode] == nil then
              if config['debug'] then print("new order="..orderCode,'No='..numOfOrders) end
              numOfOrders=numOfOrders+1
              orders[orderCode]=url
              foundNewOrders=true
            end
          else
            foundOrders=false
          end
        end)
        local nextPage=html:xpath('//li[@class="a-last"]/a[@href]')
        if nextPage:text() ~= "" then
          html=connectShop(nextPage:click())
        else
          foundEnd=true
        end
      until foundEnd
      if orderFilterVal ~= 'months-6' and not foundNewOrders and foundOrders then
        LocalStorage.orderFilterCache[orderFilterVal]=true
        --print("orderFilter="..orderFilterVal.." cached")
      end
    end
    --print("new orders="..#orders)
    return numOfOrders<config['maxOrdersToRead']
  end)

  local posbox='//div[@class="a-row"]/div[contains(@class,"a-fixed-left-grid")]//'
  local maxOrders=numOfOrders
  if maxOrders >= config['maxOrdersToRead'] then
    maxOrders=config['maxOrdersToRead']
  end

  numOfOrders=0
  local invaildOrder=''
  local transactions={}

  for orderCode,orderUrl in pairs(orders) do
    numOfOrders=numOfOrders+1
    html=connectShop("GET",orderUrl)
    if html:xpath('//div[@id="orderDetails"]'):text() == "" then
      if invaildOrder == '' then
        invaildOrder=orderCode
      end
      break
    end
    local orderDate = html:xpath('//span[@class="order-date-invoice-item"]'):text()
    if orderDate == "" then
      orderDate = html:xpath('//span[@class="a-color-secondary value"]'):text()
      if config['debug'] then
        invaildOrder=orderCode
      end
    end
    print(numOfOrders..'/'..maxOrders,'orderCode='..orderCode,'orderDate='..orderDate)
    if orderDate ~= "" then
      local orderDay,orderMonth,orderYear=string.match(orderDate,"(%d+)%.%s+([%wä]+)%s+(%d+)")
      local orderMonth=config['str2date'][orderMonth]
      if orderMonth ~= nil then
        local bookingDate=os.time({year=orderYear,month=orderMonth,day=orderDay})
        local orderPositions={}
        local total=0
        for k,position in pairs({html:xpath(posbox..'span[contains(@class,"price")]'),html:xpath(posbox..'div[contains(@class,"gift-card-instance")]')}) do
          position:each(function (index,element)
            local purpose=element:xpath('../..//a'):text()
            local amount=element:text()
            purpose=string.match(purpose,"^%s*(.+)%s*$")
            local amountHigh,amountLow=string.match(amount,"(%d+)[,%.](%d%d)")
            amount=amountHigh*100+amountLow
            --print(purpose,amount)
            table.insert(orderPositions,{purpose=purpose,amount=amount})
            total=total+amount
            return true
          end)
        end
        if #orderPositions >0 then
          LocalStorage.OrderCache[orderCode]={total=total,since=since,bookingDate=bookingDate,orderPositions=orderPositions}
          --print("store="..orderCode)
        end

      else
        invaildOrder=orderCode
      end
    else
      invaildOrder=orderCode
    end

    if numOfOrders >= config['maxOrdersToRead'] then
      print('maximal orders to read limit of',config['maxOrdersToRead'],'reached!')
      table.insert(transactions,{
        name="Warning, max order limit reached.",
        amount = 0,
        bookingDate = os.time(),
        purpose = string.format('Please reload the account to get the next %d orders.',config['maxOrdersToRead']),
        booked=false,
      })
      break
    end
  end


  if invaildOrder ~='' then
    table.insert(transactions,{
      name=invaildOrder,
      amount = 0,
      bookingDate = os.time(),
      purpose = 'Error: Invalid order found, a account reload can be fix it.',
      booked=false,
    })
  end

  local balance=0
  --since=0
  for orderCode,order in pairs(LocalStorage.OrderCache) do
    balance=balance+order.total
    if order.since >= since then
      for index,position in pairs(order.orderPositions) do
        table.insert(transactions,{
          name=orderCode,
          amount = position.amount/divisor,
          bookingDate = order.bookingDate,
          purpose = position.purpose,
          booked=not webCache
        })
      end
      if mixed then
        table.insert(transactions,{
          name=orderCode,
          amount = order.total/divisor*-1,
          bookingDate = order.bookingDate,
          purpose = config['contra']..orderCode,
          booked=not webCache
        })
      end
    end
  end

  if mixed then
    balance=0
  end

  -- Return balance and array of transactions.
  return {balance=balance/divisor, transactions=transactions}
end

function EndSession ()
  -- Logout.
  if config['reallyLogout'] then
    html= connectShop(html:xpath('//a[contains(@href,"signout")]'):click())
  end
end

