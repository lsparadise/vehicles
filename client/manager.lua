RESOURCE_NAME = GetCurrentResourceName()

local ANIMATION_DICTIONARY = 'anim@mp_player_intmenu@key_fob@'
local KEY_PROP = 'lr_prop_carkey_fob'
local AUTHORIZED_VEHICLES = json.decode(LoadResourceFile(RESOURCE_NAME, 'data/authorizedVehicles.json'))
local COLLISION_DAMAGE_MULTIPLIER = tonumber(GetConvar('collisionDamageMultiplier', '4.0'))
local DEFORMATION_DAMAGE_MULTIPLIER = tonumber(GetConvar('deformationDamageMultiplier', '1.25'))
local ENGINE_DAMAGE_MULTIPLIER = tonumber(GetConvar('engineDamageMultiplier', '2.0'))
local DISABLE_RADAR = GetConvarInt('disableRadar', 1)
local DISABLE_RADIO = GetConvarInt('disableRadio', 0)
local MAX_ROLL = tonumber(GetConvar('maxRoll', '80.0'))
local LANG = GetConvar('lang', 'en')

local authorizedVehicles = AUTHORIZED_VEHICLES
local registeredFunctions = {}
local hasGpsCallback = function () return true end

local locale = nil
local localeFile = LoadResourceFile(RESOURCE_NAME, 'locale/'.. LANG ..'.json')
if localeFile then
    locale = json.decode(localeFile)
else
    locale = json.decode(LoadResourceFile(RESOURCE_NAME, 'locale/en.json'))
end

local animationFlags = {
    loop = 1 << 0,
    freezeWhenFinish = 1 << 1,
    upperBody = 1 << 4,
    keepControl = 1 << 5,
    playOnlyWhenIdle = 1 << 7,
    revertBones = 1 << 8,
    lockPosition = 1 << 9,
    deadWhenFinished = 1 << 21,
}
local flagsIndex = {
    withPolice = 0,
    withNotAutoGenerated = 1,
    hasPedInside = 2,
    hasPlayerInside = 4,
    exclusivelyPolice = 10,
    heli = 12,
    boat = 13,
    plane = 14,
    isBusy = 16,
    trailer = 17,
    blimp = 18,
}
local allFlags = {
    withPolice = 1 << flagsIndex.withPolice,
    withNotAutoGenerated = 1 << flagsIndex.withNotAutoGenerated,
    hasPedInside = 1 << flagsIndex.hasPedInside,
    hasPlayerInside = 1 << flagsIndex.hasPlayerInside,
    exclusivelyPolice = 1 << flagsIndex.exclusivelyPolice,
    heli = 1 << flagsIndex.heli,
    boat = 1 << flagsIndex.boat,
    plane = 1 << flagsIndex.plane,
    isBusy = 1 << flagsIndex.isBusy,
    trailer = 1 << flagsIndex.trailer,
    blimp = 1 << flagsIndex.blimp,
}
local allVehicles = {
    notFlyingVehicles = {
        withPolice = true,
        withNotAutoGenerated = true,
        hasPedInside = true,
        hasPlayerInside = true,
        isBusy = true,
        trailer = true,
    },
    flyingVehicles = {
        withPolice = true,
        withNotAutoGenerated = true,
        hasPedInside = true,
        hasPlayerInside = true,
        heli = true,
        plane = true,
        isBusy = true,
        blimp = true,
    },
    boatVehicles = {
        withPolice = true,
        withNotAutoGenerated = true,
        hasPedInside = true,
        hasPlayerInside = true,
        boat = true,
        isBusy = true,
    },
}

AddEventHandler('onClientResourceStart', function (resource)
    if resource == RESOURCE_NAME then
        repeat Wait(100) until PlayerPedId()
        if DISABLE_RADAR and IsMinimapRendering() and not IsPedInAnyVehicle(PlayerPedId()) then
            DisplayRadar(false)
        end
    end
end)

AddEventHandler('gameEventTriggered', function (name, data)
    if name == 'CEventNetworkPlayerEnteredVehicle' then
        local player, vehicle = table.unpack(data)
        if player == PlayerId() then
            TriggerEvent('vehicle:player:entered', vehicle)
        end
    end
end)

