-- script_psg.lua
-- Wilson‑style preselector gearbox logic

local acRef = nil
local carPhys = nil
local msgQueue = nil
local maxGear = 4  -- sensible(?) fallback

--------------------------------------------------------------------
-- Neutral debounce state
--------------------------------------------------------------------
local neutralTimer = neutralTimer or 0
local neutralDelay = 0.4   -- 0.01 = 1 ms debounce for Neutral
local pendingNeutral = false

-- persistent state
psg_engageDelayRaw   = psg_engageDelayRaw   or 0.15
--psg_fs_protection = psg_fs_protection   or true   -- bool

if psg_fs_protection == nil then
  psg_fs_protection = false
end

psg_fs_pro_delay  = psg_fs_pro_delay   or 0.1   -- seconds off additional delay - standard: 0.1
psg_engageTimer   = psg_engageTimer   or 0
psg_preselected   = psg_preselected   or 1
psg_engaged       = psg_engaged       or 1
psg_lastLever     = psg_lastLever     or 1
psg_lastClutch    = psg_lastClutch    or 1
psg_clutchTrigger = psg_clutchTrigger or 0.2
psg_changed       = psg_changed       or 0

-- calculate final engage delay
psg_engageDelay = psg_engageDelayRaw
if psg_fs_protection then
    psg_engageDelay = psg_engageDelay + psg_fs_pro_delay
end

-- Paddle input state (persistent)
local lastPaddleUp   = false
local lastPaddleDown = false

-- anim configuration
local psg_animation_hold = 0.3     -- seconds to keep the signal high

-- anim state
local psg_animation_timer = 0      -- counts down to zero


--------------------------------------------------------------------
-- Drivetrain data (read from INI files in initPSG)
--------------------------------------------------------------------
local gearRatios         = {}       -- AC gearIndex → ratio: 0=R, 2=1st, 3=2nd …
local finalRatio         = 3.67     -- fallback
local clutchMaxTorque    = 400      -- Nm
local engineLimiter      = 6000     -- RPM
local engineIdleRPM      = 900      -- RPM
local engineInertia      = 0.28     -- kg·m²
local gearboxInertia     = 0.027    -- kg·m²
local rpmDamageThreshold = 6000     -- RPM above which engine takes damage
local gbxTorqueThreshold = 300      -- Nm above which gearbox takes damage
local drivenTyreRadius   = 0.34     -- metres
local rpmFactor          = 0        -- computed once in initPSG
local acMinRPM           = 800      -- autoclutch engage start RPM
local acMaxRPM           = 1200     -- autoclutch engage end RPM


local function gearName(idx)
    if idx == 0 then return "Reverse" end
    if idx == 1 then return "Neutral" end
    if idx == 2 then return "1st" end
    if idx == 3 then return "2nd" end
    if idx == 4 then return "3rd" end
    return (idx - 1) .. "th"
end


--------------------------------------------------------------------
-- Predict engine RPM at a given road speed in a given gear
-- (assumes zero clutch slip).
--------------------------------------------------------------------
local function predictRPM(speedKmh, gearIdx)
    if gearIdx == 1 then return engineIdleRPM end          -- Neutral
    local ratio = gearRatios[gearIdx]
    if not ratio then return 0 end
    return math.abs(speedKmh) * math.abs(ratio) * rpmFactor
end

--------------------------------------------------------------------
-- Compute safe re-engage clutch limit for a given gear.
-- Used during Phase 2 (re-engagement after the gear has already
-- been swapped while the clutch was open).
--
-- Returns:  maxClutch   (0 .. 1)
--   clutchPos × clutchMaxTorque × gearRatio  ≤  gbxTorqueThreshold
--------------------------------------------------------------------
local function safeClutchForGear(gearIdx)
    local ratio = gearRatios[gearIdx]
    if not ratio then ratio = 1 end
    ratio = math.abs(ratio)
    local sc = gbxTorqueThreshold / math.max(clutchMaxTorque * ratio, 1)
    return math.max(0.10, math.min(sc, 1.0))
