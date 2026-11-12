-- Tyre system: punctures, wear, roadside replacement, and crash-blow detection.

require "script_car_parameters"

-- Shared state (globals)
tyrePressures = {} --store the original tyre pressures here (do it when exiting pits)
tyrevKMs = {} --store the tyre vKMs here
tyreWear = {}
prevTyreWear = {}
tyrePunctureRates = {}
isCarInPits = false
currentSpares = 2 -- get this when exiting pits
tyreChangeInProgress = false --is the car changing a tyre
roadsideTyreChange = 0
tyreStockEmpty = false
carStoppedTimer = 0 --the timer to check if car is stopped for a tyre replacement
tyrePunctureTestIndex = -1 -- used by test code

-- Module-local tyre state
local prevDamageFront = thisCar.damage[0]
local prevDamageRear = thisCar.damage[1]
local prevDamageLeft = thisCar.damage[2]
local prevDamageRight = thisCar.damage[3]

-- Tyre stack placement (roadside spare service)
local maxDistanceBetweenTyreStacks = 1000
local tyreStacksPerLap = math.max(math.ceil(ac.getSim().trackLengthM / maxDistanceBetweenTyreStacks) - 1, 2)
local tyreStacksPositions = {}

local tyreReplacementTime = ac.INIConfig.carData(0, 'car.ini'):get('PIT_STOP', 'TYRE_CHANGE_TIME_SEC', 55)

function initTyrePunctureRates()
    for i = 0, 3 do
        tyrePunctureRates[i] = 0.0
    end
end

function initTyrePunctureTables()
    for i = 0, 3 do
        tyrePunctureDeflateFactor[i] = 0.0
        tyrePuncturePressureFactor[i] = 0.0
    end
end

function initTyreWearTable()
    for i = 0, 3 do
        tyreWear[i] = 0.0
        prevTyreWear[i] = 0.0
    end
end

local function initTyreStacksPositions()
    local trackLength = ac.getSim().trackLengthM
    for i = 0, tyreStacksPerLap - 1 do
        local position = (i * trackLength) / tyreStacksPerLap
        table.insert(tyreStacksPositions, position)
    end

    -- Insert the track length at the end to complete the loop.
    table.insert(tyreStacksPositions, trackLength)

    printDebug("tyreStacksPositions", tyreStacksPositions)
    printDebug("Tyre stack count", tyreStacksPerLap)
end

function getDistanceToClosestTyreStack()
    local carPositionOnTrack = thisCar.splinePosition * ac.getSim().trackLengthM
    -- Find the distance to the closest tyre stack.
    local closestTyreStackDistance = math.huge
    for i = 1, #tyreStacksPositions do
        local stackPosition = tyreStacksPositions[i]
        local distance = math.abs(stackPosition - carPositionOnTrack)
        if distance < closestTyreStackDistance then
            closestTyreStackDistance = distance
        end
    end

    return closestTyreStackDistance
end

-- Get tyre change time. If we're doing a roadside tyre change, calculate the time based on
-- the distance to the closest tyre stack.
function getTyreChangeTime()
    if currentSpares >= 0 then
        return tyreReplacementTime
    end

    local jeffRunSpeedMs = 4.0
    local timeToTyreStackAndBack = getDistanceToClosestTyreStack() / jeffRunSpeedMs * 2
    printDebug("Time to tyre stack and back", timeToTyreStackAndBack)

    return tyreReplacementTime + timeToTyreStackAndBack
end

function getCurrentSpares()
    local spares = ac.getScriptSetupValue("SPARE_WHEELS")()
    printDebug("Current spares", spares)
        if spares == "Trackside" then
            spares = -1
        end

    return spares
end

local function debugTyrevKMs()
    for i = 0, 3 do
        printDebug("tyrevKM_" .. i, tyrevKMs[i])
    end
end

function getWheelName(tyreIndex)
    wheelNames = {"Front left", "Front right", "Rear left", "Rear right"}
    return wheelNames[tyreIndex + 1]
end

