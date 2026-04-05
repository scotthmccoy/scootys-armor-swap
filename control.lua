--control.lua
require('event')
require('stringutils')
require('logging')
Logging.sasLog("Scooty's Armor Swap Setup")


-----------------------------
-- Event Handlers
-----------------------------

--[[ Register a function to be run on mod initialization. This is only called when a new save game 
is created or when a save file is loaded that previously didn't contain the mod. During it, the mod 
gets the chance to set up initial values that it will use for its lifetime. It has full access to 
LuaGameScript and the global table and can change anything about them that it deems appropriate. No 
other events will be raised for the mod until it has finished this step.
--]]
function on_init(event)
	tryCatchPrint(
		function()
			Logging.sasLog("⚡️ on_init")
			storage.armorColors = {}
		end
	)
end

--[[
Register a function to be run on save load. This is only called for mods that have been part of the save previously, 
or for players connecting to a running multiplayer session.

It gives the mod the opportunity to rectify potential differences in local state introduced by the save/load cycle. 
Doing anything other than the following three will lead to desyncs, breaking multiplayer and replay functionality. 
Access to LuaGameScript is not available. The global table can be accessed and is safe to read from, but not write to, 
as doing so will lead to an error.

The only legitimate uses of this event are these:
- Re-setup metatables as they are not persisted through the save/load cycle.
- Re-setup conditional event handlers, meaning subscribing to an event only when some condition is met to save processing time.
- Create local references to data stored in the global table.
]]
function on_load(event)
	tryCatchPrint(
		function()
			Logging.sasLog("⚡️ on_load")
			Logging.sasLog("storage.armorColors: " .. tablelength(storage.armorColors) .. " entries")
		end
	)
end


function onKeyPressHandlerEquipNextArmorHandler(event)
	tryCatchPrint(
		function()	
			Logging.sasLog("⚡️ onKeyPressHandlerEquipNextArmorHandler")

			-- Get the player or bail
			local luaPlayer = getLuaPlayerFromEvent(event)
			if luaPlayer == nil then
				return
			end

			-- Record the current armor's color for the next time it is equipped
			dyeArmorFromPlayer(luaPlayer)

			-- Equip the next armor
			equipNextArmor(luaPlayer)
		end,
		event
	)
end

function onKeyPressHandlerClearCacheHandler(event)
	tryCatchPrint(
		function()
			Logging.sasLog("⚡️ onKeyPressHandlerClearCacheHandler")
			storage.armorColors = {}
			Logging.pLog(getLuaPlayerFromEvent(event), "All Armors have been un-dyed")
		end,
		event
	)
end

function onPlayerArmorInventoryChangedHandler(event)
	tryCatchPrint(
		function()
			Logging.sasLog("⚡️ onPlayerArmorInventoryChangedHandler")

			local luaPlayer = getLuaPlayerFromEvent(event)
			if luaPlayer == nil then
				return
			end

			-- Change the player's color based on the new armor
			dyePlayerFromArmor(luaPlayer)

			-- Record the current armor's color for the next time it is equipped
			-- Note: this is to update the fuzzy match, since at the time of this writing
			-- it is suddenly obvious that that the fuzzy match is the one that is used most 
			-- frequently due to jetpack creating new item IDs.
			dyeArmorFromPlayer(luaPlayer)
		end, 
		event
	)
end

----------------------
-- API
----------------------
function equipNextArmor(luaPlayer)
	Logging.sasLog()

	local armorItemNumber = getNextArmorItemNumber(luaPlayer)

	if armorItemNumber ~= nil then
		equipArmorWithItemNumber(luaPlayer, armorItemNumber)
	end
end

function dyeArmorFromPlayer(luaPlayer)
	Logging.sasLog()

	local armorInfo = getArmorInfo(luaPlayer)
	if armorInfo == nil then
		return
	end	

	Logging.sasLog(
		"Dyeing armor "
		.. StringUtils.toString(armorInfo.keys)
		.. " to " 
		.. StringUtils.toString(luaPlayer.color)
	)
	
	-- Record color
	for _, key in ipairs(armorInfo.keys) do
    storage.armorColors[key] = luaPlayer.color
	end
end

function dyePlayerFromArmor(luaPlayer)
	Logging.sasLog()

	-- Get the currently worn armor
	local armorInfo = getArmorInfo(luaPlayer)
	if armorInfo == nil then
		return
	end


	-- Try all keys until a color is found
	for i, key in ipairs(armorInfo.keys) do
		local colorNew = storage.armorColors[key]
		if colorNew ~= nil then
			Logging.sasLog("Found color with key " .. i)

    	-- Apply Color
			luaPlayer.color = colorNew

			-- Apply Jetpack tint fix
			tryCatchPrint(jetpackTintFix, luaPlayer)

			return
		end
	end

	Logging.sasLog("Could not find armor's color, Bailing.")