AddEventHandler('vehicle:player:entered', function (vehicle)
    local playerPed = PlayerPedId()
    local model = GetEntityModel(vehicle)
    if not Entity(vehicle).state.handlingChanged then
        SetVehicleHandlingFloat(
            vehicle,
            'CHandlingData',
            'fCollisionDamageMult',
            GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fCollisionDamageMult') * COLLISION_DAMAGE_MULTIPLIER
        )
        SetVehicleHandlingFloat(
            vehicle,
            'CHandlingData',
            'fDeformationDamageMult',
            GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fDeformationDamageMult') * DEFORMATION_DAMAGE_MULTIPLIER
        )
        SetVehicleHandlingFloat(
            vehicle,
            'CHandlingData',
            'fEngineDamageMult',
            GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fEngineDamageMult') * ENGINE_DAMAGE_MULTIPLIER
        )
        Entity(vehicle).state:set('handlingChanged', true, false)
    end
    RollUpWindow(vehicle, 0)
    RollUpWindow(vehicle, 1)
    if DISABLE_RADAR and hasGps() then
        DisplayRadar(true)
    end
    SetVehicleRadioEnabled(vehicle, not DISABLE_RADIO)
    for name, vehFunction in pairs(registeredFunctions) do
        if vehFunction.entered then
            registeredFunctions[name].data = vehFunction.entered(vehicle, registeredFunctions[name].data)
        end
    end
    CreateThread(function ()
        while true do
            local roll = GetEntityRoll(vehicle)
            if not IsPedInAnyVehicle(playerPed) or not DoesEntityExist(vehicle) then
                if DISABLE_RADAR and not IsRadarHidden() then
                    DisplayRadar(false)
                end
                for name, vehFunction in pairs(registeredFunctions) do
                    if vehFunction.exited then
                        registeredFunctions[name].data = vehFunction.exited(vehicle, registeredFunctions[name].data)
                    end
                end
                TriggerEvent('vehicle:player:left', vehicle)
                return
            end
            if
                GetPedInVehicleSeat(vehicle, -1) == playerPed
                and (IsEntityInAir(vehicle) or roll > MAX_ROLL or roll < -MAX_ROLL)
                and not IsThisModelABoat(model)
                and not IsThisModelAHeli(model)
                and not IsThisModelAJetski(model)
                and not IsThisModelAPlane(model)
                and not authorizedVehicles[tostring(model)]
            then
                DisableControlAction(0, 59, true)
                DisableControlAction(0, 60, true)
            end
            for name, vehFunction in pairs(registeredFunctions) do
                if vehFunction.looped then
                    registeredFunctions[name].data = vehFunction.looped(vehicle, registeredFunctions[name].data)
                end
            end
            Wait(0)
        end
    end)
end)

local function registerHasGps(callback)
    hasGpsCallback = callback
end

local function overrideAuthorizedVehicles(vehicles)
    authorizedVehicles = vehicles
end

local function resetAuthorizedVehicles()
    authorizedVehicles = AUTHORIZED_VEHICLES
end

function registerFunction(name, data, entered, looped, exited)
    if not registeredFunctions[name] then
        registeredFunctions[name] = {
            data = data,
            entered = entered,
            looped = looped,
            exited = exited
        }
    end
end

function getLocale()
    return locale
end

function getVehicleAhead(options)
    if not options then
        options = {}
    end
    if not options.radius then
        options.radius = 2.75
    end
    if not options.distance then
        options.distance = 1.66
    end
    if not options.model then
        options.model = 0
    else
        if type(options.model) == 'string' then
            options.model = GetHashKey(options.model)
        end
    end
    if not options.position then
        local playerPed = PlayerPedId()
        options.position = GetEntityCoords(playerPed) + GetEntityForwardVector(playerPed) * options.distance
    end
    for _, vehicles in pairs(allVehicles) do
        local flag = 0
        for name, state in pairs(vehicles) do
            if state and allFlags[name] then
                flag = flag | allFlags[name]
            end
        end
        if IsAnyVehicleNearPoint(options.position, options.radius) then
            local vehicle = GetClosestVehicle(options.position.x, options.position.y, options.position.z, options.radius, options.model, flag)
            if DoesEntityExist(vehicle) then
                return vehicle
            end
        end
    end
    return nil
end

function hasGps()
    return hasGpsCallback()
end

function getVehicleFromNetId(netId, force)
    if NetworkDoesNetworkIdExist(tonumber(netId)) then
        local vehicle = NetToVeh(netId)
        if force or GetPedInVehicleSeat(vehicle, -1) == PlayerPedId() then
            return vehicle
        end
    end
    return nil
end

function control(entity, callback, maxWait)
    if not DoesEntityExist(entity) then
        return
    end
    if maxWait == nil then
        maxWait = 1000
    end
    local endTimer = GetGameTimer() + maxWait
    NetworkRequestControlOfEntity(entity)
    repeat Wait(0) until NetworkHasControlOfEntity(entity) or GetGameTimer() > endTimer
    if NetworkHasControlOfEntity(entity) and callback then
        callback()
    end
end

function playKeyAnimation(onPed)
    while not HasAnimDictLoaded(ANIMATION_DICTIONARY) do
        RequestAnimDict(ANIMATION_DICTIONARY)
        Wait(0)
    end
    while not HasModelLoaded(KEY_PROP) do
        RequestModel(KEY_PROP)
        Wait(0)
    end
    local x, y, z = table.unpack(GetEntityCoords(onPed))
    local key = CreateObject(KEY_PROP, x, y, z + 0.2, true, true, true)
    SetEntityAsMissionEntity(key, true, true)
    AttachEntityToEntity(key, onPed, GetPedBoneIndex(onPed, 57005), 0.14, 0.04, -0.0175, -110.0, 95.0, -10.0, true, true, false, true, 1, true)
    TaskPlayAnim(onPed, ANIMATION_DICTIONARY, 'fob_click_fp', 8.0, 8.0, -1, animationFlags.keepControl | animationFlags.upperBody, 1, false, false, false)
    CreateThread(function()
        Wait(1200)
        SetModelAsNoLongerNeeded(KEY_PROP)
        RemoveAnimDict(ANIMATION_DICTIONARY)
        DetachEntity(key, false, false)
        DeleteObject(key)
    end)
end

exports('registerFunction', registerFunction)
exports('registerHasGps', registerHasGps)
exports('overrideAuthorizedVehicles', overrideAuthorizedVehicles)
exports('resetAuthorizedVehicles', resetAuthorizedVehicles)
exports('getLocale', getLocale)
exports('getVehicleAhead', getVehicleAhead)
exports('hasGps', hasGps)
