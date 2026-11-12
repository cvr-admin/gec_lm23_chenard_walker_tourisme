-- an attempt to get a more realistic throttle response curve, especially at low RPMs.
-- inspired by a video by Niels Heusinkveld and throttle function discussions on the CSP discord, especially by JPG_18

-- curve gamma & slope are set in script_car_parameters.lua
---------------------------------------------------------------------------------------------------

local exp = math.exp

local acCarPhysics = ac.accessCarPhysics()
local engine_ini = ac.INIConfig.carData(0, "engine.ini")
local limit = engine_ini:get("ENGINE_DATA", "LIMITER", 10000)

local gamma = throttle_curve_gamma or 1.0
local slope = throttle_curve_slope or 1.5

local function modelCurve(throttle, rpm)
    if rpm < 1 then return 0 end
    local base = (limit / rpm) ^ gamma * slope
    local num = 2 / (1 + exp(-base * throttle)) - 1
    local den = 2 / (1 + exp(-base)) - 1

    printDebug("Throttle Model", "Input: " .. tostring(throttle) .. ", RPM: " .. tostring(rpm) .. ", Output: " .. tostring(num / den))

    return num / den
end

local M = {}

function M.runTM()
    acCarPhysics.gas = modelCurve(acCarPhysics.gas, acCarPhysics.rpm)
end

return M