end



----------------------
-- Utility Functions
----------------------

function getArmorInfo(luaPlayer)
	Logging.sasLog()

	local luaItemStackWornArmor = luaPlayer.get_inventory(defines.inventory.character_armor)[1]
	if not luaItemStackWornArmor.is_armor then
		Logging.sasLog("Not wearing armor")
		return nil
	end


	--[[
	Item numbers are usually a very stable way of "primary key"ing an item.
	However, some mods that teleport players like our beloved SE and Jetpack will destroy and re-create the player, which has the 
	unfortunate side effect of creating new item numbers for that player's armors.
	
	So, we do 2 more increasingly fuzzy matches on 

	--]]

	-- key1 is just the item_number - guaranteed to be unique, but not guaranteed to be permanent.
	local key1 = luaItemStackWornArmor.item_number

	-- key2 is a hash of the player's name, the armor name and its grid (if it has any)
	local hashInput = luaPlayer.name .. luaItemStackWornArmor.name
	if luaItemStackWornArmor.grid ~= nil then
		hashInput = hashInput .. StringUtils.toString(luaItemStackWornArmor.grid.get_contents())
	end
	local key2 = StringUtils.hash(hashInput)

	-- key3 is a hash of the armor name and its grid (if it has any)
	hashInput = luaItemStackWornArmor.name
	if luaItemStackWornArmor.grid ~= nil then
		hashInput = hashInput .. StringUtils.toString(luaItemStackWornArmor.grid.get_contents())
	end
	local key3 = StringUtils.hash(hashInput)	

	-- Return a table
	local ret = {
		name = luaItemStackWornArmor.name,
		keys = { key1, key2, key3 }
	}

	-- Log it
	Logging.sasLog(ret)

	return ret
end

function getNextArmorItemNumber(luaPlayer) 
	Logging.sasLog()
	local luaItemStackWornArmor = luaPlayer.get_inventory(defines.inventory.character_armor)[1]
	local luaInventory = luaPlayer.get_main_inventory()
	local freeSlots = luaInventory.count_empty_stacks()

	local armorItemNumbers = {}

	-- Get the current armor info
	local wornArmorItemNumber = 0
	local currentInventorySizeBonus = 0
	if luaItemStackWornArmor.is_armor then
		wornArmorItemNumber = luaItemStackWornArmor.item_number
		local currentArmorQuality = luaItemStackWornArmor.quality
		currentInventorySizeBonus = luaItemStackWornArmor.prototype.get_inventory_size_bonus(currentArmorQuality)
	end

	-- Find all armors in inventory that wouldnt cause you to drop items if they were equipped
	-- TODO: Refactor this to calculate a minimum number of free slots
	for i=1, #luaInventory do
		local luaItemStack = luaInventory[i]  
		if luaItemStack.valid_for_read then 
			if luaItemStack.is_armor then
				-- If equipping this armor would cause the player to drop items, don't consider it.
				local newInventorySizeBonus = luaItemStack.prototype.get_inventory_size_bonus(luaItemStack.quality)
				local inventorySizeBonusChange = newInventorySizeBonus - currentInventorySizeBonus
				if freeSlots + inventorySizeBonusChange >= 0 then
					table.insert(armorItemNumbers, luaItemStack.item_number)
				end
			end
		end
	end

	-- Bail if there are no valid armors in inventory
	if #armorItemNumbers == 0 then
		Logging.pLog(luaPlayer, "No valid armors in inventory")
		return nil
	end

	table.sort(armorItemNumbers)

	-- Find the next armor in sequence by comparing item numbers
	for i=1, #armorItemNumbers do
		if wornArmorItemNumber < armorItemNumbers[i] then
			return armorItemNumbers[i]
		end
	end

	return armorItemNumbers[1]
end

