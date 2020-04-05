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
local invalidPrice=1e99
local invalidDate=1e99
local invalidQty=1e99
local cacheVersion=5

local config={
  regexOrderCode="(D?%d+%-%d+%-%d+)",
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
  refundContra="Refund contra for ",
  refund="Refund for ",
  reallyLogout=true,
  maxOrdersToRead=250,
  cleanCookies=false,
  cleanOrdersCache=false,
  cleanFilterCache=false,
  cleanInvalidCache=false,
  debug=false,
  splitQty=1,
  fixEncoding='latin1',
  differenceText='Difference (shipping costs, coupon etc.)',
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
local configFile=nil
-- io=nil
-- io.open=nil
-- signed version has no io.open functions
if io ~= nil and io.open ~= nil then
  configFile=io.open(configFileName,"rb")
end

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
  if LocalStorage.cacheVersion ~= cacheVersion then
    configDirty=true
    print("clean caches...")
    LocalStorage.OrderCache={}
    LocalStorage.orderFilterCache={}
    LocalStorage.cacheVersion = cacheVersion
    LocalStorage.invalidCache={}
  end

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

  if config['cleanInvalidCache']  then
    config['cleanInvalidCache']=false
    configDirty=true
    print("clean invalid cache...")
    LocalStorage.invalidCache={}
  end

  if config['cleanCookies']  then
    config['cleanCookies']=false
    configDirty=true
    print("clean cookies...")
    LocalStorage.cookies=nil
  end

end

if configDirty and io ~= nil and io.open ~= nil then
  print('write config...')
  configFile=io.open(configFileName,"wb")
  configFile:write(JSON():set(config):json())
  io.close(configFile)
end

print(((io == nil or io.open == nil) and 'signed ' or '')  .. config['services'][1],"plugin loaded...")
if config['debug'] then print('debugging...') end

local baseurl='https://www'..config['domain']

WebBanking{version  = 1.07,
  url         = baseurl,
  services    = config['services'],
  description = config['description']}


function connectShop(method, url, postContent, postContentType, headers)
  if method == nil then
    return nil
  end
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

local RegressionTest={}

function RegressionTest.makeRows(transactions)
  local rows={}
  for _,transaction in pairs(transactions) do
    for k,v in pairs(transaction) do
      if k ~= 'name' then
        local row=transaction.name.." "..k.."("..type(v)..")".."='"..tostring(v).."'"
        if rows[row]==nil then
          rows[row]=1
        else
          rows[row]=rows[row]+1
        end
      end
    end
  end
  return rows
end

function RegressionTest.compareTrees(now,master)
  local differences=0
  for k,v in pairs(master) do
    if now[k] ~= nil then
      now[k]=now[k]-v
      master[k]=0
    end
  end
  for k,v in pairs(now) do
    if master[k] ~= nil then
      master[k]=master[k]-v
      now[k]=0
    end
  end
  print("differences master")
  for k,v in pairs(master) do
    if v ~=0 then
      print("n="..v," value="..k)
      differences=differences+1
    end
  end
  print("differences now")
  for k,v in pairs(now) do
    if v ~=0 then
      print("n="..v," value="..k)
      differences=differences+1
    end
  end
  print("differences="..differences)
  return differences~=0
end

function RegressionTest.run(transactions)
  if io ~= nil then
    local transFile=io.open("transactions_master.json",'rb')
    if transFile ~= nil then

      print("run regression test")

      local master=JSON(transFile:read('*all')):dictionary()
      transFile.close()

      local transFile=io.open("transactions.json","wb")
      local now=RegressionTest.makeRows(transactions)
      transFile:write(JSON():set(now):json())
      transFile.close()


      RegressionTest.compareTrees(now,master)
      print("regression test finish")
    end
  end
end

function getDate(text)
  if type(text)~='string' then
    return invalidDate
  end
  local day,month,year=string.match(text,"(%d+)%.%s+([%S]+)%s+(%d+)")
  local month=config['str2date'][month]
  if month ~= nil then
    return os.time({year=year,month=month,day=day})
  end
  --error(text)
  return invalidDate -- error value
end

function getPrice(text)
  if type(text)~='string' then
    return invalidPrice
  end
  local amountHigh,amountLow=string.match(text,"(%d+)[,%.](%d%d)")
  if amountHigh == nil or amountLow == nil then
    return invalidPrice
  end
  return amountHigh*100+amountLow
end

function getQty(text)
  if type(text)~='string' then
    return invalidQty
  end
  local qty=tonumber(text)
  if qty>0 then
    return qty
  end
  return invalidQty
end

function getQtyFromElement(element)
  local qty=1
  if nodeExists(element,'.//span[@class="item-view-qty"]') then
    qty=getQty(element:xpath('.//span[@class="item-view-qty"]'):text())
  end
  return qty
end

function removeSpaces(text)
  if type(text)~='string' then
    return nil
  end
  return string.match(text,"^%s*(.+)%s*$")
end

function containsOrderCode(text)
  if type(text)~='string' then
    return false
  end
  local orderCode=string.match(text,config.regexOrderCode)
  return orderCode ~= nil
end

function getOrderCode(text)
  if type(text)~='string' then
    return nil
  end
  local orderCode=string.match(text,config.regexOrderCode)
  return orderCode
end

function nodeExists(element,xpath)
  return element:xpath(xpath)[1] ~= nil
end

function getReturnHistory()

  --https://www.amazon.de/spr/returns
  -- untested :(
  local orderIDs={}
  local lhtml=connectShop("GET",baseurl..'/spr/returns/history')
  lhtml:xpath('//a[contains(@href,"orderID=") or contains(@href,"orderId=")]'):each(function (index,element)
    local url=(element:attr("href")),element:attr("href")
    if containsOrderCode(url) then
      orderIDs[getOrderCode(url)]=false
    end
  end)
  orderIDs['303-4953190-5470706']=false
  return orderIDs;
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

    -- issue5
    LocalStorage.orderFilterCache={}

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
  print("Refresh",account.accountNumber)
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

  if LocalStorage.invalidCache == nil then
    LocalStorage.invalidCache={}
  end

  local orders={}
  local returns=getReturnHistory()
  local numOfOrders=0

  -- issue5
  local countOrders={}
  --https://www.amazon.de/spr/returns


  local orderFilterSelect=html:xpath('//select[@name="orderFilter"]'):children()
  orderFilterSelect:each(function(index,element)
    local orderFilterVal=element:attr('value')
    local foundOrders=true
    local foundNewOrders=false
    if LocalStorage.orderFilterCache[orderFilterVal] == nil then
      --print(orderFilterVal)
      html:xpath('//*[@name="orderFilter"]'):select(orderFilterVal)
      html=connectShop(html:xpath('//*[@id="timePeriodForm"]'):submit())

      --issue5
      countOrders[orderFilterVal]={counts=0,text=html:xpath('//span[@class="num-orders"]'):text()}

      local foundEnd=false
      repeat

        -- get order details from overview when possible
        html:xpath('//div[contains(@class,"a-box-group")]'):each(function (index,element)
          -- handle returns
          element:xpath('.//a[contains(@href,"/returns/") and contains(@href,"_status_")]'):each(function (index,element)
            local url=element:attr("href")
            if containsOrderCode(url) then
              returns[getOrderCode(url)]=false
              print("return",getOrderCode(url))
            end
          end)

          local detailsUrl=element:xpath('.//a[contains(@href,"order-details") and @class="a-link-normal"]'):attr('href')
          -- link present for details = shorted overview -> skip
          if element:xpath('.//div[contains(@class,"shipment")]//a[contains(@href,"order-details")]'):text()=='' and  detailsUrl ~=nil then
            local headData={}
            element:xpath('.//span[@class="a-color-secondary value"]'):each(function(index,element)
              headData[index]=element:text()
            end)
            if #headData == 3 then
              local bookingDate,orderSum,orderCode=getDate(headData[1]),getPrice(headData[2]),getOrderCode(headData[3])
              if orderCode ~= nil then
                if orderSum ~= invalidPrice then
                  if bookingDate >0 and bookingDate ~= invalidDate then
                    --print(bookingDate,orderSum,orderCode)
                    local vaildOrder=true
                    local orderPositions={}
                    element:xpath('.//div[@class="a-fixed-left-grid-inner"]'):each(function (index,element)
                      local purpose=removeSpaces(element:xpath('.//div[@class="a-fixed-left-grid-col a-col-right"]/descendant::div[@class="a-row"][1]'):text())
                      local amount=getPrice(element:xpath('.//*[contains(@class,"a-color-price") or contains(@class,"gift-card-instance")]'):text())
                      local qty=getQtyFromElement(element)
                      if purpose ~= nil and qty~= invalidQty then
                        table.insert(orderPositions,{purpose=purpose,amount=amount,qty=qty})
                      else
                        vaildOrder=false
                        print("found invalid position in order",orderCode)
                      end
                      return vaildOrder
                    end)

                    if #orderPositions == 1 and orderPositions[1].amount == invalidPrice then
                      -- can be a digital article
                      orderPositions[1].amount = orderSum
                    end

                    local total=0
                    for _,v in pairs(orderPositions) do
                      if v.amount == invalidPrice then
                        vaildOrder=false
                      end
                      total=total+v.amount*v.qty
                    end

                    if vaildOrder and #orderPositions>0 then
                      LocalStorage.OrderCache[orderCode]={detailsUrl=detailsUrl,orderSum=orderSum,total=total,since=since,bookingDate=bookingDate,orderPositions=orderPositions}
                    end
                  else
                    print("no date found for order",orderCode,"found='"..tostring(headData[1]).."'")
                  end
                else
                  print("no valid sum found for order", orderCode, "found='"..tostring(headData[2]).."'")
                end
              end
            else
              print("skip order, get wrong number of elements date='"..tostring(headData[1]).."' sum='"..tostring(headData[2]).."' code='"..tostring(headData[3]).."'")
            end
          end
        end)
        -- get all order details urls
        html:xpath('//a[contains(@href,"order-details") and @class="a-link-normal"]'):each(function(index,orderLink)
          local url=orderLink:attr('href')
          local orderCode=string.match(url,'orderID='..config.regexOrderCode)
          if orderCode ~= "" then

            -- issue5
            countOrders[orderFilterVal].counts=countOrders[orderFilterVal].counts+1

            -- order cached?
            if  LocalStorage.OrderCache[orderCode] == nil and orders[orderCode] == nil then
              numOfOrders=numOfOrders+1
              if config['debug'] then print("new order="..orderCode,'No='..numOfOrders) end
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
    return numOfOrders<config['maxOrdersToRead']
  end)

  for orderCode,_ in pairs(returns) do
    if orders[orderCode] == nil and LocalStorage.OrderCache[orderCode] ~= nil then
      orders[orderCode]=LocalStorage.OrderCache[orderCode].detailsUrl
      numOfOrders=numOfOrders+1
      returns[orderCode]=true
      print("add return",orderCode)
    end
  end

  local posbox='//div[@class="a-row"]/div[contains(@class,"a-fixed-left-grid")]//'
  local maxOrders=numOfOrders
  if maxOrders >= config['maxOrdersToRead'] then
    maxOrders=config['maxOrdersToRead']
  end

  numOfOrders=0

  local transactions={}
  -- get order details from order details page
  for orderCode,orderUrl in pairs(orders) do
    print(orderCode,orderUrl)
    numOfOrders=numOfOrders+1
    local returnedArticles=nil
    html=connectShop("GET",orderUrl)
    if html:xpath('//div[@id="orderDetails"]'):text() ~= "" then
      -- get return url
      html:xpath('//a[contains(@href,"/returns/") and contains(@href,"_status_")]'):each(function (index,element)
        local url=(element:attr("href")),element:attr("href")
        if getOrderCode(url) == orderCode then
          print("detect return")
          returnedArticles={}
          local returnPage=connectShop(element:click())
          -- returned items:
          returnPage:xpath('//div[@id="-returnable-item"]'):each(function (index,element)
            local qty=getQtyFromElement(element)
            local purpose=element:xpath('.//div[@class="a-row"]/span[@class="a-size-base a-text-bold"]'):text()
            local amount=getPrice(element:xpath('.//span//font'):text())
            local bookingDate=getDate(element:xpath('//span[@class="a-size-small a-color-secondary"]//font/../..'):text())
            print(qty,purpose,amount,bookingDate)
            if qty ~= invalidQty and amount ~=invalidPrice and bookingDate ~=invalidDate then
              table.insert(returnedArticles,{qty=qty,purpose=purpose,amount=amount,bookingDate=bookingDate})
            end
          end)
        end
      end)

      local orderDate = html:xpath('//span[@class="order-date-invoice-item"]'):text()
      if orderDate == "" then
        orderDate = html:xpath('//span[@class="a-color-secondary value"]'):text()
      end
      print(numOfOrders..'/'..maxOrders,'orderCode='..orderCode,'orderDate='..orderDate)
      if orderDate ~= "" and LocalStorage.OrderCache[orderCode] == nil then
        local orderSum=invalidPrice
        html:xpath('//span[contains(@class,"a-text-bold")]'):each(function (index,element)
          orderSum=getPrice(element:text())
          return orderSum==invalidPrice
        end)
        local bookingDate=getDate(orderDate)
        if bookingDate>0 and orderSum ~= invalidPrice then
          local orderPositions={}
          local total=0
          for k,position in ipairs({html:xpath(posbox..'span[contains(@class,"price")]'),html:xpath(posbox..'div[contains(@class,"gift-card-instance")]')}) do
            position:each(function (index,element)
              local purpose=removeSpaces(element:xpath('../..//a'):text())
              local amount=getPrice(element:text())
              local qty=1
              if nodeExists(element,'../../..//span[@class="item-view-qty"]') then
                qty=getQty(element:xpath('../../..//span[@class="item-view-qty"]'):text())
              end
              --print(purpose,amount)
              table.insert(orderPositions,{purpose=purpose,amount=amount,qty=qty})
              total=total+amount*qty
              return true
            end)
          end
          if #orderPositions >0 then
            LocalStorage.OrderCache[orderCode]={orderSum=orderSum,total=total,since=since,bookingDate=bookingDate,orderPositions=orderPositions}
          end
        end
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
    if LocalStorage.OrderCache[orderCode] ~= nil then
      LocalStorage.OrderCache[orderCode].returnedArticles=returnedArticles
    else
      if LocalStorage.invalidCache[orderCode]== nil then
        LocalStorage.invalidCache[orderCode]=3
      end
      if LocalStorage.invalidCache[orderCode] > 0 then
        print("can't parse order details",orderCode,"reportCounter=",LocalStorage.invalidCache[orderCode])
        table.insert(transactions,{
          name=orderCode,
          amount = 0,
          bookingDate = os.time(),
          purpose = "Warning: Can't parse the order details, a account reload may fix it.",
          booked=false,
        })
        LocalStorage.invalidCache[orderCode]=LocalStorage.invalidCache[orderCode]-1
      else
        LocalStorage.invalidCache[orderCode]= nil
        LocalStorage.OrderCache[orderCode]={orderSum=0,
          total=0,since=since,bookingDate=os.time(),report=2,
          orderPositions={
            [1]={purpose="Error: Can't parse the order details for order "..orderCode.."!",
              amount=0,qty=1
            }
          }
        }
      end
    end
  end

  local balance=0

  for orderCode,order in pairs(LocalStorage.OrderCache) do
    balance=balance+order.orderSum

    if order.orderSum ~= order.total then
      table.insert(transactions,{
        name=orderCode,
        amount = (order.orderSum-order.total)/divisor,
        bookingDate = order.bookingDate,
        purpose = config['differenceText'],
        booked=not webCache
      })
    end

    local report=true
    if order.report~=nil then
      if order.report >0 then
        order.report=order.report-1
      else
        report=false
      end
    end
    if order.since >= since and report then
      for index,position in pairs(order.orderPositions) do
        local rQty=1
        local mQty=1
        if position.qty> config['splitQty'] then
          mQty=position.qty
        else
          rQty=position.qty
        end
        for i=1,rQty,1 do
          table.insert(transactions,{
            name=orderCode,
            amount = position.amount/divisor*mQty,
            bookingDate = order.bookingDate+1,
            purpose = MM.toEncoding(config['fixEncoding'],position.purpose),
            booked=not webCache
          })
        end
      end

      if mixed and order.orderSum ~= 0 then
        table.insert(transactions,{
          name=orderCode,
          amount = order.orderSum/divisor*-1,
          bookingDate = order.bookingDate,
          purpose = config['contra']..orderCode,
          booked=not webCache
        })
      end
    end
    if order.returnedArticles ~= nil then
      for index,position in pairs(order.returnedArticles) do
        local rQty=1
        local mQty=1
        local purpose=position.purpose
        if purpose:sub(-3) == '...' then
          local founds=0
          for i,p in pairs(order.orderPositions) do
            if p.purpose:sub(1,#position.purpose-3)==position.purpose:sub(1,#position.purpose-3) then
              founds=founds+1
              purpose=p.purpose
            end
          end
          if founds >1 then
            purpose=position.purpose
          end
        end
        if position.qty> config['splitQty'] then
          mQty=position.qty
        else
          rQty=position.qty
        end
        for i=1,rQty,1 do
          table.insert(transactions,{
            name=orderCode,
            amount = position.amount/divisor*mQty*-1,
            bookingDate = position.bookingDate+1,
            purpose = config.refund..MM.toEncoding(config['fixEncoding'],purpose),
            booked=not webCache
          })
        end
        if mixed then
          table.insert(transactions,{
            name=orderCode,
            amount = (position.amount*position.qty)/divisor,
            bookingDate = position.bookingDate,
            purpose = config.refundContra..purpose,
            booked=not webCache
          })
        end
      end
    end


  end

  if mixed then
    balance=0
  end

  -- issue5
  countOrders['last30']=nil
  countOrders['months-6']=nil
  numOfOrders=0
  for orderFilterVal,x in pairs(countOrders) do
    print("orderFilterVal="..orderFilterVal," counts=",x.counts,"text=",x.text)
    numOfOrders=numOfOrders+x.counts
  end
  print("total=",numOfOrders)

  RegressionTest.run(transactions)

  -- Return balance and array of transactions.
  return {balance=balance/divisor, transactions=transactions}
end

function EndSession ()
  -- Logout.
  if config['reallyLogout'] then
    html= connectShop(html:xpath('//a[contains(@href,"signout")]'):click())
  end
end

