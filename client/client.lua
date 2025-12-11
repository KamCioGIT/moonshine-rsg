--[[
    Moonshiner System by devchacha
    Client Script
]]

local RSGCore = exports['rsg-core']:GetCoreObject()

local still = 0
local actualBrewingTime = 0
local timeToBrew = 0
local actualBrewingMoonshine = ""
local getMoonshineMenu = false
local isBrewing = false
local isProcessingMash = false
local placedStill = false
local placedBarrel = false
local inplacing = false

-- Track active smoke effects for stills (key = entity handle, value = true/false)
local activeSmoke = {}


-- NUI State
activeMenuOptions = {} -- Global
local activeProgressPromise = nil
local activeMiniGamePromise = nil

-- Helper to submit NUI
function ShowCustomMenu(title, options)
    activeMenuOptions = options
    local optionsForNui = {}
    for i, opt in ipairs(options) do
        table.insert(optionsForNui, {
            title = opt.title or opt.header,
            description = opt.description or opt.txt,
        })
    end
    
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "openMenu",
        title = title,
        options = optionsForNui
    })
end

function CloseCustomMenu()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "closeMenu" })
end

-- NUI Callbacks
RegisterNUICallback('selectOption', function(data, cb)
    -- We can keep focus if we want nested menus, but for now close it
    -- Existing logic triggers events which might open other things
    -- But usually we select one thing.
    
    local index = data.index
    -- Execute the onSelect function we stored
    if activeMenuOptions[index] and activeMenuOptions[index].onSelect then
        -- Close menu first usually?
        -- The existing menu logic closes the menu context when an item is selected usually.
        SetNuiFocus(false, false)
        SendNUIMessage({ action = "closeMenu" })
        activeMenuOptions[index].onSelect()
    end
    cb('ok')
end)

RegisterNUICallback('closeMenu', function(data, cb)
    SetNuiFocus(false, false)
    -- Unlock prop if user closes menu without selecting action
    if currentPropCoords then
        UnlockCurrentProp()
    end
    cb('ok')
end)


RegisterNUICallback('progressComplete', function(data, cb)
    if activeProgressPromise then
        activeProgressPromise:resolve(true)
        activeProgressPromise = nil
    end
    cb('ok')
end)

RegisterNUICallback('miniGameResult', function(data, cb)
    if activeMiniGamePromise then
        activeMiniGamePromise:resolve(data.success)
        activeMiniGamePromise = nil
    end
    cb('ok')
end)



-- Custom Progress Bar
function CustomProgressBar(data)
    local playerPed = PlayerPedId()
    
    -- Send NUI
    SendNUIMessage({
        action = "startProgress",
        label = data.label,
        duration = data.duration
    })
    
    -- Animation
    if data.anim then
        lib.requestAnimDict(data.anim.dict)
        TaskPlayAnim(playerPed, data.anim.dict, data.anim.clip, 8.0, -8.0, data.duration, data.anim.flag or 1, 0, false, false, false)
    end
    
    -- Disable Controls
    local isProgressing = true
    if data.disable then
        CreateThread(function()
            while isProgressing do
                if data.disable.move then DisableControlAction(0, 0x8FD015D8, true) DisableControlAction(0, 0xD27782E3, true) end
                if data.disable.car then DisableControlAction(0, 0x4CC0E2FE, true) end
                if data.disable.combat then DisableControlAction(0, 0xC1989F95, true) end -- Attack
                Wait(0)
            end
        end)
    end
    
    -- Input Detection (Cancellation)
    if data.canCancel then
        CreateThread(function()
            while isProgressing do
                -- Backspace (0x156F7119) or ESC (0x3005A324)
                if IsControlJustPressed(0, 0x156F7119) or IsControlJustPressed(0, 0x3005A324) then
                     if activeProgressPromise then
                        activeProgressPromise:resolve(false) -- Resolve false = Cancelled
                        activeProgressPromise = nil
                     end
                     break
                end
                Wait(0)
            end
        end)
    end
    
    activeProgressPromise = promise.new()
    local result = Citizen.Await(activeProgressPromise)
    isProgressing = false
    
    -- Cleanup Animation
    if data.anim then
        ClearPedTasks(playerPed)
    end
    
    SendNUIMessage({ action = "stopProgress" })
    
    return result
end

-- Custom Mini Game
function StartMiniGame(difficulty)
    local playerPed = PlayerPedId()
    
    SendNUIMessage({
        action = "startMiniGame",
        difficulty = difficulty or 'easy'
    })
    
    activeMiniGamePromise = promise.new()
    
    -- Input Handling Thread
    CreateThread(function()
        while activeMiniGamePromise do
            -- Disable movement/actions
            DisableControlAction(0, 0x8FD015D8, true) -- Move
            DisableControlAction(0, 0xD27782E3, true) -- Move
            DisableControlAction(0, 0x4CC0E2FE, true) -- Car
            
             -- Detect Space (Fill)
            if IsControlJustPressed(0, 0xD9D0E1C0) then -- Jump/Space
                SendNUIMessage({ action = "spaceDown" })
            end
            if IsControlJustReleased(0, 0xD9D0E1C0) then
                SendNUIMessage({ action = "spaceUp" })
            end
            
            -- Detect Cancel (Backspace or ESC)
            if IsControlJustPressed(0, 0x156F7119) or IsControlJustPressed(0, 0x3005A324) then 
                SendNUIMessage({ action = "cancelGame" })
            end
            
            Wait(0)
        end
    end)
    
    local result = Citizen.Await(activeMiniGamePromise)
    
    return result
