-- Car specific parameters.

--Spark plug failures
sparkPlugFailureRateInitialValue = 80000
--random chance of spark plug failure, rolled every 2 seconds. higher = less chance of failure
math.randomseed(os.time() + math.random(0, 1000))
sparkPlugFailureDamage = math.random(200, 600)
--1000 = 100%. when you get spark plug failure, set engine damage to this percentage.
sparkPlugEngineMapFactors = {0.75, 1.0, 0.75, 0.5}
-- How much to multiply the spark plug failure rate by, based on engine map. rich, normal, lean, push.
-- 0.75 - 25% more likely to fail, 1.0 - base rate, 0.5 - half as likely to fail.
sparkPlugFailureRateMinimumValue = 50

--Fuel pump failures
fuelPumpFailureRateInitialValue = 100000
--random chance of spark plug failure, rolled every 2 seconds. higher = less chance of failure
fuelPumpRepairTime = math.random(30, 180)  -- Required time in pits for repair
fuelPumpPitTimer = 0
fuelPumpRepairInProgress = false
fuelPumpEngineMapFactors = {0.75, 1.0, 0.75, 0.75}
fuelPumpFailureRateMinimumValue = 50

--Valve failures
valveFailureRateInitialValue = 120000
--random chance of valve failure, rolled every 2 seconds. higher = less chance of failure
valveFailureMaxDamage = 100
valveFailureBaseTime = 100  -- 15 minutes at reference RPM (base time for progression)
valveFailureElapsed = 0
valveFailureActive = false
valveReferenceRPM = 6000    -- RPM (2/3 of damage threshold) at which progression runs at 100% speed
valveEngineMapFactors = {1.2, 1.0, 0.75, 0.5}
valveFailureRateMinimumValue = 50

--Oil pressure problems
oilPressureFailureRateInitialValue = 128000
--random chance of oil pressure problems, rolled every 2 seconds. higher = less chance of failure
oilPressureFailureMaxDamage = 100
oilPressureFailureBaseTime = 50  -- 7 minutes at reference RPM (base time for progression)
oilPressureFailureElapsed = 0
oilPressureFailureActive = false
oilPressureReferenceRPM = 3000    -- RPM (1/3 of damage threshold) at which progression runs at 100% speed
oilPressureEngineMapFactors = {1.1, 1.0, 1.0, 0.8}
oilPressureFailureRateMinimumValue = 50

--GEARBOX
gearFailureRate = 85000
boostedGearFailureRate = gearFailureRate
--similar to sparkplug failure, rolled every 2 seconds, higher = less chance of fail
-- Gearbox Repair
gearboxRepairTime = math.random(30, 180)  -- Time required to repair gears
gearboxPitTimer = 0
gearboxRepairInProgress = false
--Special Gearboxes
gearboxIsPSG = false                -- needs adjustments in drivetrain.ini, ext_config.ini and driver3d.ini if true
gearboxIsElectrical = false          -- at the moment only for the special Cotal/Autoclutch gearbox. requires a special [AUTOCLUTCH] setting in drivetrain.ini. See 47 Delahaye as example

--ENGINE and THROTTLE/TORQUE CURVE adjustments
throttle_curve_gamma = 0.75
throttle_curve_slope = 2.2