function generateSlowPuncture(tyreIndex, minFactor, maxFactor)
    -- Generate a factor to use deflating the tyre, defining the speed of deflation.
    -- This value will be subtracted from the pressure factor 10 times a second.
    tyrePunctureDeflateFactor[tyreIndex] = 1 / math.random(minFactor, maxFactor)
    -- Set the tyre pressure factor to start the deflation from. See ac.setTyreInflation() comment in slowTyrePuncture().
    tyrePuncturePressureFactor[tyreIndex] = 1.0
    overheadMessageQueue("Tyre puncture", getWheelName(tyreIndex) .. " tyre is leaking!", 3)
    printDebug(string.format("Puncture factor, tyre: %d", tyreIndex), string.format("%f", tyrePunctureDeflateFactor[tyreIndex]))
    logDebug("<FLR>Tyre Puncture, tyre: ", tyreIndex, " Deflate factor: ", tyrePunctureDeflateFactor[tyreIndex], true)
end

function getTyreTypeFactor()
    local tyreName = ac.getTyresName(thisCar.index)
    printDebug("tyreName", tyreName)
    local tyreTypeFactor = 1
    for i = 1, #tyreTypeFactors do
        if tyreName == tyreTypeFactors[i][1] then
            tyreTypeFactor = tyreTypeFactors[i][2]
            break
        end
    end

    return tyreTypeFactor
end

--tyre blow function. rest of tyre stuff in other functions
function tyreBlow()
    local checkTyreBlow = not isCarInPits and thisCar.speedKmh > 1
    local tyreTypeFactor = getTyreTypeFactor()
    printDebug("tyreTypeFactor", tyreTypeFactor)

    for i = 0, 3 do
        -- Car must be out of the pits and not in the grid, moving and tyre must not be already punctured.
        if checkTyreBlow and tyrePunctureDeflateFactor[i] == 0.0 then
            local rateToUse = 0

            if thisCar.wheels[i].surfaceExtendedType == ac.SurfaceExtendedType.Gravel then
                rateToUse = tyrePunctureRateGravel
                ac.setTyreWearMultiplier(i, tyreWearGravel)
                trackSurfaceType = ac.SurfaceExtendedType.Gravel
            elseif thisCar.wheels[i].surfaceExtendedType == ac.SurfaceExtendedType.Ice or
                   thisCar.wheels[i].surfaceExtendedType == ac.SurfaceExtendedType.Snow then
                rateToUse = tyrePunctureRateIce
                ac.setTyreWearMultiplier(i, tyreWearIce)
                trackSurfaceType = ac.SurfaceExtendedType.Ice
            else
                rateToUse = tyrePunctureRateAsphalt
                ac.setTyreWearMultiplier(i, tyreWearAsphalt)
                trackSurfaceType = ac.SurfaceExtendedType.Base
            end

            -- Modify rateFactor so that more worn tyres are more likely to puncture. The tyreWear table
            -- contains the accumulated wear since the start of the session, 0 meaning brand new tyres and
            -- 1 meaning fully worn tyres.
            local tyreWearFactor = 1.0 - math.min(tyreWear[i] * tyreTypeFactor, 0.999)
            rateToUse = math.floor(rateToUse * tyreWearFactor + 0.5)
            printDebug(string.format("Puncture rate, tyre: %d", i), string.format("%d", rateToUse))
            tyrePunctureRates[i] = rateToUse

            local tyrePunctureTesting = false
            if TEST_CODE and tyrePunctureTestIndex == i then
                tyrePunctureTesting = true
            end
            if math.random(1, rateToUse) == 1 or tyrePunctureTesting then
                generateSlowPuncture(i, minPunctureDeflateFactor, maxPunctureDeflateFactor)
            end
        end

        --check tyre pressure for each wheel and set to blow if it's too high
        if thisCar.wheels[i].tyrePressure > tyreBlowPressure and thisCar.wheels[i].isBlown == false and tyrePunctureDeflateFactor[i] == 0.0 then
            -- In this case, make sure the tyre always deflates quickly.
            generateSlowPuncture(i, minPunctureDeflateFactor, minPunctureDeflateFactor)

            if currentSpares > 0 then
                overheadMessageQueue("Spares available", "You have " .. currentSpares .. " spares left, pull over to the side when safe.", 2)
            else
                overheadMessageQueue("No spares", "You have no spares left, just get to the pits safely!", 2)
            end
        end
        --check tyrevKM and blow it if its past its life
        if thisCar.wheels[i].tyreVirtualKM > tyrevKMs[i] and thisCar.wheels[i].isBlown == false and tyrePunctureDeflateFactor[i] == 0.0 then
            generateSlowPuncture(i, minPunctureDeflateFactor, maxPunctureDeflateFactor)

            if currentSpares > 0 then
                overheadMessageQueue("Spares available", "You have " .. currentSpares .. " spares left, pull over to the side when safe.", 2)
            else
                overheadMessageQueue("No spares", "You have no spares left, just get to the pits safely!", 2)
            end
        end
    end
