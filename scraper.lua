-- 
-- scraper.lua
-- 
-- Script designed for scraping Wowhead pet data and massaging it into a format usable by addons.
-- 
-- Usage: lua5.3 scraper.lua
-- 

local Inspect = require("inspect")           -- inspect
local Json = require("lunajson")             -- lunajson
local HtmlParser = require("htmlparser")     -- htmlparser
local HttpRequest = require("http.request")  -- http (requires system m4 openssl libssl-dev)
local Socket = require("socket")             -- luasocket
local Lfs = require("lfs")                   -- luafilesystem

local function snakeCase(s)
  -- Remove extraneous spaces, dashes, and underscores from the beginning
  s = string.gsub(s, "^%s%-_*", "")
  -- Remove extraneous spaces, dashes, and underscores from the end
  s = string.gsub(s, "%s%-_*$", "")
  -- Replace any number of separator characters with a single character
  s = string.gsub(s, "%s+", " ")
  s = string.gsub(s, "%-+", "-")
  s = string.gsub(s, "_+", "_")
  -- Lower the entire string
  s = string.lower(s)
  -- Remove any non-alphanumeric characters unless they are space, dash, or underscore
  s = string.gsub(s, "%W", function (s)
    if s == " " or s == "-" or s == "_" then
      return "_"
    else
      return ""
    end
  end)
  return s
end

local function camelCase(s)
  -- Remove extraneous spaces, dashes, and underscores from the beginning
  s = string.gsub(s, "^%s%-_*", "")
  -- Remove extraneous spaces, dashes, and underscores from the end
  s = string.gsub(s, "%s%-_*$", "")
  -- Replace any number of separator characters with a single character
  s = string.gsub(s, "%s+", " ")
  s = string.gsub(s, "%-+", "-")
  s = string.gsub(s, "_+", "_")
  -- Lower the entire string
  s = string.lower(s)
  -- If we found a space followed by a character drop the space and capitalize the character
  s = string.gsub(s, "%s(.)", function (s)
    return string.upper(s)
  end)
  -- If we found a dash followed by a character drop the dash and capitalize the character
  s = string.gsub(s, "%-(.)", function (s)
    return string.upper(s)
  end)
  -- If we found an underscore followed by a character drop the underscore and capitalize the character
  s = string.gsub(s, "_(.)", function (s)
    return string.upper(s)
  end)
  -- Remove any remaining non-alphanumeric characters
  s = string.gsub(s, "%W", "")
  return s
end

-- Trim whitespace from the left
local function ltrim(s)
  return string.gsub(s, "^%s*", "")
end

-- Trim whitespace from the right
local function rtrim(s)
  return string.gsub(s, "%s*$", "")
end

-- Trim whitespace from the left and right
local function trim(s)
  return (rtrim(ltrim(s)))
end

-- Replace the specified element tag with the provided replacement value
local function replaceElements(s, element, replacement)
  return string.gsub(s, "<" .. element .. ".->(.-)</" .. element .. ">", replacement)
end

-- 
local function replaceSelfClosingElements(s, element, replacement)
  return string.gsub(s, "<" .. element .. ".-/%w->", replacement)
end

-- Removes the specified element's start and end tags and returns the content
local function stripElements(s, element)
  return string.gsub(s, "<" .. element .. ".->(.-)</" .. element .. ">", "%1")
end

-- 
local function writeFile(filename, data)
  local file = io.open(filename, "wb")
  if not file then return false end
  local content = file:write(data)
  file:close()
  return true
end

-- 
local function readFile(filename)
  local file = io.open(filename, "rb")
  if not file then return false end
  local data = file:read "*a"
  file:close()
  return data
end

-- 
local function getCacheDirectory()
  return "cache/"
end

-- 
local function uriToFilename(uri)
  return getCacheDirectory() .. snakeCase(uri) .. ".html"
end

-- Check to see if data has already been cached in the file system for this URI
local function dataIsCached(uri)
  if not readFile(uriToFilename(uri)) then 
    return false
  else
    return true
  end
end

-- Attempt to read the cached data
local function readCachedData(uri)
  local data = readFile(uriToFilename(uri))
  if not data then
    error("Unable to read cached data for: " .. uri .. ", from: " .. uriToFilename(uri))
  else
    return data
  end
