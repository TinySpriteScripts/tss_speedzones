local MPS_TO_MPH = 2.236936
local CHECKPOINT_SIZE = 12.0
local CHECKPOINT_ALPHA = 55
local CHECKPOINT_RADIUS = SpeedZonesConfig.pickupRadius
local startBlips, completed = {}, {}
local activeRun, lastFreeroam = nil, false

local function notify(title, kind)
    exports.streetkings:ShowNotification({ title = title, type = kind or 'info', duration = 3500 })
end

local function distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function setBlipName(blip, name)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(name)
    EndTextCommandSetBlipName(blip)
end

local function refreshStartBlip(zone)
    local blip = startBlips[zone.id]
    if not blip then
        blip = AddBlipForCoord(zone.start.x, zone.start.y, zone.start.z)
        SetBlipSprite(blip, 827)
        SetBlipScale(blip, 0.9)
        SetBlipAsShortRange(blip, false)
        SetBlipDisplay(blip, 4)
        startBlips[zone.id] = blip
    end
    local done = completed[zone.id] == true
    SetBlipColour(blip, done and SpeedZonesConfig.completedBlipColour or SpeedZonesConfig.incompleteBlipColour)
    setBlipName(blip, (done and 'Completed: ' or 'Speed Zone: ') .. zone.name)
end

local function setupBlips()
    completed = lib.callback.await('tss_speedzones:progress', false) or {}
    AddTextEntry('BLIP_CAT_23', 'Speed Zones')
    for _, zone in ipairs(SpeedZones) do
        refreshStartBlip(zone)
        SetBlipCategory(startBlips[zone.id], 23)
    end
end

