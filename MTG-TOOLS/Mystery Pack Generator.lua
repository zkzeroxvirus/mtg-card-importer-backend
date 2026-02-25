function onLoad()
  --customize card-back image
  backURL='https://steamusercontent-a.akamaihd.net/ugc/1647720103762682461/35EF6E87970E2A5D6581E7D96A99F8A575B7A15F/'

  -- Backend URL - change this to your deployed backend URL
  backendURL='http://api.mtginfo.org'

  setCode='Mystery'
  -- setCode='KLM'
  -- setCode='STX'
  -- setCode='ZNR'

  cardStackName=setCode.." Booster"
  cardStackDescription=""

  -------------- don't change these
  nBooster=0
  boosterDats={}
end

function onDestroy()
  nBooster = 0
  boosterDats = {}
end

local BOOSTER_BUILD_TIMEOUT = 25
local BOOSTER_REST_TIMEOUT = 8

--------------------------------------------------------------------------------
---- Booster Set Lookup Function
---- should be correct for all sets?
---- if not add special cases e.g. using the set:lower()=='mystery' example
--------------------------------------------------------------------------------
local function apiSet(set)
  return backendURL..'/random?q=is:booster+s:'..set..'++-is:alchemy+'
end
function rarity(m,r,u)
  if math.random(1,m or 36)==1 then return'r:mythic'
  elseif math.random(1,r or 8)==1 then return'r:rare'
  elseif math.random(1,u or 4)==1 then return'r:uncommon'
  else return'r:common'end end
