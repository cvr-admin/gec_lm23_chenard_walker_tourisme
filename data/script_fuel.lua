-- Fuel system: tank damage (leakage) and fuel exhaustion simulation at low fuel levels.

require "script_car_parameters"

-- Shared state (globals)
fuelLeakageDamage = false
fuelExhCutLength = 0
fuelExhCutTimer = 0

-- Module-local state
local normalFuelConsumptionRate = acCarPhysics.fuelConsumption
local fuelExhState = 0
local fuelExhStartCount = 0
local fuelExhStartCounter = 0
local fuelDependentGForceThreshold = 0
local fuelExhInterval = 0
local fuelExhIntervalCounter = 0

function fuelTankDamage()
    local cumulativeDamage = 0

    for i = 0, 3 do
        if fuelLeakageDamageSides[i + 1] then
            cumulativeDamage = cumulativeDamage + thisCar.damage[i]
        end
    end

    printDebug("Cumulative damage for fuel leakage", cumulativeDamage)

    if cumulativeDamage > fuelLeakageDamageThreshold then
        local fuelConsumptionRate = normalFuelConsumptionRate + cumulativeDamage / 100

        if fuelConsumptionRate > 1 then
            fuelConsumptionRate = 1
        end

        ac.setFuelConsumption(fuelConsumptionRate)
        printDebug("Fuel consumption rate", fuelConsumptionRate)
        fuelLeakageDamage = true
    else
        ac.setFuelConsumption(normalFuelConsumptionRate)
        printDebug("Fuel consumption rate", normalFuelConsumptionRate)
        fuelLeakageDamage = false
    end
end

function fuelExhaustion()
    printDebug("Fuel, fuelExhState", fuelExhState)
    -- Adjust the g-force threshold based on the current fuel level. The less fuel we have,
    -- the easier it is to trigger a stall.
    fuelDependentGForceThreshold = fuelExhaustionGForceThreshold * (thisCar.fuel / fuelExhaustionAmount)
    printDebug("Fuel, G-force", fuelDependentGForceThreshold)

    -- Idle state.
    if fuelExhState == 0 then
        if math.abs(acCarPhysics.gForces.x) > fuelDependentGForceThreshold and thisCar.fuel < fuelExhaustionAmount then
            fuelExhStartCount = thisCar.fuel
            fuelExhStartCounter = 0
            fuelExhCutLength = 0
            fuelExhInterval = 0
            fuelExhIntervalCounter = 0
            fuelExhState = 10
        end
    -- Stall detection state. Wait for enough g-force events to trigger a stall. The less we have fuel,
    -- the easier it is to trigger a stall.
    elseif fuelExhState == 10 then
        if math.abs(acCarPhysics.gForces.x) > fuelDependentGForceThreshold then
            fuelExhStartCounter = fuelExhStartCounter + 1
        else
            fuelExhStartCounter = 0
            fuelExhState = 0
        end

        if fuelExhStartCounter >= fuelExhStartCount then
            fuelExhCutLength = math.random() * (fuelExhaustionAmount - thisCar.fuel) / fuelExhaustionAmount / 2
            -- Take the speed of the car into account: under 100 km/h the cut length is minimal, but at higher speeds
            -- the cut length increases quadratically.
            fuelExhCutLength = fuelExhCutLength + (thisCar.speedKmh / 100) ^ 2
            printDebug("Fuel, cut length", fuelExhCutLength)
            fuelExhInterval = math.random() * 2
            fuelExhState = 20
        end
    -- Fuel cut active state.
    elseif fuelExhState == 20 then
        if fuelExhCutLength == 0 then
            if fuelExhIntervalCounter > fuelExhInterval then
                fuelExhState = 0
            else
                fuelExhIntervalCounter = fuelExhIntervalCounter + 0.1
            end
        end
    end
end