--ENGINE COOLANT FUNCTIONS
engineCoolAmbientFalloff = 0.25 --0.45
--how sensitive is the engine to ambient temperature. lower value -> less cooling as engine temp nears ambient
--this can make a huge change, as it changes the efficiency of the cooling factors in general. only make very very small changes to this as it makes a large difference.
--this operates as a multiplier for ALL the COOLING factors. you can view the function with a graphing calculator with the following function: f(x) = log(x - AmbientTemp) * x^0.01 * AmbientFalloff
--the mult clamps at 1 so dont be fooled by the Y being higher than 1.
engineCoolantTransferGain = 0.30
--how fast engine reacts to coolant temperature changes and vice-versa. values 0.3 - 0.5
--too low will make engine run too cool/not react to coolant, and too high will make the engine transfer too much to coolant causing overheating
--im not sure if my implementation is perfect for this honestly, i tried several approaches like weighted averages and applying those but it always had bad side effects.
--but this works fine
engineOverboilTemp = 105
--engine seizing temperature threshold in C (Coolant temp)
engineHeatGainMult = 1.94 --2.1
--use this to adjust how much heat the engine produces. its a multiplier in the formula. (baseline heat gain is 1 deg/s at high rpms)
engineGainThrottleCoefficient = 1.08 --1.8
--how much applying throttle increases engine temp relative to engineRPM.
--use the following function on a graphing calculator. X = engineRPM (1 = revlimiter), Y = celsius of temperature added per second
--f(x) = 1 - engineGainThrottleCoefficient^(-5x) * engineHeatGainMult
engineBaseCoolCoefficient = 0.025 --0.03
--how much heat dissipates out as ambient. unaffected by damage. cooling rate slows as temp gets slower to ambient. approx. celsius/sec
engineSpeedCoolCoefficient = 0.0000011 --0.000014
--how much heat dissipates out with speed. unaffected by damage. cool rate slows as temp nears ambient. see formula from radiator docs
engineIdleRpm = ac.INIConfig.carData(0, 'engine.ini'):get('ENGINE_DATA', 'MINIMUM', 900) --Default idle RPM; dynamically read from ini now. was 900

radiatorCoolCoefficientInitialValue = 0.25 --0.27
--how many celsius per second does the radiator cool the coolant (at optimum)
radiatorSpeedCoolCoefficient = 0.000005 --0.00005
--how much radiator cooling efficiency rises with speed (speedCoolFactor * speedKmh^2) (y = celsius per second)
--you can get a rough idea of its efficiency with a graphing calculator https://www.desmos.com/calculator with f(x) = radiatorSpeedCoolFactor * x^2
radiatorDamageCoefficientLoss = 0.23 --0.23
--how much radiator damage affects cooling efficiency.
--you can make radiator more sensitive to damage by making the value larger than radCoolCoef..though be careful, as that will cause total radiator failure at lower dmg%
--if radCoolCoef == radDmgCoefLoss then at 100% damage radiator loses all function. radiatorCoolCoef - (radiatorDamageCoef * damage%)

radiatorShutterAdjustEnabled = true
--For cars with radiator shutters, to be adjusted by the driver.

radiatorEfficiencyEngineMapFactors = {1.1, 1.0, 0.7, 0.6}
-- How much to multiply the radiator efficiency by, based on engine map. rich, normal, lean, push.

--REMOTE ADJUSTMENT FLAGS - whether or not the following things may be changed from the cockpit while driving or while in the pits only.
remFlags = {
    radiatorShutter = true,
    fuelMix = true,
}

--TYRE REPLACEMENT FUNCTIONS
spareWheelMass = 22
--a single spare wheel's weight in kg. spareWheelMass * currentSpares
spareWheelPos = vec3(0,0,0.5)
--spare wheel's position (meters) as relative to car center of mass(?)
--i think positive was towards the front, negative towards rear.
tyreBlowPressure = 75
--tyre explosion pressure in psi
tyreBasevKM = 1
-- Minimum tyre life (vKM)
tyrevKMvariance = 70
-- Maximum tyre life range (vKM)
biasStrength = 0.45
--tyre replacement time in seconds
tyreReplacementReactionTime = 5
--the amount of time you have to sit with handbrake pulled, before the tyre replacement routine starts

-- Slow tyre puncture variables at start.
tyrePunctureRateAsphalt = 173800
tyrePunctureRateGravel = 56600
tyrePunctureRateIce = 217250
tyrePunctureDeflateFactor = {}
tyrePuncturePressureFactor = {}
-- The deflation speed is drawn between these constants.
minPunctureDeflateFactor = 20  -- This value would empty the tyre in 2 seconds.
maxPunctureDeflateFactor = 1800  -- This value would empty the tyre in 180 seconds.