function typeCo(p,t)local n=math.random(#p-1,#p)for i=13,#p do if n==i then p[i]=p[i]..'+'..t else p[i]=p[i]..'+-('..t..')'end end return p end

local Booster=setmetatable({
  dom=function(p)return typeCo(p,'t:legendary')end,
  war=function(p)return typeCo(p,'t:planeswalker')end,
  znr=function(p)return typeCo(p,'t:land+(is:spell+or+pathway)')end,
  tsp='tsb',mb1='fmb1',mh2='h1r',bfz='exp',ogw='exp',kld='mps',aer='mps',akh='mp2',hou='mp2',stx='sta'
},{__call=function(t,set,n)
  local pack,u={},apiSet(set)
  u=u:gsub('%+s:%(','+(')
  if not n and t[set]and type(t[set])=='function'then
    return t[set](t(set,true))
  else
    for c in('wubrg'):gmatch('.')do table.insert(pack,u..'r:common+c>='..c)end
    for i=1,6 do table.insert(pack,u..'r:common+-t:basic')end
    --masterpiece math
    if not n and((t[set]and math.random(1,144)==1)or('tsp mb1 mh2'):find(set))then
      pack[#pack]=backendURL..'/random?q=is:booster+s:'..t[set]end
    for i=1,3 do table.insert(pack,u..'r:uncommon')end
    table.insert(pack,u..rarity(8,1))
    return pack
  end
end})

--ReplacementSlot
function rSlot(p,s,a,b)for i,v in pairs(p)do if i~=6 then p[i]=v..a else p[i]=backendURL..'/random?q=is:booster+s:'..s..'+'..rarity()..b end end return p end

--Weird Boosters
Booster['mystery']=function()
  urlTable={}
  -- MYSTERY BOOSTER (set mb1)
  urlPrefix=backendURL..'/random?q=set:mb1+'
  -- slot 1-10: each Convention pack has 2 commons/uncommons of each color
  for _,c in pairs({'w','u','b','r','g'}) do
    table.insert(urlTable,urlPrefix..'r<rare+c='..c)
    table.insert(urlTable,urlPrefix..'r<rare+c='..c)
  end
  -- slot 11: 1 multicolored common/uncommon
  table.insert(urlTable,urlPrefix..'c:m+r<rare')
  -- slot 12: 1 common/uncommon artifact/land
  table.insert(urlTable,urlPrefix..'c:c+r<rare')
  -- slot 13: 1 rare/mythic rare with the M15 card frame
  table.insert(urlTable,urlPrefix..'r>=rare+frame:2015')
  -- slot 14: one pre-M15 card in its original frame
  table.insert(urlTable,urlPrefix..'r>=rare+-frame:2015')
  -- slot 15: a pretend "playtest card" in the special slot that seems more like part of an Un-set
  table.insert(urlTable,backendURL..'/random?q=set:cmb1')
  return urlTable
end

Booster['stx']=function()
  local pack,u={},apiSet('stx')
  -- 1 mystical archive card  (Uncommon, Rare, or Mythic Rare, 50% chance japanese)
  if math.random(2)==1 then table.insert(pack,backendURL..'/random?q=set:sta+r>common+lang:en')
  else table.insert(pack,backendURL..'/random?q=set:sta+r>common+lang:ja') end
  table.insert(pack,u..'t:lesson+-r:u')             -- 1 lesson card (Common, Rare, or Mythic Rare)
  table.insert(pack,u..rarity(8,1))                 -- 1 rare (7/8 chance) or mythic rare (1/8 chance)
  for i=1,3 do table.insert(pack,u..'r:u') end      -- 3 uncommons
  for _,c in pairs({'w','u','b','r','g'}) do table.insert(pack,u..'r:c+c:'..c) end              -- 8 commons
  for i=1,3 do table.insert(pack,u..'r:c+-t:basic') end
  if math.random(3)==1 then table.insert(pack,u) else table.insert(pack,u..'r:c+-t:basic') end  -- 33% chance foil of any rarity (66% chance another common)
  return pack
end

Booster['2xm']=function(p)p[11]=p[#p]for i=9,10 do p[i]=backendURL..'/random?q=is:booster+s:2xm'..'+'..rarity()end return p end
for s in('isd dka soi emn'):gmatch('%S+')do
  Booster[s]=function(p)return rSlot(p,s,'+-is:transform','+is:transform')end end
for s in('mid'):gmatch('%S+')do--Crimson Moon
  Booster[s]=function(p)local n=math.random(#p-1,#p)for i,v in pairs(p)do if i==6 or i==n then p[i]=p[i]..'+is:transform'else p[i]=p[i]..'+-is:transform'end end return p end end
for s in('cns cn2'):gmatch('%S+')do
  Booster[s]=function(p)return rSlot(p,s,'+-wm:conspiracy','+wm:conspiracy')end end
for s in('rav gpt dis rtr gtc dgm grn rna'):gmatch('%S+')do
  Booster[s]=function(p)return rSlot(p,s,'+-t:land','+t:land+-t:basic')end end
for s in('ice all csp mh1 khm'):gmatch('%S+')do
  Booster[s]=function(p)p[6]=backendURL..'/random?q=is:booster+s:'..s..'+t:basic+t:snow'return p end end

--Custom Booster Packs
Booster.standard=function(qTbl)
  local pack,u={},backendURL..'/random?q=f:standard+'
  for c in ('wubrg'):gmatch('.')do
    table.insert(pack,u..'r:common+c:'..c)end
  for i=1,5 do table.insert(pack,u..'r:common+-t:basic')end
  for i=1,3 do table.insert(pack,u..'r:uncommon')end
  table.insert(pack,u..rarity(8,1))
  table.insert(pack,u..'t:basic')
  table.insert(pack,backendURL..'/random?q=(set:tafr+or+set:tstx+or+set:tkhm+or+set:tznr+or+set:sznr+or+set:tm21+or+set:tiko+or+set:tthb+or+set:teld)')
  for i=#pack-1,#pack do
    if math.random(1,2)==1 then
      pack[i]=u..'(border:borderless+or+frame:showcase+or+frame:extendedart+or+set:plist+or+set:sta)'
    end end
  return pack end
Booster.conspiracy=function(qTbl)--wubrgCCCCCTUUURT
  local p=Booster('(s:cns+or+s:cn2)')
  local z=p[#p]:gsub('r:%S+',rarity(9,6,3))
  table.insert(p,z)
  p[6]=p[math.random(11,12)]
  for i,s in pairs(p)do
    if i==6 or i==#p then
      p[i]=p[i]..'+wm:conspiracy'
    else p[i]=p[i]..'+-wm:conspiracy'end end
  return p end
Booster.innistrad=function(qTbl)--wubrgDCCCCUUUDRD
  local p=Booster('(s:isd+or+s:dka+or+s:avr+or+s:soi+or+s:emn+or+s:mid)')
  local z=p[#p]:gsub('r:%S+',rarity(8,1))
  table.insert(p,z)
  p[11]=p[12]
  for i,s in pairs(p)do
    if i==6 or i==#p or i==#p-2 then
      p[i]=p[i]..'+is:transform'
    else p[i]=p[i]..'+-is:transform'end end
  return p end
Booster.ravnica=function(qTbl)--wubrgLmmmCCUUURL
  local l,p='t:land+-t:basic',Booster('(s:rav+or+s:gpt+or+s:dis+or+s:rtr+or+s:gtc+or+s:dgm+or+s:grn+or+s:rna)')
  table.insert(p,p[#p])
  for i=7,9 do p[i]=p[6]..'+id>=2'end
  for i,s in pairs(p)do
    if i==6 or i==#p then
      p[i]=p[i]:gsub('r:%S+',rarity(9,6,3))..'+'..l
    else p[i]=p[i]..'+-'..l end end
  return p end

function getScryfallQueryTable()
  urlTable=Booster(setCode:lower())
  return urlTable
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- when a booster is taken out from the box, start scryfall query and replace booster contents
function onObjectLeaveContainer(container, leave_object)
  if container ~= self then return end

  leave_object.setName(cardStackName)

  nBooster=nBooster+1
  local boosterN=nBooster

  urlTable=getScryfallQueryTable()
  getDeckDat(urlTable,boosterN)

  leave_object.createButton({
    click_function='null',
    function_owner=self,
    label='generating\ncards',
    position={0,0.5,0},
    rotation={0,90,0},
    scale={0.5,0.5,0.5},
    width=0,
    height=0,
    font_size=1000,
    color={0,0,0,0},
    font_color={1,1,1,100},
  })

  local buildDone = false
  local replaced = false

  Wait.condition(function()
    if replaced then return end
    buildDone = true
    leave_object.clearButtons()

    local restDone = false
    Wait.condition(function()
      if restDone or replaced then return end
      restDone = true
      replaced = true
      bDat = leave_object.getData()
      bDat.ContainedObjects={boosterDats[boosterN]}
      leave_object.destruct()
      spawnObjectData({data=bDat})
      boosterDats[boosterN] = nil
    end,
    function()
      return leave_object.resting
    end)

    Wait.time(function()
      if restDone or replaced then return end
      restDone = true
      replaced = true
      bDat = leave_object.getData()
      bDat.ContainedObjects={boosterDats[boosterN]}
      leave_object.destruct()
      spawnObjectData({data=bDat})
      boosterDats[boosterN] = nil
    end, BOOSTER_REST_TIMEOUT)
  end,function()
    return boosterDats[boosterN]~=nil
  end)

  Wait.time(function()
    if buildDone or replaced then return end
    buildDone = true
    leave_object.clearButtons()
    printToAll('Mystery Pack: build timed out, please try again.', {1, 0.5, 0.2})
  end, BOOSTER_BUILD_TIMEOUT)
end


-- takes in a table of scryfall query url's
-- queries scryfall for the data
-- generates TTS deckData object with the cards (saved to boosterDats[boosterN])
local function decodeQueryValue(value)
  if not value then return '' end
  local decoded = value:gsub('%+', ' ')
  decoded = decoded:gsub('%%(%x%x)', function(hex)
    return string.char(tonumber(hex, 16))
  end)
  return decoded
end

local function extractQueryFromRandomUrl(url)
  local rawQuery = url and url:match('/random%?q=(.*)')
  if not rawQuery or rawQuery == '' then
    return nil
  end
  return decodeQueryValue(rawQuery)
end

local function firstDeckFromNDJSON(respText)
  if not respText or respText == '' then
    return nil
  end

  for line in respText:gmatch('[^\r\n]+') do
    if line and line:match('%S') then
      local parsed = JSONdecode(line)
      if type(parsed) == 'table' and parsed.Name == 'DeckCustom' then
        return parsed
      end
    end
  end

  return nil
end

local function getDeckEntryForCardId(deckObject, cardId)
  if not deckObject or not deckObject.CustomDeck or not cardId then
    return nil
  end

  local deckNum = math.floor(tonumber(cardId) / 100)
  if not deckNum or deckNum <= 0 then
    return nil
  end

  return deckObject.CustomDeck[tostring(deckNum)] or deckObject.CustomDeck[deckNum]
end

local function remapDeckCardIds(cardDat, deckObject, n)
  if not cardDat then return nil end

  local primaryDeckEntry = getDeckEntryForCardId(deckObject, cardDat.CardID)
  if not primaryDeckEntry and cardDat.CustomDeck then
    for _, deckEntry in pairs(cardDat.CustomDeck) do
      primaryDeckEntry = deckEntry
      break
    end
  end

  if not primaryDeckEntry then
    return nil
  end

  cardDat.CardID = n * 100
  cardDat.CustomDeck = {
    [n] = primaryDeckEntry
  }

  if cardDat.States and cardDat.States[2] then
    local backState = cardDat.States[2]
    local stateDeckEntry = getDeckEntryForCardId(deckObject, backState.CardID)
    if not stateDeckEntry and backState.CustomDeck then
      for _, deckEntry in pairs(backState.CustomDeck) do
        stateDeckEntry = deckEntry
        break
      end
    end

    local stateDeckId = n + 100
    backState.CardID = stateDeckId * 100
    if stateDeckEntry then
      backState.CustomDeck = {
        [stateDeckId] = stateDeckEntry
      }
    else
      backState.CustomDeck = nil
    end
  end

  return cardDat
end

local function cardDatFromBuildResponse(respText, n)
  local deckObject = firstDeckFromNDJSON(respText)
  if not deckObject or not deckObject.ContainedObjects or not deckObject.ContainedObjects[1] then
    return nil
  end

  return remapDeckCardIds(deckObject.ContainedObjects[1], deckObject, n)
end

function getDeckDat(urlTable,boosterN)

  local deckDat={
    Transform={posX=0,posY=0,posZ=0,rotX=0,rotY=180,rotZ=180,scaleX=1,scaleY=1,scaleZ=1},
    Name="Deck",
    Nickname=cardStackName,
    Description=cardStackDescription,
    DeckIDs={},
    CustomDeck={},
    ContainedObjects={},
  }

  local nLoading=0
  local nLoaded=0

  for n,url in ipairs(urlTable) do
    nLoading=nLoading+1

    local function assignCardDat(cardDat)
      if cardDat then
        deckDat.ContainedObjects[n]=cardDat
        deckDat.DeckIDs[n]=cardDat.CardID      -- add card info into deckDat
        deckDat.CustomDeck[n]=cardDat.CustomDeck[n]
      else
        printToAll('Mystery Pack: failed to fetch slot '..tostring(n), {1, 0.5, 0.2})
      end
      nLoaded=nLoaded+1
    end

    local randomQuery = extractQueryFromRandomUrl(url)
    if randomQuery then
      local payload = JSON.encode({
        q = randomQuery,
        count = 1,
        enforceCommander = false,
        back = backURL
      })

      WebRequest.custom(
        backendURL..'/random/build',
        'POST',
        true,
        payload,
        {
          Accept = 'application/x-ndjson',
          ['Content-Type'] = 'application/json'
        },
        function(wr)
        if wr.is_error or (wr.response_code and wr.response_code >= 400) then
          assignCardDat(nil)
          return
        end

        local cardDat = cardDatFromBuildResponse(wr.text, n)
        if cardDat then
          assignCardDat(cardDat)
        else
          assignCardDat(nil)
        end
        end
      )
    else
      assignCardDat(nil)
    end

  end

  local finalized = false
  local function finalizeDeckDat()
    if finalized then return end
    finalized = true

    -- check for doubles
    local doubles=false
    local namesSeen={}
    for _,card in pairs(deckDat.ContainedObjects) do
      local cardName = card and card.Nickname
      if cardName then
        if namesSeen[cardName] then
          doubles=true
          break
        end
        namesSeen[cardName]=true
      end
    end

    if doubles then   -- just redo the search
      getDeckDat(urlTable,boosterN)
    else              -- update the boosterDats
      boosterDats[boosterN]=deckDat
    end
  end

  Wait.condition(function()   -- once all the queries come back from scryfall
    finalizeDeckDat()
  end,
  function() return nLoading==nLoaded end)

  Wait.time(function()
    if finalized then return end
    printToAll('Mystery Pack: card fetch timeout, using partial results.', {1, 0.6, 0.2})
    finalizeDeckDat()
  end, BOOSTER_BUILD_TIMEOUT)

end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function getCardDatFromJSON(json,n)

  local c=JSONdecode(json)

  c.face=''
  c.oracle=''
  local qual='large'

  local imagesuffix=''
  if c.image_status~='highres_scan' then      -- cache buster for low quality images
    imagesuffix='?'..tostring(os.date("%x")):gsub('/', '')
  end

  --Check for card's spoiler image quality
  --Oracle text Handling for Split then DFC then Normal
  if c.card_faces and c.image_uris then
    for i,f in ipairs(c.card_faces) do
      if c.cmc then
        f.name=f.name:gsub('"','')..'\n'..f.type_line..' '..c.cmc..'CMC'
      else
        f.name=f.name:gsub('"','')..'\n'..f.type_line..' '..f.cmc..'CMC'
      end
      if i==1 then cardName=f.name end
      c.oracle=c.oracle..f.name..'\n'..setOracle(f)..(i==#c.card_faces and''or'\n')
    end
  elseif c.card_faces then
    local f=c.card_faces[1]
    if c.cmc then
      cardName=f.name:gsub('"','')..'\n'..f.type_line..' '..c.cmc..'CMC DFC'
    else
      cardName=f.name:gsub('"','')..'\n'..f.type_line..' '..f.cmc..'CMC DFC'
    end
    c.oracle=setOracle(f)
  else
    cardName=c.name:gsub('"','')..'\n'..c.type_line..' '..c.cmc..'CMC'
    c.oracle=setOracle(c)
  end
  local backDat=nil
  --Image Handling
  if c.card_faces and not c.image_uris then --DFC REWORKED for STATES!
    local faceAddress=c.card_faces[1].image_uris.normal:gsub('%?.*',''):gsub('normal',qual)..imagesuffix
    local backAddress=c.card_faces[2].image_uris.normal:gsub('%?.*',''):gsub('normal',qual)..imagesuffix
    if faceAddress:find('/back/') and backAddress:find('/front/') then
      local temp=faceAddress;faceAddress=backAddress;backAddress=temp
    end
    c.face=faceAddress
    local f=c.card_faces[2]
    local name
    if c.cmc then
      name=f.name:gsub('"','')..'\n'..f.type_line..' '..c.cmc..'CMC DFC'
    else
      name=f.name:gsub('"','')..'\n'..f.type_line..' '..f.cmc..'CMC DFC'
    end
    local oracle=setOracle(f)
    local b=n+100
    backDat={
      Transform={posX=0,posY=0,posZ=0,rotX=0,rotY=0,rotZ=0,scaleX=1,scaleY=1,scaleZ=1},
      Name="Card",
      Nickname=name,
      Description=oracle,
      Memo=c.oracle_id,
      CardID=b*100,
      CustomDeck={[b]={FaceURL=backAddress,BackURL=backURL,NumWidth=1,NumHeight=1,Type=0,BackIsHidden=true,UniqueBack=false}},
    }
  elseif c.image_uris then
    c.face=c.image_uris.normal:gsub('%?.*',''):gsub('normal',qual)..imagesuffix
    if cardName:lower():match('geralf') then
      c.face=c.image_uris.normal:gsub('%?.*',''):gsub('normal','png'):gsub('jpg','png')..imagesuffix
    end
  end

  local cardDat={
    Transform={posX=0,posY=0,posZ=0,rotX=0,rotY=0,rotZ=0,scaleX=1,scaleY=1,scaleZ=1},
    Name="Card",
    Nickname=cardName,
    Description=c.oracle,
    Memo=c.oracle_id,
    CardID=n*100,
    CustomDeck={[n]={FaceURL=c.face,BackURL=backURL,NumWidth=1,NumHeight=1,Type=0,BackIsHidden=true,UniqueBack=false}},
  }

  if backDat then
    cardDat.States={[2]=backDat}
  end
  return cardDat
end


function setOracle(c)local n='\n[b]'
  if c.power then
    n=n..c.power..'/'..c.toughness
  elseif c.loyalty then
    n=n..tostring(c.loyalty)
  else
    n=false
  end
  return c.oracle_text..(n and n..'[/b]'or'')
end

--------------------------------------------------------------------------------
-- pie's manual "JSONdecode" for scryfall's "object":"card"
--------------------------------------------------------------------------------

normal_card_keys={
  'object',
  'id',
  'oracle_id',
  'name',
  'lang',
  'layout',
  'image_status',
  'image_uris',
  'mana_cost',
  'cmc',
  'type_line',
  'oracle_text',
  'loyalty',
  'power',
  'toughness',
  'loyalty',
  'legalities',
  'set',
  'rulings_uri',
  'prints_search_uri',
  'collector_number'
}

image_uris_keys={    -- "image_uris":{
  'small',
  'normal',
  'large',
  'png',
  'art_crop',
  'border_crop',
}

legalities_keys={    -- "legalities":{
  'standard',
  'future',
  'historic',
  'gladiator',
  'pioneer',
  'modern',
  'legacy',
  'pauper',
  'vintage',
  'penny',
  'commander',
  'brawl',
  'duel',
  'oldschool',
  'premodern',
}

related_card_keys={     -- "all_parts":[{"object":"related_card",
  'id',
  'component',
  'name',
  'type_line',
  'uri',
}

card_face_keys={        -- "card_faces":[{"object":"card_face",
  'name',
  'mana_cost',
  'cmc',
  'type_line',
  'oracle_text',
  'power',
  'toughness',
  'loyalty',
  'image_uris',
}

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
function JSONdecode(txt)
  local txtBeginning = txt:sub(1,16)
  local jsonType = txtBeginning:match('{"object":"(%w+)"')

  -- not scryfall? use normal JSON.decode
  if not(jsonType=='card' or jsonType=='list') then
    return JSON.decode(txt)
  end

  ------------------------------------------------------------------------------
  -- parse list: extract each card, and parse it separately
  -- used when one wants to decode a whole list
  if jsonType=='list' then
    local txtBeginning = txt:sub(1,80)
    local nCards=txtBeginning:match('"total_cards":(%d+)')
    if nCards==nil then
      return JSON.decode(txt)
    end
    local cardStart=0
    local cardEnd=0
    local cardDats = {}
    for i=1,nCards do     -- could insert max number cards to parse here
      cardStart=string.find(txt,'{"object":"card"',cardEnd+1)
      cardEnd = findClosingBracket(txt,cardStart)
      local cardDat = JSONdecode(txt:sub(cardStart,cardEnd))
      table.insert(cardDats,cardDat)
    end
    local dat = {object="list",total_cards=nCards,data=cardDats}    --ignoring has_more...
    return dat
  end

  ------------------------------------------------------------------------------
  -- parse card

  txt=txt:gsub('}',',}')    -- comma helps parsing last element in an array

  local cardDat={}
  local all_parts_i=string.find(txt,'"all_parts":')
  local card_faces_i=string.find(txt,'"card_faces":')

  -- if all_parts exist
  if all_parts_i~=nil then
    local st=string.find(txt,'%[',all_parts_i)
    local en=findClosingBracket(txt,st)
    local all_parts_txt = txt:sub(all_parts_i,en)
    local all_parts={}
    -- remove all_parts snip from the main text
    txt=txt:sub(1,all_parts_i-1)..txt:sub(en+2,-1)
    -- parse all_parts_txt for each related_card
    st=1
    local cardN=0
    while st~=nil do
      st=string.find(all_parts_txt,'{"object":"related_card"',st)
      if st~=nil then
        cardN=cardN+1
        en=findClosingBracket(all_parts_txt,st)
        local related_card_txt=all_parts_txt:sub(st,en)
        st=en
        local s,e=1,1
        local related_card={}
        for i,key in ipairs(related_card_keys) do
          val,s=getKeyValue(related_card_txt,key,s)
          related_card[key]=val
        end
        table.insert(all_parts,related_card)
        if cardN>100 then break end   -- avoid inf loop if something goes strange
      end
      cardDat.all_parts=all_parts
    end
  end

  -- if card_faces exist
  if card_faces_i~=nil then
    local st=string.find(txt,'%[',card_faces_i)
    local en=findClosingBracket(txt,st)
    local card_faces_txt = txt:sub(card_faces_i,en)
    local card_faces={}
    -- remove card_faces snip from the main text
    txt=txt:sub(1,card_faces_i-1)..txt:sub(en+2,-1)

    -- parse card_faces_txt for each card_face
    st=1
    local cardN=0
    while st~=nil do
      st=string.find(card_faces_txt,'{"object":"card_face"',st)
      if st~=nil then
        cardN=cardN+1
        en=findClosingBracket(card_faces_txt,st)
        local card_face_txt=card_faces_txt:sub(st,en)
        st=en
        local s,e=1,1
        local card_face={}
        for i,key in ipairs(card_face_keys) do
          val,s=getKeyValue(card_face_txt,key,s)
          card_face[key]=val
        end
        table.insert(card_faces,card_face)
        if cardN>4 then break end   -- avoid inf loop if something goes strange
      end
      cardDat.card_faces=card_faces
    end
  end

  -- normal card (or what's left of it after removing card_faces and all_parts)
  st=1
  for i,key in ipairs(normal_card_keys) do
    val,st=getKeyValue(txt,key,st)
    cardDat[key]=val
  end

  return cardDat
end

--------------------------------------------------------------------------------
-- returns data for one card at a time from a scryfall's "object":"list"
function getNextCardDatFromList(txt,startHere)

  if startHere==nil then
    startHere=1
  end

  local cardStart=string.find(txt,'{"object":"card"',startHere)
  if cardStart==nil then
    -- print('error: no more cards in list')
    startHere=nil
    return nil,nil,nil
  end

  local cardEnd = findClosingBracket(txt,cardStart)
  if cardEnd==nil then
    -- print('error: no more cards in list')
    startHere=nil
    return nil,nil,nil
  end

  -- startHere is not a local variable, so it's possible to just do:
  -- getNextCardFromList(txt) and it will keep giving the next card or nil if there's no more
  startHere=cardEnd+1

  local cardDat = JSONdecode(txt:sub(cardStart,cardEnd))

  return cardDat,cardStart,cardEnd
end

--------------------------------------------------------------------------------
function findClosingBracket(txt,st)   -- find paired {} or []
  if st==nil then return nil end
  local ob,cb='{','}'
  local pattern='[{}]'
  if txt:sub(st,st)=='[' then
    ob,cb='[',']'
    pattern='[%[%]]'
  end
  local txti=st
  local nopen=1
  while nopen>0 do
    if txti==nil then return nil end
    txti=string.find(txt,pattern,txti+1)
    if txt:sub(txti,txti)==ob then
      nopen=nopen+1
    elseif txt:sub(txti,txti)==cb then
      nopen=nopen-1
    end
  end
  return txti
end

--------------------------------------------------------------------------------
function getKeyValue(txt,key,st)
  local str='"'..key..'":'
  local st=string.find(txt,str,st)
  local en=nil
  local value=nil
  if st~=nil then
    if key=='image_uris' then     -- special case for scryfall's image_uris table
      value={}
      local s=st
      for i,k in ipairs(image_uris_keys) do
        local val,s=getKeyValue(txt,k,s)
        value[k]=val
      end
      en=s
    elseif txt:sub(st+#str,st+#str)~='"' then      -- not a string
      en=string.find(txt,',"',st+#str+1)
      value=tonumber(txt:sub(st+#str,en-1))
    else                                           -- a string
      en=string.find(txt,'",',st+#str+1)
      value=txt:sub(st+#str+1,en-1):gsub('\\"','"'):gsub('\\n','\n'):gsub("\\u(%x%x%x%x)",function (x) return string.char(tonumber(x,16)) end)
    end
  end
  if type(value)=='string' then
    value=value:gsub(',}','}')    -- get rid of the previously inserted comma
  end
  return value,en
end
