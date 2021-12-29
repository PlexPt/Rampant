if (aiAttackWaveG) then
    return aiAttackWaveG
end
local aiAttackWave = {}

-- imports

local constants = require("Constants")
local mapUtils = require("MapUtils")
local chunkPropertyUtils = require("ChunkPropertyUtils")
local unitGroupUtils = require("UnitGroupUtils")
local movementUtils = require("MovementUtils")
local mathUtils = require("MathUtils")
local baseUtils = require("BaseUtils")

-- constants

local MINIMUM_EXPANSION_DISTANCE = constants.MINIMUM_EXPANSION_DISTANCE

local BASE_PHEROMONE = constants.BASE_PHEROMONE
local PLAYER_PHEROMONE = constants.PLAYER_PHEROMONE
local RESOURCE_PHEROMONE = constants.RESOURCE_PHEROMONE

local AI_SQUAD_COST = constants.AI_SQUAD_COST
local AI_SETTLER_COST = constants.AI_SETTLER_COST
local AI_VENGENCE_SQUAD_COST = constants.AI_VENGENCE_SQUAD_COST
local AI_STATE_AGGRESSIVE = constants.AI_STATE_AGGRESSIVE

local COOLDOWN_RALLY = constants.COOLDOWN_RALLY

local CHUNK_ALL_DIRECTIONS = constants.CHUNK_ALL_DIRECTIONS

local CHUNK_SIZE = constants.CHUNK_SIZE

local RALLY_CRY_DISTANCE = constants.RALLY_CRY_DISTANCE

local AI_STATE_SIEGE = constants.AI_STATE_SIEGE
local AI_STATE_ONSLAUGHT = constants.AI_STATE_ONSLAUGHT
local AI_STATE_RAIDING = constants.AI_STATE_RAIDING

-- imported functions

local findNearbyBase = baseUtils.findNearbyBase

local calculateKamikazeSettlerThreshold = unitGroupUtils.calculateKamikazeSettlerThreshold
local calculateKamikazeSquadThreshold = unitGroupUtils.calculateKamikazeSquadThreshold

local positionFromDirectionAndChunk = mapUtils.positionFromDirectionAndChunk

local getPassable = chunkPropertyUtils.getPassable
local getNestCount = chunkPropertyUtils.getNestCount
local getRaidNestActiveness = chunkPropertyUtils.getRaidNestActiveness
local getNestActiveness = chunkPropertyUtils.getNestActiveness
local getRallyTick = chunkPropertyUtils.getRallyTick
local setRallyTick = chunkPropertyUtils.setRallyTick

local gaussianRandomRangeRG = mathUtils.gaussianRandomRangeRG

local getNeighborChunks = mapUtils.getNeighborChunks
local getChunkByXY = mapUtils.getChunkByXY
local scoreNeighborsForFormation = movementUtils.scoreNeighborsForFormation
local scoreNeighborsForResource = movementUtils.scoreNeighborsForResource
local createSquad = unitGroupUtils.createSquad
local getDeathGenerator = chunkPropertyUtils.getDeathGenerator

local mCeil = math.ceil

-- module code

local function settlerWaveScaling(universe)
    return mCeil(gaussianRandomRangeRG(universe.settlerWaveSize,
                                       universe.settlerWaveDeviation,
                                       universe.expansionMinSize,
                                       universe.expansionMaxSize,
                                       universe.random))
end

local function attackWaveScaling(universe)
    return mCeil(gaussianRandomRangeRG(universe.attackWaveSize,
                                       universe.attackWaveDeviation,
                                       1,
                                       universe.attackWaveUpperBound,
                                       universe.random))
end

local function attackWaveValidCandidate(chunk, map)
    local isValid = getNestActiveness(map, chunk)
    if (map.state == AI_STATE_RAIDING) or (map.state == AI_STATE_SIEGE) or (map.state == AI_STATE_ONSLAUGHT) then
        isValid = isValid + getRaidNestActiveness(map, chunk)
    end
    return (isValid > 0)
end

local function scoreSettlerLocation(map, neighborChunk)
    return neighborChunk[RESOURCE_PHEROMONE] +
        -getDeathGenerator(map, neighborChunk) +
        -neighborChunk[PLAYER_PHEROMONE]
end

