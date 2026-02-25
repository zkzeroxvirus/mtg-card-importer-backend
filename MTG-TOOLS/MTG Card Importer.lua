-- ============================================================================
-- Card Importer for Tabletop Simulator
-- ============================================================================
-- Version must be >=1.9 for TyrantEasyUnified; keep mod name stable for Encoder lookup
-- Metadata
mod_name, version = 'Card Importer', '1.914'
self.setName('[854FD9]' .. mod_name .. ' [49D54F]' .. version)

-- Author Information
author = '76561198045776458'
coauthor = '76561197968157267' -- PIE
WorkshopID = 'https://steamcommunity.com/sharedfiles/filedetails/?id=1838051922'
GITURL = 'https://raw.githubusercontent.com/zkzeroxvirus/mtg-card-importer-backend/master/MTG-TOOLS/MTG%20Card%20Importer.lua'
lang = 'en'
-- Modified by Sirin

-- ============================================================================
-- Backend Configuration
-- ============================================================================
-- Change this to your backend URL:
--   - For local testing: 'http://localhost:3000'
--   - For production: Your deployed backend URL
-- Example: BACKEND_URL = 'https://your-backend.onrender.com'
BACKEND_URL = 'http://api.mtginfo.org'

-- Auto-update configuration (checks GitHub for newer version on load)
AUTO_UPDATE_ENABLED = true

-- ============================================================================
-- Classes and Utilities
-- ============================================================================
local TBL = {
  __call = function(t, k)
    if k then return t[k] end
    return t.___
  end,
  __index = function(t, k)
    if type(t.___) == 'table' then
      rawset(t, k, t.___())
    else
      rawset(t, k, t.___)
    end
    return t[k]
  end
}

function TBL.new(d, t)
  if t then
    t.___ = d
    return setmetatable(t, TBL)
  else
    return setmetatable(d, TBL)
  end
end

textItems={}
newText=setmetatable({
  type='3DText',
  position={0,2,0},
  rotation={90,0,0}},
  {__call=function(t,p,text,f,rot)
    if type(f) == 'number' and f > 360 then
      -- Old behavior: f was rotation, not font size
      rot = f
      f = 50
    end
    local rotation = {90, 0, 0}
    if rot then
      rotation = {90, rot + 180, 0}
    end
    local spawnData = {
      type='3DText',
      position=p,
      rotation=rotation
    }
    local o=spawnObject(spawnData)
    table.insert(textItems,o)
    o.TextTool.setValue(text)
    o.TextTool.setFontSize(f or 50)
    return function(t)
      if t then
        o.TextTool.setValue(t)
      else
        for i,oo in ipairs(textItems) do
          if oo==o then
            table.remove(textItems,i)
          end
        end
        o.destruct()
      end
    end
  end})

--[[Variables]]
local Deck,Tick,Test,Quality,Back=1,0.2,false,TBL.new('normal',{}),TBL.new('https://i.stack.imgur.com/787gj.png',{})

-- Request timeout tracking
local requestStartTime = nil
local REQUEST_TIMEOUT = 30  -- seconds before considering a request hung (allows for backend cold start)
local TIMEOUT_CHECK_INTERVAL = 10  -- seconds between timeout checks
local timeoutMonitorActive = false  -- Prevents multiple monitor chains
local queuePumpScheduled = false

local function scheduleImporterPump()
  if queuePumpScheduled then
    return
  end

  queuePumpScheduled = true
  Wait.frames(function()
    queuePumpScheduled = false
    Importer()
  end, 1)
end

-- Web request error handling (backend and Scryfall proxy)
function handleWebError(wr, qTbl, context)
  if wr and wr.is_error then
    local msg = (context or 'Request failed') .. ': ' .. tostring(wr.error or 'Network error')
    if wr.response_code then
      msg = msg .. ' (HTTP ' .. tostring(wr.response_code) .. ')'
    end
    if qTbl and qTbl.color then
      Player[qTbl.color].broadcast(msg,{1,0,0})
    else
      printToAll(msg,{1,0,0})
    end
    endLoop()
    return true
  end

  if wr and wr.response_code and wr.response_code >= 400 then
    local details = nil
    if wr.text and wr.text ~= '' and not wr.text:match('^%s*<') then
      local ok, json = pcall(function() return JSON.decode(wr.text) end)
      if ok and json and json.details then
        details = json.details
      end
    end
    local msg = details or ((context or 'Request failed') .. ' (HTTP ' .. tostring(wr.response_code) .. ')')
    if qTbl and qTbl.color then
      Player[qTbl.color].broadcast(msg,{1,0,0})
    else
      printToAll(msg,{1,0,0})
    end
    endLoop()
    return true
  end

  if (not wr or not wr.text or wr.text == '') and wr and wr.response_code == 204 then
    -- Silent suppression for repeated errors
    endLoop()
    return true
  end

  return false
end

function urlEncode(str)
  return (tostring(str or ''):gsub('([^%w%-%.%_%~])', function(c)
    return string.format('%%%02X', string.byte(c))
  end))
end

function urlDecode(str)
  local decoded = tostring(str or ''):gsub('+', ' ')
  decoded = decoded:gsub('%%(%x%x)', function(hex)
    return string.char(tonumber(hex, 16))
  end)
  return decoded
end

--Image Handler
function trunkateURI(uri,q,s)
  if q=='png' then uri=uri:gsub('.jpg','.png')end
  return uri:gsub('%?.*',''):gsub('normal',q)..s
end

local function spawnImageOnlyCard(qTbl)
  local faceUrl = qTbl and qTbl.customImage or nil
  if not faceUrl or faceUrl == '' then
    endLoop()
    return
  end

  local backUrl = Back[qTbl.player] or Back.___ or 'https://i.stack.imgur.com/787gj.png'
  local cardSeed = math.random(100, 999)
  local displayName = qTbl.name or ''
  if displayName == '' or displayName == 'blank card' or displayName == 'blank%20card' then
    displayName = 'Custom Image Card'
  end

  local cardDat={
    Transform={posX=0,posY=0,posZ=0,rotX=0,rotY=0,rotZ=0,scaleX=1,scaleY=1,scaleZ=1},
    Name='Card',
    Nickname=displayName,
    Description='Custom image spawn',
    CardID=cardSeed*100,
    CustomDeck={[cardSeed]={
      FaceURL=faceUrl,
      BackURL=backUrl,
      NumWidth=1,NumHeight=1,Type=0,
      BackIsHidden=true,UniqueBack=false}},
  }

  local spawnDat={
    data=cardDat,
    position=qTbl.position or {0,2,0},
    rotation=Vector(0,Player[qTbl.color].getPointerRotation(),0)
  }

  spawnObjectData(spawnDat)
  Player[qTbl.color].broadcast('Spawned custom image card.',{0.7,0.9,1})
  endLoop()
end