end



-- Notification helper function
local function Notify(message, type)
    lib.notify({
        title = 'Moonshiner',
        description = message,
        type = type or 'inform',
        duration = 5000
    })
end

-- Helper Functions
local function DrawPlacementHelp(x, y, z)
    local onScreen, _x, _y = GetScreenCoordFromWorldCoord(x, y, z)
    
    -- Draw background box
    DrawSprite("generic_textures", "hud_menu_4a", _x, _y, 0.28, 0.06, 0.0, 0, 0, 0, 180, false)
    
    -- Draw title
    SetTextScale(0.35, 0.35)
    SetTextFontForCurrentCommand(6)
    SetTextColor(255, 215, 0, 255)
    local titleStr = CreateVarString(10, "LITERAL_STRING", "SETTING UP THE OPERATION")
    SetTextCentre(1)
    DisplayText(titleStr, _x, _y - 0.025)
    
    -- Draw instructions
    SetTextScale(0.28, 0.28)
    SetTextFontForCurrentCommand(1)
    SetTextColor(255, 255, 255, 255)
    local instructStr = CreateVarString(10, "LITERAL_STRING", "[ENTER] Set It Down  |  [BACKSPACE] Not Here")
    SetTextCentre(1)
    DisplayText(instructStr, _x, _y + 0.005)
end

local function DrawText3D(x, y, z, text)
    local onScreen, _x, _y = GetScreenCoordFromWorldCoord(x, y, z)
    SetTextScale(0.35, 0.35)
    SetTextFontForCurrentCommand(1)
    SetTextColor(255, 255, 255, 215)
    local str = CreateVarString(10, "LITERAL_STRING", text)
    SetTextCentre(1)
    DisplayText(str, _x, _y)
end

local function round(num, idp)
    local mult = 10^(idp or 0)
    return math.floor(num * mult + 0.5) / mult
end

-- Prop locking state
local currentPropCoords = nil
local propInUseResult = nil
local waitingForPropCheck = false

-- Listen for prop in use result from server
RegisterNetEvent('rsg-moonshiner:client:propInUseResult', function(inUse, byPlayer)
    propInUseResult = {inUse = inUse, byPlayer = byPlayer}
    waitingForPropCheck = false
end)

-- Check if prop is available (async)
local function CheckPropAvailable(x, y, z)
    propInUseResult = nil
    waitingForPropCheck = true
    TriggerServerEvent('rsg-moonshiner:server:checkPropInUse', x, y, z)
    
    local timeout = 0
    while waitingForPropCheck and timeout < 2000 do
        Wait(10)
        timeout = timeout + 10
    end
    
    if propInUseResult and propInUseResult.inUse then
        Notify('This equipment is currently being used by another player!', 'error')
        return false
    end
    return true
end

-- Lock prop when starting to use it
local function LockCurrentProp(x, y, z)
    currentPropCoords = {x = x, y = y, z = z}
    TriggerServerEvent('rsg-moonshiner:server:lockProp', x, y, z)
end

-- Unlock prop when done
local function UnlockCurrentProp()
    if currentPropCoords then
        TriggerServerEvent('rsg-moonshiner:server:unlockProp', currentPropCoords.x, currentPropCoords.y, currentPropCoords.z)
        currentPropCoords = nil
    end
end

-- Update Props from Server
CreateThread(function()
    while true do
        Wait(1000)
        TriggerServerEvent("rsg-moonshiner:server:updateProps")
    end
end)


-- Open Still Menu
function OpenStillMenu()
    print("Moonshiner: Opening Still Menu")
    local stillMenu = {}
    
    -- Add moonshine recipes
    for k, v in pairs(Config.moonshine) do
        local itemsText = ""
        for itemName, itemCount in pairs(v.items) do
            itemsText = itemsText .. itemCount .. "x " .. itemName .. " "
        end
        
        table.insert(stillMenu, {
            title = v.label,
            description = "Required: " .. itemsText,
            icon = 'whiskey-glass',
            onSelect = function()
                print("Moonshiner: Selected", v.label)
                TriggerEvent('rsg-moonshiner:client:startBrewing', {moonshine = k, data = v})
            end
        })
    end
    
    -- Add destroy still option
    table.insert(stillMenu, {
        title = "Destroy Still",
        description = "Destroy the still completely (10s Fuse!)",
        icon = 'bomb',
        onSelect = function()
            TriggerEvent('rsg-moonshiner:client:destroyStill')
        end
    })
    
    ShowCustomMenu("Moonshine Still", stillMenu)
end