end--end of tyre blow function

-- Slow tyre puncture: deflate the tyre over time.
function slowTyrePuncture()
    for i = 0, 3 do
        -- If the tyre is punctured, we need to deflate it.
        if tyrePunctureDeflateFactor[i] > 0.0 then
            -- Calculate new (deflated) pressure factor and set it to the tyre.
            tyrePuncturePressureFactor[i] = tyrePuncturePressureFactor[i] - tyrePunctureDeflateFactor[i]
            -- Limit the pressure factor to 0, to blow the tyre.
            if tyrePuncturePressureFactor[i] < 0 then
                tyrePuncturePressureFactor[i] = 0
            end
            -- Set the deflated tyre pressure. setTyreInflation() takes a "percentage" as a parameter,
            -- from 0 to 1. 1 sets the full original pressure, and e.g. 0,5 sets half of that. For
            -- example, if the original pressure value was 50 psi, setting 0,5 here would set the pressure
            -- to 25 psi. When the factor reaches zero, the tyre will be blown.
            ac.setTyreInflation(i, tyrePuncturePressureFactor[i])

            printDebug(string.format("Set tyre: %d", i), string.format("deflated pressure: %f", tyrePuncturePressureFactor[i]))
        end
    end
end

function isAnyTyrePunctured()
    for i = 0, 3 do
        if tyrePunctureDeflateFactor[i] > 0.0 then
            return true
        end
    end
    return false
end

function updateTyreWear()
    for i = 0, 3 do
        if thisCar.wheels[i].tyreWear > prevTyreWear[i] then
            local wearDiff = thisCar.wheels[i].tyreWear - prevTyreWear[i]
            tyreWear[i] = tyreWear[i] + wearDiff
            prevTyreWear[i] = thisCar.wheels[i].tyreWear
            printDebug(string.format("tyreWear " .. i), tyreWear[i])
        end
    end
end

--helper function for generating a fresh tyre.
function generateTyrevKM()
    local randomFactor = math.random() -- Uniform random value between 0 and 1
    -- Apply weighting toward the upper end of the range
    local weightedLife = tyreBasevKM + (tyrevKMvariance * (randomFactor ^ biasStrength))
    return weightedLife
end

local function blowTyreAtCrash(damageDiff, sideDamage1, sideDamage2, tyre1, tyre2)
    local tyreToBlow = 0
    local rate = tyreBlowCrashingRate

    -- In a really hard crash, just blow both tyres.
    if damageDiff > tyreBlowDamageChangeMax then
        ac.setTyreInflation(tyre1, 0)
        ac.setTyreInflation(tyre2, 0)
        return
    end

    -- Check if there is enough change in damage to blow a tyre.
    if damageDiff > tyreBlowDamageChange then
        -- Is the damage hard enough to blow the tyre using 100% probability?
        if damageDiff > tyreBlowDamageChangeHard then
            rate = 1
        end

        -- Blow the tyre from that side, which has more damage.
        -- For example, if this is a front crash, then choose left or right.
        if sideDamage1 > sideDamage2 then
            tyreToBlow = tyre1
        else
            tyreToBlow = tyre2
        end

        if math.random(1, rate) == 1 then
            ac.setTyreInflation(tyreToBlow, 0)
        end
    end
end