local function scoreSiegeSettlerLocation(map, neighborChunk)
    return neighborChunk[RESOURCE_PHEROMONE] +
        neighborChunk[BASE_PHEROMONE] +
        -getDeathGenerator(map, neighborChunk) +
        -neighborChunk[PLAYER_PHEROMONE]
end

local function scoreUnitGroupLocation(map, neighborChunk)
    return neighborChunk[PLAYER_PHEROMONE] +
        -getDeathGenerator(map, neighborChunk) +
        neighborChunk[BASE_PHEROMONE]
end

local function validSiegeSettlerLocation(map, neighborChunk)
    return (getPassable(map, neighborChunk) == CHUNK_ALL_DIRECTIONS) and
        (getNestCount(map, neighborChunk) == 0)
end

local function validSettlerLocation(map, chunk, neighborChunk)
    local chunkResource = chunk[RESOURCE_PHEROMONE]
    return (getPassable(map, neighborChunk) == CHUNK_ALL_DIRECTIONS) and
        (getNestCount(map, neighborChunk) == 0) and
        (neighborChunk[RESOURCE_PHEROMONE] >= chunkResource)
end

local function validUnitGroupLocation(map, neighborChunk)
    return getPassable(map, neighborChunk) == CHUNK_ALL_DIRECTIONS and
        (getNestCount(map, neighborChunk) == 0)
end

local function visitPattern(o, cX, cY, distance)
    local startX
    local endX
    local stepX
    local startY
    local endY
    local stepY
    if (o == 0) then
        startX = cX - distance
        endX = cX + distance
        stepX = 32
        startY = cY - distance
        endY = cY + distance
        stepY = 32
    elseif (o == 1) then
        startX = cX + distance
        endX = cX - distance
        stepX = -32
        startY = cY + distance
        endY = cY - distance
        stepY = -32
    elseif (o == 2) then
        startX = cX - distance
        endX = cX + distance
        stepX = 32
        startY = cY + distance
        endY = cY - distance
        stepY = -32
    elseif (o == 3) then
        startX = cX + distance
        endX = cX - distance
        stepX = -32
        startY = cY - distance
        endY = cY + distance
        stepY = 32
    end
    return startX, endX, stepX, startY, endY, stepY
end

function aiAttackWave.rallyUnits(chunk, map, tick)
    if ((tick - getRallyTick(map, chunk) > COOLDOWN_RALLY) and (map.points >= AI_VENGENCE_SQUAD_COST)) then
        setRallyTick(map, chunk, tick)
        local cX = chunk.x
        local cY = chunk.y
        local startX, endX, stepX, startY, endY, stepY = visitPattern(tick % 4, cX, cY, RALLY_CRY_DISTANCE)
        local vengenceQueue = map.universe.vengenceQueue
        for x=startX, endX, stepX do
            for y=startY, endY, stepY do
                if (x ~= cX) and (y ~= cY) then
                    local rallyChunk = getChunkByXY(map, x, y)
                    if (rallyChunk ~= -1) and (getNestCount(map, rallyChunk) > 0) then
                        local pack = vengenceQueue[rallyChunk.id]
                        if not pack then
                            pack = {
                                v = 0,
                                map = map
                            }
                            vengenceQueue[rallyChunk.id] = pack
                        end
                        pack.v = pack.v + 1
                    end
                end
            end
        end

        return true
    end
end