end

-- Download data from the specified URI
local function downloadData(uri)
  local headers, stream = assert(HttpRequest.new_from_uri(uri):go())
  local body = assert(stream:get_body_as_string())
  if headers:get ":status" ~= "200" then
    error("Unable to download data from: " .. uri .. ", got status: " .. headers:get ":status")
  else
    return body
  end
end

-- Caches data downloaded from the specified URI to the file system
local function cacheData(uri, data)
  local success = writeFile(uriToFilename(uri), data)
  if not success then
    error("Unable to write cached data for: " .. uri .. ", to: " .. uriToFilename(uri))
  end
end

-- Parses down raw HTML from the hunter-pet-abilities page and creates a nice Lua table
local function parseHunterPetAbilities(data)
  -- Wowhead sends all of the pet ability data to their client in JSON so we can just rip that off without having to
  -- resort to any actual HTML string parsing.  Nice!  Look for structures like this in the page source:
  -- _[160011]={"name_enus":"Agile Reflexes","rank_enus":"Special Ability","icon":"inv_misc_foxkit","screenshot":0};
  local pattern = "_%[(%d+)%]=({.-});"
  local table = {}
  for spellId, jsonString in string.gmatch(data, pattern) do
    -- @TODO - Catch errors from the decode
    -- @TODO - Implement filtering functionality 
    -- if spellId == "17253" then table[tonumber(spellId)] = Json.decode(jsonString) end
    table[spellId] = Json.decode(jsonString)
  end
  return table
end

-- Parses the unordered list of flag down into an array
local function parseSpellDetailsFlagsRow(tdContent)
  local flags = {}
  ul = HtmlParser.parse(tdContent)
  for _, all in ipairs(ul:select("li")) do
    -- @TODO - Not really clear why I have to concat this but it prevents Lua from
    --         complaining about bad argument #2 to 'insert' (number expected, got string)
    table.insert(flags, "" .. stripElements(all:getcontent(), "a"))
  end
  return flags
end

-- Spell details row parser for simple data rows:
-- <tr>
--   <th>Cast time</th>
--   <td>Instant</td>
-- </tr>
local function parseGenericSpellDetailsRow(table, tr)
  local th = tr:select("th")[1]
  local thContent
  local td = tr:select("td")[1]
  local tdContent
  if th ~= nil then
    thContent = camelCase(th:getcontent())
  end
  if td ~= nil then
    tdContent = td:getcontent()
  end
  -- If this is not a named header then bail out
  if thContent == "" or thContent == nil then
    return table
  -- Flags
  elseif thContent == "flags" then
    table[thContent] = parseSpellDetailsFlagsRow(tdContent)
  -- Every other type of content
  else
    -- Some elements are still inside anchor tags.  Strip these.
    table[thContent] = stripElements(tdContent, "a")
  end
  return table
end

-- Spell details row parser for "icontab" rows.  Typically found for complex pet abilities
-- such as Spirit Mend or Molten Armor
-- <tr>
--   <th>Effect #1</th>
--   <td colspan="3" style="line-height: 17px">Apply Aura: Proc Trigger Spell      <small> (AP mod: 0.5)</small>
--     <table class="icontab">
--       <tr>
--         <th id="icontab-icon1"></th>
--         <td>
--           <a href="/spell=159786">Molten Hide</a>
--         </td>
--         <th style="display: none"></th>
--         <td style="display: none"></td>
--       </tr>
--     </table>

--     <script type="text/javascript">//        <![CDATA[
-- WH.ge('icontab-icon1').appendChild(g_spells.createIcon(159786, 1, "0"));
-- //]]></script>

