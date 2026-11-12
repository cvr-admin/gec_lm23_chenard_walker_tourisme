-- Debug logging and test code.
-- logXxx functions are always compiled in (controlled by DEBUG_LOG_FILE flag).
-- selectFailureForTesting / setFailureForTesting are only used when TEST_CODE = true.
-- initFailureTypeCount() must be called from script.lua after all variables are initialised.

-- Module-local debug tracking state
local debugPrevExtraA = false
local debugPrevExtraB = false
local debugPrevExtraC = false
local debugPrevExtraD = false
local debugPrevExtraE = false
local debugPrevExtraF = false
local debugPrevInPits = false
local debugPrevHandbrake = false

function logRates()
    logDebug("Rates, Spark plug: ", sparkPlugFailureRate)
    logDebug("Fuel pump: ", fuelPumpFailureRate)
    logDebug("Valves: ", valveFailureRate)
    logDebug("Oil pressure: ", oilPressureFailureRate)
    logDebug("Radiator cool coefficient: ", radiatorCoolCoefficient)
end

function logStaticInfo()
    logDebug("Track Name: ", ac.getTrackName())
    logDebug("Car Name: ", ac.getCarName(thisCar.index, true))
    local brakeDuctPercentageFront = ac.getScriptSetupValue("BRAKE_DUCT_F")()
    logDebug("BrakeDuct F: ", brakeDuctPercentageFront)
    local brakeDuctPercentageRear = ac.getScriptSetupValue("BRAKE_DUCT_R")()
    logDebug("BrakeDuct R: ", brakeDuctPercentageRear)
    local brakeDuctWingGainFront = getBrakeDuctWingGain(brakeDuctPercentageFront)
    logDebug("BrakeDuct Wing Gain F: ", brakeDuctWingGainFront)
    local brakeDuctWingGainRear = getBrakeDuctWingGain(brakeDuctPercentageRear)
    logDebug("BrakeDuct Wing Gain R: ", brakeDuctWingGainRear)
end

function logDebugDataToFile()
    logRates()

    local tyreName = ac.getTyresName(thisCar.index)
    local tyreTypeFactor = getTyreTypeFactor()
    logDebug("Tyre name: ", tyreName, ", factor: ", tyreTypeFactor)

    for i = 0, 3 do
        logDebug("Tyre " .. i .. " rate: ", tyrePunctureRates[i])
        logDebug("Tyre " .. i .. " vkm: ", thisCar.wheels[i].tyreVirtualKM)
    end

    logDebug("Engine / coolant temp: ", engineTemp, " / ", coolantTemp)
    logDebug("Engine life: ", acCarPhysics.engineLifeLeft)
    logDebug("Lap time: ", ac.lapTimeToString(thisCar.previousLapTimeMs))

    logDebug("Brake wear: ", brakeWearLevel)

    local turboCount = getTurboCount()
    for i = 0, turboCount-1 do
        logDebug("Turbo " .. i .. " fail rate: " .. getTurboFailureRate(i))
    end

    logDebug("Laps completed: ", thisCar.lapCount)
    logCumulativeRateChanges()
end

function logExtraButtonPresses()
    if thisCar.extraA and not debugPrevExtraA then
        logDebug("ExtraA pressed", true)
    end
    debugPrevExtraA = thisCar.extraA

    if thisCar.extraB and not debugPrevExtraB then
        logDebug("ExtraB pressed", true)
    end
    debugPrevExtraB = thisCar.extraB

    if thisCar.extraC and not debugPrevExtraC then
        logDebug("ExtraC pressed", true)
    end
    debugPrevExtraC = thisCar.extraC

    if thisCar.extraD and not debugPrevExtraD then
        logDebug("ExtraD pressed", true)
    end
    debugPrevExtraD = thisCar.extraD

    if thisCar.extraE and not debugPrevExtraE then
        logDebug("ExtraE pressed", true)
    end
    debugPrevExtraE = thisCar.extraE

    if thisCar.extraF and not debugPrevExtraF then
        logDebug("ExtraF pressed", true)
    end
    debugPrevExtraF = thisCar.extraF

    if thisCar.handbrake == 1 and not debugPrevHandbrake then
        logDebug("Handbrake engaged", true)
    end
    debugPrevHandbrake = (thisCar.handbrake == 1)
end

function logCarEnterAndLeavePits()
    if isCarInPits and not debugPrevInPits then
        logDebug("Enter pits", true)
    end
    if not isCarInPits and debugPrevInPits then
        logDebug("Exit pits", true)
        logStaticInfo()
    end

    debugPrevInPits = isCarInPits
end

----------------- Debug/testing code -----------------
--
-- While not in pits, press extra B to select a failure,
-- then press and hold extra C until the failure occurs.
-- To clear all failures, select it using extra B, then
-- press extra C.

