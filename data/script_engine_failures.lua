-- Engine failure simulation: spark plug, fuel pump, valve, and oil pressure failures.
-- Also handles in-pit fuel pump repair.

require "script_car_parameters"

-- Shared failure state (globals, reset by setupBits/resetCar in script.lua)
sparkPlugFailed = false
fuelPumpFailed = false
valveFailed = false
oilPressureFailed = false

-- Valve failure state
valveFailureMinDamage = thisCar.engineLifeLeft
valveFailureDamage = valveFailureMinDamage
-- Oil pressure failure state
oilPressureMinDamage = thisCar.engineLifeLeft
oilPressureFailureDamage = oilPressureMinDamage

-- Module-local failure state
local fuelPumpFailureCooldown = 0
local fuelPumpFailureDuration = 0
local fuelPumpCutoffActive = false
local valveWarning = false
local oilPressureWarning = false
local oilPressureWarning2 = false

--spark plug failure
--simply, if you roll unlucky, you get slapped with random engine damage between certain values.
--if you already have more damage, its skipped.
function sparkPlugFailure()
    if sparkPlugFailed == false then
        if math.random(1, sparkPlugFailureRate) == 1 then
            sparkPlugFailed = true
            if acCarPhysics.engineLifeLeft > sparkPlugFailureDamage then
                ac.setEngineLifeLeft(sparkPlugFailureDamage)
                -- recalculate spark plug failure amount
                --math.randomseed(os.time() + math.random(0, 10000))
                sparkPlugFailureDamage = math.random(200, 600)
                overheadMessageQueue("Spark plug failure", "You may experience engine cut-offs and power loss", 10)
                -- audioQueue("sparkplugFailure")
                logDebug("<FLR>Spark Plug Fail, rate: ", sparkPlugFailureRate, true)
            end
        end
    end
    printDebug("Spark Plug Failure", string.format("Status: %s | Amount: %.2f", tostring(sparkPlugFailed), sparkPlugFailureDamage))

end --end of spark plug failure

function fuelPumpFailureActivation()
    -- Only check for activation if not already failed
    if not fuelPumpFailed then
        -- Roll for failure (every 2 seconds)
        if math.random(1, fuelPumpFailureRate) == 1 then
            fuelPumpFailed = true
            fuelPumpFailureDuration = math.random(1, 3)
            fuelPumpFailureCooldown = math.random(4, 7)
            overheadMessageQueue("Fuel Pump Failure", "Fuel flow disrupted!", 5)
            printDebug("Fuel Pump", "Failure activated!")
            logDebug("<FLR>Fuel Pump Fail, rate: ", fuelPumpFailureRate, true)
        end
    end
end

function fuelPumpFailure(dt)
    -- Only process if failed state is active
    if not fuelPumpFailed then return end

    -- Failure behavior system (runs every tick)
    if fuelPumpCutoffActive then
        -- Active cutoff phase
        fuelPumpFailureDuration = fuelPumpFailureDuration - dt
        acCarPhysics.gas = 0  -- Hard throttle cutoff
        if fuelPumpFailureDuration <= 0 then
            fuelPumpCutoffActive = false
        end
    else
        -- Cooldown phase
        fuelPumpFailureCooldown = fuelPumpFailureCooldown - dt

        if fuelPumpFailureCooldown <= 0 then
            fuelPumpCutoffActive = true
            fuelPumpFailureDuration = math.random(1, 3)
            fuelPumpFailureCooldown = math.random(4, 7)
        end
    end

    -- Optional debug
    printDebug("Fuel Pump Behavior", string.format(
        "Cutoff: %s | Duration: %.1f | Cooldown: %.1f",
        tostring(fuelPumpCutoffActive),
        fuelPumpFailureDuration,
        fuelPumpFailureCooldown
    ))
end --end of fuel pump failure

--valve failure
--simply, if you roll unlucky, you get slapped with random engine damage between certain values.
--if you already have more damage, its skipped.
function valveFailure(dt)
    if not valveFailed then
        if math.random(1, valveFailureRate) == 1 then
            valveFailureActive = true
            valveFailed = true
            overheadMessageQueue("Valve problems", "Early stage valve issues detected", 5)
            logDebug("<FLR>Valve Fail, rate: ", valveFailureRate, true)
        end
        return
    end

    if valveFailureActive then
        -- RPM-based progression control
        if acCarPhysics.rpm > 0 and not totalMeltdown then
            valveFailureMinDamage = acCarPhysics.engineLifeLeft
            -- Calculate RPM factor (0-2.0 range)
            local rpmFactor = math.clamp(acCarPhysics.rpm / valveReferenceRPM, 0.1, 2.0)

            -- Effective time accumulation
            valveFailureElapsed = valveFailureElapsed + (dt * rpmFactor)

            -- Calculate progression (0-1)
            local progression = math.clamp(valveFailureElapsed / valveFailureBaseTime, 0, 1)

            -- Non-linear damage curve
            local damageProgression = progression^1.3  -- Faster initial degradation
            valveFailureDamage = math.lerp(valveFailureMinDamage, valveFailureMaxDamage, damageProgression)

            -- Apply damage if engine still has life
            if acCarPhysics.engineLifeLeft > valveFailureDamage then
                ac.setEngineLifeLeft(valveFailureDamage)
            end

            -- Progressive warnings
            if progression > 0.8 and not valveWarning then
                overheadMessageQueue("CRITICAL VALVE FAILURE", "Immediate pit stop required!", 10)
                valveWarning = true
            elseif progression > 0.5 then
                overheadMessageQueue("Severe valve damage", "Power loss increasing significantly", 5)
            end

            -- Final failure state
            if progression >= 1.0 then
                valveFailureActive = false
                ac.setEngineLifeLeft(valveFailureMaxDamage)
                overheadMessageQueue("Total Valve Failure", "Engine no longer operational", 0)
            end
        else
            -- Pause progression when engine is off/stalled
            overheadMessageQueue("Valve Damage Halted", "Engine shutdown paused deterioration", 2)
        end
    end

