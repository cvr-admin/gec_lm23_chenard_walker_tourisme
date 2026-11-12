-- Change failure rates based on driving conditions and driver actions.
--
-- Overrevving
--  * Increase spark plug failure possibility
--  * Increase fuel pump failure
--  * Increase oil pressure problems
--  * Increase valve damage possibility in high revs
--
-- At low rpm
--  * Increase spark plug failure
--  * Increase fuel pump failure
--  * Increase oil pressure problems
--  * Increase radiator efficiency
--
-- Running behind other cars
--  * Increase fuel pump failure
--  * Increase oil pressure problems
--  * Increase valve damage possibility
--  * Reduce radiator efficiency
--
-- Running tank low
--  * Increase fuel pump failure
--
-- Running with high coolant temp
--  * Increase fuel pump failure
--  * Increase valve damage possibility
--
-- Dusty roads
--  * Reduce radiator efficiency

require "script_car_parameters"

local coolantHandleCounter = 0
local coolantHandleInterval = 7
local fuelLevelHandleCounter = 0
local fuelLevelHandleInterval = 7

local printDebug = nil
local logDebug = nil

-- Debug logging stuff.
local overrevving = false
local lowRpm = false
local runningCloseToCarInFront = false
local coolantHandleDebugLoggingCounter = 0
local coolantHandleDebugLoggingInterval = 14
local fuelLevelHandleDebugLoggingCounter = 0
local fuelLevelHandleDebugLoggingInterval = 14

local cumulativeRateChanges = {
    overrevving = {
        sparkPlug = 0,
        fuelPump = 0,
        valveDamage = 0,
        oilPressure = 0
    },
    lowRpm = {
        sparkPlug = 0,
        fuelPump = 0,
        oilPressure = 0
    },
    runningCloseToCarInFront = {
        fuelPump = 0,
        valveDamage = 0,
        oilPressure = 0
    },
    highCoolantTemp = {
        fuelPump = 0,
        valveDamage = 0
    },
    runningTankLow = {
        fuelPump = 0
    }
}

local overrevvingState = 0

function initFailureHandlingVariables(printDebug_, logDebug_)
    printDebug = printDebug_
    logDebug = logDebug_
end

function resetCumulativeRateChanges()
    for _, modeChanges in pairs(cumulativeRateChanges) do
        for key, _ in pairs(modeChanges) do
            modeChanges[key] = 0
        end
    end
end

local function getEngineMaxRpm()
    maxRPM = ac.INIConfig.carData(0, 'engine.ini'):get('DAMAGE', 'RPM_THRESHOLD', 0)
    assert(maxRPM > 0, "DAMAGE/RPM_THRESHOLD value not found. Check engine.ini!")
    return maxRPM
end

local engineMaxRpm = getEngineMaxRpm()

local function getCarInFrontDistance(ac)
    local CAR_FORWARDNESS_TRESHOLD = 0.995
    local thisCar = ac.getCar()
    local myPos = thisCar.position
    local myDir = thisCar.look

    local closestDistance = math.huge
    local closestForwardness = -1

    for i = 1, ac.getSim().carsCount - 1 do
        local otherCar = ac.getCar(i)
        local delta = otherCar.position - myPos
        local forwardness = vec3.dot(delta:normalize(), myDir)

        if forwardness > CAR_FORWARDNESS_TRESHOLD then -- car is directly in front
            local dist = vec3.distance(myPos, otherCar.position)
            if dist < closestDistance then
                closestDistance = dist
                closestForwardness = forwardness
            end
        end
    end

    if closestForwardness < CAR_FORWARDNESS_TRESHOLD then
        printDebug("Forwardness", "0")
        return math.huge
    end

    printDebug("Forwardness", "" .. closestForwardness)

    return closestDistance
end

