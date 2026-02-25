--This Rounds Stuff
function round(num, dec)
    local mult = 10^(dec or 0)
    return math.floor(num * mult + 0.5) / mult
end

--This Spawns a Token
function onCollisionEnter(co) -- On collision
    obj = co.collision_object -- The collided object
    if obj.type=="Card" then -- Is it a Card
      world = obj.getPosition() -- Where is the Card
      llocal = self.positionToLocal(world) -- Where is the Card in regards of the Spawner
      xx = llocal.x -- What's the x position of the Card in regards of the Spawner
      test = round(xx,2) -- Round the x position to 2 decimal places
      if test == 1.89 then -- Does x = 1.89
        llocal.x = test * -1 -- Flip the x position in regards of the Spawner
        lworld = self.positionToWorld(llocal) -- Where is this new position on the spawner in regards of the world
        obj.setPosition(lworld) -- Place the card there
        bworld = self.positionToWorld({0,1.5,0}) -- Find out where the middle of the spawner is to the world
        brot = obj.getRotation() -- Find out the Card's setRotation
        url = obj.getCustomObject().face -- Find out the Card's face URL
        cardName = obj.getName() -- Get the Card's name
        cleanName = getCardNameOnly(cardName) -- Strip type/CMC from multiline names
        spawnToken(cleanName) -- Spawns Token
          test = 0 -- Reset test var
        else
          test = 0 -- Reset test var
        end
    end
end

-- Extracts only the first line from a card name
function getCardNameOnly(nameText)
  if nameText == nil then
    return ""
  end
  local firstLine = nameText:match("^([^\r\n]+)")
  if firstLine == nil then
    return nameText
  end
  return firstLine
end

-- These are the Token's Parameters
function spawnToken(cardName)
  spawnParams = spawnObject({
    type = "Custom_Model",
    position = bworld,
    rotation = brot
  })
  spawnParams.setCustomObject({
    mesh = "https://steamusercontent-a.akamaihd.net/ugc/1327949700692125593/FFAF751A7D6392C0A1C2A94727C7DA513B5F5960/",
    diffuse = url,
    collider = "https://steamusercontent-a.akamaihd.net/ugc/1327949700692125593/FFAF751A7D6392C0A1C2A94727C7DA513B5F5960/",
    type = 7,
    material = 1,
    specular_intensity = 0,
    specular_color = {224, 208, 191},
    specular_sharpness = 2,
    freshnel_strength = 0
  })
  spawnParams.setScale({0.70, 0.70, 0.70})
  spawnParams.setName("[b]Capture Ticket:[/b]  " .. cardName)
end