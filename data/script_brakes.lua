-- Brake wear simulation.
-- Accumulates wear based on brake input and wheel speed, then applies a fade effect.

require "script_car_parameters"

local function lerp(a, b, t) return a + (b - a) * t end

local function getWearMultiplier(rpmFactor)
    for i = 1, #wearLUT - 1 do
        if rpmFactor >= wearLUT[i][1] and rpmFactor <= wearLUT[i+1][1] then
            local t = (rpmFactor - wearLUT[i][1]) / (wearLUT[i+1][1] - wearLUT[i][1])
            return lerp(wearLUT[i][2], wearLUT[i+1][2], t)
        end
    end
    return wearLUT[#wearLUT][2]
end

function brakeWear(dt)
    -- BRAKE WEAR STUFF START
    local totalWear = 0
    local brakeInput = acCarPhysics.brake

    -- Calculate wear for each wheel
    for i = 0, 3 do
        local wheel = acCarPhysics.wheels[i]

        -- Convert angular velocity (rad/s) to RPM
        local wheelRPM = math.abs(wheel.angularSpeed) * 60 / (2 * math.pi)
        local rpmFactor = wheelRPM / maxBrakeRPM

        -- Calculate effective brake torque (simplified model)
        local brakeTorque = brakeInput * maxBrakeTorque

        local wearMult = getWearMultiplier(rpmFactor)

        -- Combine factors for wear calculation
        local wheelWear = wearMult * brakeInput * brakeTorque * baseWearRate
        totalWear = totalWear + wheelWear * dt
    end

    brakeWearLevel = math.min(brakeWearLevel + totalWear, 1000)

    -- Calculate brake fade with smooth interpolation
    local brakeFade = 0.0
    if brakeWearLevel > brakeFadeStart then
        local fadeT = (brakeWearLevel - brakeFadeStart) / (1000 - brakeFadeStart)
        brakeFade = fadeT * maxBrakeFade
    end

    -- Apply fade to brakes while preserving ABS functionality
    acCarPhysics.brake = acCarPhysics.brake * (1 - brakeFade)

    -- Debug output
    printDebug("Brake Wear", string.format("Total: %.1f/%d | Fade: %.1f%%", brakeWearLevel, brakeFadeStart, brakeFade * 100))
    printDebug("Brake Wear Factors", string.format("Rate: %.2f/s | Input: %.2f", totalWear/dt, brakeInput))
    acCarPhysics.controllerInputs[11] = brakeFade
    -- BRAKE WEAR STUFF END
end
