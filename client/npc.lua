local RSGCore = exports['rsg-core']:GetCoreObject()
local npcSpawned = false
local npcPed = nil
local npcBlip = nil

-- Setup Blip
local function SetupBlip()
    if Config.NPCSettings.blip.enabled then
        local blipCoords = Config.NPCSettings.coords
        npcBlip = BlipAddForCoords(1664425300, blipCoords.x, blipCoords.y, blipCoords.z)
        SetBlipSprite(npcBlip, joaat(Config.NPCSettings.blip.sprite), true)
        SetBlipScale(npcBlip, Config.NPCSettings.blip.scale)
        SetBlipName(npcBlip, Config.NPCSettings.blip.name)
        print("Moonshiner: Blip created at", blipCoords.x, blipCoords.y, blipCoords.z)
    end
end

-- Spawn NPC
local function SpawnNPC()
    if npcSpawned then return end
    
    print("Moonshiner: Starting NPC spawn...")
    local model = Config.NPCSettings.model
    local coords = Config.NPCSettings.coords
    
    -- Request model
    lib.requestModel(model, 5000)
    
    -- Get ground Z coordinate
    local groundZ = coords.z
    local foundGround, groundHeight = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 100.0, false)
    if foundGround then
        groundZ = groundHeight
        print("Moonshiner: Ground found at Z:", groundZ)
    else
        print("Moonshiner: Using config Z:", groundZ)
    end
    
    -- Create ped at ground level
    npcPed = CreatePed(joaat(model), coords.x, coords.y, groundZ, coords.w, false, false, false, false)
    print("Moonshiner: NPC Created with ID:", npcPed, "at coords:", coords.x, coords.y, groundZ)
    
    -- Wait for ped to be created
    local timeout = 0
    while not DoesEntityExist(npcPed) and timeout < 50 do
        Wait(100)
        timeout = timeout + 1
    end
    
    if not DoesEntityExist(npcPed) then
        print("Moonshiner: ERROR - NPC failed to spawn!")
        return
    end
    
    -- Set ped properties
    Citizen.InvokeNative(0x283978A15512B2FE, npcPed, true) -- SetRandomOutfitVariation
    SetEntityNoCollisionEntity(npcPed, PlayerPedId(), false)
    SetEntityCanBeDamaged(npcPed, false)
    SetEntityInvincible(npcPed, true)
    FreezeEntityPosition(npcPed, true)
    SetBlockingOfNonTemporaryEvents(npcPed, true)
    PlaceEntityOnGroundProperly(npcPed, true) -- Ensure NPC is on ground
    
    -- Set scenario
    if Config.NPCSettings.scenario then
        TaskStartScenarioInPlace(npcPed, joaat(Config.NPCSettings.scenario), -1, true, false, false, false)
    end
    
    -- Add target interaction
    exports.ox_target:addLocalEntity(npcPed, {
        {
            name = 'moonshiner_shop',
            label = 'Browse Moonshiner Shop',
            icon = 'fa-solid fa-basket-shopping',
            distance = 3.0,
            onSelect = function()
                TriggerServerEvent('rsg-moonshiner:server:openShop')
            end
        },
        {
            name = 'moonshiner_sell',
            label = 'Sell Moonshine & Mash',
            icon = 'fa-solid fa-hand-holding-usd',
            distance = 3.0,
            onSelect = function()
                TriggerServerEvent('rsg-moonshiner:server:openSellMenu')
            end
        },
        {
            name = 'moonshiner_talk',
            label = 'Talk to Moonshiner',
            icon = 'fa-solid fa-comment',
            distance = 3.0,
            onSelect = function()
                TriggerEvent('rsg-moonshiner:client:talkToNPC')
            end
        }
    })
    
    npcSpawned = true
    print("Moonshiner: NPC spawned successfully!")
end

-- Delete NPC
local function DeleteNPC()
    if npcPed then
        DeletePed(npcPed)
        npcPed = nil
        npcSpawned = false
        print("Moonshiner: NPC Deleted")
    end
end

-- Initialize NPC on resource start
CreateThread(function()
    if Config.NPCSettings.enabled then
        SetupBlip()
        Wait(1000) -- Wait a second for game to load
        SpawnNPC()
    end
end)

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        DeleteNPC()
        if npcBlip then
            RemoveBlip(npcBlip)
        end
    end
end)

-- Open Shop
RegisterNetEvent('rsg-moonshiner:client:openShop', function()
    TriggerServerEvent('rsg-moonshiner:server:openShop')
end)

-- Sell Products
RegisterNetEvent('rsg-moonshiner:client:sellProducts', function()
    TriggerServerEvent('rsg-moonshiner:server:openSellMenu')
end)

-- Talk to NPC
RegisterNetEvent('rsg-moonshiner:client:talkToNPC', function()
    local dialog = {
        "Howdy partner! Looking for some quality moonshine?",
        "I got everything you need to start your own operation.",
        "Best prices this side of the Dakota!",
        "Don't tell the law, but I can get you set up real nice.",
        "Fresh ingredients, quality equipment. What more could you want?",
        "Got some moonshine to sell? I'll pay you fair prices!",
        "Bring me your best brew, I'll make it worth your while."
    }
    
    local randomDialog = dialog[math.random(#dialog)]
    lib.notify({
        title = 'Moonshiner',
        description = randomDialog,
        type = 'inform',
        duration = 5000
    })
end)

-- Shop Menu
RegisterNetEvent('rsg-moonshiner:client:shopMenu', function()
    local shopMenu = {}
    
    for _, item in pairs(Config.ShopItems) do
        table.insert(shopMenu, {
            title = item.name,
            description = "Price: $" .. item.price,
            icon = "fa-solid fa-dollar-sign",
            onSelect = function()
                TriggerServerEvent("rsg-moonshiner:server:buyItem", {
                    item = item.name,
                    price = item.price
                })
            end
        })
    end
    
    -- Close Option (Optional, or handled by Backspace)
    table.insert(shopMenu, {
        title = "Close",
        icon = "fa-solid fa-xmark",
        onSelect = function()
            -- Just close
        end
    })
    
    ShowCustomMenu("Moonshiner Shop", shopMenu)
end)

-- Sell Menu
RegisterNetEvent('rsg-moonshiner:client:sellMenu', function(playerItems)
    local sellMenu = {}
    
    local hasItems = false
    
    -- Check player's inventory for sellable items
    for itemName, price in pairs(Config.SellPrices) do
        local hasItem = false
        local itemAmount = 0
        
        -- Check if player has this item
        for _, item in pairs(playerItems) do
            if item.name == itemName then
                hasItem = true
                itemAmount = item.amount
                break
            end
        end
        
        if hasItem and itemAmount > 0 then
            hasItems = true
            table.insert(sellMenu, {
                title = itemName,
                description = "Sell for $" .. price .. " each (You have: " .. itemAmount .. ")",
                icon = "fa-solid fa-whiskey-glass",
                onSelect = function()
                    TriggerServerEvent("rsg-moonshiner:server:sellItem", {
                        item = itemName,
                        price = price
                    })
                end
            })
        end
    end
    
    if not hasItems then
        table.insert(sellMenu, {
            title = "No Items to Sell",
            description = "You don't have any moonshine or mash to sell",
            icon = "fa-solid fa-exclamation-triangle",
            onSelect = function() end
        })
    end
    
    table.insert(sellMenu, {
        title = "Close",
        icon = "fa-solid fa-xmark",
        onSelect = function() end
    })
    
    ShowCustomMenu("Sell Products", sellMenu)
end)
