-- Copyright (C) 2022  veden

-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.

-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.

-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.


if mapUtilsG then
    return mapUtilsG
end
local mapUtils = {}

-- imports

local constants = require("Constants")
local chunkPropertyUtils = require("ChunkPropertyUtils")

-- constants

local CHUNK_NORTH_SOUTH = constants.CHUNK_NORTH_SOUTH
local CHUNK_EAST_WEST = constants.CHUNK_EAST_WEST
local CHUNK_IMPASSABLE = constants.CHUNK_IMPASSABLE
local CHUNK_ALL_DIRECTIONS = constants.CHUNK_ALL_DIRECTIONS

local CHUNK_SIZE = constants.CHUNK_SIZE

local CHUNK_SIZE_DIVIDER = constants.CHUNK_SIZE_DIVIDER

-- imported functions

local mFloor = math.floor
local getPassable = chunkPropertyUtils.getPassable

-- module code

function mapUtils.getChunkByXY(map, x, y)
    local chunkX = map[x]
    if chunkX then
        return chunkX[y] or -1
    end
    return -1
end

function mapUtils.getChunkByPosition(map, position)
    local chunkX = map[mFloor(position.x * CHUNK_SIZE_DIVIDER) * CHUNK_SIZE]
    if chunkX then
        local chunkY = mFloor(position.y * CHUNK_SIZE_DIVIDER) * CHUNK_SIZE
        return chunkX[chunkY] or -1
    end
    return -1
end

function mapUtils.getChunkById(map, chunkId)
    return map.universe.chunkIdToChunk[chunkId] or -1
end

function mapUtils.positionToChunkXY(position)
    local chunkX = mFloor(position.x * CHUNK_SIZE_DIVIDER) * CHUNK_SIZE
    local chunkY = mFloor(position.y * CHUNK_SIZE_DIVIDER) * CHUNK_SIZE
    return chunkX, chunkY
end

function mapUtils.queueGeneratedChunk(universe, event)
    local map = universe.maps[event.surface.index]
    if not map then
        return
    end
    event.tick = (event.tick or game.tick) + 20
    event.id = universe.eventId
    event.map = map
    universe.pendingChunks[event.id] = event
    universe.eventId = universe.eventId + 1
end

function mapUtils.nextMap(universe)
    local mapIterator = universe.mapIterator
    repeat
        local map
        universe.mapIterator, map = next(universe.maps, universe.mapIterator)
        if map and map.activeSurface then
            return map
        end
    until mapIterator == universe.mapIterator
end

function mapUtils.removeChunkToNest(universe, chunkId)
    universe.chunkToNests[chunkId] = nil
    if (chunkId == universe.processNestIterator) then
        universe.processNestIterator = nil
    end
    if (chunkId == universe.processMigrationIterator) then
        universe.processMigrationIterator = nil
    end
end

