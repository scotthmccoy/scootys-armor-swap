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
			dyeAllPlayersUndyedArmors()
		end
	)
end

--[[
Run when the mod's configuration changes: when the mod is added to an existing save, updated,
or removed, or when the game version changes. This (not on_load, which can't access game state
or write to storage) is where existing saves get their undyed armors seeded.
]]
function on_configuration_changed(event)
	tryCatchPrint(
		function()
			Logging.sasLog("⚡️ on_configuration_changed")
			storage.armorColors = storage.armorColors or {}
			dyeAllPlayersUndyedArmors()
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

-- Handles the /sas-clear-colors console command. Unlike the keybinding, this may be
-- run from the server console (no player_index) so we guard against a nil player.
function onClearCacheCommand(command)
	tryCatchPrint(
		function()
			Logging.sasLog("⚡️ onClearCacheCommand")
			storage.armorColors = {}
			local luaPlayer = command.player_index and game.get_player(command.player_index)
			if luaPlayer then
				Logging.pLog(luaPlayer, "All Armors have been un-dyed")
			end
		end,
		command
	)
end

-- Re-entrancy guard for the armor-changed handler. This handler both reads and writes the
-- player color and the color cache, so we make sure it can never re-enter itself (which could
-- otherwise ping-pong the color between the player and the armor). A plain Lua flag is fine
-- here: it is set and cleared within a single synchronous event, never persists across ticks,
-- and every game instance runs the handler identically, so it can't cause a desync.
handlingArmorChange = false

function onPlayerArmorInventoryChangedHandler(event)
	if handlingArmorChange then
		Logging.sasLog("⚡️ onPlayerArmorInventoryChangedHandler re-entered, ignoring")
		return
	end
	handlingArmorChange = true

	tryCatchPrint(
		function()
			Logging.sasLog("⚡️ onPlayerArmorInventoryChangedHandler")

			local luaPlayer = getLuaPlayerFromEvent(event)
			if luaPlayer == nil then
				return
			end

			-- If the equipped armor already has a saved color, adopt it as the player color.
			-- Otherwise the armor is uncolored, so it keeps the player's current color.
			dyePlayerFromArmor(luaPlayer)

			-- Re-record the color under all of the armor's keys. For an uncolored armor this
			-- dyes it to the player's current color. For an already-colored armor this writes
			-- back the same color we just adopted, which "promotes" a fuzzy match to an exact
			-- one by refreshing key1 (the item_number) for this specific instance -- so armors
			-- with stable, distinct identities keep distinct colors, and key1 is rebuilt after
			-- a mod like Jetpack recreates the armor with a new item_number.
			-- This is safe from the loop the re-entrancy guard protects against: it writes back
			-- the same value it read and raises no event, so it can never ping-pong.
			dyeArmorFromPlayer(luaPlayer)
		end,
		event
	)

	-- Always clear the guard, even if the body above errored (tryCatchPrint swallows errors).
	handlingArmorChange = false
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

-- Applies the worn armor's saved color to the player. Returns true if a saved color was
-- found and applied, false otherwise (no armor worn, or the armor is uncolored).
function dyePlayerFromArmor(luaPlayer)
	Logging.sasLog()

	-- Get the currently worn armor
	local armorInfo = getArmorInfo(luaPlayer)
	if armorInfo == nil then
		return false
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

			return true
		end
	end

	Logging.sasLog("Could not find armor's color, Bailing.")
	return false
end

-- Returns true if any of the armor's keys already has a recorded color.
function isArmorDyed(armorInfo)
	for _, key in ipairs(armorInfo.keys) do
		if storage.armorColors[key] ~= nil then
			return true
		end
	end
	return false
end

-- Dyes a single armor stack with the player's current color, but only if it isn't dyed yet.
function dyeUndyedArmor(luaPlayer, luaItemStackArmor)
	local armorInfo = getArmorInfoFromStack(luaPlayer, luaItemStackArmor)
	if isArmorDyed(armorInfo) then
		return
	end

	Logging.sasLog(
		"Dyeing undyed armor "
		.. StringUtils.toString(armorInfo.keys)
		.. " to "
		.. StringUtils.toString(luaPlayer.color)
	)

	for _, key in ipairs(armorInfo.keys) do
		storage.armorColors[key] = luaPlayer.color
	end
end

-- Dyes every undyed armor a player has (worn and in the main inventory) their player color.
function dyeUndyedArmorsForPlayer(luaPlayer)
	Logging.sasLog()

	-- Worn armor
	local armorInventory = luaPlayer.get_inventory(defines.inventory.character_armor)
	if armorInventory ~= nil and armorInventory[1].valid_for_read and armorInventory[1].is_armor then
		dyeUndyedArmor(luaPlayer, armorInventory[1])
	end

	-- Main inventory
	local mainInventory = luaPlayer.get_main_inventory()
	if mainInventory ~= nil then
		for i = 1, #mainInventory do
			local luaItemStack = mainInventory[i]
			if luaItemStack.valid_for_read and luaItemStack.is_armor then
				dyeUndyedArmor(luaPlayer, luaItemStack)
			end
		end
	end
end

-- Seeds player colors onto every player's undyed armors. Run when the mod is loaded into a
-- save (on_init for new games, on_configuration_changed for existing ones).
function dyeAllPlayersUndyedArmors()
	Logging.sasLog()
	for _, luaPlayer in pairs(game.players) do
		tryCatchPrint(dyeUndyedArmorsForPlayer, luaPlayer)
	end
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

	return getArmorInfoFromStack(luaPlayer, luaItemStackWornArmor)
end

-- Computes the color-cache keys for a specific armor item stack. Used both for the worn
-- armor (via getArmorInfo) and for armors sitting in the main inventory.
function getArmorInfoFromStack(luaPlayer, luaItemStackArmor)
	Logging.sasLog()

	--[[
	Item numbers are usually a very stable way of "primary key"ing an item.
	However, some mods that teleport players like our beloved SE and Jetpack will destroy and re-create the player, which has the
	unfortunate side effect of creating new item numbers for that player's armors.

	So, we do 2 more increasingly fuzzy matches on

	--]]

	-- key1 is just the item_number - guaranteed to be unique, but not guaranteed to be permanent.
	local key1 = luaItemStackArmor.item_number

	-- key2 is a hash of the player's name, the armor name and its grid (if it has any)
	local hashInput = luaPlayer.name .. luaItemStackArmor.name
	if luaItemStackArmor.grid ~= nil then
		hashInput = hashInput .. StringUtils.toString(luaItemStackArmor.grid.get_contents())
	end
	local key2 = StringUtils.hash(hashInput)

	-- key3 is a hash of the armor name and its grid (if it has any)
	hashInput = luaItemStackArmor.name
	if luaItemStackArmor.grid ~= nil then
		hashInput = hashInput .. StringUtils.toString(luaItemStackArmor.grid.get_contents())
	end
	local key3 = StringUtils.hash(hashInput)

	-- Return a table
	local ret = {
		name = luaItemStackArmor.name,
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


	--Switch armors
	--Swapping the worn armor stack directly with the new armor stack requires no empty
	--inventory slot, so this works even when the main inventory is full.
	--Normally, swapping armor briefly removes inventory bonus slots which can cause the player
	--to drop items on the ground. Briefly expand the inventory to prevent this, and always
	--restore it afterwards even if the swap fails.
	luaPlayer.character_inventory_slots_bonus = luaPlayer.character_inventory_slots_bonus + 60000

	if not luaItemStackWornArmor.swap_stack(luaItemStackNewArmor) then
		Logging.sasLog("Swapping armor failed")
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
				-- As of Factorio 2.1 the global rendering.set_color(id, color) was removed.
				-- Colors are now set via LuaRenderObject.color. animation_mask may be a
				-- render object id (number) or already a LuaRenderObject, so handle both.
				local animationMask = jetpack.animation_mask
				if type(animationMask) == "number" then
					animationMask = rendering.get_object_by_id(animationMask)
				end
				if animationMask ~= nil and animationMask.valid then
					animationMask.color = jetpack.character.player and jetpack.character.player.color or jetpack.character.color
				end
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
Event.addListener("on_configuration_changed", on_configuration_changed, true)
Event.addListener("scootys-armor-swap-equip-next-armor", onKeyPressHandlerEquipNextArmorHandler)
Event.addListener("scootys-armor-swap-clear-cache", onKeyPressHandlerClearCacheHandler)
Event.addListener(defines.events.on_player_armor_inventory_changed, onPlayerArmorInventoryChangedHandler)

-- Console command alternative to the "clear cache" keybinding. Registered at control-stage
-- load (commands are not persisted in the save, so this must run on every load).
commands.add_command(
	"sas-clear-colors",
	"Clears Scooty's Armor Swap color cache (un-dyes all armors).",
	onClearCacheCommand
)



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