-- Open Barrel Menu
function OpenBarrelMenu()
    local barrelMenu = {}
    
    -- Add mash recipes
    for k, v in pairs(Config.mashes) do
        local itemsText = ""
        for itemName, itemCount in pairs(v.items) do
            itemsText = itemsText .. itemCount .. "x " .. itemName .. " "
        end
        
        table.insert(barrelMenu, {
            title = v.label,
            description = "Required: " .. itemsText,
            icon = 'mortar-pestle',
            onSelect = function()
                TriggerEvent('rsg-moonshiner:client:startMash', {mash = k, data = v})
            end
        })
    end
    
    -- Add remove barrel option
    table.insert(barrelMenu, {
        title = "Remove Barrel",
        description = "Pick up the barrel",
        icon = 'hand-holding',
        onSelect = function()
            TriggerEvent('rsg-moonshiner:client:removeBarrel')
        end
    })
    
    ShowCustomMenu("Mash Barrel", barrelMenu)
end

-- Check if player is in a restricted zone (city)
local function IsInRestrictedZone(coords)
    for _, zone in pairs(Config.RestrictedZones) do
        local distance = #(coords - zone.coords)
        if distance <= zone.radius then
            return true, zone.name
        end
    end
    return false, nil
end

-- Place Prop
RegisterNetEvent('rsg-moonshiner:client:placeProp', function(propName)
    print('rsg-moonshiner: placeProp called with', propName)
    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)
    
    -- Check if player is in a restricted zone
    local isRestricted, zoneName = IsInRestrictedZone(coords)
    if isRestricted then
        Notify('You cannot set up moonshine operations in ' .. zoneName .. '! Find a secluded location outside of town.', 'error')
        TriggerServerEvent('rsg-moonshiner:server:givePropBack', propName)
        return
    end
    
    local heading = GetEntityHeading(playerPed)
    local object = GetHashKey(propName)


    print('rsg-moonshiner: Requesting model', propName, object)
    
    -- Force stream the model
    if not HasModelLoaded(object) then
        RequestModel(object)
        local timeout = 0
        while not HasModelLoaded(object) and timeout < 10000 do
            Wait(10)
            timeout = timeout + 10
        end
        if not HasModelLoaded(object) then
            print('rsg-moonshiner: Failed to load model', propName)
            Notify('Failed to load model: ' .. propName, 'error')
            return
        end
    end
    
    print('rsg-moonshiner: Model loaded, creating object')
    inplacing = true
    
    -- Create the preview object (networked = false, scriptHostObj = true)
    local forward = GetEntityForwardVector(playerPed)
    local spawnCoords = vector3(coords.x + forward.x * 2.0, coords.y + forward.y * 2.0, coords.z)
    
    local tempObj = CreateObject(object, spawnCoords.x, spawnCoords.y, spawnCoords.z, false, true, false)
    
    if not DoesEntityExist(tempObj) then
        print('rsg-moonshiner: Failed to create object')
        Notify('Failed to create preview object', 'error')
        inplacing = false
        return
    end
    
    print('rsg-moonshiner: Object created', tempObj)
    
    -- Make the object visible and semi-transparent
    SetEntityVisible(tempObj, true)
    SetEntityAlpha(tempObj, 200, false)
    SetEntityHeading(tempObj, heading)
    PlaceObjectOnGroundProperly(tempObj)
    SetEntityCollision(tempObj, false, false)
    FreezeEntityPosition(tempObj, true)
    
    local placing = true
    while placing do
        Wait(0)
        local newCoords = GetEntityCoords(playerPed)
        local newHeading = GetEntityHeading(playerPed)
        local fwd = GetEntityForwardVector(playerPed)
        local objCoords = vector3(newCoords.x + fwd.x * 2.0, newCoords.y + fwd.y * 2.0, newCoords.z)
        
        -- Update position
        FreezeEntityPosition(tempObj, false)
        SetEntityCoords(tempObj, objCoords.x, objCoords.y, objCoords.z, false, false, false, false)
        SetEntityHeading(tempObj, newHeading)
        PlaceObjectOnGroundProperly(tempObj)
        FreezeEntityPosition(tempObj, true)
        
        -- Draw styled help text
        DrawPlacementHelp(objCoords.x, objCoords.y, objCoords.z + 1.5)
        
        if IsControlJustReleased(0, 0xC7B5340A) then -- ENTER
            local finalCoords = GetEntityCoords(tempObj)
            DeleteObject(tempObj)
            
            if CustomProgressBar({
                duration = 8000,
                label = 'Setting up ' .. (propName == Config.brewProp and 'moonshine still' or 'mash barrel') .. '...',
                useWhileDead = false,
                canCancel = false,
                disable = {
                    move = true,
                    car = true,
                    combat = true
                },
                anim = {
                    dict = 'amb_work@world_human_box_pickup@1@male_a@stand_exit_withprop',
                    clip = 'exit_front',
                    flag = 1
                }
            }) then
                TriggerServerEvent('rsg-moonshiner:server:placeProp', propName, finalCoords.x, finalCoords.y, finalCoords.z)
                Notify('You set up the ' .. (propName == Config.brewProp and 'moonshine still' or 'mash barrel'), 'success')
                
                -- Trigger Global Alert on Still Placement
                if propName == Config.brewProp then
                    -- TriggerServerEvent('rsg-moonshiner:server:alertPolice', finalCoords)
                end
            end
            
            placing = false
            inplacing = false
        end
        
        if IsControlJustReleased(0, 0x156F7119) then -- BACKSPACE
            DeleteObject(tempObj)
            TriggerServerEvent('rsg-moonshiner:server:givePropBack', propName)
            placing = false
            inplacing = false
        end
    end
    
    -- Cleanup model
    SetModelAsNoLongerNeeded(object)
