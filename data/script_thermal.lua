-- Engine thermal simulation: coolant temperature, engine temperature, radiator setup.
-- Also handles engine damage limiting at light side collisions.

require "script_car_parameters"

-- Shared state (globals accessible to script.lua for reset, logging, etc.)
coolantTemp = 70 --store our own water temp, since the AC one is arbitrary and read-only.
engineTemp = 70  --engine core temp - once this hits the meltdown value its OVER.
radiatorCoolCoefficient = radiatorCoolCoefficientInitialValue
radiatorCoolCoefficientBase = radiatorCoolCoefficientInitialValue
hasRadiatorDamage = false
hasRadiatorMajorDamage = false
brakesFailed = false
totalMeltdown = false
waterTempWarning = false

-- Module-local thermal state
local airAmbientTemp = ac.getSim().ambientTemperature --get the ambient air temp, it will affect the coolant temperature cool factor

-- State for limitEngineDamageAtCrash. prevDamage*Engine are global so that
-- the test code in script_debug.lua can manipulate them to simulate crashes.
local bodyDamageLimitAtCrashEngine = 20
prevDamageFrontEngine = 0
prevDamageRearEngine = 0
prevDamageLeftEngine = 0
prevDamageRightEngine = 0
local currentEngineLifeLeft = acCarPhysics.engineLifeLeft

-- carDamageClamp is assigned inside coolantBehavior without `local`, making it
-- a global, consistent with the original code (read by the DEBUG block in update()).

function getBrakeDuctWingGain(brakeDuctPercentage)
    local steps = {
        {duct = 0, wingGain = 1.00000},
        {duct = 30, wingGain = 0.99200},
        {duct = 60, wingGain = 0.98400},
        {duct = 90, wingGain = 0.97600},
    }

    -- Find the step with the brakeDuctPercentage value. Default to the first step if not found.
    local s = steps[1]
    for _, step in ipairs(steps) do
        if step.duct == brakeDuctPercentage then
            s = step
            break
        end
    end

    return s.wingGain
end

--radiator setup
function applyRadiatorSetup(setup)
    local flapPosition = {
        "Shutters fully open",
        "Shutters one quarter closed",
        "Shutters half closed",
        "Shutters three quarters closed",
        "Shutters almost closed"
    }

    -- Get brake duct settings from setup and combine their effects with the radiator setup.
    local brakeDuctPercentageFront = ac.getScriptSetupValue("BRAKE_DUCT_F")()
    printDebug("BrakeDuct F", brakeDuctPercentageFront)
    local brakeDuctPercentageRear = ac.getScriptSetupValue("BRAKE_DUCT_R")()
    printDebug("BrakeDuct R", brakeDuctPercentageRear)
    local brakeDuctWingGainFront = getBrakeDuctWingGain(brakeDuctPercentageFront)
    printDebug("BrakeDuct Wing Gain F", brakeDuctWingGainFront)
    local brakeDuctWingGainRear = getBrakeDuctWingGain(brakeDuctPercentageRear)
    printDebug("BrakeDuct Wing Gain R", brakeDuctWingGainRear)

    -- map setup steps to wing gain + cooling multiplier
    local steps = {
        {wingIndex = 0, wingGain = 1.00000, coolMul = 1.00},
        {wingIndex = 0, wingGain = 0.98000, coolMul = 0.85},
        {wingIndex = 0, wingGain = 0.96000, coolMul = 0.70},
        {wingIndex = 0, wingGain = 0.94000, coolMul = 0.55},
        {wingIndex = 0, wingGain = 0.92000, coolMul = 0.40},
    }
    local s = steps[setup + 1]
    ac.setWingGain(s.wingIndex, s.wingGain * brakeDuctWingGainFront * brakeDuctWingGainRear, 1)
    printDebug("Combined Wing Gain", s.wingGain * brakeDuctWingGainFront * brakeDuctWingGainRear)
    radiatorCoolCoefficientBase = radiatorCoolCoefficientInitialValue * s.coolMul
    return flapPosition[setup + 1]
