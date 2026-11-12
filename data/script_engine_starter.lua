-- Engine ignition and stalling simulation.
-- Handles cranking, starting delays (hand-crank, push-start), and engine stall physics.

require "script_car_parameters"

local carState = { ignition = false, cranking = false, crankTimer = 0, stalling = false, stallRPM = 0 }
local carInfo = {
    idleRPM = ac.INIConfig.carData(0, 'engine.ini'):get('ENGINE_DATA', 'MINIMUM', engineIdleRpm),
    starterRPM = engineIdleRpm + 700
}

ac.setEngineStalling(true)
local starterTorque = 40.0
ac.setEngineStarterTorque(0)

local function applyLag(current, target, factor, dt)
    return current + (target - current) * factor * dt
end

local function getRandomStartTime() return math.random(1, 5) end
local function getFluctuatingRPM() return math.random(300, 700) end

local timeToStart = getRandomStartTime()
local teleportPrevExtraA = false

function engineStaller(dt)
    -- engine stalling / ignition functions
    local inputs = { ignition = car.extraA, clutch = acCarPhysics.clutch }
    local fixingOngoing = fuelPumpRepairInProgress or gearboxRepairInProgress

    if car.extraA and carHasTeleportedToPits then
        if car.extraA and not teleportPrevExtraA then
            overheadMessageQueue("START DISABLED", "You have teleported to the pits, race restart is not allowed", 3)
        end
        inputs.ignition = false
    end
    teleportPrevExtraA = car.extraA

    -- Cranking Logic
    if inputs.ignition and not carState.ignition and not fixingOngoing then
        carState.cranking = true
        carState.crankTimer = carState.crankTimer + dt
        ac.setEngineStarterTorque(starterTorque)

        -- push start simulation: add ~10-12 secs to timeToStart - also add hand crank penalty if not in the pits or on the grid
        -- Electro starter or on grid/in pits: as it was. Crank start elsewhere: a little bit longer. Push start for stalled hybrids out in the wild: much longer.
        local pushStartTimer = 0
        local onGrid = (ac.getSim().raceSessionType == ac.SessionType.Race and not ac.getSim().isSessionStarted)
        if not onGrid and not (thisCar.isInPitlane and thisCar.isInPit) then    -- fast starts if on grid and in pits - will have human or mechanical help there
            if ignitionType == 3 then       -- push start for stalled hybrids with flat battery
                if (acCarPhysics.controllerInputs[44] or 1) <= 0.05 then
                    pushStartTimer = math.random(8,12)
                    overheadMessageQueue("PUSH STARTING", "...because the battery is empty. This may take a good while longer.", 1, true)
                end
            end
            if (ignitionType or 1) < 2 then       -- crank start for stalled magneto or undefined types
                    pushStartTimer = math.random(4,6)
                    overheadMessageQueue("CRANK STARTING", "This may take a bit longer.", 1, true)
            end
        end


        if carState.crankTimer < (timeToStart + pushStartTimer) then
            -- Simulate fluctuating RPM between 400 and 600
            ac.setEngineRPM(getFluctuatingRPM())
        else
            -- Set RPM to starterRPM when timeToStart is reached
            ac.setEngineRPM(carInfo.starterRPM)
            carState.ignition = true
            carState.cranking = false
            ac.setEngineStarterTorque(0)
        end
    else
        carState.cranking = false
        carState.crankTimer = 0
    end

    printDebug("Ignition Time", timeToStart)

    -- Running and Stalling Logic
    if carState.ignition then
        if acCarPhysics.rpm < carInfo.idleRPM * 0.9 then -- Adjusted threshold to avoid premature stalling
            carState.ignition = false
            carState.stalling = true
            carState.stallRPM = acCarPhysics.rpm
        else
            -- Stabilize idle RPM
            acCarPhysics.rpm = math.max(acCarPhysics.rpm, carInfo.idleRPM)
        end
    elseif carState.stalling then
        carState.stallRPM = applyLag(carState.stallRPM, 0, 2.0, dt)
        ac.setEngineRPM(carState.stallRPM)
        if carState.stallRPM < 10 then
            carState.stalling = false
            timeToStart = getRandomStartTime()
        end
    else
        if not carState.cranking then ac.setEngineRPM(0) end
    end

    acCarPhysics.controllerInputs[5] = carInfo.idleRPM
    acCarPhysics.controllerInputs[6] = acCarPhysics.rpm

-- engine stalling / ignition functions end
end