end)


-- Remove Still
RegisterNetEvent('rsg-moonshiner:client:removeStill', function()
    local coords = GetEntityCoords(PlayerPedId())
    TriggerServerEvent('rsg-moonshiner:server:getCoordsId', coords.x, coords.y, coords.z)
end)

-- Remove Barrel
RegisterNetEvent('rsg-moonshiner:client:removeBarrel', function()
    local coords = GetEntityCoords(PlayerPedId())
    TriggerServerEvent('rsg-moonshiner:server:getCoordsId', coords.x, coords.y, coords.z)
end)

-- Destroy Still Request
RegisterNetEvent('rsg-moonshiner:client:destroyStill', function()
    local coords = GetEntityCoords(PlayerPedId())
    TriggerServerEvent('rsg-moonshiner:server:getCoordsIdForDestroy', coords.x, coords.y, coords.z)
end)

-- Check Destroy Distance
RegisterNetEvent('rsg-moonshiner:client:checkDestroyDist', function(x, y, z, id, object, propX, propY, propZ)
    local coords = GetEntityCoords(PlayerPedId())
    local dist = #(coords - vector3(propX, propY, propZ))
    
    if dist <= 5.0 then
        TriggerEvent('rsg-moonshiner:client:startDestroySequence', id, object, propX, propY, propZ)
    end
end)


-- Start Destroy Sequence
RegisterNetEvent('rsg-moonshiner:client:startDestroySequence', function(id, object, x, y, z)
    Notify("RUN! 10 SECONDS UNTIL EXPLOSION!", "error")
    
    AnimpostfxPlay("CamPushInJust")
    
    local countdown = 10
    while countdown > 0 do
        Notify(countdown .. "...", "error")
        Wait(1000)
        countdown = countdown - 1
    end
    
    AnimpostfxStop("CamPushInJust")
    
    -- Trigger global explosion and cleanup
    TriggerServerEvent('rsg-moonshiner:server:syncExplosion', x, y, z, id)
end)

-- Sync Explosion Event
RegisterNetEvent('rsg-moonshiner:client:syncExplosion', function(x, y, z)
    AddExplosion(x, y, z, 22, 5.0, true, false, 1.0)
    
    local prop = GetClosestObjectOfType(x, y, z, 5.0, GetHashKey(Config.brewProp), false, false, false)
    if DoesEntityExist(prop) then
        activeSmoke[prop] = nil -- Stop smoke thread
        SetEntityAsMissionEntity(prop, true, true)
        DeleteObject(prop)
        SetEntityAsNoLongerNeeded(prop)
    end
end)

-- Sync Smoke Event
RegisterNetEvent('rsg-moonshiner:client:syncSmoke', function(coords)
    local stillHash = GetHashKey(Config.brewProp)
    local stillEntity = GetClosestObjectOfType(coords.x, coords.y, coords.z, 3.0, stillHash, false, false, false)

    -- If we can't find the entity (maybe not streamed in yet, or too far), we can still play at coords,
    -- but managing the lifecycle (stopping it when entity dies) is harder.
    -- Ideally, we attach to the entity found at those coords.
    
    if DoesEntityExist(stillEntity) and not activeSmoke[stillEntity] then
        activeSmoke[stillEntity] = true
        
        CreateThread(function()
            local stillCoords = GetEntityCoords(stillEntity)
            
            -- Load core dictionary
            RequestNamedPtfxAsset("core")
            local timeout = 0
            while not HasNamedPtfxAssetLoaded("core") and timeout < 100 do
                Wait(100)
                timeout = timeout + 1
            end
            
            local smokeHandles = {}
            local workingEffect = nil
            
            if HasNamedPtfxAssetLoaded("core") then
                -- Find which effect works
                local effects = {
                    "ent_amb_smoke_fire_industrial",
                    "ent_amb_smoke_factory",
                    "ent_amb_smoke",
                }
                
                for _, effectName in ipairs(effects) do
                    UseParticleFxAsset("core")
                    local testHandle = StartParticleFxLoopedAtCoord(
                        effectName,
                        stillCoords.x,
                        stillCoords.y,
                        stillCoords.z + 1.0,
                        0.0, 0.0, 0.0,
                        4.0,
                        false, false, false, false
                    )
                    
                    if testHandle and testHandle > 0 then
                        workingEffect = effectName
                        table.insert(smokeHandles, testHandle)
                        break
                    end
                end
                
                -- Stack 6 more (total 7)
                if workingEffect then
                    local heights = {8.0, 16.0, 24.0, 32.0, 40.0, 48.0}
                    for _, height in ipairs(heights) do
                        UseParticleFxAsset("core")
                        local handle = StartParticleFxLoopedAtCoord(
                            workingEffect,
                            stillCoords.x,
                            stillCoords.y,
                            stillCoords.z + 1.0 + height,
                            0.0, 0.0, 0.0,
                            4.0,
                            false, false, false, false
                        )
                        
                        if handle and handle > 0 then
                            table.insert(smokeHandles, handle)
                        end
                    end
                end
            end
            
            -- Wait for brewing to finish or entity to be destroyed
            while activeSmoke[stillEntity] and DoesEntityExist(stillEntity) do
                Wait(1000)
            end
            
            -- Cleanup Smoke
            for _, handle in ipairs(smokeHandles) do
                if handle and handle > 0 then
                    StopParticleFxLooped(handle, false)
                    RemoveParticleFx(handle, false)
                end
            end
            
            activeSmoke[stillEntity] = nil
        end)
    end
end)


