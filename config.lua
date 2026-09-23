SpeedZonesConfig = {
    pickupRadius = 20.0,
    startRadius = 18.0,
    minimumStartSpeedMph = 15,
    maxCheckpointSeconds = 120, -- speed zone will timeout if timer reaches this amount inbetween checkpoints
    maxValidationSpeedMph = 230,
    replayCompleted = true, -- lets players try beat their best. does not award cash or xp again on second runs
    incompleteBlipColour = 59,
    completedBlipColour = 66,
    activeBlipColour = 48,
}

-- you can make more speedzones here
SpeedZones = {
    {
        id = 'great_ocean_charge', -- whats shown in players db 
        name = 'Great Ocean Charge',
        start = vector3(-1505.52, 2091.74, 57.75),
        targetAverageMph = 98, 
        reward = { cash = 3500, playerXp = 275, vehicleXp = 150 },
        checkpoints = {
            vector3(-1426.78, 1917.88, 72.99),
            vector3(-1506.9, 1679.03, 98.92),
            vector3(-1547.45, 1411.39, 123.67),
            vector3(-1625.12, 1103.92, 151.38),
            vector3(-1784.14, 781.34, 137.44),
        },
    },
}