function aiAttackWave.formSettlers(map, chunk)
    local universe = map.universe
    if (universe.builderCount < universe.AI_MAX_BUILDER_COUNT) and
        (map.random() < universe.formSquadThreshold) and
        ((map.points - AI_SETTLER_COST) > 0)
    then
        local surface = map.surface
        local squadPath, squadDirection
        if (map.state == AI_STATE_SIEGE) then
            squadPath, squadDirection = scoreNeighborsForFormation(getNeighborChunks(map, chunk.x, chunk.y),
                                                                   validSiegeSettlerLocation,
                                                                   scoreSiegeSettlerLocation,
                                                                   map)
        else
            squadPath, squadDirection = scoreNeighborsForResource(chunk,
                                                                  getNeighborChunks(map, chunk.x, chunk.y),
                                                                  validSettlerLocation,
                                                                  scoreSettlerLocation,
                                                                  map)
        end

        if (squadPath ~= -1) then
            local squadPosition = surface.find_non_colliding_position("chunk-scanner-squad-rampant",
                                                                      positionFromDirectionAndChunk(squadDirection,
                                                                                                    chunk,
                                                                                                    0.98),
                                                                      CHUNK_SIZE,
                                                                      4,
                                                                      true)
            if squadPosition then
                local squad = createSquad(squadPosition, map, nil, true)

                local scaledWaveSize = settlerWaveScaling(universe)
                universe.formGroupCommand.group = squad.group
                universe.formCommand.unit_count = scaledWaveSize
                local foundUnits = surface.set_multi_command(universe.formCommand)
                if (foundUnits > 0) then
                    if (map.state == AI_STATE_SIEGE) then
                        map.sentSiegeGroups = map.sentSiegeGroups + 1
                    end

                    if universe.NEW_ENEMIES then
                        squad.base = findNearbyBase(map, chunk)
                    end
                    local kamikazeThreshold = calculateKamikazeSettlerThreshold(foundUnits, universe)
                    if map.state == AI_STATE_SIEGE then
                        kamikazeThreshold = kamikazeThreshold * 2.5
                    end
                    squad.kamikaze = map.random() < kamikazeThreshold

                    universe.builderCount = universe.builderCount + 1
                    map.points = map.points - AI_SETTLER_COST
                    if universe.aiPointsPrintSpendingToChat then
                        game.print(map.surface.name .. ": Points: -" .. AI_SETTLER_COST .. ". [Settler] Total: " .. string.format("%.2f", map.points) .. " [gps=" .. squadPosition.x .. "," .. squadPosition.y .. "]")
                    end
                    universe.groupNumberToSquad[squad.groupNumber] = squad
                else
                    if (squad.group.valid) then
                        squad.group.destroy()
                    end
                end
            end
        end
    end
end

function aiAttackWave.formVengenceSquad(map, chunk)
    local universe = map.universe
    if (universe.squadCount < universe.AI_MAX_SQUAD_COUNT) and
        (map.random() < universe.formSquadThreshold) and
        ((map.points - AI_VENGENCE_SQUAD_COST) > 0)
    then
        local surface = map.surface
        local squadPath, squadDirection = scoreNeighborsForFormation(getNeighborChunks(map, chunk.x, chunk.y),
                                                                     validUnitGroupLocation,
                                                                     scoreUnitGroupLocation,
                                                                     map)
        if (squadPath ~= -1) then
            local squadPosition = surface.find_non_colliding_position("chunk-scanner-squad-rampant",
                                                                      positionFromDirectionAndChunk(squadDirection,
                                                                                                    chunk,
                                                                                                    0.98),
                                                                      CHUNK_SIZE,
                                                                      4,
                                                                      true)
            if squadPosition then
                local squad = createSquad(squadPosition, map)

                squad.rabid = map.random() < 0.03

                local scaledWaveSize = attackWaveScaling(universe)
                universe.formGroupCommand.group = squad.group
                universe.formCommand.unit_count = scaledWaveSize
                local foundUnits = surface.set_multi_command(universe.formCommand)
                if (foundUnits > 0) then
                    if universe.NEW_ENEMIES then
                        squad.base = findNearbyBase(map, chunk)
                    end
                    squad.kamikaze = map.random() < calculateKamikazeSquadThreshold(foundUnits, universe)
                    universe.groupNumberToSquad[squad.groupNumber] = squad
                    universe.squadCount = universe.squadCount + 1
                    map.points = map.points - AI_VENGENCE_SQUAD_COST
                    if universe.aiPointsPrintSpendingToChat then
                        game.print(map.surface.name .. ": Points: -" .. AI_VENGENCE_SQUAD_COST .. ". [Vengence] Total: " .. string.format("%.2f", map.points) .. " [gps=" .. squadPosition.x .. "," .. squadPosition.y .. "]")
                    end
                else
                    if (squad.group.valid) then
                        squad.group.destroy()
                    end
                end
            end
        end
    end
end

