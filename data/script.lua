--Historic damage script by SLIGHTLYMADESTUDIOS
--youregoingtobrazil.eu - tunarisgame.com
--description:
--big ups to Garamond247 for commissioning!
--add gobs of simulation value to your historics, including:

--random fuel pump damage
--random oil pressure problems
--random valve damage
--basic radiator damage
--basic coolant temp sim
--random spark plug failure
--random gear loss
--brake wear
--starter/stall system
--random tyre durability
--on-road tyre service
--spares, configurable carry-on spares wheels
--a basic message queue system to inform driver of instrument statuses
--slow tyre puncture

--[[ Failure Probability (2h Race and 24h race)
6666.7 ~41.74%
10000 ~30.12%
15000 ~21.34%
20000 ~16.52%
30000 ~11.29%
50000 ~6.94%
60000 ~5.8%
70000 ~5.0%
80000 ~4.4%
90000 ~3.9%
100000 ~3.5%
150000 ~2.37% - 25.1%
200000 ~1.79%
300000 ~1.19%
400000 ~0.90%
500000 ~0.72% - 8.5%
750000 ~0.48%
1000000 ~0.36% - 4.2%

10,000 + 39,000 = 36.39%
50,000 + 42,000 = 14.61%
]]

local VERSION = "3.0.1"

acCarPhysics = ac.accessCarPhysics() --extension physics shortcut

if acCarPhysics.inputMethod == ac.InputMethod.AI then
    --absolutely do not execute any of this on an AI car, who knows how badly it fucks up.
    --you can maybe make a "lite" version of this that only runs the sparkplug routine, but aside from that, all of this is way too advance for AI to understand
    return
end

--READ ONLY

thisCar = ac.getCar()

require "script_car_parameters"
require "script_supercharger"
require "script_failure_rate_handling"
require "script_electricity"
require "script_psg"

local new_throttle_model = require("script_throttle")

-- Enable/disable debug prints and test code.
-- *** Must always be false in release packages! ***
local DEBUG = false
local DEBUG_LOG_FILE = true  -- Left logging enabled for release 2.0.
local TEST_CODE = false

-- Override can be used to temporarily ignore the DEBUG flag,
-- if you want to print only certain debug data, but not all.
function printDebug(str1, str2, override)
    override = override or false
    if DEBUG or override then
        ac.debug(str1, str2)
    end
end