local Card=setmetatable({n=1,image=false},
  {__call=function(t,c,qTbl)
    local success,errorMSG=pcall(function()
      c.face,c.oracle,c.back='','',Back[qTbl.player] or Back.___
      local n,state,qual,imgSuffix=t.n,false,Quality[qTbl.player],''
      t.n=n+1

      if c.image_status~='highres_scan' then
        imgSuffix='?'..tostring(os.date('%x')):gsub('/', '')
      end

      local orientation={false}
      if c.card_faces and c.image_uris then
        local instantSorcery=0
        for i,f in ipairs(c.card_faces)do
          f.name=f.name:gsub('"','')..'\n'..f.type_line..'\n'..(c.cmc or 0)..'CMC'
          if i==1 then c.name=f.name end
          c.oracle=c.oracle..f.name..'\n'..setOracle(f)..(i==#c.card_faces and''or'\n')
          if ('split'):find(c.layout or '') and not c.oracle:find('Aftermath') then
            instantSorcery=1+instantSorcery
          end
        end
        if instantSorcery==2 then orientation[1]=true end
      elseif c.card_faces then
        local f=c.card_faces[1]
        local cmc=c.cmc or f.cmc or 0
        c.name=f.name:gsub('"','')..'\n'..f.type_line..'\n'..cmc..'CMC DFC'
        c.oracle = setOracle(f)
        for i, face in ipairs(c.card_faces) do
          if face.type_line and (face.type_line:find('Battle') or face.type_line:find('Room')) then
            orientation[i] = true
          else
            orientation[i] = false
          end
        end
      else
        c.name = (c.name or 'Unknown Card'):gsub('"', '') .. '\n' .. (c.type_line or '') .. '\n' .. tostring(c.cmc or 0) .. 'CMC'
        c.oracle = setOracle(c)
        if ('planar'):find(c.layout or '') then
          orientation[1] = true
        end
      end

      local backDat=nil
      if qTbl.deck and qTbl.image and qTbl.image[n] then
        c.face=qTbl.image[n]
      elseif c.card_faces and not c.image_uris then
        local faceAddress=trunkateURI(c.card_faces[1].image_uris.normal, qual, imgSuffix)
        local backAddress=trunkateURI(c.card_faces[2].image_uris.normal, qual, imgSuffix)
        if faceAddress:find('/back/') and backAddress:find('/front/') then
          local temp=faceAddress
          faceAddress=backAddress
          backAddress=temp
        end
        if t.image then faceAddress,backAddress=t.image,t.image end
        c.face=faceAddress
        local f=c.card_faces[2]
        local cmc=c.cmc or f.cmc or 0
        local name=f.name:gsub('"','')..'\n'..f.type_line..'\n'..cmc..'CMC DFC'
        local oracle=setOracle(f)
        local b=n
        if qTbl.deck then b=qTbl.deck+n end
        backDat={
          Transform={posX=0,posY=0,posZ=0,rotX=0,rotY=0,rotZ=0,scaleX=1,scaleY=1,scaleZ=1},
          Name='Card',
          Nickname=name,
          Description=oracle,
          Memo=c.oracle_id,
          CardID=b*100,
          CustomDeck={[b]={
            FaceURL=backAddress,
            BackURL=c.back,
            NumWidth=1,NumHeight=1,Type=0,
            BackIsHidden=true,UniqueBack=false}},
        }
      elseif t.image then
        c.face=t.image
        t.image=false
      elseif c.image_uris then
        c.face=trunkateURI(c.image_uris.normal, qual, imgSuffix)
      end

      local cardDat={
        Transform={posX=0,posY=0,posZ=0,rotX=0,rotY=0,rotZ=0,scaleX=1,scaleY=1,scaleZ=1},
        Name='Card',
        Nickname=c.name,
        Description=c.oracle,
        Memo=c.oracle_id,
        CardID=n*100,
        CustomDeck={[n]={
          FaceURL=c.face,
          BackURL=c.back,
          NumWidth=1,NumHeight=1,Type=0,
          BackIsHidden=true,UniqueBack=false}},
      }

      if backDat then cardDat.States={[2]=backDat} end

      local landscapeView={0,180,270}
      if orientation[1] then cardDat.AltLookAngle=landscapeView end
      if orientation[2] and cardDat.States and cardDat.States[2] then cardDat.States[2].AltLookAngle=landscapeView end

      if not(qTbl.deck) or qTbl.deck==1 then
        local spawnDat={
          data=cardDat,
          position=qTbl.position or {0,2,0},
          rotation=Vector(0,Player[qTbl.color].getPointerRotation(),0)
        }
        spawnObjectData(spawnDat)
        uLog(qTbl.color..' spawned '..(c.name or 'Card'):gsub('\n.*',''))
        endLoop()
      else
        if Deck==1 then
          deckDat={
            Transform={posX=0,posY=0,posZ=0,rotX=0,rotY=0,rotZ=0,scaleX=1,scaleY=1,scaleZ=1},
            Name='Deck',
            Nickname=Player[qTbl.color].steam_name or 'Deck',
            Description=qTbl.full or 'Deck',
            DeckIDs={},
            CustomDeck={},
            ContainedObjects={},
          }
        end
        deckDat.DeckIDs[Deck]=cardDat.CardID
        deckDat.CustomDeck[n]=cardDat.CustomDeck[n]
        deckDat.ContainedObjects[Deck]=cardDat
        if Deck<qTbl.deck then
          qTbl.text('Spawning here\n'..Deck..' cards loaded')
          Deck=Deck+1
        elseif Deck==qTbl.deck then
          local spawnDat={
            data=deckDat,
            position=qTbl.position or {0,2,0},
            rotation=Vector(0,Player[qTbl.color].getPointerRotation(),180)
          }
          spawnObjectData(spawnDat)
          Player[qTbl.color].broadcast('All '..Deck..' cards loaded!',{0.5,0.5,0.5})
          Deck=1
          endLoop()
        end
      end
    end)
    if not success then
      printToAll('[b][FF0000]❌ Importer Error Detected[/b]',{1,0,0})
      printToAll(tostring(errorMSG),{0.8,0,0})
      printToAll('[b][0099FF]♻️ Restarting Importer...[/b]',{0,0.5,1})
      for i,o in ipairs(textItems) do
        if o~=nil then o.destruct() end
      end
      self.reload()
    end
  end})

function setOracle(c)local n='\n[b]'
  local oracleText = (c.oracle_text or ''):gsub('"',"'")
  if c.power then n=n..c.power..'/'..(c.toughness or '')
  elseif c.loyalty then n=n..tostring(c.loyalty)
  else n=false end return oracleText..(n and n..'[/b]'or'') end

function setCard(wr,qTbl,originalData)
  if handleWebError(wr, qTbl, 'Card request failed') then
    return
  end

  if not wr or not wr.text or wr.text == '' then
    endLoop()
    return
  end

  if wr.text:match('^%s*<') or wr.text:match('<!DOCTYPE') then
    Player[qTbl.color].broadcast('Backend returned HTML error. Check connection.',{1,0,0})
    endLoop()
    return
  end

  local ok, json = pcall(function() return JSON.decode(wr.text) end)
  if not ok or not json then
    Player[qTbl.color].broadcast('Invalid card payload from backend.',{1,0,0})
    endLoop()
    return
  end

  if json.object=='card' then
    if json.lang==lang or not json.set or not json.collector_number then
      Card(json, qTbl)
      return
    elseif json.lang=='en' then
      WebRequest.get(BACKEND_URL..'/cards/'..json.set..'/'..json.collector_number..'/'..lang,function(request)
        local success, result = pcall(function()
          setCard(request, qTbl, json)
        end)
        if not success then
          log('[Card Importer] Error in language fallback nested request: ' .. tostring(result))
          Card(json,qTbl)
        end
      end)
      return
    else
      WebRequest.get(BACKEND_URL..'/cards/'..json.set..'/'..json.collector_number..'/en',function(a)
        local success, result = pcall(function()
          setCard(a,qTbl,json)
        end)
        if not success then
          log('[Card Importer] Error in English fallback nested request: ' .. tostring(result))
          Card(json,qTbl)
        end
      end)
      return
    end
  elseif originalData and originalData.name then
    WebRequest.get(BACKEND_URL..'/card/'..originalData.name:gsub('%W',''),function(a)
      local success, result = pcall(function()
        setCard(a,qTbl)
      end)
      if not success then
        log('[Card Importer] Error in originalData name search: ' .. tostring(result))
        Player[qTbl.color].broadcast('Error processing card data.',{1,0,0})
        endLoop()
      end
    end)
    return
  elseif json.object=='error' then
    Player[qTbl.color].broadcast(json.details,{1,0,0})
    endLoop()
    return
  end

  endLoop()
end

function parseForToken(oracle,qTbl)endLoop()end
--[[  if oracle:find('token')and oracle:find('[Cc]reate')then
    --My first attempt to parse oracle text for token info
    local ptcolorType,abilities=oracle:match('[Cc]reate(.+)(token[^\n]*)')
    --Check for power and toughness
    local power,toughness='_','_'
    if ptColorType:find('%d/%d')then
      power,toughness=ptColorType:match('(%d+)/(%d+)')end
    --It wouldn't be able to find treasure or clues
    local colors=''
    for k,v in pairs({w='white',u='blue',b='black',r='red',g='green',c='colorless'})do
     if ptColorType:find(v)then colors=colors..k end end
    --How the heck am I going to do abilities
    if abilities:find('tokens? with ')then
      local abTbl={}
      abilities=abilities:gsub('"([^"]+)"',function(a)
        table.insert(abTbl,a)return''end)
      for _,v in pairs({'haste','first strike','double strike','reach','flying'})do
        if abilities:find(v)then table.insert(abTbl,v)end end
    end
  end
end]]

function spawnList(wr,qTbl)
  if handleWebError(wr, qTbl, 'Search failed') then
    return
  end
  uLog(wr.url)
  local txt=wr.text
  if txt then --PIE's Rework
    -- Check if response is HTML
    if txt:match('^%s*<') or txt:match('<!DOCTYPE') then
      Player[qTbl.color].broadcast('Backend returned HTML error.',{1,0,0})
      endLoop()
      return
    end
    local jsonType = txt:sub(1,20):match('{"object":"(%w+)"')
    if jsonType=='list' then
      local nCards=txt:match('"total_cards":(%d+)')
      if nCards~=nil then nCards=tonumber(nCards) else
        -- a jsonlist but couldn't find total_cards ? shouldn't happen, but just in case
        textItems[#textItems].destruct()
        table.remove(textItems,#textItems)
        endLoop()   --pieHere, I missed this one too
        return
      end
      if tonumber(nCards)>100 then
        Player[qTbl.color].broadcast('This search query gives too many results (>100)',{1,0,0})
        textItems[#textItems].destruct()
        table.remove(textItems,#textItems)
        endLoop()   --pieHere, I missed this one too
        return
      end
      qTbl.deck=nCards
      local last=0
      local cards={}
      for i=1,nCards do
        start=string.find(txt,'{"object":"card"',last+1)
        last=findClosingBracket(txt,start)
        local card = JSON.decode(txt:sub(start,last))
        Wait.time(function() Card(card,qTbl) end, i*Tick)
      end
      return

    elseif jsonType=='card' then
      local n,json=1,JSON.decode(txt)
      Card(json,qTbl)
      return

    elseif jsonType=='error' then
      local n,json=1,JSON.decode(txt)
      Player[qTbl.color].broadcast(json.details,{1,0,0})
    end
  end
  endLoop()
end

local function createFastProgressTicker(qTbl, count)
  local active = true
  local progress = 0
  local target = math.max((tonumber(count) or 1) - 1, 1)

  local function tick()
    if not active then
      return
    end

    if progress < target then
      progress = progress + 1
    end

    if qTbl and qTbl.text then
      qTbl.text('Spawning here\n'..tostring(progress)..' cards loaded')
    end

    Wait.time(tick, 0.06)
  end

  tick()

  return function(finalCount)
    active = false
    local finalValue = tonumber(finalCount) or progress
    if qTbl and qTbl.text and finalValue > 0 then
      qTbl.text('Spawning here\n'..tostring(finalValue)..' cards loaded')
    end
  end
end

local function requestRandomDeckFast(qTbl, queryRaw, count, onFallback)
  if not qTbl or not queryRaw or queryRaw == '' or not count or count <= 1 then
    return false
  end

  local payload = {
    q = queryRaw,
    count = count,
    back = Back[qTbl.player] or Back.___
  }

  if qTbl.text then
    qTbl.text('Building random deck\nfast path')
  end

  local stopProgressTicker = function() end
  if qTbl and qTbl.text then
    stopProgressTicker = createFastProgressTicker(qTbl, count)
  end

  WebRequest.custom(
    BACKEND_URL .. '/random/build',
    'POST',
    true,
    JSON.encode(payload),
    {
      Accept = 'application/x-ndjson',
      ['Content-Type'] = 'application/json'
    },
    function(wr)
      if not wr.is_done then
        return
      end

      if wr.is_error or (wr.response_code and wr.response_code >= 400) or not wr.text or wr.text == '' then
        stopProgressTicker(0)
        if onFallback then
          onFallback()
        else
          handleWebError(wr, qTbl, 'Random deck fast path failed')
        end
        return
      end

      local deckLine = nil
      for s in wr.text:gmatch('[^\r\n]+') do
        if s and s ~= '' then
          local ok, parsed = pcall(function()
            return JSON.decode(s)
          end)
          if ok and parsed and parsed.object ~= 'warning' then
            deckLine = s
            break
          end
        end
      end

      if not deckLine then
        stopProgressTicker(0)
        if onFallback then
          onFallback()
        else
          Player[qTbl.color].broadcast('Backend returned no cards for random deck.',{1,0,0})
          endLoop()
        end
        return
      end

      local okDeck, deckDat = pcall(function()
        return JSON.decode(deckLine)
      end)
      if not okDeck or not deckDat or not deckDat.ContainedObjects then
        stopProgressTicker(0)
        if onFallback then
          onFallback()
        else
          Player[qTbl.color].broadcast('Invalid random deck payload from backend.',{1,0,0})
          endLoop()
        end
        return
      end

      local spawnDat={
        data=deckDat,
        position=qTbl.position or {0,2,0},
        rotation=Vector(0,Player[qTbl.color].getPointerRotation(),180)
      }
      stopProgressTicker(#deckDat.ContainedObjects)
      spawnObjectData(spawnDat)
      Player[qTbl.color].broadcast('All '..tostring(#deckDat.ContainedObjects)..' cards loaded (fast path)!',{0.5,0.8,0.5})
      endLoop()
    end
  )

  return true
end

--[[Importer Data Structure]]
Importer=setmetatable({
  --Variables
  request={},
  --Functions
  Search=function(qTbl)
    WebRequest.get(BACKEND_URL..'/search?q='..qTbl.name,function(wr)
        spawnList(wr,qTbl)end)end,

  Back=function(qTbl)
    if qTbl.target then qTbl.url=qTbl.target.getJSON():match('BackURL": "([^"]*)"')end
    Back[qTbl.player]=qTbl.url
    Player[qTbl.color].broadcast('Card Backs set to\n'..qTbl.url,{0.9,0.9,0.9})
    endLoop()end,

  Spawn=function(qTbl)
    -- Encode name if not already encoded (handle both onChat and direct Importer() calls)
    local encodedName = qTbl.name
    if not encodedName:find('%%') then
      encodedName = urlEncode(encodedName)
    end
    WebRequest.get(BACKEND_URL..'/card/'..encodedName,function(wr)
        if handleWebError(wr, qTbl, 'Card lookup failed') then
          return
        end
        if wr.text:match('^%s*<') or wr.text:match('<!DOCTYPE') then
          Player[qTbl.color].broadcast('Backend returned HTML error.',{1,0,0})
          endLoop()
          return
        end
        local obj=JSON.decode(wr.text)
        -- Force token search if result is a Token, art_series, or other non-playable card type
        local shouldForceTokenSearch = false
        if obj.object=='card' then
          if obj.type_line and obj.type_line:match('Token') then
            shouldForceTokenSearch = true
          elseif obj.layout and (obj.layout == 'art_series' or obj.layout == 'token' or obj.layout == 'double_faced_token' or obj.layout == 'emblem') then
            shouldForceTokenSearch = true
          end
        end
        
        if shouldForceTokenSearch then
          WebRequest.get(BACKEND_URL..'/search?unique=card&q=t:token+'..encodedName,function(wr)
              spawnList(wr,qTbl)end)
          return false
        end
        if obj.object=='error' then
          if obj.details then
            Player[qTbl.color].broadcast(obj.details,{1,0,0})
          end
          -- Card not found, try finding all tokens matching this name/type (unique=card for unique names)
          WebRequest.get(BACKEND_URL..'/search?unique=card&q=t:token+'..encodedName,function(wr)
              spawnList(wr,qTbl)end)
          return false
        else setCard(wr,qTbl)end end)end,

  Token=function(qTbl)
    -- Get the card name - either from target or command
    local cardName = qTbl.target and qTbl.target.getName():gsub('\n.*','') or qTbl.name
    local encodedName = urlEncode(cardName)
    
    -- Fetch the card via generic endpoint (we filter all_parts to tokens/emblems below)
    WebRequest.get(BACKEND_URL..'/card/'..encodedName,function(wr)
      if handleWebError(wr, qTbl, 'Token lookup failed') then
        return
      end
      if wr.text and wr.text ~= '' then
        if wr.text:match('^%s*<') or wr.text:match('<!DOCTYPE') then
          Player[qTbl.color].broadcast('Backend returned HTML error.',{1,0,0})
          endLoop()
          return
        end
        local json=JSON.decode(wr.text)
        
        -- Check if card has all_parts (tokens/emblems)
        if json.all_parts and #json.all_parts>0 then
          -- Filter out the card itself, only spawn tokens/related cards
          local tokensToSpawn = {}
          for _,tokenPart in ipairs(json.all_parts)do
            local partType = (tokenPart.type_line or ''):lower()
            local partComponent = (tokenPart.component or ''):lower()
            local isTokenPart = partType:find('token') or partType:find('emblem') or partComponent == 'token' or partComponent == 'emblem'
            if tokenPart.id ~= json.id and isTokenPart then  -- Only spawn tokens/emblems, not the card itself
              table.insert(tokensToSpawn, tokenPart)
            end
          end
          
          if #tokensToSpawn > 0 then
            qTbl.deck=#tokensToSpawn
            for i,tokenPart in ipairs(tokensToSpawn)do
              Wait.time(function()
                -- Proxy each token via the backend proxy endpoint
                local proxyUrl = BACKEND_URL..'/proxy?uri='..tokenPart.uri:gsub('([^%w%-%.%_%~%:%/%?%#%[%]%@%!%$%&%\'%(%)*%+%,%;%=])', function(c)
                  return string.format('%%%02X', string.byte(c))
                end)
                WebRequest.get(proxyUrl,function(wr)setCard(wr,qTbl)end)
              end,i*Tick)
            end
          else
            -- No other tokens found, try parsing oracle text
            local oracle=json.oracle_text or ''
            if json.card_faces then
              for _,f in ipairs(json.card_faces)do 
                if f.oracle_text then
                  oracle=oracle..'\n'..setOracle(f)
                end
              end
            end
            parseForToken(oracle,qTbl)
          end
        elseif json.object=='card' then
          -- Card found but no tokens in all_parts, try parsing oracle text for token info
          local oracle=json.oracle_text or ''
          if json.card_faces then
            for _,f in ipairs(json.card_faces)do 
              if f.oracle_text then
                oracle=oracle..'\n'..setOracle(f)
              end
            end
          end
          parseForToken(oracle,qTbl)
        elseif qTbl.target then
          -- Button call with target but no Scryfall data, parse target description
          local o=qTbl.target.getDescription()
          if o:find('[Cc]reate')or o:find('emblem')then 
            parseForToken(o,qTbl)
          else 
            Player[qTbl.color].broadcast('Card not found in Scryfall\nAnd did not have oracle text to parse.',{0.9,0.9,0.9})
            endLoop()
          end
        else
          Player[qTbl.color].broadcast('No Tokens Found',{0.9,0.9,0.9})
          endLoop()
        end
      else
        endLoop()
      end
    end)
  end,

  Print=function(qTbl)
    local url,n=BACKEND_URL..'/search?q=',qTbl.name:lower():gsub('%s',''):gsub('%%20','')    -- pieHere, making search with spaces possible
    if('plains island swamp mountain forest'):find(n)then
      --url=url:gsub('prints','art')end
      broadcastToAll('[b][FFAA00]⚠️ Basic Lands Not Printed[/b]\n' ..
                     '[FFFFFF]Please specify which basics you want in your decklist,\n' ..
                     'or spawn them individually:\n' ..
                     '[00CCFF]Example: [b]Scryfall island&set=kld[/b] (for Kaladesh Island)',{0.9,0.9,0.9})
      endLoop()
    else
      if qTbl.oracleid~=nil then
        WebRequest.get(url..qTbl.oracleid,function(wr)spawnList(wr,qTbl)end)
      else
        WebRequest.get(url..qTbl.name,function(wr)spawnList(wr,qTbl)end)
      end
    end
  end,

  Legalities=function(qTbl)
    WebRequest.get(BACKEND_URL..'/card/'..qTbl.name,function(wr)
      if handleWebError(wr, qTbl, 'Legalities lookup failed') then
        return
      end
      local legal=JSON.decode(wr.text:match('"legalities":({[^}]+})'))
      for f,l in pairs(legal)do
        printToAll(l..' in '..f)
      end
      endLoop()
    end)
  end,

  Legal=function(qTbl)
    WebRequest.get(BACKEND_URL..'/card/'..qTbl.name,function(wr)
        if handleWebError(wr, qTbl, 'Legality lookup failed') then
          return
        end
        local n,s,t='','',JSON.decode(wr.text:match('"legalities":({[^}]+})'))
        for f,l in pairs(t)do if l=='legal'and s==''then s='[11ff11]'..f:sub(1,1):upper()..f:sub(2)..' Legal'
          elseif l=='not_legal'and s~=''then if n==''then n='Not Legal in:' end n=n..' '..f end end

        if s==''then s='[ff1111]Banned' else local b=''
          for f,l in pairs(t)do if l=='banned'then b=b..' '..f end end
          if b~=''then s=s..'[-]\n[ff1111]Banned in:'..b end end

        local r=''
        for f,l in pairs(t)do if l=='restricted'then r=r..' '..f end end
        if r~=''then s=s..'[-]\n[ffff11]Restricted in:'..r end
        printToAll('Legalities:'..qTbl.full:match('%s.*')..'\n'..s,{1,1,1})
        endLoop()end)end,

  Text=function(qTbl)
    WebRequest.get(BACKEND_URL..'/card/'..qTbl.name,function(wr)
        if handleWebError(wr, qTbl, 'Text lookup failed') then
          return
        end
        if qTbl.target then qTbl.target.setDescription(wr.text)
        else Player[qTbl.color].broadcast(wr.text)end
        endLoop()end)end,

  Rules=function(qTbl)
    WebRequest.get(BACKEND_URL..'/card/'..qTbl.name,function(wr)
      if handleWebError(wr, qTbl, 'Rules lookup failed') then
        return
      end
      if wr.text:match('^%s*<') or wr.text:match('<!DOCTYPE') then
        Player[qTbl.color].broadcast('Backend returned HTML error.',{1,0,0})
        endLoop()
        return
      end
      local cardDat=JSON.decode(wr.text)
      if cardDat.object=="error" then
        broadcastToAll(cardDat.details,{0.9,0.9,0.9})
        endLoop()
        return
      end

      if cardDat.object=="card" and cardDat.rulings_uri then
        local proxyUrl=BACKEND_URL..'/proxy?uri='..cardDat.rulings_uri:gsub('([^%w%-%.%_%~%:%/%?%#%[%]%@%!%$%&%\'%(%)%*%+%,%;%=])',function(c)
          return string.format('%%%02X',string.byte(c))
        end)

        WebRequest.get(proxyUrl,function(wr)
          if handleWebError(wr, qTbl, 'Rulings lookup failed') then
            return
          end
          if wr.text:match('^%s*<') or wr.text:match('<!DOCTYPE') then
            broadcastToAll('[b][FF6666]❌ Failed to fetch rulings[/b]\n' ..
                           '[AAAAAA]The rulings service might be temporarily unavailable.',{0.9,0.9,0.9})
            endLoop()
            return
          end
          local data,text=JSON.decode(wr.text),'[00cc88]'
          if data.object=='list' then data=data.data end

          if data and data[1] then
            for _,v in pairs(data)do
              text=text..v.published_at..'[-]\n[ff7700]'..v.comment..'[-][00cc88]\n'
            end
          else
            text='No Rulings'
          end

          if text:len()>1000 then
            uNotebook(cardDat.name,text)
            broadcastToAll('[b][FFAA00]📖 Rulings Saved to Notebook[/b]\n' ..
                           '[FFFFFF]Too many rulings to display in chat.\n' ..
                           '[00CCFF]Check the Notebook tab: [b]' .. cardDat.name .. '[/b]',{0.9,0.9,0.9})
          elseif qTbl.target then
            qTbl.target.setDescription(text)
          else
            broadcastToAll(text,{0.9,0.9,0.9})
          end
          endLoop()
        end)
      else
        endLoop()
      end
    end)
  end,

  Mystery=function(qTbl)
    Player[qTbl.color].broadcast('Mystery booster mode has been removed from this importer.',{1,0.6,0.2})
    endLoop()
  end,

  Booster=function(qTbl)
    Player[qTbl.color].broadcast('Booster mode has been removed from this importer.',{1,0.6,0.2})
    endLoop()
  end,

  Random=function(qTbl)
    local url,q1=BACKEND_URL..'/random','?q=is:hires'

    local count = tonumber((qTbl.full or ''):match('%s(%d+)%s*$'))
    if not count then
      count = tonumber((qTbl.name or ''):match('^(%d+)%s*$'))
    end
    if count and count > 100 then
      count = 100
    end

    if qTbl.name:find('q=') then
      local queryRaw = (qTbl.full and qTbl.full:match('%?q=(.+)')) or ''
      if queryRaw ~= '' then
        queryRaw = queryRaw:gsub('%s+%d+%s*$', '')
        queryRaw = queryRaw:gsub('%+', ' ')
        queryRaw = queryRaw:gsub('%%20', ' ')
      end

      if queryRaw == '' then
        queryRaw = 'is:hires'
      end

      local encodedQuery = urlEncode(queryRaw)
      url = BACKEND_URL..'/random?q='..encodedQuery

      uLog(url,qTbl.color..' Importer '..qTbl.full)
      if count then
        qTbl.deck=count
        local startedFast = requestRandomDeckFast(qTbl, queryRaw, count, function()
          for i=1,count do
            Wait.time(function()
              WebRequest.get(url,function(wr)setCard(wr,qTbl)end)
            end,i*Tick)
          end
        end)
        if startedFast then
          return
        end
      else
        WebRequest.get(url,function(wr)setCard(wr,qTbl)end)
      end
      return
    end

    for _,tbl in ipairs({{w='c%3Aw',u='c%3Au',b='c%3Ab',r='c%3Ar',g='c%3Ag',n='c%3Ac'},
      {i='t%3Ainstant',s='t%3Asorcery',e='t%3Aenchantment',c='t%3Acreature',a='t%3Aartifact',l='t%3Aland',p='t%3Aplaneswalker',o='t%3Acontraption'}})do
      local t,q2=0,''
      for k,m in pairs(tbl) do
        if string.match(qTbl.name:lower(),k)then
          if t==1 then q2='('..q2 end
          if t>0 then q2=q2..'or+'end
          t,q2=t+1,q2..m..'+'end end
      if t>1 then q2=q2..')+'end
      q1=q1..q2 end
    local tst,cmc=qTbl.full:match('([=<>]+)(%d+)')
    if tst then q1=q1..'cmc'..tst..cmc end
    if q1~='?q='then url=url..(q1..' '):gsub('%+ ',''):gsub(' ','')end

    uLog(url,qTbl.color..' Importer '..qTbl.full)
    if count then
      qTbl.deck=count
      local encodedQuery = url:match('%?q=(.+)$') or ''
      local queryRaw = urlDecode(encodedQuery)
      local startedFast = requestRandomDeckFast(qTbl, queryRaw, count, function()
        for i=1,count do
          Wait.time(function()
            WebRequest.get(url,function(wr)setCard(wr,qTbl)end)
          end,i*Tick)
        end
      end)
      if startedFast then
        return
      end
    else WebRequest.get(url,function(wr)setCard(wr,qTbl)end)end end,

  Quality=function(qTbl)
    if('small normal large art_crop border_crop'):find(qTbl.name) then
      Quality[qTbl.player]=qTbl.name
    end
    endLoop()
  end,

  Lang=function(qTbl)
    lang=qTbl.name
    if lang and lang~=''then
      p.print('Change the language to '..lang,{0.9,0.9,0.9})return false
    else
      p.print('Please type specific language',{0.9,0.9,0.9})return false
    end endLoop()
  end,

  Deck=function(qTbl)
    Player[qTbl.color].broadcast('Deck import mode has been removed from this importer.',{1,0.6,0.2})
    endLoop()
    return false
  end,

  Rawdeck=function(qTbl)
    Player[qTbl.color].broadcast('Raw deck import mode has been removed from this importer.',{1,0.6,0.2})
    endLoop()
  end,

    },{
  __call=function(t,qTbl)
    if qTbl then
      local pointerRot = Player[qTbl.color].getPointerRotation()
      qTbl.text=newText(qTbl.position,Player[qTbl.color].steam_name..'\n'..qTbl.full,50,pointerRot)
      table.insert(t.request,qTbl)
      log(qTbl,'Importer Request '..qTbl.color)
    end
    --Main Logic
    if t.request[13] and qTbl then
      Player[qTbl.color].broadcast('Clearing Previous requests yours added and being processed.')
      endLoop()
    elseif qTbl and t.request[2]then
      local msg='Queueing request '..#t.request
      if t.request[4]then msg=msg..'. Queue auto clears after the 13th request!'
      elseif t.request[3]then msg=msg..'. Type `Scryfall clear queue` to Force quit the queue!'end
      Player[qTbl.color].broadcast(msg)
    elseif t.request[1]then
      local tbl = t.request[1]
      -- Set start time for timeout detection
      requestStartTime = os.time()
      -- Custom Image Replace
      if tbl.customImage then
        -- NEW: Handle custom image proxy
        if (not tbl.mode) or tbl.name == '' or tbl.name == 'blank card' or tbl.name == 'blank%20card' then
          spawnImageOnlyCard(tbl)
        else
          Card.image = tbl.customImage
          t.Spawn(tbl)
        end
      elseif t[tbl.mode] then
        t[tbl.mode](tbl)
      else
        t.Spawn(tbl)  -- Attempt to Spawn
      end
    elseif qTbl then broadcastToAll('Something went Wrong please contact Amuzet\nImporter did not get a mode. MAIN LOGIC')
  end end})
MODES=''
for k,v in pairs(Importer)do if not('request'):find(k)then
MODES=MODES..' '..k end end
--[[Functions used everywhere else]]
local Usage = [[━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  [b][854FD9]%s [49D54F]%s
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[b][00CCFF]⚡ QUICK START - BASIC COMMANDS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[b][0077ff]Scryfall[/b] [i]CardName[/i]
   → Spawn a single card by name
   → Example: [b]Scryfall Lightning Bolt[/b]


[b][00FF77]🎨 CUSTOM ARTWORK (PROXIES)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[b][0077ff]Scryfall[/b] [i]CardName ImageURL[/i]
   → Spawn card with official text & stats + your custom art
   → Example: [b]Scryfall Island https://i.imgur.com/abc123.jpg[/b]
   → Fetches card data from Scryfall, displays your image
   → Supports: Imgur, Steam CDN


[b][FFAA00]⚙️ UTILITY COMMANDS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[b][0077ff]Scryfall help[/b]
   → Display this help message

[b][0077ff]Scryfall clear queue[/b]
   → Cancel pending requests & reload importer

[b][0077ff]Scryfall clear back[/b]
   → Reset custom card backs to default

[b][0077ff]Scryfall hide[/b]
   → Toggle chat message visibility (admin only)


[b][77FF77]✅ AUTO-RECOVERY SYSTEM
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
The importer automatically detects and recovers from:
  • Hung/frozen requests (30 second timeout)
  • Network failures & API errors
  • Backend connection issues

Stuck requests are automatically cleared and the queue continues.


[b][AAAAAA]━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[i]Modified by Sirin • Custom backend support
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━]]

-- Check for hung requests and auto-recover
function checkRequestTimeout()
  if Importer.request[1] and requestStartTime then
    -- Capture timestamp locally to avoid race condition
    local startTime = requestStartTime
    local currentTime = os.time()
    local elapsed = currentTime - startTime
    
    if elapsed >= REQUEST_TIMEOUT then
      local failedRequest = Importer.request[1]
      local playerColor = failedRequest.color or 'White'
      local requestInfo = failedRequest.full or failedRequest.name or 'Unknown'
      
      log('[Card Importer] Request timeout detected after ' .. elapsed .. 's: ' .. requestInfo)
      broadcastToAll('[b][FF7700]⚠️ Request Timeout[/b]\n' ..
                     '[FFFFFF]Request took too long (>' .. elapsed .. 's):\n' ..
                     '[AAAAAA]' .. requestInfo .. '\n' ..
                     '[77FF77]✓ Automatically moving to next request...', {1, 0.5, 0})
      
      -- Clear the hung request and move to next
      if failedRequest.text and type(failedRequest.text) == 'function' then
        failedRequest.text()  -- Clean up the text indicator
      end
      table.remove(Importer.request, 1)
      requestStartTime = nil
      
      -- Process next request on next frame to reduce spike chaining
      scheduleImporterPump()
    end
  end
end

-- Start the timeout monitor (only one instance)
function startTimeoutMonitor()
  if timeoutMonitorActive then
    return  -- Already running, don't start another chain
  end
  
  timeoutMonitorActive = true
  
  local function monitorLoop()
    if not timeoutMonitorActive then
      return  -- Stop if deactivated
    end
    
    checkRequestTimeout()
    
    -- Schedule next check
    Wait.time(monitorLoop, TIMEOUT_CHECK_INTERVAL)
  end
  
  -- Start the monitoring loop
  Wait.time(monitorLoop, TIMEOUT_CHECK_INTERVAL)
end

-- Stop the timeout monitor
function stopTimeoutMonitor()
  timeoutMonitorActive = false
end

function endLoop()
  if Importer.request[1] then 
    if Importer.request[1].text and type(Importer.request[1].text) == 'function' then
      Importer.request[1].text()
    end
    table.remove(Importer.request,1)
  end 
  requestStartTime=nil 
  scheduleImporterPump()
end
function delay(fN,tbl)local timerParams={function_name=fN,identifier=fN..'Timer'}
  if type(tbl)=='table'then timerParams.parameters=tbl end
  if type(tbl)=='number'then timerParams.delay=tbl*Tick
  else timerParams.delay=1.5 end
  Timer.destroy(timerParams.identifier)
  Timer.create(timerParams)
end
function uLog(a,b)if Test then log(a,b)end end
function uNotebook(t,b,c)local p={index=-1,title=t,body=b or'',color=c or'Grey'}
  for i,v in ipairs(getNotebookTabs())do if v.title==p.title then p.index=i end end
  if p.index<0 then addNotebookTab(p)else editNotebookTab(p)end return p.index end
function uVersion(wr)
  -- Check if WebRequest failed
  if wr.is_error then
    log('[Card Importer] Update check failed - WebRequest error: ' .. tostring(wr.error))
    broadcastToAll('[b][Card Importer][/b] [FF6666]Update check failed.[/b] Check connection or trusted URLs.', {1, 0.4, 0.4})
    ensureRegisterModule()
    return
  end
  
  -- Check if we got valid text response
  if not wr.text or wr.text == '' then
    log('[Card Importer] Update check failed - Empty response from GitHub')
    broadcastToAll('[b][Card Importer][/b] [FF6666]Update check failed.[/b] Empty response from GitHub.', {1, 0.4, 0.4})
    ensureRegisterModule()
    return
  end
  
  -- Try to parse version from response (support single/double quotes and extra spacing)
  local v = wr.text:match("version%s*=%s*['\"]([%d%.]+)['\"]")
  if not v then
    v = wr.text:match("mod_name,%s*version%s*=%s*['\"][^'\"]+['\"],%s*['\"]([%d%.]+)['\"]")
  end
  
  if not v then
    log('[Card Importer] Update check failed - Could not parse version from GitHub response')
    log('Response preview: ' .. wr.text:sub(1, 200))
    broadcastToAll('[b][Card Importer][/b] [FF6666]Update check failed.[/b] Invalid version format.', {1, 0.4, 0.4})
    ensureRegisterModule()
    return
  end
  
  -- Convert both to numbers for comparison
  local function versionToNumber(value)
    if not value then
      return nil
    end
    local parts = {}
    for part in tostring(value):gmatch('%d+') do
      table.insert(parts, tonumber(part))
    end
    if #parts == 0 then
      return nil
    end
    while #parts < 3 do
      table.insert(parts, 0)
    end
    return (parts[1] * 1000000) + (parts[2] * 1000) + parts[3]
  end

  local vNum = versionToNumber(v)
  local versionNum = versionToNumber(version)
  
  if not vNum or not versionNum then
    log('[Card Importer] Update check failed - Invalid version format')
    broadcastToAll('[b][Card Importer][/b] [FF6666]Update check failed.[/b] Invalid version format.', {1, 0.4, 0.4})
    ensureRegisterModule()
    return
  end
  
  log('GitHub Version ' .. v .. ' | Current Version ' .. version)
  
  local statusMsg = '\nLatest Version ' .. self.getName()
  
  if versionNum > vNum or Test then
    Test = true
    statusMsg = '\n[fff600]Experimental Version of Importer Module'
  elseif versionNum < vNum then
    statusMsg = '\n[b][00FF00]🔄 Updating Importer...[/b]'
    statusMsg = statusMsg .. '\n[FFFFFF]New version [b]v' .. v .. '[/b] available (you have [b]v' .. version .. '[/b])'
    statusMsg = statusMsg .. '\n[00CCFF]Downloading from GitHub...'
    broadcastToAll('[b][Card Importer][/b]' .. statusMsg, {0.4, 1, 0.4})
    
    -- Update the script
    self.setLuaScript(wr.text)
    
    Wait.time(function()
      broadcastToAll('[b][Card Importer][/b] [00FF00]✓ Update complete![/b] Reloading...', {0.4, 1, 0.4})
      self.reload()
    end, 1)
    return
  else
    statusMsg = '\n[ffffff]You have the latest version!'
    broadcastToAll('[b][Card Importer][/b] [00FF00]✓ Up to date![/b] Running version [b]' .. version .. '[/b]', {0.4, 1, 0.4})
  end
  
  ensureRegisterModule()
end

-- Manual update check function (callable from button)
function checkForUpdates()
  broadcastToAll('[b][Card Importer][/b] [00CCFF]🔄 Checking for updates from GitHub...', {0.7, 0.7, 1})
  WebRequest.get(GITURL, self, 'uVersion')
end

function ensureRegisterModule()
  if isRegistered then
    return
  end
  if Global.getVar('Encoder') then
    registerModule()
  else
    Wait.condition(registerModule, function() return Global.getVar('Encoder') ~= nil end)
  end
end

--[[Tabletop Callbacks]]
function onSave()self.script_state=JSON.encode(Back)end
function onLoad(data)
  -- Reset registration guard on load
  isRegistered = false
  
  -- Guard against nil objects or missing properties during load
  local objs = getObjects() or {}
  for _, o in pairs(objs) do
    if o and o.getName and o.getVar and o ~= self then
      local name = o.getName() or ''
      if name:find(mod_name) then
        local other = o.getVar('version')
        if other then
          local otherNum = tonumber(other)
          local versionNum = tonumber(version)
          if otherNum and versionNum and versionNum < otherNum then
            self.destruct()
          else
            o.destruct()
          end
        else
          o.destruct()
        end
        break
      end
    end
  end

  -- Auto-update check (can be disabled by setting AUTO_UPDATE_ENABLED = false)
  if AUTO_UPDATE_ENABLED then
    checkForUpdates()
  else
    -- If auto-update is disabled, register immediately
    ensureRegisterModule()
  end

  ensureRegisterModule()
  
  -- Load saved card back settings
  if data ~= '' then
    Back = JSON.decode(data)
  end
  if not Back or type(Back) ~= 'table' then
    Back = {}
  end
  Back.___ = Back.___ or 'https://i.stack.imgur.com/787gj.png'
  Back = TBL.new(Back)
  
  -- Create UI buttons
  self.createButton({
    label = "+",
    click_function = 'registerModule',
    function_owner = self,
    position = {0, 0.2, -0.5},
    height = 100,
    width = 100,
    font_size = 100,
    tooltip = "Adds Oracle Look Up"
  })
  
  self.createButton({
    label = "🔄",
    click_function = 'checkForUpdates',
    function_owner = self,
    position = {0, 0.2, -0.7},
    height = 100,
    width = 100,
    font_size = 80,
    tooltip = "Check for Updates from GitHub"
  })
  
  -- Setup usage text and description
  Usage = Usage:format(mod_name, version)
  uNotebook('SHelp', Usage)
  local u = Usage:gsub('\n\n.*', '\n\n[b][FFFF77]📖 Full help available in Notebook tab: SHelp[/b]')
  u = u .. '\n\n[b][77FF77]✨ Ready to import cards![/b]'
  -- Backend URL and Auto-update status removed from chat display
  self.setDescription(u:gsub('[^\n]*\n', '', 1):gsub('%]  %[', ']\n['))
  -- Less intrusive chat message - full help in notebook (SHelp)
  printToAll('[b][77FF77]' .. self.getName() .. ' [/b] Check [b]Notebook > SHelp[/b]', {0.9, 0.9, 0.9})
  
  -- Registration happens in uVersion() after update check, or above if auto-update is disabled
  startTimeoutMonitor()

  onChat('Scryfall clear back')
end
function onDestroy()
  -- Stop the timeout monitor to prevent orphaned callbacks
  stopTimeoutMonitor()
  
  for _, o in pairs(textItems) do
    if o ~= nil then
      o.destruct()
    end
  end
end

local SMG, SMC = '[b]Scryfall: [/b]', {0.5, 1, 0.8}
local chatToggle = false

local function isLikelyImageUrl(url)
  if not url or url == '' then return false end
  local u = tostring(url):lower()
  local noFragment = u:gsub('#.*$', '')
  local noQuery = noFragment:gsub('%?.*$', '')

  if noQuery:match('%.png$') or noQuery:match('%.jpe?g$') or noQuery:match('%.webp$') or noQuery:match('%.gif$') or noQuery:match('%.bmp$') or noQuery:match('%.avif$') then
    return true
  end

  if u:find('steamusercontent', 1, true) or u:find('steamuserimages', 1, true) or u:find('i.imgur.com', 1, true) then
    return true
  end

  return false
end

function onChat(msg,p)
  if msg:find('!?[Ss]cryfall ')then
    local a=msg:match('!?[Ss]cryfall (.*)')or false
    if a=='hide'and p.admin then
      chatToggle=not chatToggle
      if chatToggle then msg='hiding' else msg='showing'end
      broadcastToAll('[b][FFAA00]👁️ Chat Display Toggle[/b]\n' ..
                     '[FFFFFF]Now [b]' .. msg .. '[/b] importer chat messages.\n' ..
                     '[AAAAAA]Toggle anytime with "[b]Scryfall hide[/b]"',SMC)
    elseif a=='help'then
      p.print('[b][00CCFF]📖 Help Documentation[/b]\n\n' ..
              '[FFFFFF]Full command list available in [b][FFFF77]Notebook > SHelp tab[/b]\n\n' ..
              '[AAAAAA]Quick reference:\n' ..
              '• [b]Scryfall CardName[/b] - Spawn a card\n' ..
              '• [b]Scryfall random[/b] - Random card\n\n' ..
              '[77FF77]Check the SHelp notebook for complete documentation!',{0.9,0.9,0.9})
      return false
    elseif a=='promote me' and p.steam_id==author then
      p.promote()
    elseif a=='clear queue'then
      -- Clear the queue by reloading the object
      printToAll('[b][00CCFF]♻️ Respawning Importer...[/b]',SMC)
      self.reload()
    elseif a=='clear back'then
      self.script_state=string.gsub([[{}]],'\n','')

			-- Card back default (matches backend default); per-player overrides stored in script_state
			Back=TBL.new('https://steamusercontent-a.akamaihd.net/ugc/1647720103762682461/35EF6E87970E2A5D6581E7D96A99F8A575B7A15F/',JSON.decode(self.script_state))

    elseif a then
      -- Parse command: support custom image proxy
      -- Syntax: "scryfall cardname https://custom-image-url"
      local trimmedInput = a:gsub('^%s+',''):gsub('%s+$','')
      local fullUrlInput = trimmedInput:match('^(https?://[^%s]+)$')
      local customImageUrl = nil
      local nameWithoutUrl = trimmedInput

      if fullUrlInput then
        if isLikelyImageUrl(fullUrlInput) then
          customImageUrl = fullUrlInput
        else
          p.print('[FF6666]Deck URL import is no longer supported.[-]\n[AAAAAA]Supported URL use: [b]Scryfall CardName ImageURL[/b]', {0.95,0.55,0.55})
          return false
        end
        nameWithoutUrl = ''
      else
        local trailingUrl = trimmedInput:match('(https?://[^%s]+)$')
        if trailingUrl then
          if isLikelyImageUrl(trailingUrl) then
            customImageUrl = trailingUrl
          else
            p.print('[FF6666]Deck URL import is no longer supported.[-]\n[AAAAAA]Supported URL use: [b]Scryfall CardName ImageURL[/b]', {0.95,0.55,0.55})
            return false
          end
          nameWithoutUrl = trimmedInput:gsub('https?://[^%s]+$',''):gsub('%s+$','')
        else
          local inlineUrl = trimmedInput:match('(https?://[^%s]+)')
          if inlineUrl then
            if isLikelyImageUrl(inlineUrl) then
              customImageUrl = inlineUrl
            else
              p.print('[FF6666]Deck URL import is no longer supported.[-]\n[AAAAAA]Supported URL use: [b]Scryfall CardName ImageURL[/b]', {0.95,0.55,0.55})
              return false
            end
            nameWithoutUrl = trimmedInput:gsub('https?://[^%s]+',''):gsub('%s+$','')
          end
        end
      end
      
      local tbl = {
        position = p.getPointerPosition(),
        player = p.steam_id,
        color = p.color,
        url = nil,
        customImage = customImageUrl,  -- NEW: Store custom image URL separately
        mode = nameWithoutUrl:match('(%S+)'),
        name = nameWithoutUrl,
        full = a
      }
      
      if tbl.color == 'Grey' then
        tbl.position = {0, 2, 0}
      end
      
      if tbl.mode then
        for k, v in pairs(Importer) do
          if tbl.mode:lower() == k:lower() and type(v) == 'function' then
            tbl.mode, tbl.name = k, tbl.name:lower():gsub(k:lower(), '', 1)
            break
          end
        end
      end

      if tbl.name:len() < 1 then
        tbl.name = 'blank card'
      else
        if tbl.name:sub(1, 1) == ' ' then
          tbl.name = tbl.name:sub(2, -1)  -- Remove 1st space
        end
        -- URL encoding for special characters
        charEncoder = {
          [' '] = '%%20',
          ['>'] = '%%3E',
          ['<'] = '%%3C',
          [':'] = '%%3A',
          ['%('] = '%%28',
          ['%)'] = '%%29',
          ['%{'] = '%%7B',
          ['%}'] = '%%7D',
          ['%['] = '%%5B',
          ['%]'] = '%%5D',
          ['%|'] = '%%7C',
          ['%/'] = '%%2F',
          ['\\'] = '%%5C',
          ['%^'] = '%%5E',
          ['%$'] = '%%24',
          ['%?'] = '%%3F',
          ['%!'] = '%%3F'
        }
        for char, replacement in pairs(charEncoder) do
          tbl.name = tbl.name:gsub(char, replacement)
        end
      end
      Importer(tbl)
      if chatToggle then
        uLog(msg, p.steam_name)
        return false
      end
    end
  end
end

-- find paired {} and []
function findClosingBracket(txt,st)   -- find paired {} or []
  local ob,cb='{','}'
  local pattern='[{}]'
  if txt:sub(st,st)=='[' then
    ob,cb='[',']'
    pattern='[%[%]]'
  end
  local txti=st
  local nopen=1
  while nopen>0 do
    txti=string.find(txt,pattern,txti+1)
    if txt:sub(txti,txti)==ob then
      nopen=nopen+1
    elseif txt:sub(txti,txti)==cb then
      nopen=nopen-1
    end
  end
  return txti
end

--[[Card Encoder]]
pID=mod_name
local isRegistered = false  -- Guard to prevent double registration

function registerModule()
  enc=Global.getVar('Encoder')
  if not enc or isRegistered then
    return
  end

  buttons={'Respawn','Oracle','Rulings','Emblem\nAnd Tokens','Printings','Set Sleeve','Reverse Card'}

  local function versionToNumber(value)
    if value == nil then
      return 0
    end
    local parts = {}
    for part in tostring(value):gmatch('%d+') do
      table.insert(parts, tonumber(part))
    end
    if #parts == 0 then
      return 0
    end
    while #parts < 3 do
      table.insert(parts, 0)
    end
    return (parts[1] * 1000000) + (parts[2] * 1000) + parts[3]
  end

  local encVersionNum = versionToNumber(enc.getVar('version'))

  local prop={name=pID,funcOwner=self,activateFunc='toggleMenu'}
  if encVersionNum < versionToNumber('4.4.0') then
    prop.toolID=pID
    prop.display=true
    enc.call('APIregisterTool',prop)
  else
    prop.values={}
    prop.visible=true
    prop.propID=pID
    prop.tags='tool,cardImporter,Amuzet'
    enc.call('APIregisterProperty',prop)
  end

  function eEmblemAndTokens(o,p)ENC(o,p,'Token')end function eOracle(o,p)ENC(o,p,'Text')end function eRulings(o,p)ENC(o,p,'Rules')end function ePrintings(o,p)ENC(o,p,'Print')end function eRespawn(o,p)ENC(o,p,'Spawn')end function eSetSleeve(o,p)ENC(o,p,'Back')end
  function eReverseCard(o,p)ENC(o,p)spawnObjectJSON({json=o.getJSON():gsub('BackURL','FaceURL'):gsub('FaceURL','BackURL',1)})

  isRegistered = true
end

function ENC(o,p,m)
  enc.call('APIrebuildButtons',{obj=o})
  if m then
    if o.getName()=='' and m~='Back' then
      Player[p].broadcast('Card has no name!',{1,0,1})
    else
      local oracleid=nil
      if o.memo~=nil and o.memo~='' then
        oracleid='oracleid:'..o.memo
      end
      Importer({
        position=o.getPosition()+Vector(0,1,0)+o.getTransformRight():scale(-2.4),
        target=o,
        player=Player[p].steam_id,
        color=p,
        oracleid=oracleid,
        name=o.getName():gsub('\n.*','')or'Energy Reserve',
        mode=m,
        full='Card Encoder'
      })
    end
  end
end

function toggleMenu(o)enc=Global.getVar('Encoder')if enc then flip=enc.call("APIgetFlip",{obj=o})for i,v in ipairs(buttons)do Button(o,v,flip)end Button:reset()end end
Button=setmetatable({label='UNDEFINED',click_function='eOracle',function_owner=self,height=400,width=2100,font_size=360,scale={0.4,0.4,0.4},position={0,0.28,-1.35},rotation={0,0,90},reset=function(t)t.label='UNDEFINED';t.position={0,0.28,-1.35}end
  },{__call=function(t,o,l,f)
      local inc,i=0.325,0
      l:gsub('\n',function()t.height,inc,i=t.height+400,inc+0.1625,i+1 end)
      t.label,t.click_function,t.position,t.rotation[3]=l,'e'..l:gsub('%s',''),{0,0.28*f,t.position[3]+inc},90-90*f
      o.createButton(t)
      t.height=400
      if i%2==1 then t.position[3]=t.position[3]+0.1625 end end})
  end      
--EOF