local function clearStartBlips()
    for id, blip in pairs(startBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
        startBlips[id] = nil
    end
end

local function clearCheckpoint(run)
    if run.checkpoint then DeleteCheckpoint(run.checkpoint) end
    if run.blip and DoesBlipExist(run.blip) then RemoveBlip(run.blip) end
    if run.nextBlip and DoesBlipExist(run.nextBlip) then RemoveBlip(run.nextBlip) end
    if run.waypointId then exports.streetkings:RemoveWaypoint(run.waypointId) end
    run.checkpoint, run.blip, run.nextBlip, run.waypointId = nil, nil, nil, nil
end

local function clearGps()
    ClearGpsMultiRoute()
end

local function showCheckpoint(run, index)
    clearCheckpoint(run)
    local points, point = run.zone.checkpoints, run.zone.checkpoints[index]
    local nextPoint, isLast = points[index + 1], index == #points
    local z = point.z - 1.0
    local nx, ny, nz = point.x, point.y, z
    if nextPoint then nx, ny, nz = nextPoint.x, nextPoint.y, nextPoint.z - 1.0 end

    run.checkpoint = CreateCheckpoint(isLast and 4 or 0, point.x, point.y, z, nx, ny, nz,
        CHECKPOINT_SIZE, 255, 210, 0, CHECKPOINT_ALPHA, 0)
    run.blip = AddBlipForCoord(point.x, point.y, point.z)
    SetBlipSprite(run.blip, isLast and 38 or 1)
    SetBlipScale(run.blip, isLast and 1.1 or 1.05)
    SetBlipColour(run.blip, SpeedZonesConfig.activeBlipColour)
    SetBlipRoute(run.blip, true)
    SetBlipRouteColour(run.blip, SpeedZonesConfig.activeBlipColour)
    setBlipName(run.blip, isLast and 'Speed Zone Finish' or 'Speed Zone Checkpoint')

    if nextPoint then
        run.nextBlip = AddBlipForCoord(nextPoint.x, nextPoint.y, nextPoint.z)
        SetBlipSprite(run.nextBlip, index + 1 == #points and 38 or 1)
        SetBlipScale(run.nextBlip, 0.72)
        SetBlipColour(run.nextBlip, SpeedZonesConfig.activeBlipColour)
    end

    run.waypointId = exports.streetkings:CreateWaypoint({
        coords = point,
        text = isLast and 'FINISH' or 'CHECKPOINT',
        color = '#ffd200',
        icon = isLast and 'flag-checkered' or 'circle-dot',
        showDist = true,
        groundBeam = true,
    })

    ClearGpsMultiRoute()
    StartGpsMultiRoute(6, false, true)
    local previous = index == 1 and run.zone.start or points[index - 1]
    AddPointToGpsMultiRoute(previous.x, previous.y, previous.z)
    for i = index, #points do
        local cp = points[i]
        AddPointToGpsMultiRoute(cp.x, cp.y, cp.z)
    end
    SetGpsMultiRouteRender(true)
end

local function cleanupRun(cancelServer)
    local run = activeRun
    if not run then return end
    if cancelServer then TriggerServerEvent('tss_speedzones:cancel', run.zone.id) end
    clearCheckpoint(run)
    clearGps()
    SendNUIMessage({ type = 'hide' })
    activeRun = nil
end

local function waitForResultsDismiss()
    local deadline = GetGameTimer() + 15000
    while GetGameTimer() < deadline do
        if IsControlJustReleased(0, 51) or IsDisabledControlJustReleased(0, 51) then break end
        Wait(0)
    end
    SendNUIMessage({ type = 'hide' })
end

local function finishRun(run)
    clearCheckpoint(run)
    clearGps()
    SendNUIMessage({ type = 'timerStop' })
    local result = lib.callback.await('tss_speedzones:finish', false, run.zone.id)
    activeRun = nil
    if not result or not result.ok then
        notify('Speed zone run could not be validated', 'error')
        SendNUIMessage({ type = 'hide' })
        return
    end

    if result.newlyCompleted then
        completed[run.zone.id] = true
        refreshStartBlip(run.zone)
    end

    SendNUIMessage({
        type = 'results',
        name = run.zone.name,
        average = result.averageMph,
        target = run.zone.targetAverageMph,
        passed = result.passed,
        newlyCompleted = result.newlyCompleted,
        alreadyCompleted = result.alreadyCompleted,
        reward = result.reward,
    })
    CreateThread(waitForResultsDismiss)
end

local function runZone(zone, begin)
    local run = {
        zone = zone,
        startedAt = GetGameTimer(),
        lastCheckpointAt = GetGameTimer(),
        index = 1,
        coveredMeters = 0.0,
        previous = zone.start,
        routeDistanceMeters = begin.routeDistanceMeters,
    }
    activeRun = run
    if startBlips[zone.id] then SetBlipAlpha(startBlips[zone.id], 100) end
    SendNUIMessage({ type = 'timerStart', name = zone.name, target = zone.targetAverageMph, current = 1, total = #zone.checkpoints })
    showCheckpoint(run, 1)

    CreateThread(function()
        while activeRun == run do
            if exports.streetkings:GetGameState() ~= 'freeroam' then
                cleanupRun(true)
                return
            end
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)
            if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped or IsEntityDead(ped) then
                notify('Speed zone cancelled', 'warning')
                cleanupRun(true)
                return
            end
            local elapsed = (GetGameTimer() - run.startedAt) / 1000.0
            if (GetGameTimer() - run.lastCheckpointAt) > SpeedZonesConfig.maxCheckpointSeconds * 1000 then
                notify('Speed zone timed out', 'warning')
                cleanupRun(true)
                return
            end
            local point = zone.checkpoints[run.index]
            local pos = GetEntityCoords(ped)
            local segmentLength = distance(run.previous, point)
            local progress = math.max(0.0, math.min(segmentLength, segmentLength - distance(pos, point)))
            local liveAverage = ((run.coveredMeters + progress) / math.max(elapsed, 0.1)) * MPS_TO_MPH
            SendNUIMessage({ type = 'timerTick', average = liveAverage, target = zone.targetAverageMph })
            Wait(100)
        end
    end)

    while activeRun == run do
        local point = zone.checkpoints[run.index]
        if #(GetEntityCoords(PlayerPedId()) - point) <= CHECKPOINT_RADIUS then
            local accepted = lib.callback.await('tss_speedzones:checkpoint', false, zone.id, run.index)
            if not accepted then
                notify('Speed zone checkpoint rejected', 'error')
                cleanupRun(true)
                return
            end
            PlaySoundFrontend(-1, 'CHECKPOINT_AHEAD', 'HUD_MINI_GAME_SOUNDSET', true)
            TriggerEvent('streetkings:nitrous:checkpointCleared')
            run.coveredMeters = run.coveredMeters + distance(run.previous, point)
            run.previous = point
            run.lastCheckpointAt = GetGameTimer()
            if run.index == #zone.checkpoints then
                finishRun(run)
                return
            end
            run.index = run.index + 1
            SendNUIMessage({ type = 'progress', current = run.index, total = #zone.checkpoints })
            showCheckpoint(run, run.index)
        end
        Wait(0)
    end
end

local function canStart(zone, vehicle)
    if GetEntitySpeed(vehicle) * MPS_TO_MPH < SpeedZonesConfig.minimumStartSpeedMph then return false end
    local toward = zone.checkpoints[1] - zone.start
    local forward = GetEntityForwardVector(vehicle)
    return (forward.x * toward.x + forward.y * toward.y) > 0.0
end

CreateThread(function()
    while true do
        local freeroam = exports.streetkings:GetGameState() == 'freeroam'
        if freeroam and not lastFreeroam then setupBlips() end
        if not freeroam and lastFreeroam then
            if activeRun then cleanupRun(true) end
            clearStartBlips()
        end
        lastFreeroam = freeroam

        if freeroam and not activeRun then
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)
            if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
                local pos = GetEntityCoords(ped)
                for _, zone in ipairs(SpeedZones) do
                    if #(pos - zone.start) <= SpeedZonesConfig.startRadius and canStart(zone, vehicle) then
                        local begin = lib.callback.await('tss_speedzones:begin', false, zone.id)
                        if begin and begin.ok then
                            CreateThread(function() runZone(zone, begin) end)
                        end
                        break
                    end
                end
            end
        end
        Wait(activeRun and 500 or 200)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if activeRun then cleanupRun(true) end
    clearStartBlips()
end)

RegisterNetEvent('tss_speedzones:progressReset', function()
    completed = {}
    for _, zone in ipairs(SpeedZones) do
        if startBlips[zone.id] then refreshStartBlip(zone) end
    end
end)