end

--coolant behavior/engine damage handling
function coolantBehavior(dt)
    carDamageClamp = math.clampN((thisCar.damage[0] + thisCar.damage[2] + thisCar.damage[3]) / 3 * 0.01, 0, 1)
    --clamp the actual bumper damage as ac can make it over 100%
    if thisCar.damage[0] > 30 or thisCar.damage[2] > 35 or thisCar.damage[3] > 35 then
        if hasRadiatorDamage == false then
            hasRadiatorDamage = true
            overheadMessageQueue("Cooling damage", "Engine cooling is slightly damaged. Watch for engine temps.", 2)
        end
    end

    --if damage is over 50% you lose some of the brake power
    if thisCar.damage[0] > 50 or thisCar.damage[2] > 50 or thisCar.damage[3] > 50 then
        if brakesFailed == false then
            brakesFailed = true
            overheadMessageQueue("Brake problem", "Front damage caused brakes to lose power. Take it careful!", 3)
        end
    end
    if brakesFailed == true then
        if randomBrakeLimit == nil then
            randomBrakeLimit = 0.4 + math.random() * (0.9 - 0.4)
        end
        if acCarPhysics.brake > randomBrakeLimit then
            acCarPhysics.brake = randomBrakeLimit
        end
    end


    if thisCar.damage[0] > 75 or thisCar.damage[2] > 75 or thisCar.damage[3] > 75  then
        if hasRadiatorMajorDamage == false then
            hasRadiatorMajorDamage = true
        if acCarPhysics.engineLifeLeft > 500 then
            acCarPhysics.engineLifeLeft = 500
        end
        overheadMessageQueue("Major radiator damage", "Engine cooling has major damage. Watch for engine temps.", 2)
        end
    end

    if engineTemp > engineOverboilTemp and totalMeltdown == false then
        totalMeltdown = true
        overheadMessageQueue("Engine meltdown", "Your racing prospects are over!", 5)
        acCarPhysics.engineLifeLeft = 0
    end

    if coolantTemp > engineOverboilTemp - 5 and not waterTempWarning then
        overheadMessageQueue("Coolant temperature", "Water temperature is nearing boiling point. Hold off the throttle.", 3)
        waterTempWarning = true
    end

    if engineTemp > engineOverboilTemp - 5 then
        if acCarPhysics.gas > 0.8 then
            acCarPhysics.gas = 0.8
        end
    end

    --all the radiator/engine thermals are handled here

    engineAmbientFactor = math.clamp(math.log(engineTemp - airAmbientTemp) * engineTemp^0.01 * engineCoolAmbientFalloff, 0, 1)
    radiatorAmbientFactor = math.clamp(math.log(coolantTemp - airAmbientTemp) * coolantTemp^0.01 *engineCoolAmbientFalloff, 0, 1)

    engineHeatingFactor = (1 - engineGainThrottleCoefficient^(-5 * (thisCar.rpm * 0.0001))) * currentEngineHeatGainMult * acCarPhysics.gas

    if oilPressureFailureActive == true then
        engineHeatingFactor = engineHeatingFactor * 1.25
    end

    engineCoolingFactor = (engineBaseCoolCoefficient + engineSpeedCoolCoefficient * thisCar.speedKmh^2) * engineAmbientFactor
    engineTemp = engineTemp + ((engineHeatingFactor - engineCoolingFactor) * dt)

    -- Speed-based radiator cooling is scaled by shutter position: closed shutters block
    -- ram-air cooling just as they block convective cooling.
    local shutterFactor = math.clamp(radiatorCoolCoefficient / radiatorCoolCoefficientInitialValue, 0, 1)
    radiatorCoolingFactor = (math.clamp(radiatorCoolCoefficient - (radiatorDamageCoefficientLoss * carDamageClamp), 0, 1) + radiatorSpeedCoolCoefficient * thisCar.speedKmh^2 * shutterFactor) * radiatorAmbientFactor
    coolantTemp = coolantTemp - (radiatorCoolingFactor * dt)

    --temperatureAvg = ((engineTemp * engineCoolantTransferGain) + (coolantTemp * (1 - engineCoolantTransferGain))) * 0.5
    temperatureDifferential = (engineTemp - coolantTemp) * dt

    -- Heat only flows from engine to coolant, not reverse. In reality the engine block does absorb
    -- heat from coolant during off-throttle phases, but on a much longer time scale than this
    -- simplified model allows — the bidirectional transfer caused coolant to drain back to 70°C
    -- every time the driver lifted off, preventing any temperature accumulation.
    if temperatureDifferential > 0 then
        engineTemp = engineTemp - (temperatureDifferential * engineCoolantTransferGain)
        coolantTemp = coolantTemp + (temperatureDifferential * engineCoolantTransferGain)
    end

    --give weighted transfer gains another try once i get back home
    --engineTemp = engineTemp - (temperatureDifferential * engineCoolantTransferGain)
    --coolantTemp = coolantTemp + (temperatureDifferential * (1 - engineCoolantTransferGain))

    --coolantTemp = math.lerp(coolantTemp, temperatureAvg, 0.5)
    --engineTemp = math.lerp(engineTemp, temperatureAvg, 0.5)

    --prevent temps go under 70 if idle or waiting for race start
    coolantTemp = math.max(coolantTemp, 70)
    engineTemp = math.max(engineTemp, 70)

    acCarPhysics.controllerInputs[0] = coolantTemp
    acCarPhysics.controllerInputs[1] = engineTemp
    --these dynamic controllers can be read by analog or digital instruments with INPUT = CPHYS_SCRIPT_X