-- Blow a tyre when the car is crashed into something. Check the change in
-- car damage, and when it exceeds the predefined value, then blow a tyre.
function tyreBlowWhenCrashing()
    printDebug("-Front dmg", thisCar.damage[0])
    printDebug("-Rear dmg", thisCar.damage[1])
    printDebug("-Left dmg", thisCar.damage[2])
    printDebug("-Right dmg", thisCar.damage[3])

    -- Front crash.
    blowTyreAtCrash(thisCar.damage[0] - prevDamageFront, thisCar.damage[2], thisCar.damage[3], 0, 1)
    -- Rear crash.
    blowTyreAtCrash(thisCar.damage[1] - prevDamageRear, thisCar.damage[2], thisCar.damage[3], 2, 3)
    -- Left crash.
    blowTyreAtCrash(thisCar.damage[2] - prevDamageLeft, thisCar.damage[0], thisCar.damage[1], 0, 2)
    -- Right crash.
    blowTyreAtCrash(thisCar.damage[3] - prevDamageRight, thisCar.damage[0], thisCar.damage[1], 1, 3)

    prevDamageFront = thisCar.damage[0]
    prevDamageRear = thisCar.damage[1]
    prevDamageLeft = thisCar.damage[2]
    prevDamageRight = thisCar.damage[3]
end

--tyre replacement bits - this function is the whole routine
function tyreReplacement(dt)
    --dont check if speed is just 0, chances are that ac sometimes breaks and doesnt let you come to a full stop
    if (thisCar.speedKmh < 1 and thisCar.handbrake == 1 or tyreChangeInProgress) and not isRepairingBelt then
        carStoppedTimer = carStoppedTimer + dt

        --starting the tyre replacement routine
        if carStoppedTimer > tyreReplacementReactionTime and tyreChangeInProgress == false then
            --check that there is actually a burst tyre
            blownTyres = false
            for i = 0, 3 do
                if thisCar.wheels[i].isBlown or tyrePunctureDeflateFactor[i] > 0.0 then
                    tyreChangeInProgress = true
                    blownTyres = true
                end
            end
            --check that you have an available spare, if not, cancel routine
            --also reset the timer, no point in checking it every tick if you dont have a spare
            if currentSpares == 0 then
                tyreChangeInProgress = false
                blownTyres = false
                ac.setSystemMessage("You have no spare tyres left", "Drive carefully to the pits")
            end
            if blownTyres == false then
                carStoppedTimer = 0
            end
        end

        --tyre change routine, seize controls
        if tyreChangeInProgress then
            acCarPhysics.gas = 0
            acCarPhysics.brake = 1
            acCarPhysics.handbrake = 1
            local tyreChangeTime = getTyreChangeTime()
            if carStoppedTimer < tyreChangeTime - tyreReplacementTime then
                ac.setSystemMessage("Fetching tyre", "Getting a tyre from the nearest stack...")
                roadsideTyreChange = 1
            else
                ac.setSystemMessage("Changing tyre", "Sit tight...")
                roadsideTyreChange = 2
            end
            --skip the queue for this because its essential info regardless
            --and also breaks the queue by spamming it

            --end the routine once the time has passed
            if carStoppedTimer > getTyreChangeTime() then
                overheadMessageQueue("Tyre change complete", "!VAMOS!", 2)
                tyreChangeInProgress = false
                roadsideTyreChange = 3
                currentSpares = math.max(currentSpares - 1, -1)
                if currentSpares > 0 then
                    overheadMessageQueue("Tyre change complete", "You have " .. currentSpares .. " spares left.", 3)
                end
                if currentSpares == 0 then
                    tyreStockEmpty = true
                else
                    tyreStockEmpty = false
                end
                carStoppedTimer = 0
                for i = 0, 3 do
                    if thisCar.wheels[i].isBlown or tyrePunctureDeflateFactor[i] > 0.0 then
                        ac.setTyreInflation(i, tyrePressures[i])
                        --because current vKM doesnt reset when just reinflating the tyre, add the existing vKM on top.
                        tyrevKMs[i] = thisCar.wheels[i].tyreVirtualKM + generateTyrevKM()
                        tyrePunctureDeflateFactor[i] = 0.0
                        -- Reset the tyre wear for the replaced tyre.
                        tyreWear[i] = 0.0
                        break;
                    end
                end--find the first tyre and repair it
            end--end of repair routine

        end--end of seizing controls
        acCarPhysics.controllerInputs[3] = carStoppedTimer
    end--end of stop-checking

    if thisCar.speedKmh > 30 then
        roadsideTyreChange = 0
    end

    printDebug("Tyre change state", roadsideTyreChange)
end--end of tyre replacement function

-- Initialise on load
initTyrePunctureRates()
initTyrePunctureTables()
initTyreWearTable()
initTyreStacksPositions()