-- Delete Prop
RegisterNetEvent('rsg-moonshiner:client:deleteProp', function(id, object, xpos, ypos, zpos)
    local playerPed = PlayerPedId()
    local prop = GetClosestObjectOfType(xpos, ypos, zpos, 1.0, GetHashKey(object), false, false, false)
    
    if CustomProgressBar({
        duration = 5000,
        label = 'Removing...',
        useWhileDead = false,
        canCancel = false,
        disable = {
            move = true,
            car = true,
            combat = true
        },
        anim = {
            dict = 'amb_work@world_human_box_pickup@1@male_a@stand_exit_withprop',
            clip = 'exit_front'
        }
    }) then
        DeleteObject(prop)
        TriggerServerEvent('rsg-moonshiner:server:removeProp', id)
        TriggerServerEvent('rsg-moonshiner:server:givePropBack', object)
        Notify('You picked up the ' .. (object == Config.brewProp and 'still' or 'barrel'), 'success')
    end
end)

-- Start Mash Production
RegisterNetEvent('rsg-moonshiner:client:startMash', function(data)
    TriggerServerEvent('rsg-moonshiner:server:checkMashItems', data.mash, data.data)
end)

RegisterNetEvent('rsg-moonshiner:client:processMash', function(mash, mashData)
    isProcessingMash = true
    local playerPed = PlayerPedId()
    local mashTime = mashData.mashTime * 60 * 1000
    
    if CustomProgressBar({
        duration = mashTime,
        label = 'Producing ' .. mashData.label,
        useWhileDead = false,
        canCancel = false,
        disable = {
            move = true,
            car = true,
            combat = true
        },
        anim = {
            dict = 'amb_work@world_human_box_pickup@1@male_a@stand_exit_withprop',
            clip = 'exit_front'
        }
    }) then
        TriggerServerEvent('rsg-moonshiner:server:giveMash', mash, mashData)
        Notify('Mash prepared!', 'success')
    end
    
    isProcessingMash = false
    UnlockCurrentProp()
end)


-- Start Brewing
RegisterNetEvent('rsg-moonshiner:client:startBrewing', function(data)
    print("Moonshiner: startBrewing event triggered", data.moonshine)
    TriggerServerEvent('rsg-moonshiner:server:checkMoonshineItems', data.moonshine, data.data)
end)

