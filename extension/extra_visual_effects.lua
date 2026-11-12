require("car_parameters")

local P = ac.getCarPhysics(0)

local radiatorSmoke = {}
radiatorSmoke["color"] = rgbm(0.9, 0.9, 0.9, 0.5) --color
radiatorSmoke["colorConsistency"] = 1.0 --how fast smoke loses color as it dissipates. 0-1
radiatorSmoke["thickness"] = 0.4  --smoke strength. 0-1
radiatorSmoke["life"] = 1.1 --smoke particle lifespan in seconds
radiatorSmoke["size"] = 0.01 --particle spawn size
radiatorSmoke["spreadK"] = 2.0 --randomness factor for speed and direction (affects other variables slightly)
radiatorSmoke["growK"] = 0.01 --how fast smoke spreads/expands
radiatorSmoke["targetYVelocity"] = 0.5 --smoke "temperature". 1 makes smoke rise, -1 makes smoke go down
radiatorSmokeStrength = 0.5 --emitter "amount" variable. higher value will make more smoke

local radiatorSmokeEmitter = ac.Particles.Smoke(radiatorSmoke)
--create emitter object

local function radiatorDamage()
    if P.scriptControllerInputs[0] > 90 then
    --if car.damage[4] > 50 then
        local emitterOffset = car.localVelocity * 0.01
        --offset value for emitter positions, as emitters lag behind.
        radiatorSmokeEmitter:emit(
            vec3(radiatorSteamPosLeftRight, radiatorSteamPosHeight, radiatorSteamPosDistance) + emitterOffset,
            vec3(0.0,0.1,0.0),
            0.1
        )
    end
end

local turboExplSmoke = {}
turboExplSmoke["color"] = rgbm(0.714, 0.714, 1.0, 1.0) --color
turboExplSmoke["colorConsistency"] = 1.0 --how fast smoke loses color as it dissipates. 0-1
turboExplSmoke["thickness"] = 1  --smoke strength. 0-1
turboExplSmoke["life"] = 15.1 --smoke particle lifespan in seconds
turboExplSmoke["size"] = 0.01 --particle spawn size
turboExplSmoke["spreadK"] = 2.0 --randomness factor for speed and direction (affects other variables slightly)
turboExplSmoke["growK"] = 0.01 --how fast smoke spreads/expands
turboExplSmoke["targetYVelocity"] = 0.5 --smoke "temperature". 1 makes smoke rise, -1 makes smoke go down
turboExplSmokeStrength = 150.5 --emitter "amount" variable. higher value will make more smoke

local turboExplSmokeEmitter = ac.Particles.Smoke(turboExplSmoke)
--create emitter object

local soundExplosion = ui.MediaPlayer()
soundExplosion:setSource("./sfx/explosion.mp3"):setAutoPlay(false)

local prevInput = 0
local soundDuration = 1
local soundTimer = soundDuration

local function turboExplosionDamage(dt)
    if P.scriptControllerInputs[25] == 1 then
        local emitterOffset = car.localVelocity * 0.01
        --offset value for emitter positions, as emitters lag behind.
        turboExplSmokeEmitter:emit(
            vec3(turboSmokePosLeftRight, turboSmokePosHeight, turboSmokePosDistance) + emitterOffset,
            vec3(0.0,0.1,0.0),
            0.1
        )

        -- Only play sound once.
        if prevInput == 0 then
            soundTimer = 0
        end
    end

    if soundTimer < soundDuration then
        soundExplosion:play()
        soundTimer = soundTimer + dt
    end

    prevInput = P.scriptControllerInputs[25]
end

function script.update(dt)
    radiatorDamage()
    turboExplosionDamage(dt)
end
