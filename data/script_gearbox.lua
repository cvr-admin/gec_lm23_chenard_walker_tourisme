-- Gearbox failure simulation and in-pit repair.

require "script_car_parameters"

-- Shared state (global, reset by initDeadGears/resetCar)
deadGears = {} --dead gears, boolean array

-- AC uses 1=neutral, 2=1st gear, etc.
function getCurrentGearIndex()
    return acCarPhysics.gear - 1
end

-- Initialize deadGears array - index 1 for 1st gear, etc.
function initDeadGears()
    for i = 1, thisCar.gearCount do
        deadGears[i] = false
    end
end

-- Function to adjust gear failure rate dynamically
function updateGearFailureRate(gearboxDamageValue)
    -- Ensure gearboxDamage is within valid range (0 to 1)
    gearboxDamageValue = math.clamp(gearboxDamageValue, 0, 1)

    if gearboxDamageValue > 0.5 then
        boostedGearFailureRate = gearFailureRate / 3  -- Increase failure chance
    else
        boostedGearFailureRate = gearFailureRate  -- Reset to base rate
    end
end

function gearboxFailure()
    local currentGearIndex = getCurrentGearIndex()
    if currentGearIndex > 0 and math.random(1, boostedGearFailureRate) == 1 then
        deadGears[currentGearIndex] = true  -- Mark gear as dead
        overheadMessageQueue("GEAR FAILURE", "Gear "..(currentGearIndex).." has failed!", 5)
        logDebug("<FLR>Gear Fail, gear: ", currentGearIndex, ", rate: ", boostedGearFailureRate, true)
    end
end

function gearboxFailureHshifter(tick)
    local currentGearIndex = getCurrentGearIndex()
    -- this factor increases the failure chance for h-shifters to make it more likely to see failures in a reasonable time frame. The actual per-2s failure chance is boostedGearFailureRate / hShifterGearFailFactor, and the per-dt chance is calculated from that.
    local hShifterGearFailFactor = 2833     -- 2833 gives an average failure time of 60s when boostedGearFailureRate is 85000; 1420 ~120s; very conservative, but one has to start somewhere
    local p = (tick) / (2 * (boostedGearFailureRate / hShifterGearFailFactor)) -- this would be the faster approximation; use below for accuracy
    --local q = 1 / (boostedGearFailureRate / hShifterGearFailFactor)
    --local p = 1 - (1 - q)^(tick / 2)

    if currentGearIndex > 0 and not deadGears[currentGearIndex] and math.random() < p then
        deadGears[currentGearIndex] = true  -- Mark gear as dead
        overheadMessageQueue("GEAR FAILURE (H-Shifter)", "Gear "..(currentGearIndex).." has failed!", 5)
        logDebug("<FLR>Gear Fail, gear: ", currentGearIndex, ", rate: ", boostedGearFailureRate, true)
    end
end

function isAnyGearBroken()
    for i = 1, thisCar.gearCount do
        if deadGears[i] then
            return true
        end
    end
    return false
end

-- In-pit gearbox repair routine. Call from update() when car is in pits.
function gearboxPitRepair(dt)
    if isCarInPits and not fuelPumpRepairInProgress then
        local needsRepair = false
        for i = 1, thisCar.gearCount do
            if deadGears[i] then
                needsRepair = true
                break
            end
        end

        if needsRepair then
            if thisCar.extraB and not gearboxRepairInProgress then
                gearboxRepairInProgress = true
                gearboxPitTimer = 0
                overheadMessageQueue("Gearbox Repair", "Repair started. Hold position!", 3)
            end

            if gearboxRepairInProgress then
                gearboxPitTimer = gearboxPitTimer + dt
                ac.setSystemMessage("Gearbox Repair",
                    string.format("Progress: %.1f%%",
                    (gearboxPitTimer/gearboxRepairTime)*100))

                -- Complete repair
                if gearboxPitTimer >= gearboxRepairTime then
                    initDeadGears()
                    gearboxRepairInProgress = false
                    gearboxRepairTime = math.random(30, 180)
                    overheadMessageQueue("GEARBOX REPAIRED", "All gears restored!", 5)
                end
            end
        end
    end
end

-- Initialise on load
initDeadGears()