function handleOverrevving(failureRates, engineRpm)
    printDebug("Engine RPM", "" .. engineRpm)
    local overrevvingThreshold = math.floor(engineMaxRpm * overrevvingThresholdFactor + 0.5)
    local overrevvingThresholdHigh = math.floor(engineMaxRpm * overrevvingThresholdFactorHigh + 0.5)
    local overrevvingWarningThreshold = math.floor(overrevvingThreshold * overrevvingWarningThresholdFactor + 0.5)

    if engineRpm > overrevvingThresholdHigh then
        overrevvingState = 2
    elseif engineRpm > overrevvingWarningThreshold then
        overrevvingState = 1
    else
        overrevvingState = 0
    end
    if engineRpm > overrevvingThreshold then
        printDebug("Overrevving", "ACTIVE")

        local rpmOverrevAmount = engineRpm - overrevvingThreshold
        local progressiveRpmAmount = math.floor((rpmOverrevAmount ^ overrevvingProgressionExponent) * overrevvingRateDecreaseStepFactor + 0.5)

        failureRates.sparkPlug = failureRates.sparkPlug - progressiveRpmAmount
        failureRates.fuelPump = failureRates.fuelPump - progressiveRpmAmount
        failureRates.valveDamage = failureRates.valveDamage - progressiveRpmAmount
        failureRates.oilPressure = failureRates.oilPressure - progressiveRpmAmount

        cumulativeRateChanges.overrevving.sparkPlug = cumulativeRateChanges.overrevving.sparkPlug + progressiveRpmAmount
        cumulativeRateChanges.overrevving.fuelPump = cumulativeRateChanges.overrevving.fuelPump + progressiveRpmAmount
        cumulativeRateChanges.overrevving.valveDamage = cumulativeRateChanges.overrevving.valveDamage + progressiveRpmAmount
        cumulativeRateChanges.overrevving.oilPressure = cumulativeRateChanges.overrevving.oilPressure + progressiveRpmAmount

        overrevving = true
    else
        printDebug("Overrevving", "inactive")
        if overrevving then
            logDebug("<FRH>Overrevving, rates after:")
            logDebug(" SPlug: " .. failureRates.sparkPlug .. ", Fpump: " .. failureRates.fuelPump ..
                     ", VDmg: " .. failureRates.valveDamage .. ", OPres: " .. failureRates.oilPressure)
        end
        overrevving = false
    end
end

function handleLowRpm(failureRates, engineRpm)
    local lowRpmThresholdRpm = math.floor(engineMaxRpm * lowRpmThreshold + 0.5)

    if engineRpm < lowRpmThresholdRpm then
        printDebug("Low RPM", "ACTIVE")

        local lowRpmStep = math.floor((lowRpmThresholdRpm - engineRpm) / 100 + 0.5)
        printDebug("Step", lowRpmStep)

        failureRates.sparkPlug = failureRates.sparkPlug - lowRpmStep
        failureRates.fuelPump = failureRates.fuelPump - lowRpmStep
        failureRates.oilPressure = failureRates.oilPressure - lowRpmStep

        cumulativeRateChanges.lowRpm.sparkPlug = cumulativeRateChanges.lowRpm.sparkPlug + lowRpmStep
        cumulativeRateChanges.lowRpm.fuelPump = cumulativeRateChanges.lowRpm.fuelPump + lowRpmStep
        cumulativeRateChanges.lowRpm.oilPressure = cumulativeRateChanges.lowRpm.oilPressure + lowRpmStep

        lowRpm = true
        return true
    else
        printDebug("Low RPM", "inactive")

        if lowRpm then
            logDebug("<FRH>Low RPM, below treshold: " .. engineMaxRpm * lowRpmThreshold)
            logDebug("Rates after:")
            logDebug(" SPlug: " .. failureRates.sparkPlug .. ", Fpump: " .. failureRates.fuelPump ..
                     ", OPres: " .. failureRates.oilPressure)
        end

        lowRpm = false
    end

    return false
end

function handleRunningCloseToCarInFront(failureRates, speed, ac)
    if speed < closeCarInFrontSpeedThreshold then
        return 0
    end

    local distance = getCarInFrontDistance(ac)
    printDebug("Distance to car in front", "" .. distance)
    if distance < closeCarInFrontDistanceThreshold then
        -- The closer the car is running to the car in front, the larger the step to subtract.
        -- The divider 4 is to reduce the effect to be less severe, since this is called every
        -- 0,3 seconds.
        local step = math.floor(closeCarInFrontDistanceMin / math.max(distance, closeCarInFrontDistanceMin) * closeCarInFrontDistanceThreshold / 4 + 0.5)
        failureRates.fuelPump = failureRates.fuelPump - step
        failureRates.valveDamage = failureRates.valveDamage - step
        failureRates.oilPressure = failureRates.oilPressure - step
        printDebug("Distance to car", "ACTIVE: " .. step)

        cumulativeRateChanges.runningCloseToCarInFront.fuelPump = cumulativeRateChanges.runningCloseToCarInFront.fuelPump + step
        cumulativeRateChanges.runningCloseToCarInFront.valveDamage = cumulativeRateChanges.runningCloseToCarInFront.valveDamage + step
        cumulativeRateChanges.runningCloseToCarInFront.oilPressure = cumulativeRateChanges.runningCloseToCarInFront.oilPressure + step

        runningCloseToCarInFront = true
        return step
    else
        printDebug("Distance to car", "inactive")

        if runningCloseToCarInFront then
            logDebug("<FRH>Running close to car in front, rates after:")
            logDebug(" Fpump: " .. failureRates.fuelPump .. ", VDmg: " .. failureRates.valveDamage ..
                     ", OPres: " .. failureRates.oilPressure)
        end

        runningCloseToCarInFront = false
    end

    return 0