-- Tyrewear factors.
tyreWearAsphalt = 1.0
tyreWearGravel = 1.2
tyreWearIce = 1.0

-- tyreTypeFactors - insert all available tyre's short name (from tyres.ini) and a multiplier for the tyre wear. This is used to make certain types of tyres wear faster or slower, based on their compound.
tyreTypeFactors = {
        {"SH", 1.2},
        {"HS", 4},
        {"LS", 4},
        {"HSI", 1},
        {"FS", 4},
}

-- Damage limits for tyre blow when crashing.
-- When this amount is exceeded in the crash, then a tyre will be blown, using the rate below.
tyreBlowDamageChange = 30
tyreBlowCrashingRate = 2  -- Every second time the tyre blows, for some randomness.
-- If the crash is hard enough, then blow the tyre for certain (do not use the rate above).
tyreBlowDamageChangeHard = 60
-- If the crash is really bad, blow both tyres on the side, which gets the damage.
tyreBlowDamageChangeMax = 90

-- Brake Wear System
brakeWearLevel = 0.0  -- Accumulated brake wear (0-1000)
maxBrakeRPM = 1300    -- RPM where wear starts accelerating (convert angular velocity to RPM)
baseWearRate = 0.00009 -- Base wear rate coefficient
brakeFadeStart = 600  -- Wear level where fade begins
maxBrakeFade = 0.7    -- Maximum brake force reduction (90%)
maxBrakeTorque = ac.INIConfig.carData(0, 'brakes.ini'):get('DATA', 'MAX_TORQUE', 770) -- Maximum brake torque (Nm) - car specific; read from ini now. was 770
-- Brake Wear curve LUT: [RPM factor, wear rate multiplier]
wearLUT = {
    {0.0, 0.0},   -- No wear when stopped
    {0.3, 0.12},   -- Low speed wear
    {0.7, 0.45},   -- Medium speed wear
    {1.0, 1.00},   -- Peak efficiency
    {1.5, 2.20},   -- Over-speed wear
    {2.0, 3.50}    -- Dangerous over-revs
}
resetBrakeWearAtTyreChange = false

-- *** Supercharger/turbo failure parameters. ***
--
-- Failure rate to start with. This value will be subtracted when boost is above the limit,
-- making a failure more probable.
turboFailureRate = 180000  -- 5% probability for failure in a 2,5 hour race.
-- Exponent of the progressive failure rate calculation.
turboFailureRateProgression = 10
-- Maximum rate decrease step.
rateDecreaseStepMax = 36
-- Minimum failure rate. We shall not go below this.
turboFailureRateMin = 50000
-- Rate of degrading the turbo from 100 to target percentage, when problem has occurred.
turboFailureFactorMin = 1000  -- This would degrade the turbo in 1000 seconds.
turboFailureFactorMax = 2   -- This would degrade the turbo in 2 seconds.
-- Limits of target boost value after failure has occurred. The value will be random between
-- these. If the value should be e.g. 30, then the max. boost would go down to 30 % of the maximum.
turboBoostAfterFailurePercentMin = 0
turboBoostAfterFailurePercentMax = 50
-- Rate (probability) of turbo explosion, one out of this value. When a failure occurs, this rate
-- defines the possibility of explosion.
turboExplosionRate = 2
-- Engine damage percent after exposion. The current engine life will be reduced with a factor between
-- these values. For example, if this should be 50 %, then the engine life would be reduced to
-- 50 % of the current value.
engineLifeAfterExplosionPercentMin = 30
engineLifeAfterExplosionPercentMax = 70
-- Rate (probability) of overheating when having a turbo failure. When a failure occurs, this rate
-- defines the possibility of overheating the engine.
turboFailureEngineOverheatingRate = 2
-- Engine overheating gain increase. This increased value is used when turbo failure causes
-- the engine temperature to rise.
engineHeatGainMultTurbo = engineHeatGainMult + 0.1

