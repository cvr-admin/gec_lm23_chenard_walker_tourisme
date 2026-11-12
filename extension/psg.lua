-- a try of a sound-level sensitive PSG sounds implementation

local P = ac.getCarPhysics(0)
local car = ac.getCar(0)

local vol = ac.getAudioVolume('main') * ac.getAudioVolume('engine')

local filesH = {
    "./sfx/psg1b_ll.wav",
    "./sfx/psg2b_ll.wav",
    "./sfx/psg3b_ll.wav"
}
local filesM = {
    "./sfx/psg1b_lll.wav",
    "./sfx/psg2b_lll.wav",
    "./sfx/psg3b_lll.wav"
}
local filesL = {
    "./sfx/psg1b_llll.wav",
    "./sfx/psg2b_llll.wav",
    "./sfx/psg3b_llll.wav"
}

local clickCooldown = 0
local lastInput = 0



function script.update(dt)
    local now = ac.getSim().time
    local input = P.scriptControllerInputs[50]

    -- Skip if menu is open
    if dt < 0.0001 then return end

    -- Rising edge detection + cooldown
    if input == 1 and lastInput == 0 and now > clickCooldown then
        
        local file = filesM[math.random(#filesM)]
        if vol < 0.4 then file = filesL[math.random(#filesL)] end
        if vol > 0.8 then file = filesH[math.random(#filesH)] end

        local soundGear = ui.MediaPlayer()
        soundGear:setSource(file)
        soundGear:play()

        clickCooldown = now + 0.6
    end

    lastInput = input

end