RegisterNetEvent('rsg-moonshiner:client:processBrewing', function(moonshine, moonshineData)
    if isBrewing then
        Notify('Already brewing moonshine!', 'error')
        return
    end
    
    print("Moonshiner Client: Starting brewing process")
    isBrewing = true
    local brewTime = moonshineData.brewTime * 60 * 1000
    
    -- Global Alert removed
    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)
    -- TriggerServerEvent('rsg-moonshiner:server:alertPolice', coords)
    
    -- Find the nearest still for smoke effect
    local stillHash = GetHashKey(Config.brewProp)
    local still = GetClosestObjectOfType(coords.x, coords.y, coords.z, 5.0, stillHash, false, false, false)
    local smokeHandle = nil
    
    -- Custom Mini-game (Fill the Mash)
    local result = StartMiniGame('easy')
    
    local amountToGive = 0
    
    if result == 'cancel' then
        isBrewing = false
        UnlockCurrentProp()
        Notify('Brewing cancelled.', 'error')
        return
    elseif result == 'fail' then
        -- Fail Reward: 2-3
        amountToGive = math.random(2, 3)
        Notify('You spilt some mash, but salvaged ' .. amountToGive .. ' bottles of moonshine.', 'error')
    elseif result == 'perfect' then
        -- Lucky/Perfect Reward: 10-12
        amountToGive = math.random(10, 12)
        Notify('Perfect fermentation! Yielded ' .. amountToGive .. ' bottles of moonshine!', 'success')
    else 
        -- Success/Pass Reward: 4-7
        amountToGive = math.random(4, 7)
        Notify('Good brew. Yielded ' .. amountToGive .. ' bottles of moonshine.', 'success')
    end
    
    -- Smoke effect - persists until still is destroyed
    local stillEntity = still

    -- Smoke effect - persists until still is destroyed
    local stillEntity = still
    
    -- Request global smoke sync
    if DoesEntityExist(stillEntity) then
        local stCoords = GetEntityCoords(stillEntity)
        TriggerServerEvent('rsg-moonshiner:server:syncSmoke', stCoords)
    end
    




    -- START BREWING FX (Fire, Sparks, Sound)
    -- Coordinate Based (More Reliable for visibility than entity attach for static props)
    local activeEntity = still
    local fireCoords = coords
    local audioEntity = PlayerPedId()
    
    if DoesEntityExist(activeEntity) then
        fireCoords = GetEntityCoords(activeEntity)
        audioEntity = activeEntity
    else
        -- Fallback
        local pCoords = GetEntityCoords(PlayerPedId())
        local pFwd = GetEntityForwardVector(PlayerPedId())
        fireCoords = pCoords + pFwd * 1.2
    end
    
    print("Moonshiner FX: Attempting to start fire at " .. tostring(fireCoords))

    -- 1. Load Assets
    local dict = "core"
    local fireName = "ent_amb_fire_bonfire_small" -- Stronger fire
    local sparkName = "ent_amb_sparks_bonfire" 
    
    RequestNamedPtfxAsset(dict)
    local maxWait = 100
    while not HasNamedPtfxAssetLoaded(dict) and maxWait > 0 do
        Wait(10)
        maxWait = maxWait - 1
    end
    -- print("Moonshiner FX: Loaded Dict: " .. dict)

    -- 2. Visuals (Particle)
    UseParticleFxAsset(dict)
    local fireFxHandle = StartParticleFxLoopedAtCoord(fireName, fireCoords.x, fireCoords.y, fireCoords.z - 0.95, 0.0, 0.0, 0.0, 1.0, false, false, false, false)
    
    UseParticleFxAsset(dict)
    local sparkFxHandle = StartParticleFxLoopedAtCoord(sparkName, fireCoords.x, fireCoords.y, fireCoords.z - 0.5, 0.0, 0.0, 0.0, 2.0, false, false, false, false)
    
    -- print("Moonshiner FX: Fire Handle -> " .. tostring(fireFxHandle) .. " | Spark Handle -> " .. tostring(sparkFxHandle))
    
    -- 3. Visuals (Prop Fallback)
    -- If particle failed (Handle 0) OR purely to ensure visibility, we can spawn a campfire prop
    local fireProp = nil
    if not fireFxHandle or fireFxHandle == 0 then
        -- print("Moonshiner FX: Particles failed. Spawning Fallback Prop.")
        local model = GetHashKey("p_campfire05x")
        RequestModel(model)
        local t = 0
        while not HasModelLoaded(model) and t < 50 do Wait(10) t=t+1 end
        
        if HasModelLoaded(model) then
            fireProp = CreateObject(model, fireCoords.x, fireCoords.y, fireCoords.z - 0.95, true, true, false)
            SetEntityCollision(fireProp, false, false)
            FreezeEntityPosition(fireProp, true)
            -- print("Moonshiner FX: Fallback Prop Spawned -> " .. tostring(fireProp))
        end
    end
    
    -- 4. Audio
    local brewSoundId = GetSoundId()
    local bubbleSoundId = GetSoundId()

    -- Native: _PLAY_SOUND_FROM_POSITION
    Citizen.InvokeNative(0x89049DD63C08B5D1, brewSoundId, "Campfire_Idle_Loop", fireCoords.x, fireCoords.y, fireCoords.z, "App_Campfire_Sounds", true, 0, false, 0)
    Citizen.InvokeNative(0x89049DD63C08B5D1, bubbleSoundId, "Cooking_Pot_Bubble_Loop", fireCoords.x, fireCoords.y, fireCoords.z, "App_Camp_Cooking_Sounds", true, 0, false, 0)

    -- PROGRESS BAR
    if CustomProgressBar({
        duration = brewTime,
        label = 'Brewing ' .. moonshineData.label .. ' (Backspace to Cancel)',
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = true,
            car = true,
            combat = true
        },
        anim = {
            dict = 'script_re@moonshine_camp@player_put_in_herbs',
            clip = 'put_in_still',
            flag = 1
        }
    }) then
        print("Moonshiner Client: Brewing complete, giving moonshine")
        isBrewing = false
        smokeActive = false -- Stop smoke thread
        TriggerServerEvent('rsg-moonshiner:server:giveMoonshineDirect', moonshine, amountToGive)
    else
        print("Moonshiner Client: Brewing CANCELLED")
        isBrewing = false
        smokeActive = false 
        Notify('Brewing cancelled!', 'error')
    end
    
    -- STOP BREWING FX
    if fireFxHandle and fireFxHandle ~= 0 then StopParticleFxLooped(fireFxHandle, false) end
    if sparkFxHandle and sparkFxHandle ~= 0 then StopParticleFxLooped(sparkFxHandle, false) end
    if fireProp and DoesEntityExist(fireProp) then DeleteObject(fireProp) end
    
    if brewSoundId then 
        Citizen.InvokeNative(0xA3B0C41BA5CC032F, brewSoundId) -- StopSound
        ReleaseSoundId(brewSoundId) 
    end
    if bubbleSoundId then 
        Citizen.InvokeNative(0xA3B0C41BA5CC032F, bubbleSoundId) -- StopSound
        ReleaseSoundId(bubbleSoundId) 
    end
    
    print("Moonshiner: Brewing ended, smoke should stop")
    
    UnlockCurrentProp()