end

--------------------------------------------------------------------
-- Phase 1 timing:
--   MIN_PHASE1  – minimum disconnect time (gear swap happens here)
--   MAX_PHASE1  – safety cap (won't hold open forever)
--   Phase 1 extends adaptively until RPM drops below target.
--------------------------------------------------------------------
local MIN_PHASE1_FRAC = 0.30       -- at least 30% disconnect
local MAX_PHASE1_FRAC = 0.80       -- at most 80% (leaves 20% for re-engage)
local psg_gearSwapped  = false      -- tracks whether the gear has been swapped this shift
local psg_phase2Start  = -1         -- progress value when Phase 2 began (-1 = not yet)
local psg_shiftDir     = 0          -- +1 = upshift, -1 = downshift (frozen at shift start)
local psg_shiftTarget  = 1          -- gear index we are shifting INTO (frozen at shift start)


function initPSG(ac_, overheadMessageQueue_)
    acRef = ac_
    carPhys = acRef.accessCarPhysics()
    msgQueue = overheadMessageQueue_

    ----------------------------------------------------------------
    -- Read drivetrain.ini
    ----------------------------------------------------------------
    local dtIni = acRef.INIConfig.carData(0, 'drivetrain.ini')

    -- Gear count
    local gearCount = dtIni:get('GEARS', 'COUNT', 0)
    if gearCount > 0 then
        maxGear = gearCount + 1          -- AC index: 0=R, 1=N, 2=1st …
    else
        local car = acRef.getCar()
        if car and car.gearCount then
            gearCount = car.gearCount - 2  -- gearCount includes R + N
            maxGear   = car.gearCount - 1
        else
            gearCount = maxGear - 1        -- use module-level fallback
        end
    end

    -- Gear ratios  (index 0 = Reverse, 2 = 1st, 3 = 2nd, …)
    gearRatios = {}
    gearRatios[0] = dtIni:get('GEARS', 'GEAR_R', -3.0)
    for i = 1, gearCount do
        gearRatios[i + 1] = dtIni:get('GEARS', 'GEAR_' .. i, 1.0)
    end
    finalRatio = dtIni:get('GEARS', 'FINAL', finalRatio)

    -- Clutch
    clutchMaxTorque = dtIni:get('CLUTCH', 'MAX_TORQUE', clutchMaxTorque)

    -- Gearbox
    gearboxInertia = dtIni:get('GEARBOX', 'INERTIA', gearboxInertia)

    -- Autoclutch
    acMinRPM = dtIni:get('AUTOCLUTCH', 'MIN_RPM', acMinRPM)
    acMaxRPM = dtIni:get('AUTOCLUTCH', 'MAX_RPM', acMaxRPM)

    -- Drivetrain damage thresholds
    gbxTorqueThreshold = dtIni:get('DAMAGE', 'TORQUE_THRESHOLD', gbxTorqueThreshold)

    -- Traction type → driven axle
    local tractionType = dtIni:get('TRACTION', 'TYPE', 'RWD')

    ----------------------------------------------------------------
    -- Read engine.ini
    ----------------------------------------------------------------
    local engIni = acRef.INIConfig.carData(0, 'engine.ini')
    engineLimiter      = engIni:get('ENGINE_DATA', 'LIMITER',  engineLimiter)
    engineIdleRPM      = engIni:get('ENGINE_DATA', 'MINIMUM',  engineIdleRPM)
    engineInertia      = engIni:get('ENGINE_DATA', 'INERTIA',  engineInertia)
    rpmDamageThreshold = engIni:get('DAMAGE', 'RPM_THRESHOLD', engineLimiter)

    ----------------------------------------------------------------
    -- Read tyre radius of driven wheels (tyres.ini)
    ----------------------------------------------------------------
    local tyreIni = acRef.INIConfig.carData(0, 'tyres.ini')
    if tractionType == 'FWD' then
        drivenTyreRadius = tyreIni:get('FRONT', 'RADIUS', drivenTyreRadius)
    else  -- RWD / AWD → rear
        drivenTyreRadius = tyreIni:get('REAR',  'RADIUS', drivenTyreRadius)
    end

    ----------------------------------------------------------------
    -- Pre-compute speed→RPM conversion factor
    --   RPM = speedKmh × |gearRatio| × rpmFactor
    ----------------------------------------------------------------
    rpmFactor = finalRatio * 60.0 / (3.6 * 2.0 * math.pi * drivenTyreRadius)

    --print(string.format(
    --    "[PSG] Init: %d gears | final=%.2f | clutch=%dNm | limiter=%d | rpmDmg=%d | gbxTrq=%dNm | tyreR=%.4f",
    --    gearCount, finalRatio, clutchMaxTorque, engineLimiter,
    --    rpmDamageThreshold, gbxTorqueThreshold, drivenTyreRadius
    --))

    -- Sanity check: print per-gear safe clutch limits
    --print("[PSG] Per-gear sanity check:")
    for i = 0, maxGear do
        local ratio = gearRatios[i]
        if ratio then
            local sc = safeClutchForGear(i)
            local peakTorque = sc * clutchMaxTorque * math.abs(ratio)
            local headroom = gbxTorqueThreshold - peakTorque
            --print(string.format(
            --    "  [%s] ratio=%.3f | safeClutch=%.2f | peakGbxTorque=%.0fNm | headroom=%.0fNm %s",
            --    gearName(i), ratio, sc, peakTorque, headroom,
            --    headroom < 20 and "<< TIGHT" or ""
            --))
        end
    end
    --print(string.format(
    --    "[PSG] Engage delay=%.0fms (raw=%.0fms + fsp=%.0fms) | Phase1(disconnect)=%.0f-%.0fms (adaptive) | Phase2(re-engage)=%.0f-%.0fms",
    --    psg_engageDelay * 1000, psg_engageDelayRaw * 1000,
    --    psg_fs_protection and (psg_fs_pro_delay * 1000) or 0,
    --    psg_engageDelay * MIN_PHASE1_FRAC * 1000,
    --    psg_engageDelay * MAX_PHASE1_FRAC * 1000,
    --    psg_engageDelay * (1 - MAX_PHASE1_FRAC) * 1000,
    --    psg_engageDelay * (1 - MIN_PHASE1_FRAC) * 1000
    --))
end



function updatePSG(dt)
    -- Read physics

    local clutchInput = carPhys.clutch

    local speed = carPhys.speedKmh

    -- Speed ramp parameters
    local maxOverrideSpeed = 25.0  -- km/h
    local t = speed / maxOverrideSpeed

    -- Clamp 0..1
    if t < 0 then t = 0 end
    if t > 1 then t = 1 end

    -- Default override clutch value (PSG logic may change this later)
    local overrideClutch = 1.0

    -- Blend between player clutch and override clutch
    local blendedClutch = clutchInput * (1 - t) + overrideClutch * t

    -- Apply blended clutch to the sim
    carPhys.clutch = blendedClutch

    local lever  = carPhys.requestedGearIndex

    if lever < 0 then
        lever = 1        -- force Neutral
    end

    -- Ignore invalid lever inputs
    if lever > maxGear then
        lever = psg_lastLever
    end


    -- Read paddle inputs directly from physics object
    local paddleUp   = carPhys.gearUp
    local paddleDown = carPhys.gearDown



    --------------------------------------------------------------------
    -- 1. HANDLE PRESELECT INPUTS (H‑shifter + paddles)
    --------------------------------------------------------------------

    -- H‑shifter movement
    if lever ~= psg_lastLever then

        if lever == 1 then
            ------------------------------------------------------------
            -- Lever is in Neutral → start debounce timer
            ------------------------------------------------------------
            neutralTimer = neutralDelay
            pendingNeutral = true

        else
            ------------------------------------------------------------
            -- Lever moved to a real gear → cancel Neutral debounce
            ------------------------------------------------------------
            neutralTimer = 0
            pendingNeutral = false

            psg_preselected = lever
            msgQueue("PRESELECT", gearName(psg_preselected), 1)
            psg_changed = 1
        end
    end

    -- Paddle upshift (debounced)
    if paddleUp and not lastPaddleUp then
        neutralTimer = 0
        pendingNeutral = false

        psg_preselected = math.min(psg_preselected + 1, maxGear)
        msgQueue("PRESELECT", gearName(psg_preselected), 1)
        psg_changed = 1
    end

    -- Paddle downshift (debounced)
    if paddleDown and not lastPaddleDown then
        neutralTimer = 0
        pendingNeutral = false

        psg_preselected = math.max(psg_preselected - 1, 0)
        msgQueue("PRESELECT", gearName(psg_preselected), 1)
        psg_changed = 1
    end

    -- Update paddle state for next frame
    lastPaddleUp   = paddleUp
    lastPaddleDown = paddleDown

    --------------------------------------------------------------------
    -- 1b. PROCESS NEUTRAL DEBOUNCE TIMER
    --------------------------------------------------------------------
    if pendingNeutral then
        neutralTimer = neutralTimer - dt

        if neutralTimer <= 0 then
            -- Lever stayed in Neutral long enough → accept it
            psg_preselected = 1
            msgQueue("PRESELECT", "Neutral", 1)
            psg_changed = 1

            pendingNeutral = false
        end
    end


    -- for external animation - so that [50] is 1 long enough that the other script catches it
    --carPhys.controllerInputs[50] = psg_changed       -- shifting animation
    --print("PSG: preselect change" , carPhys.controllerInputs[50])
    --psg_changed = 0

        -- when a new preselect happens, set the timer
    if psg_changed == 1 then
        psg_animation_timer = psg_animation_hold
        psg_changed = 0
    end

    -- count down the timer
    if psg_animation_timer > 0 then
        psg_animation_timer = psg_animation_timer - dt
        carPhys.controllerInputs[50] = 1
    else
        carPhys.controllerInputs[50] = 0
    end



    --------------------------------------------------------------------
    -- 2. BLOCK AC FROM CHANGING GEARS (Wilson preselector behavior)
    --------------------------------------------------------------------
    carPhys.requestedGearIndex = psg_engaged

  --------------------------------------------------------------------
    -- 3. TRIGGER ENGAGEMENT WHEN CLUTCH IS PRESSED
    --    Direction-aware over-rev protection.
    --    Ignores same-gear "shifts" (nothing to do).
    --------------------------------------------------------------------
    if clutchInput  <= psg_clutchTrigger and psg_lastClutch > psg_clutchTrigger then
        -- Skip if preselected gear is already engaged
        if psg_preselected ~= psg_engaged then
            local blocked = false

            if psg_preselected ~= 1 then
                local targetRPM = predictRPM(speed, psg_preselected)
                local isDown = psg_preselected < psg_engaged

                -- Downshifts: conservative — block if target RPM
                -- would enter the engine damage zone.
                -- Upshifts: permissive — only block if target RPM
                -- would exceed the rev limiter (RPM drops in upshifts).
                local limit
                if isDown then
                    limit = rpmDamageThreshold * 0.96
                else
                    limit = engineLimiter * 0.98
                end

                if targetRPM > limit then
                    msgQueue("BLOCKED", "Over-rev protection kicked in!", 1)
                    --msgQueue("BLOCKED", "Over-rev! (" .. math.floor(targetRPM) .. " RPM)", 1)
                    blocked = true
                end
            end

            if not blocked then
                psg_engageTimer = psg_engageDelay
                psg_gearSwapped = false
                psg_phase2Start = -1
                if psg_preselected > psg_engaged then
                    psg_shiftDir = 1
                elseif psg_preselected < psg_engaged then
                    psg_shiftDir = -1
                else
                    psg_shiftDir = 0
                end
                psg_shiftTarget = psg_preselected
            end
        end
    end

 
    --------------------------------------------------------------------
    -- 4. ENGAGEMENT (Wilson preselector style)
    --
    --    UPSHIFT:
    --      Keep clutch PARTIALLY engaged at safe-torque level.
    --      With clutch fully open the engine has no external load;
    --      RPM decays only from internal friction (~340 RPM/s for
    --      this engine).  Partial engagement loads the engine through
    --      the drivetrain at ~5700-7200 RPM/s — RPM drops below the
    --      damage threshold in < 0.1 s.
    --      safeClutchForGear() guarantees gearbox torque ≤ threshold.
    --
    --    DOWNSHIFT:
    --      Clutch open, gas cut for entire duration.
    --
    --    All limits are derived from drivetrain.ini, engine.ini
    --    and tyres.ini so the logic adapts to any car.
    --------------------------------------------------------------------
    if psg_engageTimer > 0 then
        psg_engageTimer = psg_engageTimer - dt

        if psg_engageTimer > 0 then
            local progress = 1.0 - (psg_engageTimer / psg_engageDelay)  -- 0…1

            if psg_shiftDir == 1 then  -- UPSHIFT

                if speed < maxOverrideSpeed then
                    ------------------------------------------------
                    -- LOW SPEED (standing start / pit-lane):
                    -- No over-rev risk.  Just swap the gear with
                    -- the clutch fully open and let the player
                    -- control engagement via pedal.  No gas cut.
                    ------------------------------------------------
                    carPhys.clutch = 0.0

                    if not psg_gearSwapped and progress >= 0.10 then
                        psg_engaged = psg_shiftTarget
                        carPhys.requestedGearIndex = psg_engaged
                        psg_gearSwapped = true
                    end

                    -- Finish immediately after gear swap
                    if psg_gearSwapped then
                        psg_engageTimer = 0
                    end
                else
                    ------------------------------------------------
                    -- HIGH SPEED (flat shift):
                    -- Cut gas, keep clutch partially engaged at
                    -- the safe-torque level so drivetrain load
                    -- decelerates the engine quickly.
                    ------------------------------------------------
                    carPhys.gas = 0.0

                    if not psg_gearSwapped and progress >= 0.10 then
                        psg_engaged = psg_shiftTarget
                        carPhys.requestedGearIndex = psg_engaged
                        psg_gearSwapped = true
                    end

                    carPhys.clutch = safeClutchForGear(psg_engaged)

                    if psg_gearSwapped and carPhys.rpm < rpmDamageThreshold * 0.92 then
                        psg_engageTimer = 0
                    end
                end

            elseif psg_shiftDir == -1 then  -- DOWNSHIFT
                carPhys.clutch = 0.0
                if psg_fs_protection then
                    carPhys.gas = 0.0
                end

            else
                carPhys.clutch = 0.0
            end
        end

        -- Timer expired → finalise (catches MAX_PHASE1 timeout)
        if psg_engageTimer <= 0 then
            psg_engaged = psg_shiftTarget
            carPhys.requestedGearIndex = psg_engaged
            psg_gearSwapped = false
            psg_phase2Start = -1
            psg_shiftDir    = 0

            if speed < maxOverrideSpeed then
                -- Low speed: player controls clutch & gas
                carPhys.clutch = 0.0
            else
                -- High speed: safe partial engagement, gas cut
                carPhys.clutch = safeClutchForGear(psg_engaged)
                carPhys.gas    = 0.0
            end
        end
    end


    --------------------------------------------------------------------
    -- 5. CLEAR AC INPUT FLAGS (important!)
    --------------------------------------------------------------------
    carPhys.gearUp = false
    carPhys.gearDown = false

    --------------------------------------------------------------------
    -- 6. UPDATE LAST INPUT STATE
    --------------------------------------------------------------------
    psg_lastLever  = lever
    psg_lastClutch = clutchInput

    carPhys.controllerInputs[49] = psg_preselected       -- pre-selected gear saved for other scripts/UI
end