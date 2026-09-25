StringUtils = {}

-- Converts anything to a string
function StringUtils.toString(val)
  if not val then
  	return "nil"
  end

  

  -- Tables
  if type(val) == 'table' then

  	-- Factorio's classes are tables that only have {__self = "userdata"}
  	-- According to https://forums.factorio.com/viewtopic.php?t=33877 you can look up their properties here: https://lua-api.factorio.com/latest/classes.html
  	-- We're not about to write and maintain a gigantic mapping of all the possible members on all possible LuaEntities so that we can generically print them 
  	-- to the log.
  	-- Thankfully, almost all classes have an object_name field, typically inherited from LuaEntity or LuaPlayer
  	if type(val.__self) == 'userdata' then
	    objectName = val.object_name
			ret = "[Factorio." .. objectName

  		if objectName == "LuaItemStack" then
  			ret = ret .. " ("
				if val.valid_for_read then
      		ret = ret .. val.name
      	else
      		ret = ret .. "empty"
      	end

      	ret = ret .. ")"
      end

      ret = ret .. "]"
      return ret
  	end

    -- Uses https://github.com/pkulchenko/serpent
    return serpent.block(val)
  end

  -- For non-tables, use tostring
  return tostring(val)
end

-- Gets the keys of a table as a string
function StringUtils.getKeys(t)
  local strKeys = "[\n"
  for key,_ in pairs(t) do
    strKeys = strKeys .. "\t" .. key .. ",\n"
  end
  strKeys = strKeys .. "]"
  return strKeys
end

return StringUtils