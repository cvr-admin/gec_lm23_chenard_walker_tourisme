-- Supercharger/turbo failures script.
--
-- When supercharger problems occur, calculate new reduced maximum boost value and use it.
--
-- When the boost is above the defined limit, the failure rate is decreased (increasing the probability).
-- See the parameters in the car_parameters.lua.

require "script_car_parameters"

local acRef = nil
local car = nil
local carPhys = nil
local turboCount = nil
local turbos = {}
local printDebug = nil
local currentTurboFailureRate = nil
local aboveBoostLimit = false
local engineOverheatingActive = false

function initTurboVariables(ac_, printDebug_)
    acRef = ac_
    car = acRef.getCar()
    carPhys = acRef.accessCarPhysics()
    turboCount = car.turboCount
    engineOverheatingActive = false
    printDebug = printDebug_
    printDebug("Turbo count", "" .. turboCount)

    for i = 0, turboCount-1 do
        local turboStr = "TURBO_" .. i
        local turbo = {}
        local maxBoost = acRef.INIConfig.carData(0, 'engine.ini'):get(turboStr, 'MAX_BOOST', 0)

        acRef.setTurboMaxBoost(i, maxBoost)
        turbo["maxBoost"] = maxBoost
        turbo["currentBoost"] = maxBoost
        turbo["failureFactorRate"] = maxBoost / math.random(turboFailureFactorMin, turboFailureFactorMax)
        local targetFactor = math.random(turboBoostAfterFailurePercentMin, turboBoostAfterFailurePercentMax) / 100
        turbo["targetBoostValue"] = maxBoost * targetFactor
        turbo["failureActive"] = false
        turbo["currentTurboFailureRate"] = turboFailureRate
        turbo["active"] = true
        turbo["loggedFailure"] = false
        turbos[i] = turbo
        printDebug("Turbo target boost " .. i, "" .. turbos[i]["targetBoostValue"])
    end
end

-- Should be called once a second.
function updateTurboState(logDebug)
    for i = 0, turboCount-1 do
        if turbos[i]["active"] then
            printDebug("Current Turbo boost" .. i, "" .. car.turboBoosts[i])

            local turboFailureRateStep = (car.turboBoosts[i] / turbos[i]["maxBoost"]) ^ turboFailureRateProgression * rateDecreaseStepMax
            turboFailureRateStep = math.floor(turboFailureRateStep + 0.5)
            printDebug("turboFailureRateStep " .. i, "" .. turboFailureRateStep)

            if turbos[i]["failureActive"] == false then
                turbos[i]["currentTurboFailureRate"] = math.max(
                    turbos[i]["currentTurboFailureRate"] - turboFailureRateStep,
                    turboFailureRateMin
                )
                printDebug("currentTurboFailureRate " .. i, "" .. turbos[i]["currentTurboFailureRate"])
            end

            if turbos[i]["failureActive"] == false and math.random(1, turbos[i]["currentTurboFailureRate"]) == 1 then
                turbos[i]["failureActive"] = true
                -- Is this a major damage (explosion of the turbo)?
                if math.random(1, turboExplosionRate) == 1 then
                    turbos[i]["targetBoostValue"] = 0
                    local engineLifeFactor = math.random(
                        engineLifeAfterExplosionPercentMin, engineLifeAfterExplosionPercentMax
                    ) / 100
                    -- Calculate degraded engine life and round to integer.
                    local engineLife = math.floor(carPhys.engineLifeLeft * engineLifeFactor + 0.5)
                    ac.setEngineLifeLeft(engineLife)
                -- Will this failure cause engine overheating.
                elseif math.random(1, turboFailureEngineOverheatingRate) == 1 then
                    engineOverheatingActive = true
                end
            end

            printDebug("Engine life", "" .. carPhys.engineLifeLeft)

            if turbos[i]["failureActive"] then
                if turbos[i]["targetBoostValue"] > 0 then
                    turbos[i]["currentBoost"] = math.max(
                        turbos[i]["currentBoost"] - turbos[i]["failureFactorRate"],
                        turbos[i]["targetBoostValue"]
                    )
                else
                    turbos[i]["currentBoost"] = 0
                end
                acRef.setTurboMaxBoost(i, turbos[i]["currentBoost"])
                printDebug("Turbo " .. i, "Failed, boost: " .. turbos[i]["currentBoost"])
                if not turbos[i]["loggedFailure"] then
                    logDebug("<FLR>Turbo " .. i .. " failed, boost: " .. turbos[i]["currentBoost"], true)
                    turbos[i]["loggedFailure"] = true
                end
            end
        else
            acRef.setTurboMaxBoost(i, 0)
        end
    end
end

function isAboveBoostLimit()
    return aboveBoostLimit
end

function getTurboCount()
    return turboCount
end

function getFailedTurboCount()
    local failedCount = 0

    for i = 0, turboCount-1 do
        if turbos[i]["failureActive"] then
            failedCount = failedCount + 1
        end
    end

    return failedCount
end

function isTurboFailureEngineOverheatingActive()
    return engineOverheatingActive
end

function enableTurbo(enabled)
    for i = 0, turboCount-1 do
        turbos[i]["active"] = enabled
    end
end

function getTurboFailureRate(index)
    return turbos[index]["currentTurboFailureRate"]
end