turboOnOffButtonEnabled = false
-- Enable/disable turbo/supercharger system. Should be enabled only for those cars
-- that have a possibility to turn the system on/off during driving.

-- *** Failure rate handling parameters. ***
-- Overrevving.
overrevvingThresholdFactor = 0.938 -- Percentage of max RPM where overrevving effects start.
overrevvingThresholdFactorHigh = 0.975 -- Percentage of max RPM where overrevving gets more severe.
overrevvingProgressionExponent = 1.108
overrevvingRateDecreaseStepFactor = 0.4
overrevvingWarningThresholdFactor = 0.97  -- Percentage of treshold RPM where warning starts.
-- Low RPM.
lowRpmThreshold = 0.5       -- Percentage of max RPM where low RPM effects start.
radiatorEfficiencyLowRpmMultiplier = 1.1
-- Running close to car in front.
closeCarInFrontSpeedThreshold = 50  -- Speed in km/h where close car effects start.
closeCarInFrontDistanceThreshold = 40  -- Distance in meters where close car effects start.
closeCarInFrontDistanceMin = 5  -- Closest detectable distance to another car.
-- Engine temperature effects.
highEngineTempThreshold = 75
-- Normal coolant temperature. Any temperature above this will start increasing failure rates.
-- Running on low fuel level.
fuelLevelThreshold = 10    -- Fuel level (litres) where low fuel effects start.
fuelPumpLowFuelStep = 5
-- Running on dusty track.
radiatorEfficiencyDustMultiplier = 0.9

-- Fuel tank damage leakage parameters.
-- Sides of the car that can cause fuel leakage when damaged.
fuelLeakageDamageSides = {false, true, true, true}  -- {front, rear, left, right}
fuelLeakageDamageThreshold = 40  -- Damage level where leakage starts.

-- Fuel exhaustion parameters.
fuelExhaustionAmount = 30 -- Amount of fuel (litres) where fuel exhaustion effects start.
fuelExhaustionGForceThreshold = 0.9  -- Lateral G-force threshold where fuel exhaustion effects start.

-- Car type - defines if battery feature is in play or not as GP cars had carburetors, not battery
ignitionType = 3 -- 1 = Magneto, 2 = Battery, 3 = Hybrid

-- Settings for electricity system
alternatorFailureRPM = 6500           -- RPM threshold for stressing alternator leash - see below
alternatorFailureRate = 15000            -- added to make closer to other systems. the failureRPM above are redundant atm, because the overrevhighlimit is being used as treshold - 15000 seems quite low, but testing will show
alternatorRepairTime = math.random(100, 200) -- How long alternator leash repairs should take on the side of the track (seconds). It's half that in the pits
tempThresholdElectricity = 95         -- Temperature threshold for electronic system starts taking damage
suspensionShockThreshold = 0.5        -- The damper speed interpreted as a "shock" event that will degrade battery
alternatorOK = true
alternatorHealth = 1.0
batteryCurrentCharge = 100.0
batteryMaxCapacity = 100.0
isRepairingBelt = false
beltRepairTimer = 0
powerDrainSystems = 0.00833  -- Defaults to 0.00833; power drain rate of vehicles system excluding headlights in units per second; hybrid cars take only half of that by default
powerDrainHeadlights = 0.01296  -- Defaults to 0.01296; power drain rate of vehicles headlights (high beams) in units per second; low beams take only half of that by default

-- Debug / telemetry (Lua Debug App)
DEBUG_ELECTRICITY = false             -- prints key values using ac.debug()
DEBUG_ELECTRICITY_INTERVAL = 0.25    -- seconds between prints