end

function handleHighCoolantTemp(failureRates, coolantTemp)
    -- Handle coolant temperature effects at a lower frequency.
    coolantHandleCounter = coolantHandleCounter + 1
    if coolantHandleCounter < coolantHandleInterval then
        return
    end
    coolantHandleCounter = 0

    local tempDiff = coolantTemp - highEngineTempThreshold
    if tempDiff > 0 then
        printDebug("High coolant", "ACTIVE: " .. tempDiff)
        failureRates.fuelPump = failureRates.fuelPump - math.floor(tempDiff + 0.5)
        failureRates.valveDamage = failureRates.valveDamage - math.floor(tempDiff + 0.5)

        cumulativeRateChanges.highCoolantTemp.fuelPump = cumulativeRateChanges.highCoolantTemp.fuelPump + math.floor(tempDiff + 0.5)
        cumulativeRateChanges.highCoolantTemp.valveDamage = cumulativeRateChanges.highCoolantTemp.valveDamage + math.floor(tempDiff + 0.5)

        if coolantHandleDebugLoggingCounter == 0 then
            logDebug("<FRH>High coolant temperature: " .. coolantTemp .. " C")
            logDebug("Current rates:")
            logDebug(" Fpump: " .. failureRates.fuelPump .. ", VDmg: " .. failureRates.valveDamage)
        end
        coolantHandleDebugLoggingCounter = (coolantHandleDebugLoggingCounter + 1) % coolantHandleDebugLoggingInterval
    else
        printDebug("High coolant", "inactive")
        coolantHandleDebugLoggingCounter = 0
    end
end

function handleRunningTankLow(failureRates, fuelLevel)
    -- Handle fuel level effects at a lower frequency.
    fuelLevelHandleCounter = fuelLevelHandleCounter + 1
    if fuelLevelHandleCounter < fuelLevelHandleInterval then
        return
    end
    fuelLevelHandleCounter = 0

    if fuelLevel < fuelLevelThreshold then
        printDebug("Running tank low", "ACTIVE")
        failureRates.fuelPump = failureRates.fuelPump - fuelPumpLowFuelStep

        cumulativeRateChanges.runningTankLow.fuelPump = cumulativeRateChanges.runningTankLow.fuelPump + fuelPumpLowFuelStep

        if fuelLevelHandleDebugLoggingCounter == 0 then
            logDebug("<FRH>Running tank low, fuel level: " .. fuelLevel .. " L")
            logDebug("Fpump rate: " .. failureRates.fuelPump)
        end
        fuelLevelHandleDebugLoggingCounter = (fuelLevelHandleDebugLoggingCounter + 1) % fuelLevelHandleDebugLoggingInterval
    else
        printDebug("Running tank low", "inactive")
        fuelLevelHandleDebugLoggingCounter = 0
    end
end

function handleRadiatorEfficiency(radiatorCoolCoefficientBase, lowRpm, runningCloseToCarInFrontStep, trackSurfaceType, engineMap)
    if lowRpm then
        radiatorCoolCoefficientBase = radiatorCoolCoefficientBase * radiatorEfficiencyLowRpmMultiplier
    end

    if runningCloseToCarInFrontStep > 0 then
        -- This reduces the radiator efficiency based on how close the car is to the car in front,
        -- with e.g. 1 meter resulting in a factor 0.6, 2 meters 0.8 and 3 meters 0.88, etc.
        radiatorCoolCoefficientBase = radiatorCoolCoefficientBase * (1 - runningCloseToCarInFrontStep / 25)
    end

    if trackSurfaceType == ac.SurfaceExtendedType.Gravel then
        radiatorCoolCoefficientBase = radiatorCoolCoefficientBase * radiatorEfficiencyDustMultiplier
    end

    -- Adjust based on engine map (fuel mixture): rich, normal, lean, push.
    radiatorCoolCoefficientBase = radiatorCoolCoefficientBase * radiatorEfficiencyEngineMapFactors[engineMap]

    return radiatorCoolCoefficientBase
end

function logCumulativeRateChanges()
    logDebug("Cumulative rate changes:")
    for mode, changes in pairs(cumulativeRateChanges) do
        local changesStr = mode .. ":"
        for key, value in pairs(changes) do
            changesStr = changesStr .. " " .. key .. "=" .. value .. ","
        end
        logDebug(changesStr)
        printDebug("RC", changesStr)
    end
end

function getOverrevvingState()
    return overrevvingState
end

function getLowRpmState()
    return lowRpm
end
