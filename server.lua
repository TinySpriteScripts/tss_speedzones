local MPS_TO_MPH = 2.236936
local sessions = {}
local locks = {}
local zonesById = {}

local function distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

for _, zone in ipairs(SpeedZones) do
    local total, previous = 0.0, zone.start
    for _, point in ipairs(zone.checkpoints) do
        total = total + distance(previous, point)
        previous = point
    end
    zone.routeDistanceMeters = total
    zonesById[zone.id] = zone
end

local function completedFor(source)
    local value = exports.streetkings:ReadSaveData(source, 'speedZones.completed')
    return type(value) == 'table' and value or {}
end

local function driverNear(source, point, radius)
    local ped = GetPlayerPed(source)
    if ped == 0 then return false end
    local vehicle = GetVehiclePedIsIn(ped, false)
    return vehicle ~= 0
        and GetPedInVehicleSeat(vehicle, -1) == ped
        and distance(GetEntityCoords(ped), point) <= radius
end

lib.callback.register('tss_speedzones:progress', function(source)
    if not exports.streetkings:HasActiveSave(source) then return {} end
    return completedFor(source)
end)

lib.callback.register('tss_speedzones:begin', function(source, zoneId)
    local zone = zonesById[zoneId]
    if not zone or not exports.streetkings:HasActiveSave(source) then return { ok = false } end
    if exports.streetkings:GetPlayerGameState(source) ~= 'freeroam' then return { ok = false } end
    if not driverNear(source, zone.start, SpeedZonesConfig.startRadius + 8.0) then return { ok = false } end

    local completed = completedFor(source)[zoneId] == true
    if completed and not SpeedZonesConfig.replayCompleted then return { ok = false } end

    sessions[source] = {
        zoneId = zoneId,
        startedAt = GetGameTimer(),
        lastCheckpointAt = GetGameTimer(),
        lastPoint = zone.start,
        nextCheckpoint = 1,
    }
    return { ok = true, completedBefore = completed, routeDistanceMeters = zone.routeDistanceMeters }
end)

lib.callback.register('tss_speedzones:checkpoint', function(source, zoneId, index)
    local run, zone = sessions[source], zonesById[zoneId]
    if not run or run.zoneId ~= zoneId or not zone or index ~= run.nextCheckpoint then return false end
    if exports.streetkings:GetPlayerGameState(source) ~= 'freeroam' then sessions[source] = nil return false end
    local point = zone.checkpoints[index]
    if not point or not driverNear(source, point, SpeedZonesConfig.pickupRadius + 8.0) then return false end
    local now = GetGameTimer()
    local segmentSeconds = (now - run.lastCheckpointAt) / 1000.0
    if segmentSeconds > SpeedZonesConfig.maxCheckpointSeconds then
        sessions[source] = nil
        return false
    end
    local segmentMph = (distance(run.lastPoint, point) / math.max(segmentSeconds, 0.001)) * MPS_TO_MPH
    if segmentSeconds < 0.2 or segmentMph > SpeedZonesConfig.maxValidationSpeedMph then
        sessions[source] = nil
        return false
    end
    run.lastCheckpointAt = now
    run.lastPoint = point
    run.nextCheckpoint = run.nextCheckpoint + 1
    return true
end)

lib.callback.register('tss_speedzones:finish', function(source, zoneId)
    if locks[source] then return { ok = false } end
    locks[source] = true
    local run, zone = sessions[source], zonesById[zoneId]
    if not run or run.zoneId ~= zoneId or not zone or run.nextCheckpoint ~= #zone.checkpoints + 1 then
        locks[source] = nil
        return { ok = false }
    end
    sessions[source] = nil

    local elapsed = (GetGameTimer() - run.startedAt) / 1000.0
    local average = (zone.routeDistanceMeters / math.max(elapsed, 0.001)) * MPS_TO_MPH
    if average > SpeedZonesConfig.maxValidationSpeedMph then
        locks[source] = nil
        return { ok = false }
    end

    local passed = average >= zone.targetAverageMph
    local completed = completedFor(source)
    local alreadyCompleted = completed[zoneId] == true
    local reward

    exports.streetkings:RecordActivityBest(source, 'speedzone_' .. zoneId, math.floor(average + 0.5), 'speed')

    if passed and not alreadyCompleted then
        completed[zoneId] = true
        if not exports.streetkings:WriteSaveData(source, 'speedZones.completed', completed) then
            locks[source] = nil
            return { ok = false }
        end
        local cfg = zone.reward
        if cfg.cash > 0 then exports.streetkings:AddPlayerCash(source, cfg.cash) end
        local player = cfg.playerXp > 0 and exports.streetkings:AwardPlayerXp(source, cfg.playerXp) or nil
        local vehicle = cfg.vehicleXp > 0 and exports.streetkings:AwardVehicleXp(source, cfg.vehicleXp) or nil
        exports.streetkings:IncrementStat(source, 'speedZonesCompleted', 1)
        exports.streetkings:SetStatMax(source, 'bestSpeedZoneAverageMph', math.floor(average + 0.5))
        reward = {
            cash = { amount = cfg.cash },
            player = player,
            vehicle = vehicle,
        }
    else
        exports.streetkings:SetStatMax(source, 'bestSpeedZoneAverageMph', math.floor(average + 0.5))
    end

    locks[source] = nil
    return {
        ok = true,
        elapsed = elapsed,
        averageMph = average,
        passed = passed,
        newlyCompleted = passed and not alreadyCompleted,
        alreadyCompleted = alreadyCompleted,
        reward = reward,
    }
end)

RegisterNetEvent('tss_speedzones:cancel', function(zoneId)
    local source = source --[[@as integer]]
    if sessions[source] and (not zoneId or sessions[source].zoneId == zoneId) then sessions[source] = nil end
end)

AddEventHandler('playerDropped', function()
    sessions[source] = nil
    locks[source] = nil
end)

CreateThread(function()
    Wait(0)
    exports.streetkings:RegisterStat('speedZonesCompleted')
    exports.streetkings:RegisterStat('bestSpeedZoneAverageMph')
end)
