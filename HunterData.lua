HunterData = LibStub("AceAddon-3.0"):NewAddon("HunterData", "AceConsole-3.0")
local HunterPetData = getHunterDataTable()

-- Helper function for checking key existence in a table
local function tableKeyExists(table, key)
  for k, v in pairs(table) do
    if k == key then return true end
  end
  return false
end

-- Looks up a pet family id by the pet family's textual name.  e.g. Raptor, Spider, etc.
-- @param   petFamilyName  {string}  Pet family name.  See HunterDataTable for possible options.
-- @return                 {string}  Numeric identifer for the pet family returned as a string.
function HunterData:getPetIdByFamilyName(petFamilyName)
    for petId, pet in pairs(HunterPetData.Pets) do
    if pet.name == petFamilyName then
      return petId
    end
  end
end

-- Returns a table of spells known by the provided petFamilyId
-- @param   petFamilyId  {string}     Numeric identifier but passed as a string
-- @return               {table|nil}  A table of spellIds or nil if the pet family was not found
function HunterData:getPetSpellsByPetId(petFamilyId)
  if tableKeyExists(HunterPetData.Pets, petFamilyId) then
    return HunterPetData.Pets[petFamilyId].spells
  else
    return nil
  end
end

-- Returns a single pet spell attribute for one or more spells
-- @param   spellIds  {table}   Single dimensional table of spell identifiers
-- @param   key       {string}  The key to be retrieved from the spell table
-- @return            {table}   Table containing the matching attribute values
function HunterData:getPetSpellAttributeBySpellIds(spellIds, key)
  local attributes = {}
  for k, spellId in pairs(spellIds) do
    if tableKeyExists(HunterPetData.Spells, spellId) then
      table.insert(attributes, HunterPetData.Spells[spellId][key])
    end
  end
  return attributes
end

-- Returns a table representing a Hunter's Call Pet spell slots
-- @return  {table}
function HunterData:getCallPetSpells()
  return {
    [883]   = 1,
    [83242] = 2,
    [83243] = 3,
    [83244] = 4,
    [83245] = 5,
  }
end

-- Return the entire HunterPetData table.  This shouldn't be used often if at all.  More specific 
-- functions should be added to cover specific data retrieval needs.
-- @return  {table}
function HunterData:getHunterPetData()
  return HunterPetData
end