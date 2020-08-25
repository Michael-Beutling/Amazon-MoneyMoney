-- Amazon Plugin for https://moneymoney-app.com
--
-- Copyright 2019-2020 Michael Beutling

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
local cacheVersion=9
local debugBuffer={context=''}
local webCacheLastId=nil

local config={
  configOk=true,
  reallyLogout=true,
  cleanCookies=false,
  cleanOrdersCache=false,
  cleanFilterCache=false,
  cleanInvalidCache=false,
  debug=false,
}

local const={
  regexOrderCodeNew="([D%d]%d%d%-%d%d%d%d%d%d%d%-%d%d%d%d%d%d%d)",
  regexPrice="EUR%s+(%d+),(%d%d)",
  str2date = {
    Januar=1,
    January=1,
    Februar=2,
    February=2,
    ["März"]=3,
    March=3,
    April=4,
    Mai=5,
    May=5,
    Juni=6,
    June=6,
    Juli=7,
    July=7,
    August=8,
    September=9,
    Oktober=10,
    October=10,
    November=11,
    Dezember=12,
    December=12
  },
  domain='.amazon.de',
  services    = {"Amazon Orders"},
  description = "Give you an overview about your amazon orders.",
  contra="Amazon contra ",
  returnText="Returned item: ",
  returnTextContra="Amazon contra returned item: ",
  refundTransaction="Refund for order ",
  refundTransactionContra="Amazon contra refund for order ",
  fixEncoding='latin1',
  differenceText='Difference (shipping costs, coupon etc.)',
  xpathOrderHistoryLink='//a[@id="nav-orders" or contains(@href,"/order-history")]',
  monthlyContra="monthy contra",
  yearlyContra="yearly contra",
  daysByMonth={31,28,31,30,31,30,31,31,30,31,30,31}
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
  end

  if config.cleanOrdersCache and LocalStorage ~=nil then
    config.cleanOrdersCache=false
    configDirty=true
    print("clean orders cache...")
    LocalStorage.OrderCache={}
  end

  if config.cleanFilterCache  then
    config.cleanFilterCache=false
    configDirty=true
    print("clean filter cache...")
    LocalStorage.orderFilterCache={}
  end

  if config.cleanInvalidCache  then
    config.cleanInvalidCache=false
    configDirty=true
    print("clean invalid cache...")
    LocalStorage.invalidCache={}
  end

  if config.cleanCookies then
    config.cleanCookies=false
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

print(((io == nil or io.open == nil) and 'signed ' or '')  .. const.services[1],"plugin loaded...")
if config.debug then print('debugging...') end

local baseurl='https://www'..const.domain

WebBanking{version  = 1.12,
  url         = baseurl,
  services    = const.services,
  description = const.description}

function debugBuffer.tablePrint(tbl)
  local t={}
  for k,v in pairs(tbl) do
    if type(v)=='table' then
      table.insert(t,k.."(#table)={"..debugBuffer.tablePrint(v).."}")
    else
      table.insert(t,k.."#"..type(v).."='"..tostring(v).."'")
    end
  end
  return table.concat(t,",")
end

function debugBuffer.print(...)
  if debugBuffer.context == nil then
    debugBuffer.context=''
  end
  --local args={debugBuffer.getStack(),debugBuffer.context}
  local args={debugBuffer.context}
  for _,v in pairs({...}) do
    local n
    if type(v)=='table' then
      n=type(v).."='"..debugBuffer.tablePrint(v).."'"
    else
      n=type(v).."='"..tostring(v).."'"
    end
    table.insert(args,n)
  end
  table.insert(debugBuffer,table.concat(args," "))
end

function debugBuffer.getStack(skip)
  local stack={}
  if skip== nil then
  skip=3
  end
  while debug.getinfo(skip) ~= nil do
  	table.insert(stack,debug.getinfo(skip).name)
  	skip=skip+1
  end
  
  return(table.concat(stack,"#"))
end

function debugBuffer.flush()
  if io ~= nil and config.debug then
    local debugFile=io.open("amazon-debug.log","a")
    if debugFile ~= nil then
      for i,v in ipairs(debugBuffer) do
        debugFile:write(v.."\n")
        debugBuffer[i]=nil
      end
      debugFile:close()
    end
  end
  for i,v in ipairs(debugBuffer) do
    print(v)
    debugBuffer[i]=nil
  end

end

function removeWebCacheLastItem()
  if webCache then
    os.remove(webCacheFolder..'/'..webCacheLastId..'.html')
    os.remove(webCacheFolder..'/'..webCacheLastId..'.json')
    print("remove",webCacheLastId,"from webCache")
  end
end

function connectShop(method, url, postContent, postContentType, headers)
  if method == nil then
    return nil
  end
  return HTML(connectShopRaw(method, url, postContent, postContentType, headers))
end

function connectShopJson(method, url, postContent, postContentType, headers)
  if method == nil then
    return nil
  end
  headers={["X-Requested-With"]="XMLHttpRequest" }
  return JSON(connectShopRaw(method, url, postContent, postContentType, headers)):dictionary()
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
    if config.debug then
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
          connection:setCookie(i..'; Domain='..const.domain..'; Expires=Tue, 01-Jan-2036 08:00:01 GMT; Path=/')
        else
        -- print("suppress cockie:"..i)
        end
      end
    end) --pcall
  end

  local cached=false
  local content, charset, mimeType, filename, headers
  local writeCache=false
  if webCache then
    writeCache=true
    webCacheLastId=MM.md5(tostring(method)..tostring(url)..tostring(postContent)..tostring(postContentType)..tostring(headers)..webCacheState)
    local webFile=io.open(webCacheFolder..'/'..webCacheLastId..'.json','rb')
    if webFile then
      local metaJSON=webFile:read('*all')
      local meta=JSON(metaJSON):dictionary()
      webFile:close()
      webFile=io.open(webCacheFolder..'/'..webCacheLastId..'.html','rb')
      if webFile then
        content=webFile:read('*all')
        webFile:close()
        charset=meta['charset']
        mimeType=meta['mimeType']
        filename=meta['filename']
        headers=meta['headers']
        cached=true
        print("webCache id="..webCacheLastId.." read.")
        webCacheHit=true
      end
      writeCache=false
    end
    if not cached and webCacheHit then
      error('webCache error!')
    end

  end

  if not cached then
    content, charset, mimeType, filename, headers = connection:request(method, url, postContent, postContentType, headers)
    if writeCache then
      local webFile=io.open(webCacheFolder..'/'..webCacheLastId..'.json',"wb")
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
      webFile=io.open(webCacheFolder..'/'..webCacheLastId..'.html',"wb")
      webFile:write(content)
      webFile:close()
      print("webCache id="..webCacheLastId.." written.")
    end
  end

  if not cached and baseurl == connection:getBaseURL():lower():sub(1,#baseurl)  then
    -- work around for deleted cookies, prevent captcha
    connection:setCookie('a-ogbcbff=; Domain='..const.domain..'; Expires=Thu, 01-Jan-1970 00:00:10 GMT; Path=/')
    connection:setCookie('ap-fid=; Domain='..const.domain..'; Expires=Thu, 01-Jan-1970 00:00:10 GMT; Path=/ap/; Secure')

    if config.debug then
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
  -- if config.debug then print("skip cookie saving") end
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
  debugBuffer.print("differences master")
  for k,v in pairs(master) do
    if v ~=0 then
      debugBuffer.print("n="..v," value="..k)
      differences=differences+1
    end
  end
  debugBuffer.print("differences now")
  for k,v in pairs(now) do
    if v ~=0 then
      debugBuffer.print("n="..v," value="..k)
      differences=differences+1
    end
  end
  debugBuffer.print("differences="..differences)
  return differences
end

function RegressionTest.run(transactions,regTestPre)
  if io ~= nil then
    local transFile=io.open(regTestPre.."_transactions_master.json",'rb')
    if transFile ~= nil then

      debugBuffer.print("run regression test")

      local master=JSON(transFile:read('*all')):dictionary()
      transFile.close()

      local transFile=io.open(regTestPre.."_transactions.json","wb")
      local now=RegressionTest.makeRows(transactions)
      transFile:write(JSON():set(now):json())
      transFile.close()


      local num=RegressionTest.compareTrees(now,master)
      debugBuffer.print("regression test finish")
      table.insert(transactions,{
        name="regression test finish",
        amount = num,
        bookingDate = os.time(),
        purpose = 'run '..LocalStorage.loginCounter,
        booked = false,
        accountNumber='accountNumber',
        bankCode='bankCode',
        bookingText='bookingText',
        endToEndReference='endToEndReference',
        mandateReference='mandateReference',
        creditorId='creditorId',
        returnReason='returnReason',
      --comment='comment\ncomment\n',
      --category="test"
      })
    end
  end
end

function connectShopWithCheck(method, url, postContent, postContentType, headers)
  if method == nil then
    return nil
  end
  local html=HTML(connectShopRaw(method, url, postContent, postContentType, headers))
  local xpform='//form[@name="signIn"]'
  if html:xpath(xpform):attr("name") ~= '' then
    removeWebCacheLastItem()
    print("Forced log out detect, enter username/password")
    html:xpath('//*[@name="email"]'):attr("value", secUsername)
    html:xpath('//*[@name="password"]'):attr("value",secPassword)
    html= connectShop(html:xpath(xpform):submit())
  end
  return html
end

function getDate(text)
  if type(text)~='string' then
    return invalidDate
  end
  local day,month,year=string.match(text,"(%d+)%.%s+([%S]+)%s+(%d+)")
  if day == nil then
    day,month,year=string.match(text,"(%d+)%s+([%S]+)%s+(%d+)")
  end
  local month=const.str2date[month]
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
  local amountHigh,amountLow=string.match(text,const.regexPrice)
  --debugBuffer.print(text,amountHigh,amountLow)
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

function getOrderCode(text)
  if type(text)~='string' then
    return nil
  end
  local orderCode=string.match(text,const.regexOrderCodeNew)
  return orderCode
end

function nodeExists(element,xpath)
  return element:xpath(xpath)[1] ~= nil
end

function getLastElementText(html,...)
  local elements=html:xpath(table.concat({...}))
  if elements:length() == 0 then
    return ''
  end
  return elements:get(elements:length()):text()
end

function getOrderInfosFromSummaryHeader(orderInfo,order)
  if orderInfo:text() == "" then
    return false
  end

  local headData={}

  orderInfo:xpath('.//span[@class="a-color-secondary value"]'):each(function(index,element)
    headData[index]=element:text()
  end)

  if #headData == 3 then
    -- customer account
    order.orderCode=getOrderCode(headData[3])
    debugBuffer.context=order.orderCode
    order.bookingDate=getDate(headData[1])
    order.orderTotal=getPrice(headData[2])
  elseif #headData == 4 then
    -- business account
    order.orderCode=getOrderCode(headData[4])
    debugBuffer.context=order.orderCode
    order.bookingDate=getDate(headData[1])
    order.accountNumber=headData[2]
    order.orderTotal=getPrice(headData[3])
  elseif #headData == 5 then
    -- business account
    order.orderCode=getOrderCode(headData[5])
    debugBuffer.context=order.orderCode
    order.bookingDate=getDate(headData[1])
    order.accountNumber=headData[2]
    order.bookingText=headData[4]
    order.orderTotal=getPrice(headData[3])
  else
    debugBuffer.print("unkown elements",table.concat(headData,"#"))
    return false
  end

  -- only business accounts
  local endToEndReference=orderInfo:xpath('.//div[contains(@class,"placed-by")]//span[@class="trigger-text"]'):text()
  if endToEndReference ~= '' then
    order.endToEndReference=endToEndReference
  end

  if order.bookingDate == invalidDate then
    order.orderCode=nil
  end

  if order.orderTotal == invalidPrice then
    order.orderCode=nil
  end

  order.detailsUrl=orderInfo:xpath('.//a[@class="a-link-normal" and contains(@href,"/order-details/")]'):attr('href')
  if order.detailsUrl == "" then
    order.digitalUrl=orderInfo:xpath('.//a[@class="a-link-normal" and contains(@href,"/digital/")]'):attr('href')
    if order.digitalUrl == "" then
      order.orderCode=nil
    end
  end

  return order.orderCode ~= nil
end

function isShipmentShorted(shipment)
  return shipment:xpath('.//a[contains(@href,"/order-details/")]'):length() ~= 0
end

--- @type orderPosition
-- @field purpose
-- @field amount
-- @field qty

--- @type order
-- @field #string orderCode
-- @field #number totalSum
-- @field #number orderTotal   total from header
-- @field #number refund       sum of refund from header
-- @field #number bookingDate  date of order
-- @field #string detailsUrl
-- @field #string digitalUrl
-- @field #list<#orderPosition> orderPositions
-- @field #boolean invalidArticles
-- @field #number detailsDate
-- @field #string accountNumber
-- @field #string endToEndReference

--- @type totals
-- @field  #number orderTotal Sum of order showed by Amazon
-- @field  #number refund amount of refund showed by Amazon

--- @function  getTotalsFromDetails
-- @return #totals
--



function getTotalsFromDetails(orderDetails)
  local totals={} --#totals

  local xPathPrefix=('//div[@id="od-subtotals"]//div[contains(@class,"a-span-last")]//')
  totals.orderTotal=getPrice(getLastElementText(orderDetails,xPathPrefix,'span[@class="a-color-base a-text-bold"]'))
  totals.refund=getPrice(getLastElementText(orderDetails,xPathPrefix,'span[@class="a-color-success a-text-bold"]'))
  if totals.refund ==invalidPrice then
    totals.refund=0
  end
  return totals

end

--- @function  getArticleFromShipment
-- @param #string shipment
-- @param #order order
-- @param #boolean doInsert
-- @return
function getArticleFromShipment(shipment,order,doInsert)
  doInsert=doInsert ~= false

  local refund=invalidPrice
  local refundText=shipment:xpath('.//div[@class="actions"]'):text()
  if refundText ~=""then
    refund=getPrice(refundText)
    --debugBuffer.print("action",order.orderCode,doInsert,refund)
  end

  shipment:xpath('.//div[@class="a-fixed-left-grid-inner"]'):each(function(index,article)
    local purpose
    local amount=invalidPrice
    local qty=getQtyFromElement(article)
    article:xpath('.//div[@class="a-row"]'):each(function(index,row)
      if purpose==nil then
        purpose=row:text()
      else
        local price=getPrice(row:text())
        if price~=invalidPrice then
          amount=price
        end
      end
    end) -- row
    if order.digitalUrl ~= nil then
      amount=order.orderTotal
      --debugBuffer.print(amount,purpose,qty)
    end
    if purpose~= nil and amount ~=invalidPrice and qty~= invalidQty then
      if doInsert then
        table.insert(order.orderPositions,{purpose=purpose,amount=amount,qty=qty})
        order.orderSum=order.orderSum+amount*qty
      end
      if refund~=invalidPrice then
        order.orderPositions[#order.orderPositions].refund=refund
        refund=invalidPrice
        --debugBuffer.print("refunded",order)
      end
    else
      order.invalidArticles=true
      --debugBuffer.print("invalid article",order.orderCode,amount,qty)
    end
  end) -- article
end

--- @function makeBranch
-- @param #map tree
-- @param #list branch
-- @return #map


function makeBranch(tree,branch)
  local temp=tree
  for _,v in ipairs(branch) do
    if temp[v] == nil then
      temp[v]={}
    end
    temp=temp[v]
  end
  return temp
end

--- @type returned
--  @field #number amount
--  @number #number bookingDate

--- @function getReturnsFromDetails
-- @param #table orderDetails
-- @param #order order
-- @return

function getReturnsFromDetails(orderDetails,order)
  orderDetails:xpath('//div[@id="od-returns-panel"]//div[@class="a-box-inner"]'):each(function(index,returnedShipments)
    -- debugBuffer.print(order.orderCode)
    local bookingDate=getDate(returnedShipments:xpath('.//div[@class="a-row a-spacing-base"]'):text())

    if bookingDate ~= invalidDate then
      returnedShipments:xpath('.//div[@class="a-row a-spacing-mini"]'):each(function(index,returnedItems)
        local purpose
        local amount=invalidPrice
        returnedItems:xpath('.//div[@class="a-row"]'):each(function(index,row)
          if purpose==nil then
            purpose=row:text()
          else
            local price=getPrice(row:text())
            if price~=invalidPrice then
              amount=price
            end
          end
        end) -- row
        if amount ~=invalidPrice and bookingDate ~=invalidDate then
          makeBranch(order,{'returns',bookingDate,amount,purpose})
          -- debugBuffer.print(order.returns)
        end
      end)
    end
  end)
  return
end

--- @function getRefundTransActions
-- @param  #table orderDetails
-- @param #order order
-- @return
--
function getRefundTransActions(orderDetails,order)
  orderDetails:xpath('.//div[@class="a-box a-last"]//div[@class="a-row a-color-success"]'):each(function(index,transaction)
    local bookingDate=getDate(transaction:text())
    local amount=getPrice(transaction:text())
    if bookingDate ~= invalidDate and amount ~= invalidPrice  then
      makeBranch(order,{'refundTransactions',bookingDate,amount})
    end
  end)
  return
end


--- @function getOrderaddress
-- @param #table html
-- @param #order order
-- @return
--

function getOrderaddress(orderDetails,order)
  if order.endToEndReference == nil then
    local name=orderDetails:xpath('//div[contains(@class,"od-shipping-address-container")]//div[@class="a-row"]'):text()
    local address=orderDetails:xpath('//div[contains(@class,"od-shipping-address-container")]//div[@class="displayAddressDiv"]'):text()

    if name ~='' and address ~= '' then
      name=name.." "..address
    elseif name == '' then
      name=address
    end

    if name ~= '' then
      order.endToEndReference=name
    end
  end
end

--- @function getOrderDetails
-- @param #order order
-- @return
--
function getOrderDetails(order)
  debugBuffer.context=order.orderCode
  if order.detailsUrl ~= "" then
    --debugBuffer.print("getOrderDetails")
    local html=connectShopWithCheck("GET",order.detailsUrl)
    local orderDetails=html:xpath('//div[@id="orderDetails"]')
    if orderDetails:text() ~="" then
      local totals=getTotalsFromDetails(html)
      --debugBuffer.print("total error",order.orderCode,"order",order.orderTotal , "totals",totals.orderTotal)
      local doInsert=#order.orderPositions == 0
      if doInsert then
        order.orderSum=0
      end
      local shipments=orderDetails:xpath('.//div[contains(concat(" ", normalize-space(@class), " "), " a-box shipment ")]')
      if shipments:text()=='' then
        shipments=orderDetails:xpath('./div[contains(concat(" ", normalize-space(@class), " "), " a-box ")]')
      end
      shipments:each( function(index,shipment)
        getArticleFromShipment(shipment,order,doInsert)
      end)
      getReturnsFromDetails(orderDetails,order)
      getRefundTransActions(orderDetails,order)
      getOrderaddress(orderDetails,order)
      order.detailsDate=os.time()+math.floor((math.random()*90+90)*24*60*60) -- distribute rescans randomly in future
    else
      debugBuffer.print("getOrderDetails no details",order.orderCode)
    end
  else
    -- no handling for digital orders
    order.detailsDate=os.time()+math.floor((math.random()*90+90)*24*60*60) -- distribute rescans in future
  end
  debugBuffer.context=''
end

function getOrdersFromSummary(html)
  local orders={}
  html:xpath('//div[@id="ordersContainer"]//div[@class="a-box-group a-spacing-base order"]'):each(function(index,orderBox)
    local orderInfo=orderBox:xpath('.//div[contains(@class,"order-info")]')
    local order={orderPositions={},orderSum=0,refund=0,detailsDate=2} -- #order
    if getOrderInfosFromSummaryHeader(orderInfo,order) then
      orderBox:xpath('.//div[not(contains(@class,"order-info"))]//div[@class="a-box-inner"]'):each(function(index,shipment)
        if isShipmentShorted(shipment) then
          order.detailsDate=0
          --debugBuffer.print("shorted",order.orderCode)
        else
          getArticleFromShipment(shipment,order)
        end
      end) -- shipment
      if order.invalidArticles ~= nil then
        order.orderPositions={}
        order.invalidArticles=nil
      end
      orders[order.orderCode]=order
    end
    debugBuffer.context=''
  end) -- orderbox
  return orders
end

function getMessageListURL(ajaxToken,page,pageToken)
  local url='/gp/message/ajax/message-list.html?'
  local fields={
    messageType='all',
    startDateTime=1000,
    endDateTime=3167942400000,
    pageSize=10,
    pageNum=page,
    sourcePage='inbox',
    isMobile=0,
    pageToken=pageToken,
    token=ajaxToken,
    stringDebug='',
    isDebug=''
  }
  local t={}
  for k,v in pairs(fields) do
    if v ~= nil then
      table.insert(t,k..'='..MM.urlencode(v))
    end
  end
  return url..table.concat(t,"&")
end

function getMessageURL(ajaxToken,messageId,threadId,messageDateTime)
  local url='/gp/message/ajax/message-content.html?'
  local fields={
    messageId=messageId,
    threadId=threadId,
    messageType='all',
    sourcePage='inbox',
    messageDateTime=messageDateTime,
    isMobile=0,
    token=ajaxToken,
    stringDebug='',
    isDebug=''
  }
  local t={}
  for k,v in pairs(fields) do
    if v ~= nil then
      table.insert(t,k..'='..MM.urlencode(v))
    end
  end
  return url..table.concat(t,"&")
end


function getMessageList(since)
  since=since*1000 -- in milliseconds
  local orderIds={}
  local html=connectShop("GET","/gp/message")
  local ajaxToken=html:xpath('//script[@type="a-state"]'):text()
  ajaxToken=string.match(ajaxToken,'{"token":"([A-Z0-9]+)"}')
  --print("ajaxToken",ajaxToken)
  if ajaxToken ~= "" then
    local page=1
    local messages={}
    local nextPageToken
    repeat
      MM.printStatus("Get page",page,"from Amazon message center.")
      local json=connectShopJson("GET",getMessageListURL(ajaxToken,page,nextPageToken))
      local noNextPage=true
      if json.html ~= nil then
        local newMessages=false
        local html=HTML("<html><body>"..json['html'].."</html></body>")
        html:xpath('//td'):each(function(index,td)
          local message={}
          for _,k in pairs({'messageSentTime','messageId','threadId'}) do
            message[k]=td:attr(k:lower())
          end
          if tonumber(message.messageSentTime) > since then
            messages[message.messageId]=message
            newMessages=true
          end
          --debugBuffer.print(message)
        end)
        json.html = nil
        --debugBuffer.print(page,json)
        if json.nextPageToken~= nil and newMessages then
          noNextPage=false
          page=page+1
          nextPageToken=json.nextPageToken
        end
      end
      --debugBuffer.flush()
    until noNextPage
    local numAll=0
    local num=0
    for _,v in pairs(messages) do
      numAll=numAll+1
    end
    for _,v in pairs(messages) do
      num=num+1
      MM.printStatus("Get Amazon message",num,"of",numAll)
      local json=connectShopJson("GET",getMessageURL(ajaxToken,v.messageId,v.threadId,v.messageSentTime))
      if json.html ~= nil then
        local html=HTML("<html><body>"..json['html'].."</html></body>")
        for orderId in html:html():gmatch(const.regexOrderCodeNew) do
          orderIds[orderId]=tonumber(v.messageSentTime)/1000 -- in milliseconds
        end
      end
    end
  end
  local numOrders=0
  for k,v in pairs(orderIds) do
    numOrders=numOrders+1
  end
  print(numOrders,"orders from messages")
  --debugBuffer.print(orderIds)
  --debugBuffer.flush()
  return orderIds
end

function getLastDayOfPeriod(period)
  local year=string.match(period,"(%d%d%d%d)")
  local month=string.match(period,"-(%d%d)")
  --debugBuffer.print("getLastDayOfPeriod",period,year,month)
  if month == nil then
    month="12"
  end
  year=tonumber(year)
  month=tonumber(month)
  local day=const.daysByMonth[month]
  if month == 2 and (year%4) == 0 and ((year%400)==0 or (year%100)~=0) then
    day=29
  end
  return os.time{year=year,month=month,day=day}
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
      html= connectShop(html:xpath(const.xpathOrderHistoryLink):click())
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

    if LocalStorage.loginCounter == nil then
      LocalStorage.loginCounter=0
    end
    LocalStorage.loginCounter=LocalStorage.loginCounter+1
    print("run=",LocalStorage.loginCounter)

    if config.debug then
      webCache=os.rename(webCacheFolder,webCacheFolder) and true or false
      if webCache then
        print("webcache on")
        local temp=webCacheFolder.."/cleanLocalStorage"
        local cleanLocalStorage=os.rename(temp,temp) and true or false
        if cleanLocalStorage then
          print("clean LocalStorage")
          LocalStorage.OrderCache={}
          LocalStorage.orderFilterCache={}
          LocalStorage.newestMessage=0
          LocalStorage.balancesByPeriod={}
        end
      end
    end
    html = connectShop("GET",baseurl)
    html= connectShop(html:xpath(const.xpathOrderHistoryLink):click())

    enterCredentials('1.login')
  end

  -- Captcha
  --
  local captcha=html:xpath('//img[@id="auth-captcha-image"]'):attr('src')
  --div id="image-captcha-section"
  if captcha ~= "" then
    if config.debug then print("login captcha") end
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
    if config.debug then print("passcode 1. part") end
    html:xpath('//input[@type="radio"]'):each(function (index,element)
      text=text..index..". "..element:xpath('..'):text().."\n"
      number=index
      if  tonumber(index) == tonumber(credentials[1]) then
        element:attr('checked','checked')
        if config.debug then print("select",element:xpath('..'):text()) end
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
    if config.debug then print("passcode 2. part") end
    html:xpath('//*[@name="code"]'):attr("value",credentials[1])
    html= connectShop(html:xpath('//form[@action="verify"]'):submit())
  end

  -- 2.FA
  local mfatext=html:xpath('//form[@id="auth-mfa-form"]//p'):text()
  if mfatext ~= "" then
    if config.debug then print("login mfa") end
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
    aName=html:xpath('//span[@class="nav-shortened-name"]'):text()
    if aName == "" then
      aName=html:xpath('//span[@class="abnav-accountfor"]'):text()
      aName=string.gsub(aName,"Konto für ","")
    end
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
  local accounts={}
  for _,i in pairs({"mix","normal","inverse","monthly","yearly"}) do
    table.insert(accounts,{ name = "Amazon "..name, owner = secUsername, accountNumber=i, type = AccountTypeOther})
    LocalStorage.getOrders[i]=false
  end
  return accounts
end

function RefreshAccount (account, since)
  local mixed=false
  local periodly=false
  local now=os.time()

  webCacheState='RefreshAccount'

  if type(account.attributes) == 'table' then
    for k,v in pairs(account.attributes) do
      print("attribut",k,config[k])
      if type(config[k]) == 'boolean' then
        if v == 'true' then
          print("set config",k,"= true")
          config[k]=true
        else
          print("set config",k,"= true")
          config[k]=false
        end
      end
      if type(const[k]) == 'string' then
        print("const k=",v)
        const[k]=v      
      end
      if k == 'resetCache' and v ~= LocalStorage.resetCache then
        LocalStorage.OrderCache={}
        LocalStorage.orderFilterCache={}
        LocalStorage.invalidCache={}
        LocalStorage.resetCache=v
        return {balance=0, transactions={[1]=
          {
              name="Cache reset, please reload!",
              amount = 0,
              bookingDate = now,
              purpose = "... and drink a coffee :)",
              booked = false,
            }
          }}
      end
    end
  end

  local divisor=-100
  if account.accountNumber == "inverse" then
    divisor=100
  end

  if account.accountNumber == "mix" then
    mixed=true
  end
 
  local periodFmt
  local periodContra
  if account.accountNumber == "monthly" then
    mixed=true
    periodly=true
    periodFmt="%Y-%m"
    periodContra=const.monthlyContra
  end
  if account.accountNumber == "yearly" then
    mixed=true
    periodly=true
    periodFmt="%Y"
    periodContra=const.yearlyContra
  end
 
  print("Refresh",account.accountNumber)

  if LocalStorage.getOrders[account.accountNumber] == false or LocalStorage.getOrders[account.accountNumber] == nil then
    LocalStorage.getOrders[account.accountNumber]=true

    return {balance=0, transactions={[1]=
      {
        name="Please reload!",
        amount = 0,
        bookingDate = now,
        purpose = "... and drink a coffee :)",
        booked = false,
      }
    }}
  end

  local transactions={}

  if LocalStorage.loginCounter ~= LocalStorage.lastLoginCounter then

    html=connectShop("GET",baseurl)

    -- Bestellungen
    html= connectShop(html:xpath(const.xpathOrderHistoryLink):click())

    if LocalStorage.OrderCache == nil then
      LocalStorage.OrderCache={}
    end

    if LocalStorage.orderFilterCache == nil then
      LocalStorage.orderFilterCache={}
    end

    if LocalStorage.invalidCache == nil then
      LocalStorage.invalidCache={}
    end

    local orderFilterSelect=html:xpath('//select[@name="orderFilter"]'):children()
    orderFilterSelect:each(function(index,element)
      local orderFilterVal=element:attr('value')
      local foundOrders=true
      local foundNewOrders=false
      if string.match(orderFilterVal, "months-") or LocalStorage.orderFilterCache[orderFilterVal] == nil then
        MM.printStatus('Get order overview for "'..element:text()..'"')
        --print(orderFilterVal)
        html:xpath('//*[@name="orderFilter"]'):select(orderFilterVal)
        html=connectShop(html:xpath('//*[@id="timePeriodForm"]'):submit())

        local foundEnd=false
        repeat
          for k,v in pairs(getOrdersFromSummary(html)) do
            foundOrders=true
            if LocalStorage.OrderCache[k]==nil then
              LocalStorage.OrderCache[k]=v
              foundNewOrders=true
            end
          end
          local nextPage=html:xpath('//li[@class="a-last"]/a[@href]')
          if nextPage:text() ~= "" then
            html=connectShop(nextPage:click())
          else
            foundEnd=true
          end
        until foundEnd
        if not foundNewOrders and foundOrders then
          LocalStorage.orderFilterCache[orderFilterVal]=true
          --print("orderFilter="..orderFilterVal.." cached")
        end
      end
      return true
    end)

    -- modified orders? read messages
    if LocalStorage.newestMessage == nil then
      LocalStorage.newestMessage = now-(24*60*60)
    end

    local newestMessage=LocalStorage.newestMessage

    for orderCode,messageTime in pairs(getMessageList(LocalStorage.newestMessage)) do

      if newestMessage<messageTime then
        newestMessage=messageTime
      end
      if LocalStorage.OrderCache[orderCode] ~= nil then
        LocalStorage.OrderCache[orderCode].detailsDate=1
      end
    end
    LocalStorage.newestMessage = newestMessage

    -- count order details to get

    local ordersCounter=0
    local ordersTotal=0

    for orderCode,order in pairs(LocalStorage.OrderCache) do
      if order.detailsDate < now then
        ordersTotal=ordersTotal+1
      end
    end

    -- get order details from order details page

    for orderCode,order in pairs(LocalStorage.OrderCache) do
      if order.detailsDate < now then
        ordersCounter=ordersCounter+1
        MM.printStatus(ordersCounter.."/"..ordersTotal,"Get details for order",orderCode)
        getOrderDetails(order)
      end
    end

    LocalStorage.lastLoginCounter = LocalStorage.loginCounter
  else
    print("skip account scan")
  end

  local balance=0
  local balancesByPeriod={}
  for orderCode,order in pairs(LocalStorage.OrderCache) do

    -- orderPositions,{purpose=purpose,amount=amount,qty=qty})
    if not mixed then
      balance=balance+order.orderTotal
    end
    if order.since == nil then
      order.since=now
    end

    local report=order.since >= since
    
    if periodly then
      local period=os.date(periodFmt,order.bookingDate)
      if balancesByPeriod[period] == nil then
        balancesByPeriod[period] = {report=true,balance=order.orderTotal}
      else
        balancesByPeriod[period].balance=balancesByPeriod[period].balance+order.orderTotal
      end
      if not report then
        balancesByPeriod[period].report=false
      end  
    end
    
    
    if report then
      for index,position in pairs(order.orderPositions) do
        table.insert(transactions,{
          name=orderCode,
          amount = position.amount/divisor*position.qty,
          bookingDate = order.bookingDate+1,
          purpose = MM.toEncoding(const.fixEncoding,position.purpose),
          endToEndReference = order.endToEndReference,
          accountNumber = order.accountNumber,
          bookingText=order.bookingText,
        })
      end

      if order.orderSum ~= order.orderTotal then
        table.insert(transactions,{
          name=orderCode,
          amount = (order.orderTotal-order.orderSum)/divisor,
          bookingDate = order.bookingDate,
          purpose = const.differenceText,
          endToEndReference = order.endToEndReference,
          accountNumber = order.accountNumber,
          bookingText=order.bookingText,
        })
      end

      if mixed and order.orderTotal ~= 0 and not periodly then
        if order.since >= since then
          table.insert(transactions,{
            name=orderCode,
            amount = order.orderTotal/divisor*-1,
            bookingDate = order.bookingDate,
            purpose = const.contra..orderCode,
            endToEndReference = order.endToEndReference,
            accountNumber = order.accountNumber,
            bookingText=order.bookingText,
          })
        end
      end
    end

    -- makeBranch(order,{'refundTransactions',bookingDate,amount})
    if order.refundTransactions ~= nil then
      for bookingDate,v in pairs(order.refundTransactions) do
        
        local period=os.date(periodFmt,bookingDate)
        if balancesByPeriod[period] == nil then
          balancesByPeriod[period] = {report=true,balance=0}
        end
        for amount,v in pairs(v) do

          if not mixed then
            balance=balance-amount
          end

          if v.since== nil then
            v.since=now
          end

          local report=v.since >= since
          
          if periodly then
            balancesByPeriod[period].balance=balancesByPeriod[period].balance-amount
            if not report then
              balancesByPeriod[period].report=false
            end  
          end
                    
          if v.since >= since then
            table.insert(transactions,{
              name=orderCode,
              amount = amount/divisor*-1,
              bookingDate = bookingDate,
              purpose = const.refundTransaction..orderCode,
              endToEndReference = order.endToEndReference,
              accountNumber = order.accountNumber,
              bookingText=order.bookingText,
            })
            if mixed and not periodly then
              table.insert(transactions,{
                name=orderCode,
                amount = amount/divisor,
                bookingDate = bookingDate,
                purpose = const.refundTransactionContra..orderCode,
                endToEndReference = order.endToEndReference,
                accountNumber = order.accountNumber,
                bookingText=order.bookingText,
              })
            end
          end
        end
      end
    end

    -- makeBranch(order,{'returns',bookingDate,amount,purpose})
    if order.returns ~= nil then
      for bookingDate,v in pairs(order.returns) do
        for amount,v in pairs(v) do
          for purpose,v in pairs(v) do
            -- if not mixed then
            --   balance=balance-amount
            -- end
            if v.since== nil then
              v.since=now
            end
            if v.since >= since then
              table.insert(transactions,{
                name=orderCode,
                amount = amount/divisor*-1,
                bookingDate = bookingDate,
                purpose = MM.toEncoding(const.fixEncoding,const.returnText..purpose),
                endToEndReference = order.endToEndReference,
                accountNumber = order.accountNumber,
                bookingText=order.bookingText,
              })
              table.insert(transactions,{
                name=orderCode,
                amount = amount/divisor,
                bookingDate = bookingDate,
                purpose = MM.toEncoding(const.fixEncoding,const.returnTextContra..purpose),
                endToEndReference = order.endToEndReference,
                accountNumber = order.accountNumber,
                bookingText=order.bookingText,
              })
            end
          end
        end
      end
    end
  end
  
  if periodly then
    if LocalStorage.balancesByPeriod == nil then
      LocalStorage.balancesByPeriod={}
    end
    local lastPeriod=""
    
    for k,v in pairs(balancesByPeriod) do
      if lastPeriod<k then
        lastPeriod=k
       end
       -- debugBuffer.print(k)
    end
    
    -- debugBuffer.print("lastPeriod=",lastPeriod)

    for k,v in pairs(balancesByPeriod) do
      if v.report then
        if k == lastPeriod then
          LocalStorage.balancesByPeriod[k]={v.balance}
        else
          if LocalStorage.balancesByPeriod[k] == nil then
            LocalStorage.balancesByPeriod[k]={}
          end
          local sum=0
          for _,v in  ipairs(LocalStorage.balancesByPeriod[k]) do
            sum=sum+v
          end
          if sum ~= v.balance then
            table.insert(LocalStorage.balancesByPeriod[k],v.balance-sum)
          end
        end
        for _,v in  ipairs(LocalStorage.balancesByPeriod[k]) do
              table.insert(transactions,{
                name=k,
                amount = v/divisor*-1,
                bookingDate = getLastDayOfPeriod(k),
                purpose = periodContra,
                booked= k~=lastPeriod,
              })
              if k == lastPeriod then
                balance=v
              end
          -- debugBuffer.print(k,v,getLastDayOfPeriod(k))
        end
      end
    end 
  end
  
  --print(balance)
  RegressionTest.run(transactions,account.accountNumber)

  debugBuffer.flush()

  if webCache then
    for _,v in pairs(transactions) do
      v.booked=false
    end
  end

  for _,v in pairs(transactions) do
    if v.accountNumber == nil then
      v.accountNumber=account.owner
    end
  end

  -- Return balance and array of transactions.
  return {balance=balance/divisor, transactions=transactions}
end

function EndSession ()
  -- Logout.
  if config.reallyLogout then
    local logoutElement=html:xpath('//a[@id="nav-item-signout" or contains(@href,"sign-out")]')
    if logoutElement ~= nil then
      print("Logout")
      if logoutElement:click() ~= nil then
        html= connectShop(logoutElement:click())
      end
    else
      print("error: logout link not found")
    end
  end
end