end--end of coolant behavior function

function limitEngineDamageAtCrash()
    -- When the car touches for example a wall just slightly, the engine can take a huge amount of damage,
    -- which is not very realistic. To limit this, we can check the change in damage at front, and if it's
    -- not too big, then we can limit the engine damage.
    local damageDiffFront = thisCar.damage[0] - prevDamageFrontEngine
    local damageDiffRear = thisCar.damage[1] - prevDamageRearEngine
    local damageDiffLeft = thisCar.damage[2] - prevDamageLeftEngine
    local damageDiffRight = thisCar.damage[3] - prevDamageRightEngine
    printDebug("DmgFront", thisCar.damage[0])
    printDebug("DmgRear", thisCar.damage[1])
    printDebug("DmgLeft", thisCar.damage[2])
    printDebug("DmgRight", thisCar.damage[3])

    if damageDiffLeft > 0 or damageDiffRight > 0 then
        if damageDiffFront < bodyDamageLimitAtCrashEngine and damageDiffRear < bodyDamageLimitAtCrashEngine then
            local maxEngineDamage = math.min(currentEngineLifeLeft - acCarPhysics.engineLifeLeft, (damageDiffFront + damageDiffRear) * 10)
            printDebug("damageDiffFront", damageDiffFront)
            printDebug("damageDiffRear", damageDiffRear)
            printDebug("Engine life left before", currentEngineLifeLeft)
            ac.setEngineLifeLeft(currentEngineLifeLeft - maxEngineDamage)
            printDebug("Engine life left after", acCarPhysics.engineLifeLeft)
        end
    end

    printDebug("Engine life", acCarPhysics.engineLifeLeft)
    prevDamageFrontEngine = thisCar.damage[0]
    prevDamageRearEngine = thisCar.damage[1]
    prevDamageLeftEngine = thisCar.damage[2]
    prevDamageRightEngine = thisCar.damage[3]
    currentEngineLifeLeft = acCarPhysics.engineLifeLeft
end