function mapUtils.removeChunkFromMap(map, x, y, chunkId)
    local universe = map.universe
    map[x][y] = nil
    universe.chunkIdToChunk[chunkId] = nil
    universe.chunkToActiveNest[chunkId] = nil
    universe.chunkToActiveRaidNest[chunkId] = nil
    universe.chunkToDrained[chunkId] = nil
    universe.chunkToRetreats[chunkId] = nil
    universe.chunkToRallys[chunkId] = nil
    universe.chunkToPassScan[chunkId] = nil
    universe.chunkToNests[chunkId] = nil
    universe.vengenceQueue[chunkId] = nil
    universe.processActiveNest[chunkId] = nil
    universe.chunkToVictory[chunkId] = nil
    map.chunkToBase[chunkId] = nil
    map.chunkToTurrets[chunkId] = nil
    map.chunkToTraps[chunkId] = nil
    map.chunkToUtilities[chunkId] = nil
    map.chunkToHives[chunkId] = nil
    map.chunkToNestIds[chunkId] = nil
    map.chunkToHiveIds[chunkId] = nil
    map.chunkToTrapIds[chunkId] = nil
    map.chunkToTurretIds[chunkId] = nil
    map.chunkToUtilityIds[chunkId] = nil
    map.chunkToPlayerBase[chunkId] = nil
    map.chunkToResource[chunkId] = nil
    map.chunkToPlayerCount[chunkId] = nil
    map.chunkToSquad[chunkId] = nil
    map.chunkToPassable[chunkId] = nil
    map.chunkToPathRating[chunkId] = nil
    map.chunkToDeathGenerator[chunkId] = nil

    if universe.processActiveNestIterator == chunkId then
        universe.processActiveNestIterator = nil
    end
    if universe.victoryScentIterator == chunkId then
        universe.victoryScentIterator = nil
    end
    if universe.processNestIterator == chunkId then
        universe.processNestIterator = nil
    end
    if universe.chunkToDrainedIterator == chunkId then
        universe.chunkToDrainedIterator = nil
    end
    if universe.chunkToRetreatIterator == chunkId then
        universe.chunkToRetreatIterator = nil
    end
    if universe.chunkToRallyIterator == chunkId then
        universe.chunkToRallyIterator = nil
    end
    if universe.chunkToPassScanIterator == chunkId then
        universe.chunkToPassScanIterator = nil
    end
    if universe.processActiveSpawnerIterator == chunkId then
        universe.processActiveSpawnerIterator = nil
    end
    if universe.processActiveRaidSpawnerIterator == chunkId then
        universe.processActiveRaidSpawnerIterator = nil
    end
    if universe.processMigrationIterator == chunkId then
        universe.processMigrationIterator = nil
    end
    if universe.deployVengenceIterator == chunkId then
        universe.deployVengenceIterator = nil
    end
end

--[[
    1 2 3
    \|/
    4- -5
    /|\
    6 7 8
]]--
function mapUtils.getNeighborChunks(map, x, y)
    local neighbors = map.universe.neighbors
    local chunkYRow1 = y - CHUNK_SIZE
    local chunkYRow3 = y + CHUNK_SIZE
    local xChunks = map[x-CHUNK_SIZE]
    if xChunks then
        neighbors[1] = xChunks[chunkYRow1] or -1
        neighbors[4] = xChunks[y] or -1
        neighbors[6] = xChunks[chunkYRow3] or -1
    else
        neighbors[1] = -1
        neighbors[4] = -1
        neighbors[6] = -1
    end

    xChunks = map[x+CHUNK_SIZE]
    if xChunks then
        neighbors[3] = xChunks[chunkYRow1] or -1
        neighbors[5] = xChunks[y] or -1
        neighbors[8] = xChunks[chunkYRow3] or -1
    else
        neighbors[3] = -1
        neighbors[5] = -1
        neighbors[8] = -1
    end

    xChunks = map[x]
    if xChunks then
        neighbors[2] = xChunks[chunkYRow1] or -1
        neighbors[7] = xChunks[chunkYRow3] or -1
    else
        neighbors[2] = -1
        neighbors[7] = -1
    end
    return neighbors
end


--[[
    1 2 3
    \|/
    4- -5
    /|\
    6 7 8
]]--
function mapUtils.canMoveChunkDirection(map, direction, startChunk, endChunk)
    local canMove = false
    local startPassable = getPassable(map, startChunk)
    local endPassable = getPassable(map, endChunk)
    if (startPassable == CHUNK_ALL_DIRECTIONS) then
        if ((direction == 1) or (direction == 3) or (direction == 6) or (direction == 8)) then
            canMove = (endPassable == CHUNK_ALL_DIRECTIONS)
        elseif (direction == 2) or (direction == 7) then
            canMove = ((endPassable == CHUNK_NORTH_SOUTH) or (endPassable == CHUNK_ALL_DIRECTIONS))
        elseif (direction == 4) or (direction == 5) then
            canMove = ((endPassable == CHUNK_EAST_WEST) or (endPassable == CHUNK_ALL_DIRECTIONS))
        end
    elseif (startPassable == CHUNK_NORTH_SOUTH) then
        if ((direction == 1) or (direction == 3) or (direction == 6) or (direction == 8)) then
            canMove = (endPassable == CHUNK_ALL_DIRECTIONS)
        elseif (direction == 2) or (direction == 7) then
            canMove = ((endPassable == CHUNK_NORTH_SOUTH) or (endPassable == CHUNK_ALL_DIRECTIONS))
        end
    elseif (startPassable == CHUNK_EAST_WEST) then
        if ((direction == 1) or (direction == 3) or (direction == 6) or (direction == 8)) then
            canMove = (endPassable == CHUNK_ALL_DIRECTIONS)
        elseif (direction == 4) or (direction == 5) then
            canMove = ((endPassable == CHUNK_EAST_WEST) or (endPassable == CHUNK_ALL_DIRECTIONS))
        end
    else
        canMove = (endPassable ~= CHUNK_IMPASSABLE)
    end
    return canMove