function aiAttackWave.formVengenceSettler(map, chunk)
    local universe = map.universe
    if (universe.builderCount < universe.AI_MAX_BUILDER_COUNT) and
        (map.random() < universe.formSquadThreshold) and
        ((map.points - AI_VENGENCE_SQUAD_COST) > 0)
    then
        local surface = map.surface
        local squadPath, squadDirection = scoreNeighborsForFormation(getNeighborChunks(map, chunk.x, chunk.y),
                                                                     validUnitGroupLocation,
                                                                     scoreUnitGroupLocation,
                                                                     map)
        if (squadPath ~= -1) then
            local squadPosition = surface.find_non_colliding_position("chunk-scanner-squad-rampant",
                                                                      positionFromDirectionAndChunk(squadDirection,
                                                                                                    chunk,
                                                                                                    0.98),
                                                                      CHUNK_SIZE,
                                                                      4,
                                                                      true)
            if squadPosition then
                local squad = createSquad(squadPosition, map, nil, true)

                squad.rabid = map.random() < 0.03

                local scaledWaveSize = settlerWaveScaling(universe)
                universe.formGroupCommand.group = squad.group
                universe.formCommand.unit_count = scaledWaveSize
                local foundUnits = surface.set_multi_command(universe.formCommand)
                if (foundUnits > 0) then
                    if universe.NEW_ENEMIES then
                        squad.base = findNearbyBase(map, chunk)
                    end
                    squad.kamikaze = map.random() < calculateKamikazeSettlerThreshold(foundUnits, universe)
                    universe.groupNumberToSquad[squad.groupNumber] = squad
                    universe.builderCount = universe.builderCount + 1
                    map.points = map.points - AI_VENGENCE_SQUAD_COST
                    if universe.aiPointsPrintSpendingToChat then
                        game.print(map.surface.name .. ": Points: -" .. AI_VENGENCE_SQUAD_COST .. ". [Vengence Settlers] Total: " .. string.format("%.2f", map.points) .. " [gps=" .. squadPosition.x .. "," .. squadPosition.y .. "]")
                    end
                else
                    if (squad.group.valid) then
                        squad.group.destroy()
                    end
                end
            end
        end
    end
end

function aiAttackWave.formSquads(map, chunk)
    local universe = map.universe
    if (universe.squadCount < universe.AI_MAX_SQUAD_COUNT) and
        attackWaveValidCandidate(chunk, map) and
        (map.random() < universe.formSquadThreshold) and
        ((map.points - AI_SQUAD_COST) > 0)
    then
        local surface = map.surface
        local squadPath, squadDirection = scoreNeighborsForFormation(getNeighborChunks(map, chunk.x, chunk.y),
                                                                     validUnitGroupLocation,
                                                                     scoreUnitGroupLocation,
                                                                     map)
        if (squadPath ~= -1) then
            local squadPosition = surface.find_non_colliding_position("chunk-scanner-squad-rampant",
                                                                      positionFromDirectionAndChunk(squadDirection,
                                                                                                    chunk,
                                                                                                    0.98),
                                                                      CHUNK_SIZE,
                                                                      4,
                                                                      true)
            if squadPosition then
                local squad = createSquad(squadPosition, map)

                squad.rabid = map.random() < 0.03

                local scaledWaveSize = attackWaveScaling(universe)
                universe.formGroupCommand.group = squad.group
                universe.formCommand.unit_count = scaledWaveSize
                local foundUnits = surface.set_multi_command(universe.formCommand)
                if (foundUnits > 0) then
                    if (map.state == AI_STATE_SIEGE) then
                        map.sentSiegeGroups = 0
                    end

                    if universe.NEW_ENEMIES then
                        squad.base = findNearbyBase(map, chunk)
                    end
                    squad.kamikaze = map.random() < calculateKamikazeSquadThreshold(foundUnits, universe)
                    map.points = map.points - AI_SQUAD_COST
                    universe.squadCount = universe.squadCount + 1
                    universe.groupNumberToSquad[squad.groupNumber] = squad
                    if (map.state == AI_STATE_AGGRESSIVE) then
                        map.sentAggressiveGroups = map.sentAggressiveGroups + 1
                    end
                    if universe.aiPointsPrintSpendingToChat then
                        game.print(map.surface.name .. ": Points: -" .. AI_SQUAD_COST .. ". [Squad] Total: " .. string.format("%.2f", map.points) .. " [gps=" .. squadPosition.x .. "," .. squadPosition.y .. "]")
                    end
                else
                    if (squad.group.valid) then
                        squad.group.destroy()
                    end
                end
            end
        end
    end
end


aiAttackWaveG = aiAttackWave
return aiAttackWave