end --end of valve failure

--oil pressure failure
--simply, if you roll unlucky, you get slapped with random engine damage between certain values.
--if you already have more damage, its skipped.
function oilPressureFailure(dt)
    if not oilPressureFailed then
        if math.random(1, oilPressureFailureRate) == 1 then
            oilPressureFailureActive = true
            oilPressureFailed = true
            overheadMessageQueue("Oil pressure problems", "Early stage oil pressure issues detected", 5)
            logDebug("<FLR>Oil Pressure Fail, rate: ", oilPressureFailureRate, true)
        end
        return
    end

    if oilPressureFailureActive then
        -- RPM-based progression control
        if acCarPhysics.rpm > 0 and not totalMeltdown then
            oilPressureFailureMinDamage = acCarPhysics.engineLifeLeft
            -- Calculate RPM factor (0-2.0 range)
            local oilPressurerpmFactor = math.clamp(acCarPhysics.rpm / oilPressureReferenceRPM, 0.1, 2.0)

            -- Effective time accumulation
            oilPressureFailureElapsed = oilPressureFailureElapsed + (dt * oilPressurerpmFactor)

            -- Calculate progression (0-1)
            local oilPressureProgression = math.clamp(oilPressureFailureElapsed / oilPressureFailureBaseTime, 0, 1)

            -- Non-linear damage curve
            local oilPressureDamageProgression = oilPressureProgression^1.3  -- Faster initial degradation
            oilPressureFailureDamage = math.lerp(oilPressureFailureMinDamage, oilPressureFailureMaxDamage, oilPressureDamageProgression)

            -- Apply damage if engine still has life
            if acCarPhysics.engineLifeLeft > oilPressureFailureDamage then
                ac.setEngineLifeLeft(oilPressureFailureDamage)
            end

            -- Progressive warnings
            if oilPressureProgression > 0.8 and not oilPressureWarning then
                overheadMessageQueue("CRITICAL OIL PRESSURE", "Immediate pit stop required!", 10)
                oilPressureWarning = true
            elseif oilPressureProgression > 0.5 and not oilPressureWarning2 then
                overheadMessageQueue("Really low oil pressure", "Power loss and engine overheating increasing significantly", 5)
                oilPressureWarning2 = true
            end

            -- Final failure state
            if oilPressureProgression >= 1.0 then
                oilPressureFailureActive = false
                ac.setEngineLifeLeft(oilPressureFailureMaxDamage)
                overheadMessageQueue("Total oil pressure issue", "Engine no longer operational", 0)
            end
        else
            -- Pause progression when engine is off/stalled
            overheadMessageQueue("Engine stalled", "Cooling down", 2)
        end
    end

end --end of oil pressure failure

-- In-pit fuel pump repair routine. Call from update() when car is in pits.
function fuelPumpPitRepair(dt)
    if isCarInPits and fuelPumpFailed then
        -- Check if Extra B is pressed
        if thisCar.extraB and not fuelPumpRepairInProgress then
            fuelPumpRepairInProgress = true
            fuelPumpPitTimer = 0  -- Reset timer when repair starts
            overheadMessageQueue("Fuel Pump Repair", "Repair started. Hold position until done", 3)
            printDebug("Fuel Pump Repair", "Repair process started")
        end

        -- If repair is in progress, count time
        if fuelPumpRepairInProgress then
            fuelPumpPitTimer = fuelPumpPitTimer + dt

            -- Show repair progress
            ac.setSystemMessage("Fuel Pump Repair",
                    string.format("Progress: %.1f%%",
                    (fuelPumpPitTimer/fuelPumpRepairTime)*100))
            printDebug("Fuel Pump Repair Progress", string.format("%.1f sec left", fuelPumpRepairTime - fuelPumpPitTimer))

            -- When repair time has passed, complete the repair
            if fuelPumpPitTimer >= fuelPumpRepairTime then
                fuelPumpFailed = false
                fuelPumpRepairInProgress = false
                fuelPumpPitTimer = 0
                fuelPumpRepairTime = math.random(30, 180)

                -- Reset failure rates to initial values, as the pump has been fixed.
                fuelPumpFailureRate = fuelPumpFailureRateInitialValue
                fuelPumpFailureRateBase = fuelPumpFailureRateInitialValue

                overheadMessageQueue("Fuel Pump Repaired", "You're good to go!", 3)
                printDebug("Fuel Pump Repair", "Repair complete!")
            end
        end
    else
        -- Reset if car leaves pits
        fuelPumpRepairInProgress = false
        fuelPumpPitTimer = 0
    end
end