end)



-- Replace Props (sync with other players)
RegisterNetEvent('rsg-moonshiner:client:replaceProps', function(object, x1, y1, z1, actif)
    local prop = GetClosestObjectOfType(x1, y1, z1, 1.0, GetHashKey(object), false, false, false)
    local ped = PlayerPedId()
    local radius = 100.0
    local entityCoords = GetEntityCoords(ped, true)
    local distance = #(vector3(x1, y1, z1) - entityCoords)
    
    if distance <= radius then
        if actif == 0 then
            -- Delete if inactive
            if DoesEntityExist(prop) then
                DeleteObject(prop)
            end
        elseif actif == 1 then
            -- Create if active and missing
            if not DoesObjectOfTypeExistAtCoords(x1, y1, z1, 1.0, GetHashKey(object), false) then
                if DoesEntityExist(prop) then DeleteObject(prop) end -- Cleanup existing just in case
                
                local tempObj = CreateObject(GetHashKey(object), x1, y1, z1, false, false, false)
                PlaceObjectOnGroundProperly(tempObj)
                FreezeEntityPosition(tempObj, true) -- Ensure it stays put
                
                -- Add ox_target to the prop
                if object == Config.brewProp then
                    exports.ox_target:addLocalEntity(tempObj, {
                        {
                            name = 'moonshine_still',
                            label = 'Use Moonshine Still',
                            icon = 'fa-solid fa-flask',
                            distance = 2.5,
                            onSelect = function()
                                local propCoords = GetEntityCoords(tempObj)
                                if CheckPropAvailable(propCoords.x, propCoords.y, propCoords.z) then
                                    LockCurrentProp(propCoords.x, propCoords.y, propCoords.z)
                                    OpenStillMenu()
                                end
                            end
                        }
                    })
                elseif object == Config.mashProp then
                    exports.ox_target:addLocalEntity(tempObj, {
                        {
                            name = 'mash_barrel',
                            label = 'Use Mash Barrel',
                            icon = 'fa-solid fa-barrel-oil',
                            distance = 2.5,
                            onSelect = function()
                                local propCoords = GetEntityCoords(tempObj)
                                if CheckPropAvailable(propCoords.x, propCoords.y, propCoords.z) then
                                    LockCurrentProp(propCoords.x, propCoords.y, propCoords.z)
                                    OpenBarrelMenu()
                                end
                            end
                        }
                    })

                end
            end
        end
    end
end)

RegisterNetEvent('rsg-moonshiner:client:getId', function(x1, y1, z1, object, x2, y2, z2)
    local coords = GetEntityCoords(PlayerPedId())
    local distance = #(coords - vector3(x2, y2, z2))
    
    if distance <= 2 then
        TriggerServerEvent("rsg-moonshiner:server:getObjectId", object, x2, y2, z2)
    end
end)

-- Drunk System
local isDrunk = false
local drunkLevel = 0