end

function mapUtils.getCardinalChunks(map, x, y)
    local neighbors = map.universe.cardinalNeighbors
    local xChunks = map[x]
    if xChunks then
        neighbors[1] = xChunks[y-CHUNK_SIZE] or -1
        neighbors[4] = xChunks[y+CHUNK_SIZE] or -1
    else
        neighbors[1] = -1
        neighbors[4] = -1
    end

    xChunks = map[x-CHUNK_SIZE]
    if xChunks then
        neighbors[2] = xChunks[y] or -1
    else
        neighbors[2] = -1
    end

    xChunks = map[x+CHUNK_SIZE]
    if xChunks then
        neighbors[3] = xChunks[y] or -1
    else
        neighbors[3] = -1
    end
    return neighbors
end

function mapUtils.positionFromDirectionAndChunk(direction, startPosition, scaling)
    local endPosition = {}
    if (direction == 1) then
        endPosition.x = startPosition.x - CHUNK_SIZE * (scaling - 0.1)
        endPosition.y = startPosition.y - CHUNK_SIZE * (scaling - 0.1)
    elseif (direction == 2) then
        endPosition.x = startPosition.x
        endPosition.y = startPosition.y - CHUNK_SIZE * (scaling + 0.25)
    elseif (direction == 3) then
        endPosition.x = startPosition.x + CHUNK_SIZE * (scaling - 0.1)
        endPosition.y = startPosition.y - CHUNK_SIZE * (scaling - 0.1)
    elseif (direction == 4) then
        endPosition.x = startPosition.x - CHUNK_SIZE * (scaling + 0.25)
        endPosition.y = startPosition.y
    elseif (direction == 5) then
        endPosition.x = startPosition.x + CHUNK_SIZE * (scaling + 0.25)
        endPosition.y = startPosition.y
    elseif (direction == 6) then
        endPosition.x = startPosition.x - CHUNK_SIZE * (scaling - 0.1)
        endPosition.y = startPosition.y + CHUNK_SIZE * (scaling - 0.1)
    elseif (direction == 7) then
        endPosition.x = startPosition.x
        endPosition.y = startPosition.y + CHUNK_SIZE * (scaling + 0.25)
    elseif (direction == 8) then
        endPosition.x = startPosition.x + CHUNK_SIZE * (scaling - 0.1)
        endPosition.y = startPosition.y + CHUNK_SIZE * (scaling - 0.1)
    end
    return endPosition
end

function mapUtils.positionFromDirectionAndFlat(direction, startPosition, multipler)
    local lx = startPosition.x
    local ly = startPosition.y
    if not multipler then
        multipler = 1
    end
    if (direction == 1) then
        lx = lx - CHUNK_SIZE * multipler
        ly = ly - CHUNK_SIZE * multipler
    elseif (direction == 2) then
        ly = ly - CHUNK_SIZE * multipler
    elseif (direction == 3) then
        lx = lx + CHUNK_SIZE * multipler
        ly = ly - CHUNK_SIZE * multipler
    elseif (direction == 4) then
        lx = lx - CHUNK_SIZE * multipler
    elseif (direction == 5) then
        lx = lx + CHUNK_SIZE * multipler
    elseif (direction == 6) then
        lx = lx - CHUNK_SIZE * multipler
        ly = ly + CHUNK_SIZE * multipler
    elseif (direction == 7) then
        ly = ly + CHUNK_SIZE * multipler
    elseif (direction == 8) then
        lx = lx + CHUNK_SIZE * multipler
        ly = ly + CHUNK_SIZE * multipler
    end
    return {
        x = lx,
        y = ly
    }
end

mapUtilsG = mapUtils
return mapUtils