local failureTypes = {
    sparkPlugFailure = 1,
    fuelPumpFailure = 2,
    valveFailure = 3,
    oilPressureFailure = 4,
    gearFailure = 5,
    tyrePuncture_FL = 6,
    tyrePuncture_FR = 7,
    tyrePuncture_RL = 8,
    tyrePuncture_RR = 9,
    highSpeedLightCollision1 = 10,
    highSpeedLightCollision2 = 11,
    clearAllFailures = 12
}

local failureDescriptions = {
    "Spark plug failure",
    "Fuel pump failure",
    "Valve failure",
    "Oil pressure failure",
    "Gear failure",
    "Tyre puncture front left",
    "Tyre puncture front right",
    "Tyre puncture rear left",
    "Tyre puncture rear right",
    "Test high speed collision - 150",
    "Test high speed collision - 750",
    "Clear all failures"
}

-- origXxx values are captured in initFailureTypeCount(), which is called from
-- script.lua after all variables are initialised (not at require/load time).
local origSparkPlugFailureRateBase
local origFuelPumpFailureRateBase
local origValveFailureRateBase
local origOilPressureFailureRateBase
local origGearFailureRate
local origBoostedGearFailureRate
local origTyrePunctureRate

local highSpeedCollisionDone = false
local failureTypeCount = 0
local selectedFailure = 0
local prevExtraBState = false

function initFailureTypeCount()
    for _ in pairs(failureTypes) do
        failureTypeCount = failureTypeCount + 1
    end
    -- Capture original values now that all variables are initialised.
    origSparkPlugFailureRateBase = sparkPlugFailureRateBase
    origFuelPumpFailureRateBase = fuelPumpFailureRateBase
    origValveFailureRateBase = valveFailureRateBase
    origOilPressureFailureRateBase = oilPressureFailureRateBase
    origGearFailureRate = gearFailureRate
    origBoostedGearFailureRate = boostedGearFailureRate
    origTyrePunctureRate = tyrePunctureRate
end

-- These should not be included in release packages,
-- therefore calls to these functions MUST be behind
-- the TEST_CODE flag!
function selectFailureForTesting()
    if not isCarInPits and not thisCar.extraB and prevExtraBState then
        selectedFailure = selectedFailure + 1
        if selectedFailure > failureTypeCount then
            selectedFailure = 1
        end
        prevExtraBState = false
        printDebug("Selected failure type:", failureDescriptions[selectedFailure], true)
    end

    if thisCar.extraB then
        prevExtraBState = true
    else
        prevExtraBState = false
    end
end

function setFailureForTesting()
    if  not isCarInPits and thisCar.extraC then
        if selectedFailure == failureTypes.clearAllFailures then
            resetCar()
            highSpeedCollisionDone = false
            tyrePunctureTestIndex = -1
        elseif selectedFailure == failureTypes.sparkPlugFailure then
            sparkPlugFailureRateBase = 1
        elseif selectedFailure == failureTypes.fuelPumpFailure then
            fuelPumpFailureRateBase = 1
        elseif selectedFailure == failureTypes.valveFailure then
            valveFailureRateBase = 1
        elseif selectedFailure == failureTypes.oilPressureFailure then
            oilPressureFailureRateBase = 1
        elseif selectedFailure == failureTypes.gearFailure then
            gearFailureRate = 1
            boostedGearFailureRate = 1
        elseif selectedFailure == failureTypes.tyrePuncture_FL then
            tyrePunctureTestIndex = 0
        elseif selectedFailure == failureTypes.tyrePuncture_FR then
            tyrePunctureTestIndex = 1
        elseif selectedFailure == failureTypes.tyrePuncture_RL then
            tyrePunctureTestIndex = 2
        elseif selectedFailure == failureTypes.tyrePuncture_RR then
            tyrePunctureTestIndex = 3
        elseif selectedFailure == failureTypes.highSpeedLightCollision1 then
            if not highSpeedCollisionDone then
                prevDamageRightEngine = prevDamageRightEngine - 10
                prevDamageFrontEngine = prevDamageFrontEngine - 7
                prevDamageRearEngine = prevDamageRearEngine - 8
                ac.setEngineLifeLeft(acCarPhysics.engineLifeLeft-500)
                highSpeedCollisionDone = true
            end
        elseif selectedFailure == failureTypes.highSpeedLightCollision2 then
            if not highSpeedCollisionDone then
                prevDamageRightEngine = prevDamageRightEngine - 5
                prevDamageFrontEngine = prevDamageFrontEngine - 21
                ac.setEngineLifeLeft(acCarPhysics.engineLifeLeft-750)
                highSpeedCollisionDone = true
            end
        end
    else
        sparkPlugFailureRateBase = origSparkPlugFailureRateBase
        fuelPumpFailureRateBase = origFuelPumpFailureRateBase
        valveFailureRateBase = origValveFailureRateBase
        oilPressureFailureRateBase = origOilPressureFailureRateBase
        gearFailureRate = origGearFailureRate
        boostedGearFailureRate = origBoostedGearFailureRate
        tyrePunctureRate = origTyrePunctureRate
        tyrePunctureTestIndex = -1
    end
end

----------------- End of debug/testing code -----------------