RegisterNetEvent('rsg-moonshiner:client:drinkMoonshine', function(level)
    print("Moonshiner Client: Drink event received, level:", level)
    local playerPed = PlayerPedId()
    
    -- Drinking animation
    local propModel = `p_jug01x` -- Verified VALID large jug
    
    if not IsModelInCdimage(propModel) then 
        print("Invalid model") 
        return 
    end
    RequestModel(propModel)
    while not HasModelLoaded(propModel) do Wait(10) end

    local prop = CreateObject(propModel, GetEntityCoords(playerPed), true, true, false, false, true)
    -- Fixing floating: Bringing Z down significantly (-0.22). Resetting rotation to default for this check.
    AttachEntityToEntity(prop, playerPed, GetEntityBoneIndexByName(playerPed, "PH_R_HAND"), 0.0, 0.0, -0.22, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(propModel)
    
    if not IsPedOnMount(playerPed) and not IsPedInAnyVehicle(playerPed) then
        lib.requestAnimDict('mech_inventory@drinking@bottle_cylinder_d1-3_h30-5_neck_a13_b2-5')
        TaskPlayAnim(playerPed, 'mech_inventory@drinking@bottle_cylinder_d1-3_h30-5_neck_a13_b2-5', 'uncork', 8.0, -8.0, 500, 31, 0, true, false, false)
        Wait(500)
        TaskPlayAnim(playerPed, 'mech_inventory@drinking@bottle_cylinder_d1-3_h30-5_neck_a13_b2-5', 'chug_a', 8.0, -8.0, 5000, 31, 0, true, false, false)
        Wait(5000)
    else
        -- Note: the interaction hash might need to be specific to the prop or generic. 
        -- Back to right-hand interaction
        TaskItemInteraction_2(playerPed, 1737033966, prop, `p_jug01x_ph_r_hand`, `DRINK_Bottle_Cylinder_d1-55_H18_Neck_A8_B1-8_QUICK_RIGHT_HAND`, true, 0, 0)
        Wait(4000)
    end
    
    ClearPedTasks(playerPed)
    if DoesEntityExist(prop) then
        DetachEntity(prop, true, true)
        DeleteObject(prop)
    end
    
    drunkLevel = level
    isDrunk = true
    
    print("Moonshiner Client: Applying drunk effects for level", level)
    
    -- Apply drunk effects based on level
    if level == 1 then
        print("Moonshiner Client: Level 1 drunk effects")
        Notify('That\'s some strong moonshine! *hic*', 'inform')
        
        Citizen.InvokeNative(0x406CCF555B04FAD3, playerPed, 1, 0.3)
        AnimpostfxPlay("PlayerDrunk01")
        
    elseif level == 2 then
        print("Moonshiner Client: Level 2 drunk effects")
        Notify('You\'re feeling pretty drunk... *hic*', 'inform')
        
        Citizen.InvokeNative(0x406CCF555B04FAD3, playerPed, 1, 0.6)
        AnimpostfxPlay("PlayerDrunk01")
        
    elseif level >= 3 then
        print("Moonshiner Client: Level 3+ drunk effects - BLACKOUT!")
        Notify('Everything is spinning...', 'error')
        
        Citizen.InvokeNative(0x406CCF555B04FAD3, playerPed, 1, 0.95)
        AnimpostfxPlay("PlayerDrunk01")
        
        Wait(3000)
        
        -- Pass out animation
        lib.requestAnimDict('amb_misc@world_human_vomit@male_a@idle_b')
        TaskPlayAnim(playerPed, 'amb_misc@world_human_vomit@male_a@idle_b', 'idle_f', 8.0, -8.0, 3000, 31, 0, true, false, false)
        Wait(3000)
        ClearPedTasks(playerPed)
        
        -- Sleep animation
        lib.requestAnimDict('amb_rest@world_human_sleep_ground@arm@male_b@idle_b')
        TaskPlayAnim(playerPed, 'amb_rest@world_human_sleep_ground@arm@male_b@idle_b', 'idle_f', 8.0, -8.0, 5000, 1, 0, true, false, false)
        
        -- Black out and teleport to Rhodes
        print("Moonshiner Client: Starting blackout sequence")
        AnimpostfxPlay("PlayerPassOut")
        DoScreenFadeOut(2000)
        Wait(2000)
        
        print("Moonshiner Client: Screen is black, teleporting")
        ClearPedTasks(playerPed)
        Citizen.InvokeNative(0x58F7DB5BD8FA2288, playerPed)
        
        -- Rhodes camp location
        local rhodesCoords = vector4(1225.0, -1305.0, 76.0, 0.0)
        print("Moonshiner Client: Teleporting to Rhodes", rhodesCoords)
        SetEntityCoords(playerPed, rhodesCoords.x, rhodesCoords.y, rhodesCoords.z, false, false, false, false)
        SetEntityHeading(playerPed, rhodesCoords.w)
        
        Wait(1000)
        
        -- Wake up
        print("Moonshiner Client: Waking up")
        Citizen.InvokeNative(0x406CCF555B04FAD3, playerPed, 1, 0.5)
        AnimpostfxPlay("PlayerWakeUp")
        DoScreenFadeIn(2000)
        Wait(2000)
        AnimpostfxStop("PlayerWakeUp")
        
        Notify('You wake up near Rhodes... What happened?!', 'error')
        
        drunkLevel = 0
        
        -- Groggy effect
        Wait(30000)
        AnimpostfxStop("PlayerDrunk01")
        Citizen.InvokeNative(0x406CCF555B04FAD3, playerPed, 1, 0.0)
        isDrunk = false
        Notify('You\'re finally sober...', 'success')
    end
    
    -- Clear drunk effects after 60 seconds (if not level 3+)
    if level < 3 then
        CreateThread(function()
            Wait(60000)
            if drunkLevel == level then
                print("Moonshiner Client: Sobering up...")
                AnimpostfxStop("PlayerDrunk01")
                Citizen.InvokeNative(0x406CCF555B04FAD3, playerPed, 1, 0.0)
                isDrunk = false
                Notify('You\'re feeling sober now', 'success')
            end
        end)
    end
end)

-- Police Alert Blip
RegisterNetEvent('rsg-moonshiner:client:policeAlert', function(coords)
    -- Use standard RedM blip creation
    local blip = N_0x554d9d53f696d002(1664425300, coords.x, coords.y, coords.z)
    
    if blip and blip ~= 0 then
        SetBlipSprite(blip, joaat('blip_ambient_drunk'), true)
        SetBlipScale(blip, 0.8)
        
        local blipName = CreateVarString(10, 'LITERAL_STRING', "Illegal Moonshine Activity")
        SetBlipName(blip, blipName)
        
        -- Remove blip after 10 minutes
        CreateThread(function()
            Wait(600000)
            if blip and type(blip) == 'number' and DoesBlipExist(blip) then
                RemoveBlip(blip)
            end
        end)
    else
        print("rsg-moonshiner: Failed to create police alert blip")
    end
end)


-- Debug Commands Removed