-- Swaps the the currently equipped armor with the specified item number in the inventory and updates player color
function equipArmorWithItemNumber(luaPlayer, armorItemNumber) 
	Logging.sasLog()

	local mainInventory = luaPlayer.get_main_inventory()

	--Get the armors
	local luaItemStackWornArmor = luaPlayer.get_inventory(defines.inventory.character_armor)[1]
	local luaItemStackNewArmor = findArmorByItemNumber(mainInventory, armorItemNumber)

	Logging.sasLog("Worn armor: " .. StringUtils.toString(luaItemStackWornArmor))
	Logging.sasLog("New armor: " .. StringUtils.toString(luaItemStackNewArmor))

	-- Validate armors
	if luaItemStackNewArmor == nil then
		Logging.sasLog("New armor nil: " .. StringUtils.toString(luaItemStackNewArmor))
		return
	end

	if luaItemStackWornArmor == nil then
		Logging.sasLog("Worn armor nil: " .. StringUtils.toString(luaItemStackWornArmor))
		return
	end

	-- If we're not wearing armor, simply put on the new one and bail
	if not luaItemStackWornArmor.valid_for_read then
		Logging.sasLog("Not wearing armor")
		if not luaItemStackWornArmor.swap_stack(luaItemStackNewArmor) then
			Logging.sasLog("Putting on new armor " .. luaItemStackNewArmor.name .. " failed")
		end
		return
	end


	local putWornArmorHere = mainInventory.find_empty_stack(luaItemStackWornArmor.name)

	-- Bail if full
	if putWornArmorHere == nil then
		Logging.sasLog("Nowhere to put worn armor")
		return
	end	

	--Switch armors
	--Normally, swapping armor briefly removes inventory bonus slots which can cause the player
	--to drop items on the ground. Briefly expand the inventory to prevent this.
	luaPlayer.character_inventory_slots_bonus = luaPlayer.character_inventory_slots_bonus + 60000

	
	if not luaItemStackWornArmor.swap_stack(putWornArmorHere) then
		Logging.sasLog("Taking off armor failed")
		return
	end

	if not luaItemStackNewArmor.swap_stack(luaItemStackWornArmor) then
		Logging.sasLog("Putting on new armor failed")
		return
	end

	-- Reset character_inventory_slots_bonus 
	luaPlayer.character_inventory_slots_bonus = luaPlayer.character_inventory_slots_bonus - 60000  		

end

-- Used by equipArmorWithItemNumber to convert the inventory item number to the actual item stack
function findArmorByItemNumber(luaInventory, armorItemNumber)
	Logging.sasLog()
	for i=1, #luaInventory do
		local luaItemStack = luaInventory[i]  
		if luaItemStack.is_armor and luaItemStack.item_number == armorItemNumber then
			return luaItemStack
		end
	end
	return nil
end

function getLuaPlayerFromEvent(event)
	Logging.sasLog()
	if event.player_index and game.players[event.player_index] and game.players[event.player_index].connected then
		local luaPlayer = game.players[event.player_index]
		if luaPlayer.character then
			return luaPlayer
		end
	end

	Logging.sasLog("No player in event!!")
	return nil
end

function jetpackTintFix(luaPlayer)
	Logging.sasLog()

	-- Since this talks to another mod, put it into a try catch
	tryCatchPrint(
		function()
			if remote.interfaces["jetpack"] == nil then
				Logging.sasLog("Jetpack not installed, bailing")
				return
			end

			Logging.sasLog("Applying jetpack tint fix...")

			local jetpack = remote.call("jetpack", "get_jetpack_for_character", {character=luaPlayer.character})
			if jetpack ~= nil then
				rendering.set_color(jetpack.animation_mask, jetpack.character.player and jetpack.character.player.color or jetpack.character.color)
			end
		end, 
		luaPlayer
	)
end

-- Wrapper for pcall
function tryCatchPrint(aFunction, arg)
	success, error = pcall(aFunction, arg)
	if not success then
		Logging.sasLog("🚨 Error: " .. StringUtils.toString(error))
	end
end

-- Gets the number of entries in a table
function tablelength(T)
  local count = 0
  if T then
	  for _ in pairs(T) do 
	  	count = count + 1 
	  end
	end
  return count
end

--------------------
-- Event Listeners 
--------------------

-- Note - these must be added last, after the funcs are defined
Event.addListener("on_init", on_init, true)
Event.addListener("on_load", on_load, true)
Event.addListener("scootys-armor-swap-equip-next-armor", onKeyPressHandlerEquipNextArmorHandler)
Event.addListener("scootys-armor-swap-clear-cache", onKeyPressHandlerClearCacheHandler)
Event.addListener(defines.events.on_player_armor_inventory_changed, onPlayerArmorInventoryChangedHandler)



-- Helpful for debugging
--[[

/c  local player = game.player
player.insert{name="power-armor-mk2", count = 1}
local p_armor = player.get_inventory(5)[1].grid
	p_armor.put({name = "fusion-reactor-equipment"})
	p_armor.put({name = "fusion-reactor-equipment"})
	p_armor.put({name = "fusion-reactor-equipment"})
	p_armor.put({name = "exoskeleton-equipment"})
	p_armor.put({name = "exoskeleton-equipment"})
	p_armor.put({name = "exoskeleton-equipment"})
	p_armor.put({name = "exoskeleton-equipment"})
	p_armor.put({name = "energy-shield-mk2-equipment"})
	p_armor.put({name = "energy-shield-mk2-equipment"})
	p_armor.put({name = "personal-roboport-mk2-equipment"})
	p_armor.put({name = "night-vision-equipment"})
	p_armor.put({name = "battery-mk2-equipment"})
	p_armor.put({name = "battery-mk2-equipment"})


player.insert{name="iron-plate", count = 5000}

player.print(serpent.block(storage) )

]]