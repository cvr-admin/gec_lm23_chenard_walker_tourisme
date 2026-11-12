-- a try of enhanced electricity features

local P = ac.getCarPhysics(0)
local car = ac.getCar(0)

local function brightnessFactor(charge)
    -- 0..100
    local V = 11.0 + 0.016 * charge          -- 11.0V..12.6V
    local bRaw = (V / 12.6) ^ 3.5            -- physical-ish curve

    -- Precomputed from charge=0 and charge=100
    local bRawMin = (11.0 / 12.6) ^ 3.5      -- ≈ 0.624
    local bRawMax = 1.0

    -- Remap [bRawMin..bRawMax] -> [0.17..1.0]
    local t = (bRaw - bRawMin) / (bRawMax - bRawMin)
    if t < 0.0 then t = 0.0 elseif t > 1.0 then t = 1.0 end

    return 0.17 + t * (1.0 - 0.17)
end


local function colorWithBattery(baseColor, charge)
    -- baseColor: vec3 (r,g,b) in 0..1
    local b = brightnessFactor(charge)

    -- 0 at full, 1 at empty
    local t = 1.0 - charge / 100.0

    -- warm tint from (1,1,1) to (1.0, 0.9, 0.7)
    local tintR = 1.0 * (1.0 - t) + 1.0 * t
    local tintG = 1.0 * (1.0 - t) + 0.9 * t
    local tintB = 1.0 * (1.0 - t) + 0.7 * t

    return vec3(
        baseColor.x * b * tintR,
        baseColor.y * b * tintG,
        baseColor.z * b * tintB
    )
end

--initiate things
carRootReference = ac.findNodes('carRoot:' .. car.index)
    ac.debug("rootRef: ", carRootReference)
yourMeshReference = carRootReference:findMeshes("glassbump_hl") --make sure it is the mesh name NOT the parent node - light_hl
    ac.debug("meshRef: ", yourMeshReference)
yourMeshReference2 = carRootReference:findMeshes("headlights_cones") --make sure it is the mesh name NOT the parent node - light_hl
    ac.debug("meshRef2: ", yourMeshReference2)
yourMeshReference3 = carRootReference:findMeshes("glassbump_tl") --make sure it is the mesh name NOT the parent node - light_hl
    ac.debug("meshRef3: ", yourMeshReference3)
yourMeshReference4 = carRootReference:findMeshes("light_bulb_rear1") --make sure it is the mesh name NOT the parent node - light_hl
    ac.debug("meshRef4: ", yourMeshReference4)
--if the light does not have an unique material, make sure to instantiate it
yourMeshReference2:ensureUniqueMaterials()

local brightness = 1.0


function script.update(dt)
    local now = ac.getSim().time
    local input = P.scriptControllerInputs[50]

    -- Skip if menu is open
    if dt < 0.0001 then return end

    brightness = brightnessFactor(P.scriptControllerInputs[44])

    ac.debug("charge: ", P.scriptControllerInputs[44])
    ac.debug("brightness: ", brightness)

    --IN UPDATE FUNCTION
        --yourMeshReference:setMaterialProperty("ksEmissive", rgbm(0.1,0.1,1,brightness))
        yourMeshReference2:setMaterialProperty("ksEmissive", rgbm(0.25,1,0.8,500000))
        --yourMeshReference3:setMaterialProperty("ksEmissive", rgbm(0.1,0.1,0.9,brightness))
        --yourMeshReference4:setMaterialProperty("ksEmissive", rgbm(0.1,0.1,0.9,brightness))
    --put variables (such as the battery charge level) in the RGBM to adjust the luminosity., adjusting the final value is easiest as it is MAGNITUDE, strength of the illum.

end