-- Log debug messages to the csp log file. Append 'true' as the last argument
-- to force logging regardless of the DEBUG_LOG_FILE flag.
-- For example: logDebug("This will always be logged!", true)
--              logDebug("This will be logged only if DEBUG_LOG_FILE is true.")
function logDebug(...)
    local argCount = select('#', ...)
    local lastArg = select(argCount, ...)
    local isLastArgBooleanAndTrue = argCount > 0 and type(lastArg) == "boolean" and lastArg == true

    if DEBUG_LOG_FILE or isLastArgBooleanAndTrue then
        local args = {...}
        local message = "CVR_LOG " .. os.date("[%H:%M:%S]") .. "\t"
        local limit = isLastArgBooleanAndTrue and (#args - 1) or #args
        for i = 1, limit do
            message = message .. tostring(args[i])
        end
        ac.log(message)
    end
end

-- New subsystem modules. Order matters: overhead_messages first so overheadMessageQueue
-- is available to all modules that follow. All placed after printDebug/logDebug so
-- module-load-time code can call them safely.
require "script_overhead_messages"
require "script_engine_failures"
require "script_gearbox"
require "script_tyre"
require "script_thermal"
require "script_engine_starter"
require "script_fuel"
require "script_brakes"
-- script_debug is required later (after failure rate vars are initialised below).

local doOnceAtStart = false

initTurboVariables(ac, printDebug, logDebug)
initFailureHandlingVariables(printDebug, logDebug)

local superchargerExists = 0
if getTurboCount() > 0 then
    superchargerExists = 1
end

local turboFailureTimer = 0
currentEngineHeatGainMult = engineHeatGainMult
local prevFailedTurboCount = 0
local turboSmokeDuration = 25
local turboSmokeTimer = turboSmokeDuration

-- Teleport to pits callback. Will be called when the car is teleported to pits.
-- When this happens we will prevent starting of the engine, thus ending the race
-- for the car that was teleported to pits.
carHasTeleportedToPits = false

function teleportToPitsCallback(carIndex)
    printDebug("Car teleported to pits", "Car index: " .. carIndex)
    printDebug("This car index", "Car index: " .. thisCar.index)
    local raceStarted = (ac.getSim().raceSessionType == ac.SessionType.Race and ac.getSim().isSessionStarted)

    if raceStarted and thisCar.isInPit then
        carHasTeleportedToPits = true
    end
end

ac.onCarJumped(thisCar.index, teleportToPitsCallback)

local optimizationTimer = 0 --run a small timer rather than running some of the checks every tick. should save on CPU.

local radiatorSetup = nil   -- handled by setupBits now
local prevRadiatorSetup = 0
local turboEnabled = true
local prevextraDState = false
local prevextraEState = false
local prevextraFState = false

local hasEngineDamage = false

local ENGINE_MAP_RICH = 0
local ENGINE_MAP_NORMAL = 1
local ENGINE_MAP_LEAN = 2
local ENGINE_MAP_PUSH = 3
local EGINE_MAP_DESCRIPTIONS = { "Rich", "Normal", "Lean", "Push" }

-- Failure rates. Base rates are global so that failure_rate_handling and script_debug can access them.
-- The actual (engine-map-adjusted) rates are also global so that the failure functions can read them.
sparkPlugFailureRate = sparkPlugFailureRateInitialValue
sparkPlugFailureRateBase = sparkPlugFailureRateInitialValue
fuelPumpFailureRate = fuelPumpFailureRateInitialValue
fuelPumpFailureRateBase = fuelPumpFailureRateInitialValue
valveFailureRate = valveFailureRateInitialValue
valveFailureRateBase = valveFailureRateInitialValue
oilPressureFailureRate = oilPressureFailureRateInitialValue
oilPressureFailureRateBase = oilPressureFailureRateInitialValue
remFlags = remFlags or {}

local prevEngineMap = -1
local prevLapCount = 0

local failureRateHandlingTimer = 0
local failureRateHandlingInterval = 0.3

trackSurfaceType = ac.SurfaceExtendedType.Base

local mediumSpeedDtTimer = 0
local tyreBlowCrashingTimer = 0

-- call once so current setup is applied on load - this did not work because AC's logic on that matter is weird. Now handled in setupBits
--applyRadiatorSetup(radiatorSetup)

-- script_debug required here so that its module-level code runs after all vars above are set.
require "script_debug"

-- Initialise failure type counter for test code (captures orig failure rate values).
if TEST_CODE then
    initFailureTypeCount()
end

--this quick helper func to convert some of the setup params to bool.
local function inputToBool(value)
    maldito = {}
    maldito[0] = false
    maldito[1] = true
    return maldito[value]
end

--this function gets the setup menu values for the tyre pressures (so that when you restore a wheel, it gives the correct static pressure, in case its not built-in)
--and also the count of spare wheels. the spare wheels get also replaced with a fresh set of spares when you pit.

--get some setup params when leaving pits so that they can be reset to the original state at one point or another
local function setupBits()
    local inGrid = (ac.getSim().raceSessionType == ac.SessionType.Race and not ac.getSim().isSessionStarted)
    --check if cars in pit to reset the values, and also check nil for initialization
    if isCarInPits or inGrid or tyrePressures[0] == nil then
        --get setup tyre pressures, and initialize vKMs
        if ac.getCar(0).isChangingTyres or inGrid or tyrePressures[0] == nil then
            for i = 0, 3 do
                -- 1.0 means inflated to the pressure defined in the setup.
                tyrePressures[i] = 1.0
                ac.setTyreInflation(i, tyrePressures[i])
                --ac.debug("Tyre stuff fired",i)
                -- Only generate a new lifespan if the tyre is not already initialized
                if not tyrevKMs[i] or tyrevKMs[i] < thisCar.wheels[i].tyreVirtualKM then
                    tyrevKMs[i] = generateTyrevKM()
                    -- tyrevKMs[i] = thisCar.wheels[i].tyreVirtualKM + generateTyrevKM()
                end
                --debugTyrevKMs() -- Log initialized vKM values
                tyrePunctureDeflateFactor[i] = 0.0

                -- Reset the tyre wear for the replaced tyre(s).
                tyreWear[i] = 0.0
                prevTyreWear[i] = 0.0
            end--end of tyre vKM generation

            -- Check if brake wear is to be reset when changing tyres in pits.
            -- This is done outside the per-wheel loop since brakeWearLevel is a single value.
            -- We check isChangingTyres directly rather than tyreVirtualKM, because the game
            -- resets VKM only after the tyre change completes (i.e. after isChangingTyres turns false),
            -- so VKM is still the old value while this code runs.
            if resetBrakeWearAtTyreChange == true and ac.getCar(0).isChangingTyres then
                brakeWearLevel = 0.0
            end
        end

        -- Get a bunch of stuff that should be reset when you enter pits
        -- but only if engine has been fixed already.
        if acCarPhysics.engineLifeLeft == 1000 then
            sparkPlugFailed = false

            valveFailed = false
            valveFailureActive = false
            valveFailureElapsed = 0
            valveFailureDamage = valveFailureMinDamage

            oilPressureFailed = false
            oilPressureFailureActive = false
            oilPressureFailureElapsed = 0
            oilPressureFailureDamage = oilPressureFailureMinDamage

            -- Cut the failure rate losses to half, if the engine has been fixed,
            -- i.e. if there was engine damage before entering the pits.
            if hasEngineDamage then
                sparkPlugFailureRateBase = sparkPlugFailureRateBase + (sparkPlugFailureRateInitialValue - sparkPlugFailureRateBase) * 0.5
                valveFailureRateBase = valveFailureRateBase + (valveFailureRateInitialValue - valveFailureRateBase) * 0.5
                oilPressureFailureRateBase = oilPressureFailureRateBase + (oilPressureFailureRateInitialValue - oilPressureFailureRateBase) * 0.5
                hasEngineDamage = false
            end
        end

        --[[ for i = 1, thisCar.gearCount do
        --offset the index by 1 due to janky implementation
        deadGears[i + 1] = false
        end ]]

        --get count of spare wheels equipped in the setup
        --and add the additional mass
        --MAKE SURE TO ADD THE LINE INTO THE SETUP.INI!!!
        currentSpares = getCurrentSpares()
        overheadMessagesEnabled = inputToBool(ac.getScriptSetupValue("OVERHEAD_MESSAGES")())

        tyreChangeInProgress = false

        -- Drop coolant temp down to a more reasonable temp... (irl they throw buckets of water on the rads)
        if coolantTemp > 80 or engineTemp > 80 then
            coolantTemp = 80
            engineTemp = 80
        else
            --once thats been called, reset JEFF the next time around
            totalMeltdown = false
            waterTempWarning = false
        end
        --SETTING CAR EXTRA MASS (SPARE WHEEL) CAN BE DONE IN UPDATE LOOP!!
    end--end of checking if car is in pits insanity

    if ((lastSetupRad or -1) ~= ac.getScriptSetupValue("RADIATOR")()) or radiatorSetup == nil then
        radiatorSetup = ac.getScriptSetupValue("RADIATOR")()
        lastSetupRad = radiatorSetup
        prevRadiatorSetup = radiatorSetup
        applyRadiatorSetup(radiatorSetup)
        --overheadMessageQueue("Radiator setup SetupBits", ac.getScriptSetupValue("RADIATOR")(), 3, true)
    end

    -- Fix turbo in other sessions, than race.
    if superchargerExists == 1 and isCarInPits and ac.getSim().raceSessionType ~= ac.SessionType.Race then
        initTurboVariables(ac, printDebug)
        acCarPhysics.controllerInputs[25] = 0
        turboSmokeTimer = turboSmokeDuration
        currentEngineHeatGainMult = engineHeatGainMult
        prevFailedTurboCount = 0
    end

    -- Call the radiator dmg warning resets only after radiator has been fixed.
    -- For this we don't need to be in the pits. It fixes a bug where a pit
    -- stop was not correctly detected, therefore faults stayed active, even though
    -- they were fixed during the pit stop.
    if thisCar.damage[0] < 10 and thisCar.damage[2] < 10 and thisCar.damage[3] < 10  then
        hasRadiatorDamage = false
        hasRadiatorMajorDamage = false
        brakesFailed = false
        boxDamaged = false
        randomBrakeLimit = nil
    end
end--end of setupbits function

local function adjustRatesAccordingToEngineMap()
    local engineMap = thisCar.fuelMap + 1

    -- Calculate the actual failure rates using the base rates, which may have changed by e.g.
    -- overrevving, or other factors. This way the possibly modified base rates are adjusted
    -- according to the engine map factors.
    sparkPlugFailureRate = math.floor(sparkPlugFailureRateBase * sparkPlugEngineMapFactors[engineMap] + 0.5)
    fuelPumpFailureRate = math.floor(fuelPumpFailureRateBase * fuelPumpEngineMapFactors[engineMap] + 0.5)
    valveFailureRate = math.floor(valveFailureRateBase * valveEngineMapFactors[engineMap] + 0.5)
    oilPressureFailureRate = math.floor(oilPressureFailureRateBase * oilPressureEngineMapFactors[engineMap] + 0.5)

    printDebug("Engine map", EGINE_MAP_DESCRIPTIONS[engineMap])

    if DEBUG_LOG_FILE and engineMap ~= prevEngineMap then
        logDebug("Engine map: ", EGINE_MAP_DESCRIPTIONS[engineMap])
        prevEngineMap = engineMap
    end
end

-- Set everything to initial state. Useful for resetting the
-- car for a race, for example.
function resetCar()
    ac.ControlButton("__EXT_ENGINEMAP_UP"):setDisabled(false)
    sparkPlugFailed = false
    valveFailed = false
    valveFailureActive = false
    valveFailureElapsed = 0
    valveFailureDamage = valveFailureMinDamage
    oilPressureFailed = false
    oilPressureFailureActive = false
    oilPressureFailureElapsed = 0
    oilPressureFailureDamage = oilPressureFailureMinDamage
    currentSpares = getCurrentSpares()
    hasRadiatorDamage = false
    hasRadiatorMajorDamage = false
    brakesFailed = false
    brakeWearLevel = 0.0
    boxDamaged = false
    randomBrakeLimit = nil
    fuelPumpFailed = false
    initDeadGears()
    ac.setEngineLifeLeft(1000)
    carHasTeleportedToPits = false
    coolantTemp = 70
    engineTemp = 70
    radiatorSetup = ac.getScriptSetupValue("RADIATOR")()
    prevRadiatorSetup = radiatorSetup
    applyRadiatorSetup(radiatorSetup)
    radiatorCoolCoefficient = radiatorCoolCoefficient
    sparkPlugFailureRate = sparkPlugFailureRateInitialValue
    sparkPlugFailureRateBase = sparkPlugFailureRateInitialValue
    fuelPumpFailureRate = fuelPumpFailureRateInitialValue
    fuelPumpFailureRateBase = fuelPumpFailureRateInitialValue
    valveFailureRate = valveFailureRateInitialValue
    valveFailureRateBase = valveFailureRateInitialValue
    oilPressureFailureRate = oilPressureFailureRateInitialValue
    oilPressureFailureRateBase = oilPressureFailureRateInitialValue
    radiatorCoolCoefficient = radiatorCoolCoefficientInitialValue
    radiatorCoolCoefficientBase = radiatorCoolCoefficientInitialValue
    hasEngineDamage = false

    if superchargerExists == 1 then
        initTurboVariables(ac, printDebug)
        currentEngineHeatGainMult = engineHeatGainMult
        prevFailedTurboCount = 0
        turboSmokeTimer = turboSmokeDuration
        acCarPhysics.controllerInputs[25] = 0
    end

    tyreStockEmpty = false
    tyreChangeInProgress = false
    blownTyres = false
    initTyrePunctureTables()
    for i = 0, 3 do
        ac.setTyreInflation(i, 1.0)
    end

    initTyreWearTable()
    resetCumulativeRateChanges()


    ResetEle()  --added for electricity

    logDebug("Physics script version: ", VERSION, true)
    logDebug("Car reset done.")
    logRates()
end

-- run resetCar at each session restart
ac.onSessionStart(resetCar)
-- setDisable engineMap button to false at start. just in case it did not reset properly in a previous session
ac.ControlButton("__EXT_ENGINEMAP_UP"):setDisabled(false)
-- callbacks to re-enable engineMap button
function DIH_reEnableEngineMapButton()
    ac.ControlButton("__EXT_ENGINEMAP_UP"):setDisabled(false)
end

local disposalHandle = ac.onLuaScriptDisposal(function(senderName, senderType, senderID)
    -- This runs when the script is unloaded
    DIH_reEnableEngineMapButton()
end)

ac.onRelease(DIH_reEnableEngineMapButton)
ac.onOpenMainMenu(DIH_reEnableEngineMapButton)
ac.onLuaScriptDisposal(DIH_reEnableEngineMapButton)

-- MAIN UPDATE STARTS
function update(dt)
    if acCarPhysics.inputMethod == ac.InputMethod.AI then
        return
    end

    if thisCar.isInPit or inGrid or (dt < 0.0001) or ac.getSim().isInMainMenu or ac.getSim().isPaused then
        ac.ControlButton("__EXT_ENGINEMAP_UP"):setDisabled(false)
    end

    if currentSpares ~= 0 then
        tyreStockEmpty = false
    end
    if TEST_CODE then
        selectFailureForTesting()
        setFailureForTesting()
    end

    if thisCar.isInPitlane then
        if thisCar.isInPit then
            isCarInPits = true
        end
    else
        isCarInPits = false
    end
    printDebug("isCarInPits", isCarInPits)

    if ac.getSim().inputMode ~= ac.UserInputMode.Keyboard then
        new_throttle_model.runTM()
    end

    logExtraButtonPresses()
    logCarEnterAndLeavePits()

    optimizationTimer = optimizationTimer + dt

    brakeWear(dt)
    fuelPumpFailure(dt)
    setupBits()
    coolantBehavior(dt)
    tyreReplacement(dt)
    overheadMessageDisplay(dt)
    engineStaller(dt)

    if (ignitionType == 2) or (ignitionType == 3) then

        updateElectricity(dt)
        handleRepairs(dt, overheadMessageQueue)

        debugElectricity(dt)  -- <-- added

        if thisCar.isInPit and (batteryCurrentCharge < 95 or batteryMaxCapacity < 95 or alternatorHealth < 0.9 or not alternatorOK) then
            -- Check if Extra B is pressed
            if thisCar.extraB and not isRepairingBelt then
                isRepairingBelt = true
                beltRepairTimer = 0  -- Reset timer when repair starts
                overheadMessageQueue("Alternator Repair", "Repair started. Hold position until done", 3)
                printDebug("Alternator Repair", "Repair process started")
            end

            -- If repair is in progress, count time
            if isRepairingBelt then
                beltRepairTimer = beltRepairTimer + dt

                -- todo: adjust batteryMaxCapacity based on what is the problem. new battery - for simplicity I'll just assume they check and replace everything

                -- Show repair progress - repairing the alternator in the pits only takes half as long
                overheadMessageQueue("ELECTRICITY", "Repairing alternator: " .. string.format("%d%%", math.floor((beltRepairTimer / (alternatorRepairTime/2)) * 100)) .. " done", 1, true)
                printDebug("Alternator Repair Progress", string.format("%.1f sec left", (alternatorRepairTime/2) - beltRepairTimer))

                -- When repair time has passed, complete the repair
                if beltRepairTimer >= (alternatorRepairTime/2) then
                    alternatorOK = true
                    alternatorHealth = math.min((alternatorHealth or 0) + 0.5, 1.0) --? why not just 1?
                    beltRepairTimer = 0
                    isRepairingBelt = false
                    acCarPhysics.controllerInputs[52] = 0
                    alternatorRepairTime = math.random(100, 200)
                    batteryCurrentCharge = 100
                    batteryMaxCapacity = 100
                    overheadMessageQueue("ELECTRICITY", "The Alternator has been repaired", 3)
                end
            end
        end
    end

    mediumSpeedDtTimer = mediumSpeedDtTimer + dt

    if mediumSpeedDtTimer >= 0.1 then
        slowTyrePuncture()
        fuelExhaustion()
        limitEngineDamageAtCrash()
        mediumSpeedDtTimer = 0
    end

    if fuelExhCutLength > 0 then
        if fuelExhCutTimer < fuelExhCutLength then
            acCarPhysics.gas = math.random() * 0.2
            fuelExhCutTimer = fuelExhCutTimer + dt
        else
            fuelExhCutLength = 0
            fuelExhCutTimer = 0
        end
    end

    if superchargerExists == 1 then
        turboFailureTimer = turboFailureTimer + dt

        if not isCarInPits and turboFailureTimer >= 1 then
            if (acCarPhysics.rpm > 100) then
                updateTurboState(logDebug)
            end
            if isTurboFailureEngineOverheatingActive() then
                currentEngineHeatGainMult = engineHeatGainMultTurbo
                printDebug("Turbo", "Engine overheating active")
            end
            turboFailureTimer = 0
        end
    end

    tyreBlowCrashingTimer = tyreBlowCrashingTimer + dt

    if tyreBlowCrashingTimer >= 0.2 then
        tyreBlowWhenCrashing()
        tyreBlowCrashingTimer = 0
    end

    -- Enable/disable turbo, if the option is available.
    if turboOnOffButtonEnabled then
        if thisCar.extraD and not prevExtraDState then
            turboEnabled = not turboEnabled
            enableTurbo(turboEnabled)

            if turboEnabled then
                overheadMessageQueue("Turbo enabled", "", 3)
            else
                overheadMessageQueue("Turbo disabled", "", 3)
            end
        end
        prevExtraDState = thisCar.extraD
    end

    -- enable/disable remote fuel mix change based on flags (move to optimizeTimer part maybe?)
    if remFlags.fuelMix or thisCar.isInPit or inGrid or (dt < 0.0001) or ac.getSim().isInMainMenu or ac.getSim().isPaused then
        ac.ControlButton("__EXT_ENGINEMAP_UP"):setDisabled(false)
    else
        ac.ControlButton("__EXT_ENGINEMAP_UP"):setDisabled(true)
    end
    --

    -- radiator setup
    if radiatorShutterAdjustEnabled and ((remFlags.radiatorShutter) or thisCar.isInPit) then
        if thisCar.extraE and not prevextraEState then
            radiatorSetup = (radiatorSetup + 1) % 5
        end
        if thisCar.extraF and not prevextraFState then
            radiatorSetup = (radiatorSetup - 1) % 5
        end
        if radiatorSetup ~= prevRadiatorSetup then
            local shutterMsg = applyRadiatorSetup(radiatorSetup)
            overheadMessageQueue("Radiator setup", shutterMsg, 3, true)
            printDebug("Radiator setup", tostring(radiatorSetup))
            logDebug("Radiator setup: ", tostring(radiatorSetup))
        end
        prevextraEState = thisCar.extraE
        prevextraFState = thisCar.extraF
        prevRadiatorSetup = radiatorSetup
    end

    failureRateHandlingTimer = failureRateHandlingTimer + dt

    if failureRateHandlingTimer >= failureRateHandlingInterval and thisCar.speedKmh > 1 then
        local rates = {
            sparkPlug = sparkPlugFailureRateBase,
            fuelPump = fuelPumpFailureRateBase,
            valveDamage = valveFailureRateBase,
            oilPressure = oilPressureFailureRateBase
        }

        local rpmRounded = math.floor(thisCar.rpm + 0.5)
        handleOverrevving(rates, rpmRounded)
        local lowRpm = handleLowRpm(rates, rpmRounded)
        local runningCloseStep = handleRunningCloseToCarInFront(rates, thisCar.speedKmh, ac)
        handleHighCoolantTemp(rates, coolantTemp)
        handleRunningTankLow(rates, thisCar.fuel)
        radiatorCoolCoefficient = handleRadiatorEfficiency(radiatorCoolCoefficientBase, lowRpm, runningCloseStep, trackSurfaceType, thisCar.fuelMap + 1)

        sparkPlugFailureRateBase = rates.sparkPlug
        fuelPumpFailureRateBase = rates.fuelPump
        valveFailureRateBase = rates.valveDamage
        oilPressureFailureRateBase = rates.oilPressure

        printDebug("Spark plug failure rate", sparkPlugFailureRate)
        printDebug("Fuel pump failure rate", fuelPumpFailureRate)
        printDebug("Valve failure rate", valveFailureRate)
        printDebug("Oil pressure failure rate", oilPressureFailureRate)
        printDebug("radiatorCoolCoefficient", radiatorCoolCoefficient)

        failureRateHandlingTimer = 0
    end

    if DEBUG_LOG_FILE then
        ac.setLogSilent(false)

        if thisCar.lapCount ~= prevLapCount then
            if ac.getSim().raceFlagType == ac.FlagType.Finished then
                logDebug("*** SESSION FINISHED ***")
            else
                logDebug("* LAP COMPLETED *")
            end

            logDebugDataToFile()
            logDebug("***")
            prevLapCount = thisCar.lapCount
        end
    end

    --run some bits only every few ticks, no point in checking them every tick.
    if optimizationTimer > 2 then
        --setExtraMass call is free if the position and mass is the same as last call, so this is fine here.
        
        if currentSpares > 0 then
            local currentSparesBugfix = currentSpares + 0.1
            ac.setExtraMass(spareWheelPos, currentSparesBugfix * spareWheelMass, vec3(0.05,0.05,0.05))
        end

        -- Prior starting the race, reset all possible failures and wear
        -- accumulated in previous (practice) sessions.
        local inGrid = (ac.getSim().raceSessionType == ac.SessionType.Race and not ac.getSim().isSessionStarted)
        if inGrid then
            if not doOnceAtStart then
                resetCar()
                logStaticInfo()
                doOnceAtStart = true
            end
        else
            tyreBlow()
            if (acCarPhysics.rpm > 100) then
                fuelPumpFailureActivation()
            end
            updateTyreWear()
        end

        adjustRatesAccordingToEngineMap()

        printDebug("Engine life left", acCarPhysics.engineLifeLeft)
        if acCarPhysics.engineLifeLeft < 1000 then
            hasEngineDamage = true
        end

        -- Only run failure checks when NOT in repair state
        if not gearboxRepairInProgress and not isCarInPits and not inGrid then
            if (acCarPhysics.rpm > 100) then
                sparkPlugFailure()
                valveFailure(dt)
                oilPressureFailure(dt)
                if not ac.getSim().controlsWithShifter then  -- added so the old method runs for paddle shifters only
                    gearboxFailure()
                end
            end
            --fuelTankDamage() -- once should be enough an it'S already being called right below
        end

        fuelTankDamage()

        local deadGearCount = 0
        for i = 1, thisCar.gearCount do
            if deadGears[i] then deadGearCount = deadGearCount + 1 end
        end
        local gearboxDamage = deadGearCount / thisCar.gearCount
        updateGearFailureRate(gearboxDamage)

        -- If repairs are on going then force engine off.
        if fuelPumpRepairInProgress or gearboxRepairInProgress or isRepairingBelt or thisCar.isRepairing then
            ac.setEngineRPM(0)
        end

        optimizationTimer = 0
    end

    -- new h-shifter gearbox failure system. Based on gearGrind state. needs to be outside of the optimization timer because otherwise one would potentially miss the window where this should apply
    if thisCar.isGearGrinding and ac.getSim().controlsWithShifter then  -- added so the old method runs for paddle shifters only
        gearboxFailureHshifter(dt)
    end

    fuelPumpPitRepair(dt)

    gearboxPitRepair(dt)

    -- Limit the minimum failure rates.
    if sparkPlugFailureRateBase < sparkPlugFailureRateMinimumValue then
        sparkPlugFailureRateBase = sparkPlugFailureRateMinimumValue
    end
    if fuelPumpFailureRateBase < fuelPumpFailureRateMinimumValue then
        fuelPumpFailureRateBase = fuelPumpFailureRateMinimumValue
    end
    if valveFailureRateBase < valveFailureRateMinimumValue then
        valveFailureRateBase = valveFailureRateMinimumValue
    end
    if oilPressureFailureRateBase < oilPressureFailureRateMinimumValue then
        oilPressureFailureRateBase = oilPressureFailureRateMinimumValue
    end

    -- Avoid calling printDebug() at every iteration in normal use,
    -- since function calls are pretty expensive in Lua.
    if DEBUG then
        -- local tyreName = ac.getTyresName(0, -1)
        --printDebug("TyreName", tyreName)

        printDebug("Extra Buttons", string.format("A: %s | B: %s", tostring(thisCar.extraA), tostring(thisCar.extraB)))

        printDebug("Radiator", string.format("Damage: %.1f | Coolant: %.1f°C | Engine: %.1f°C", carDamageClamp, coolantTemp, engineTemp))
        printDebug("Tyres", string.format("Spares: %s | Time: %.2f", tostring(currentSpares), carStoppedTimer))
        printDebug("Brake Damage", brakesFailed)
        printDebug("Gearbox Failure", "Status: " .. tostring(isGearboxFailed))
        printDebug("Gearbox Ratio", acCarPhysics.gearsFinalRatio)
        printDebug("Gearbox", string.format("Damage: %.1f | Rate: %.1f", thisCar.gearboxDamage, boostedGearFailureRate))
        printDebug("Repair times", string.format("Fuel pump: %s | Gearbox: %s", fuelPumpRepairTime, gearboxRepairTime))
        printDebug("Valve Failure", string.format(
        "RPM: %d | Progress: %.1f%% | Damage: %.1f/%.1f | Status: %s",
            acCarPhysics.rpm,
            (valveFailureElapsed/valveFailureBaseTime)*100,
            valveFailureDamage,
            valveFailureMaxDamage,
            tostring(valveFailureActive)
        ))
        printDebug("Oil pressure problems", string.format(
        "RPM: %d | Progress: %.1f%% | Damage: %.1f/%.1f | Status: %s",
        tonumber(acCarPhysics.rpm) or 0,
        (tonumber(oilPressureFailureElapsed) or 0) / (tonumber(oilPressureFailureBaseTime) or 1) * 100,
        tonumber(oilPressureFailureDamage) or 0,
        tonumber(oilPressureFailureMaxDamage) or 1,
        tostring(oilPressureFailureActive)
    ))

        printDebug("Fuel Pump failure", string.format(
            "Gas: %.3f | Fuel flows: %.1f%% | Status: %s",
            tonumber(acCarPhysics.gas) or 0,  -- Ensuring gas is a number, default to 0 if nil
            tonumber(fuelPumpFailureCooldown) or 0,  -- Ensure a valid number (module-local; shows 0 in debug)
            tostring(fuelPumpFailed) -- Convert boolean/nil to string safely
        ))
        --printDebug("Fuel Pump Repair", string.format("[%-30s] %.1f sec left", string.rep("#", (fuelPumpPitTimer / fuelPumpRepairTime) * 30), fuelPumpRepairTime - fuelPumpPitTimer))

        local currGearIndex = getCurrentGearIndex()
        printDebug("Gearbox Status", "Gear " .. currGearIndex .. ": " .. tostring(deadGears[currGearIndex]))
        printDebug("Fuel Pump", "Active: " .. tostring(fuelPumpFailed))
    end

    -- PSG update loop
    if gearboxIsPSG then

        if not psgInitialized then
            initPSG(ac, overheadMessageQueue)
            psgInitialized = true
        end

        updatePSG(dt,thisCar)
    end

    -- Simulate gear failure by cutting throttle
    local currentGearIndex = getCurrentGearIndex()
    if currentGearIndex > 0 and deadGears[currentGearIndex] then
        acCarPhysics.clutch = 0.1 + math.random() * 0.4  -- Generates a value between 0.1 and 0.6 - Fuck up failed gears
        --overheadMessageQueue("Gear failure", "Gear "..(currentGearIndex).." is broken!", 3)
    end

    acCarPhysics.controllerInputs[2] = currentSpares
    acCarPhysics.controllerInputs[4] = brakesFailed
    acCarPhysics.controllerInputs[7] = oilPressureFailureActive
    acCarPhysics.controllerInputs[8] = valveFailureActive
    acCarPhysics.controllerInputs[9] = fuelPumpFailed
    acCarPhysics.controllerInputs[10] = sparkPlugFailed
    acCarPhysics.controllerInputs[12] = gearboxRepairInProgress
    acCarPhysics.controllerInputs[13] = fuelPumpRepairInProgress
    acCarPhysics.controllerInputs[14] = isAnyGearBroken()
    acCarPhysics.controllerInputs[15] = hasRadiatorDamage or hasRadiatorMajorDamage
    acCarPhysics.controllerInputs[16] = isAnyTyrePunctured()
    acCarPhysics.controllerInputs[17] = tyreStockEmpty
    acCarPhysics.controllerInputs[20] = ac.getAltitude()
    acCarPhysics.controllerInputs[21] = acCarPhysics.airDensity
    acCarPhysics.controllerInputs[22] = superchargerExists
    acCarPhysics.controllerInputs[23] = isAboveBoostLimit()

    if not isCarInPits and superchargerExists == 1 then
        local currentFailedTurboCount = getFailedTurboCount()
        acCarPhysics.controllerInputs[24] = currentFailedTurboCount

        if currentFailedTurboCount > prevFailedTurboCount then
            if turboSmokeTimer < turboSmokeDuration then
                acCarPhysics.controllerInputs[25] = 0
            end
            turboSmokeTimer = 0
        end

        prevFailedTurboCount = currentFailedTurboCount

        if turboSmokeTimer < turboSmokeDuration then
            turboSmokeTimer = turboSmokeTimer + dt
        end

        if turboSmokeTimer < turboSmokeDuration then
            -- Delay the sound a bit, otherwise if another supercharger
            -- explodes during the `turboSmokeDuration` time, then
            -- the event wouldn't be caught in `supercharger.lua`.
            if turboSmokeTimer > 0.5 then
                acCarPhysics.controllerInputs[25] = 1
            end
        else
            acCarPhysics.controllerInputs[25] = 0
        end

        printDebug("turboSmokeTimer", "" .. turboSmokeTimer)
    end

    if resetBrakeWearAtTyreChange == nil then
        acCarPhysics.controllerInputs[26] = false
    else
        acCarPhysics.controllerInputs[26] = resetBrakeWearAtTyreChange
    end

    acCarPhysics.controllerInputs[27] = carHasTeleportedToPits

    acCarPhysics.controllerInputs[28] = thisCar.fuelMap
    printDebug("Fuelmap", "" .. thisCar.fuelMap)
    acCarPhysics.controllerInputs[29] = radiatorSetup
    acCarPhysics.controllerInputs[30] = turboEnabled
    acCarPhysics.controllerInputs[31] = getDistanceToClosestTyreStack()
    printDebug("Distance to closest tyre stack", acCarPhysics.controllerInputs[31])
    acCarPhysics.controllerInputs[32] = getOverrevvingState()
    printDebug("OverrevvingState", acCarPhysics.controllerInputs[32])
    acCarPhysics.controllerInputs[33] = fuelLeakageDamage
    acCarPhysics.controllerInputs[34] = fuelExhaustionAmount

    acCarPhysics.controllerInputs[35] = sparkPlugFailureRate
    acCarPhysics.controllerInputs[36] = fuelPumpFailureRate
    acCarPhysics.controllerInputs[37] = oilPressureFailureRate
    acCarPhysics.controllerInputs[38] = valveFailureRate
    acCarPhysics.controllerInputs[39] = brakeFadeStart
    acCarPhysics.controllerInputs[40] = brakeWearLevel

    acCarPhysics.controllerInputs[41] = getLowRpmState()

    -- 0 = nothing's happening, 1 = fetching tyre, 2 = changing tyre, 3 = tyre change done
    acCarPhysics.controllerInputs[42] = roadsideTyreChange
    -- 43 - 48: electricity stuff
    -- 49 & 50 == PSG
    acCarPhysics.controllerInputs[51] = ignitionType
    -- 52 == Alternator being repaired 0 or 1
end
-- MAIN UPDATE ENDS