--   </td>
-- </tr>
local function parseIconTabSpellDetailsRow(table, tr)
  local th = tr:select("th")[1]
  local thContent
  local td = tr:select("td")[1]
  local tdContent
  local iconTabAnchor = tr:select("td > table.icontab > tr > td > a")[1]
  local iconTabSpellId
  local iconTabSpellName
  -- 
  if th ~= nil then
    thContent = th:getcontent()
  end
  -- 
  if td ~= nil then
    tdContent = replaceElements(td:getcontent(), "table", "")
    tdContent = replaceElements(tdContent, "script", "")
    tdContent = trim(tdContent)
  end
  -- 
  if iconTabAnchor ~= nil then
    iconTabSpellId = iconTabAnchor.attributes["href"]
    iconTabSpellId = string.gsub(iconTabSpellId, "/spell=", "")
    iconTabSpellName = iconTabAnchor:getcontent()
  end
  -- 
  if thContent == "" or thContent == nil then
    return table
  -- Flags
  elseif thContent == "flags" then
    table[thContent] = parseSpellDetailsFlagsRow(tdContent)
  else
    table[camelCase(thContent)] = {
      ["description"] = tdContent,
      ["spellId"] = iconTabSpellId,
      ["spellName"] = iconTabSpellName,
    }
  end
  return table
end

-- Chooses the appropriate row parsing function
local function parseRow(table, tr)
  if tr:select("td > table.icontab > tr > td > a")[1] ~= nil then
    parseIconTabSpellDetailsRow(table, tr)
  else
    parseGenericSpellDetailsRow(table, tr)
  end
  return table
end

-- Parses down raw HTML from the hunter-pet-abilities spell details table and creates a nice Lua table
local function parseSpellDetails(data)
  local spellDetailsPattern = "</h2>%s*(<table.-id=\"spelldetails\">.-)<h2.->Related</h2>"
  local spellDetailsDataTable = string.match(data, spellDetailsPattern)
  local root
  local table = {}
  -- print(spellDetailsDataTable)
  spellDetailsDataTable = stripElements(spellDetailsDataTable, "dfn")
  spellDetailsDataTable = stripElements(spellDetailsDataTable, "small")
  spellDetailsDataTable = stripElements(spellDetailsDataTable, "span")
  -- Trash line breaks early on in the parsing otherwise they break lua-htmlparser selection
  spellDetailsDataTable = replaceSelfClosingElements(spellDetailsDataTable, "br", "\n")
  -- Break down the Spell Details table into something usable.  We start by selecting <th> and walking back up to <tr>
  -- because we are only interested in rows with headers not container rows with no headings.
  -- @TODO - Turn the unordered list of Flags into something more useful
  root = HtmlParser.parse(spellDetailsDataTable)
  for _, tr in ipairs(root:select("tr")) do
    table = parseRow(table, tr)
  end
  return table
end

-- Parse down the page data and extract a list of which pets use which abilities
local function parseSpellUsedByPet(hunterDataPetsTable, data, spellId)
  -- @NOTE - So called "Generic" pet abilities also make it into the list somehow.  We probably want to make parsing smart enough
  --         to ignore abilities that don't have used-by-pet lists in the page content.
  -- if spellId == 2649 or spellId == "2649" then return end -- Growl
  -- if spellId == 65220 or spellId == "65220" then return end -- Avoidance
  -- if spellId == 191336 or spellId == "191336" then return end -- Hunting Companion
  -- if spellId == 88680 or spellId == "88680" then return end -- Kindred Spirits
  -- Wowhead sends all of the pet ability used-by data to their client in JSON so we can just rip that off without having to
  -- resort to any actual HTML string parsing.  Nice!  Look for structures like this in the page source:
  -- new Listview({template: 'pet', id: 'used-by-pet', name: LANG.tab_usedby, tabs: tabsRelated, parent: 'lkljbjkb574', data: [{"armor":5,"damage":5,"diet":17,"expansion":1,"health":5,"icon":"ability_hunter_pet_netherray","id":34,"maxlevel":0,"minlevel":0,"name":"Nether Ray","type":2}, ...
  local pattern = "new%s-Listview%({.-'used%-by%-pet'.-data:%s-(%[{.-}%])}%);"
  local pets = {}
  local jsonString = string.match(data, pattern)
  local spellIdStr = tostring(spellId)
  -- print(jsonString)
  if not jsonString then
    return hunterDataPetsTable
  end
  -- @TODO - Catch errors from the decode
  pets = Json.decode(jsonString)
  for _, pet in ipairs(pets) do
    local petIdStr = tostring(pet.id)
    -- print(Inspect(tonumber(pet.id)))
    -- If we haven't added this pet yet then add it and its details
    if hunterDataPetsTable[petIdStr] == nil then
      -- print("NO ID: " .. pet.id)
      hunterDataPetsTable[petIdStr] = pet
      hunterDataPetsTable[petIdStr]["spells"] = {}
      table.insert(hunterDataPetsTable[petIdStr]["spells"], spellIdStr)
    else
      -- print("FOUND ID: " .. pet.id)
      table.insert(hunterDataPetsTable[petIdStr]["spells"], spellIdStr)
    end
  end
  return hunterDataPetsTable
end

-------------------------------------------------------------------------------
-- Execution Begins
-------------------------------------------------------------------------------

-- @TODO - Rework this so it dynamically follows links and handles paged content
local hunterPetAbilitiesUrls = {
  "http://www.wowhead.com/hunter-pet-abilities/live-only:on",
  "http://www.wowhead.com/hunter-pet-abilities/live-only:on#50+1+17+2"
}
-- local hunterPetAbilitiesUrl = "http://www.wowhead.com/hunter-pet-abilities/live-only:off"
local hunterPetAbilitiesData
local hunterPetAbilitiesTable = {}
local spellUrlPattern = "http://www.wowhead.com/spell="
local spellUrl
local spellData
local hunterDataPetSpellsTable = {}
local hunterDataPetsTable = {}

-- If the cache directory doesn't exist create it now
Lfs.mkdir(getCacheDirectory())

-- Go get the hunter pet abilities from Wowhead
-- io.write("Parsing hunter pet abilities ... ")
for _, hunterPetAbilitiesUrl in pairs(hunterPetAbilitiesUrls) do
  if dataIsCached(hunterPetAbilitiesUrl) then
    hunterPetAbilitiesData = readCachedData(hunterPetAbilitiesUrl)
  else
    hunterPetAbilitiesData = downloadData(hunterPetAbilitiesUrl)
    cacheData(hunterPetAbilitiesUrl, hunterPetAbilitiesData)
  end
end
-- io.write("DONE! \n")
-- print(Inspect(hunterPetAbilitiesData))

-- Parse the hunter pet abilities into a nice table that we can interact with
hunterPetAbilitiesTable = parseHunterPetAbilities(hunterPetAbilitiesData)
-- print(Inspect(hunterPetAbilitiesTable))

-- Iterate over all of the hunter pet abilities to get their details
-- io.write("Parsing hunter pet ability details: ")
for spellId, hunterPetAbility in pairs(hunterPetAbilitiesTable) do
  spellUrl = spellUrlPattern .. spellId
  -- Go get the hunter pet spell details from Wowhead
  if dataIsCached(spellUrl) then
    -- io.write(spellId .. " (C) ... ")
    spellData = readCachedData(spellUrl)
  else
    -- @TODO - Fix the delayed printing here.  It looks like nothing is happening while it's downloading.
    --         Probably some async nonsense.
    -- io.write(spellId .. " (D) ... ")
    -- If we need to download sleep a bit first to avoid raising ire from Wowhead sentinels
    Socket.sleep(1)
    spellData = downloadData(spellUrl)
    cacheData(spellUrl, spellData)
  end
  -- 
  hunterDataPetSpellsTable[spellId] = parseSpellDetails(spellData)
  hunterDataPetSpellsTable[spellId]["icon"] = hunterPetAbility["icon"]
  hunterDataPetSpellsTable[spellId]["name"] = hunterPetAbility["name_enus"]
  hunterDataPetSpellsTable[spellId]["rank"] = hunterPetAbility["rank_enus"]
  hunterDataPetSpellsTable[spellId]["screenshot"] = hunterPetAbility["screenshot"]
  -- 
  hunterDataPetsTable = parseSpellUsedByPet(hunterDataPetsTable, spellData, spellId)
end
-- io.write("DONE! \n")

-- Now we combine what we have learned into a useful data structure
local HunterData = {
  Pets = hunterDataPetsTable,
  Spells = hunterDataPetSpellsTable
}

-- Abuse Inspect to write-out a valid Lua table as a string
writeFile("HunterDataTable.lua", string.gsub(Inspect(HunterData), "^{", "function getHunterDataTable() return {"))
-- @TODO - Automatically add the end block
