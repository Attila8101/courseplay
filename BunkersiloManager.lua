---@class FieldManager
BunkerSiloManager = CpObject()

--for reference look up : "https://gdn.giants-software.com/documentation_scripting_fs19.php?version=script&category=26&class=244"
--mostly : "BunkerSilo:load(id, xmlFile, key)"
--[[
	example bunker with only one entrance side

				-----------------	<-- heightNode (hx,_,hz)
				| X X X X X X X |  				   ---
				| X X X X X X X | 					|
				| X X X X X X X | 					|
				| X X X X X X X | 					|
				| X X X X X X X | 					|	 bunkerLength 
				| X X X X X X X | 					|
				| X X X X X X X | 					|
				| X X X X X X X | 					|
				| X X X X X X X | 					|
				| X X X X X X X |  				   ---
widthNode -->	|				|	<-- startNode (sx,_,sz)
(wx,_,wz)	
				|---------------|
				   bunkerWidth
		
		X = unitArea = unitWidth*unitHeigth


]]--

--BunkerSiloManager should be a class of a bunkerSiloMap and not a global container for functions

-- Constructor
function BunkerSiloManager:init()
	print("BunkerSiloManager: init()")

end

g_bunkerSiloManager = BunkerSiloManager()

--createBunkerSiloMap() is not only for bunkerSilo or it dosen't always has the correct bunker setup ..

--width is workWidth of the tool
function BunkerSiloManager:createBunkerSiloMap(vehicle, Silo, width, height)
	-- the developer could have added comments explaining what sx/wx/hx is but chose not to do so
	-- ignoring his fellow developers ...
	
	--only for Heaps as this createBunkerSiloMap() also applies to it ..
	local sx,sz = Silo.bunkerSiloArea.sx,Silo.bunkerSiloArea.sz; --start BunkerNode
	local wx,wz = Silo.bunkerSiloArea.wx,Silo.bunkerSiloArea.wz; --width BunkerNode "x cordinate"
	local hx,hz = Silo.bunkerSiloArea.hx,Silo.bunkerSiloArea.hz; --height/"depth" BunkerNode "z cordinate"
	local bunkerWidth = courseplay:distance(sx,sz, wx, wz) 
	local bunkerLength = courseplay:distance(sx,sz, hx, hz)
	local sy = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, sx, 1, sz);
	
	-- check the distance from our vehicle either we are comming from the front or back of the silo
	local startDistance = courseplay:distanceToPoint(vehicle, sx, sy, sz)
	local endDistance = courseplay:distanceToPoint(vehicle, hx, sy, hz)
	
	--correct data for bunkerSilos
	--shorten the BunkerArea by 1.0 , as the silo size from Giants tends to be bigger the the actual fillArea 
	if Silo.bunkerSiloArea.start then
		sx, _, sz = localToWorld(Silo.bunkerSiloArea.start,-0.5,0,0) --start BunkerNode
		wx, _, wz = localToWorld(Silo.bunkerSiloArea.width,0.5,0,0) --width BunkerNode "x cordinate"
		hx, _, hz = localToWorld(Silo.bunkerSiloArea.height,-0.5,0,1) --height/"depth" BunkerNode "z cordinate"
		bunkerWidth = calcDistanceFrom(Silo.bunkerSiloArea.start,Silo.bunkerSiloArea.width)-1
		bunkerLength = calcDistanceFrom(Silo.bunkerSiloArea.start,Silo.bunkerSiloArea.height)-1
	end

		
	local widthDirX,widthDirY,widthDirZ,widthDistance = courseplay:getWorldDirection(sx,sy,sz, wx,sy,wz);
	local heightDirX,heightDirY,heightDirZ,heightDistance = courseplay:getWorldDirection(sx,sy,sz, hx,sy,hz);

	local widthCount = 0
	courseplay.debugVehicle(10, vehicle, 'Bunker width %.1f, working width %.1f (passed in)', bunkerWidth, width)
	widthCount =math.ceil(bunkerWidth/width)
	
	if vehicle.cp.mode10.leveling and courseplay:isEven(widthCount) then
		widthCount = widthCount+1
	end

	local heightCount = math.ceil(bunkerLength/ width)
	local unitWidth = bunkerWidth/widthCount
	local unitHeigth = bunkerLength/heightCount
	
	--width/height in 2D(x and z seperated) of silo

	local heightLengthX = (hx-sx)/heightCount
	local heightLengthZ = (hz-sz)/heightCount
	local widthLengthX = (wx-sx)/widthCount
	local widthLengthZ = (wz-sz)/widthCount
	local getOffTheWall = 0.5;

	local lastValidfillType = 0
	local map = {}
	for heightIndex = 1,heightCount do
		map[heightIndex]={}
		for widthIndex = 1,widthCount do
			local newWx = sx + widthLengthX
			local newWz = sz + widthLengthZ
			local newHx = sx + heightLengthX
			local newHz = sz + heightLengthZ
			
			--herrain height at start of small part
			local wY = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, newWx, 1, newWz);
			--herrain height at end of small part
			local hY = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, newHx, 1, newHz);
			--fillType in between 
			local fillType = DensityMapHeightUtil.getFillTypeAtLine(newWx, wY, newWz, newHx, hY, newHz, 5)
			if lastValidfillType ~= fillType and fillType ~= 0 then
				lastValidfillType = fillType
			end
			--fillLevel in small part
			local newFillLevel = DensityMapHeightUtil.getFillLevelAtArea(fillType, sx, sz, newWx, newWz, newHx, newHz )
			--center probably of small part ??
			local bx = sx + (widthLengthX/2) + (heightLengthX/2)
			local bz = sz + (widthLengthZ/2) + (heightLengthZ/2)
			local offset = 0
			if vehicle.cp.mode9TargetSilo and vehicle.cp.mode9TargetSilo.type and vehicle.cp.mode9TargetSilo.type == "heap" then
				--no idea ??
				offset = unitWidth/2
			else
				if widthIndex == 1 then
					offset = getOffTheWall + (width / 2)
				elseif widthIndex == widthCount then
					offset = unitWidth- (getOffTheWall + (width / 2))
				else
					offset = unitWidth / 2
				end
			end
			-- something with direction ??
			local cx,cz = sx +(widthDirX*offset)+(heightLengthX/2),sz +(widthDirZ*offset)+ (heightLengthZ/2)
			if vehicle.cp.mode == courseplay.MODE_SHOVEL_FILL_AND_EMPTY and heightIndex == heightCount then
				cx,cz = sx +(widthDirX*offset)+(heightLengthX),sz +(widthDirZ*offset)+ (heightLengthZ)
			end
			local unitArea = unitWidth*unitHeigth

			map[heightIndex][widthIndex] ={
				sx = sx;	-- start?
				sz = sz;
				y = wY;
				wx = newWx; -- width?
				wz = newWz;
				hx = newHx; -- height?
				hz = newHz;
				cx = cx;     -- center
				cz = cz;
				bx = bx;
				bz = bz;
				area = unitArea;
				fillLevel = newFillLevel;
				fillType = fillType;
				bunkerLength = bunkerLength;
				bunkerWidth = bunkerWidth;
			}

			sx = map[heightIndex][widthIndex].wx
			sz = map[heightIndex][widthIndex].wz
		end
		sx = map[heightIndex][1].hx
		sz = map[heightIndex][1].hz
	end
	if lastValidfillType > 0 then
		courseplay:debug(('%s: Bunkersilo filled with %s(%i) will be devided in %d lines and %d columns'):format(nameNum(vehicle),g_fillTypeManager.indexToName[lastValidfillType], lastValidfillType, heightCount, widthCount), 10);
	else
		courseplay:debug(('%s: empty Bunkersilo will be devided in %d lines and %d columns'):format(nameNum(vehicle), heightCount, widthCount), 10);
	end
	--invert table as we are comming from the back into the silo
	if endDistance < startDistance then
		courseplay:debug(('%s: Bunkersilo will be approached from the back -> turn map'):format(nameNum(vehicle)), 10);
		local newMap = {}
		local lineCounter = #map
		for lineIndex=1,lineCounter do
			local newLineIndex = lineCounter+1-lineIndex;
			--print(string.format("put line%s into line%s",tostring(lineIndex),tostring(newLineIndex)))
			newMap[newLineIndex]={}
			local columnCount = #map[lineIndex]
			for columnIndex =1, columnCount do
				--print(string.format("  put column%s into column%s",tostring(columnIndex),tostring(columnCount+1-columnIndex)))
				newMap[newLineIndex][columnCount+1-columnIndex] = map[lineIndex][columnIndex]
			end
		end
		map = newMap
	end
	return map
end

---get the best colum to fill
---@param siloMap BunkerSiloMap
---@return leastColumnIndex best column to fill
function BunkerSiloManager:getBestColumnToFill(siloMap)
	local leastFillLevel = math.huge
	local leastColumnIndex = 0
	for columnIndex=2,#siloMap[1]-1 do
		local currentFillLevel = 0
		for lineIndex=1,#siloMap do
			local fillUnit = siloMap[lineIndex][columnIndex]
			currentFillLevel = currentFillLevel + fillUnit.fillLevel
			--print(string.format("check:line %s, column %s fillLevel:%s",tostring(lineIndex),tostring(columnIndex),tostring(fillUnit.fillLevel)))
		end
		--print("column:"..tostring(columnIndex).." :"..tostring(currentFillLevel))
		if currentFillLevel<leastFillLevel then
			leastFillLevel = currentFillLevel
			leastColumnIndex = columnIndex
		end

	end
	return leastColumnIndex
end

---set the waypoint cordinates for the correct colum of the bunkerSiloMap
---@param course course of the driver
---@param siloMap BunkerSiloMap
---@param bestColumn target colum of the BunkerSiloMap
---@param ix currentWaypointIx of the driver
---@return foundFirst return first waypointIndex to start offset course from
function BunkerSiloManager:setOffsetsPerWayPoint(course,siloMap,bestColumn,ix)
	local points =	{}
	local foundFirst = 0
	for index=ix,course:getNumberOfWaypoints() do
		if BunkerSiloManagerUtil.getTargetBunkerSiloByPointOnCourse(course,index)~= nil then
			local closest,cx,cz = 0,0,0
			local leastDistance = math.huge
			for lineIndex=1,#siloMap do
				local fillUnit= siloMap[lineIndex][bestColumn]
				local x,z = fillUnit.cx,fillUnit.cz
				local distance = course:getDistanceBetweenPointAndWaypoint(x,z, index)
				if leastDistance > distance then
					leastDistance = distance
					closest = lineIndex
					cx,cz = x,z
				end
			end
			local y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, cx, 1, cz);
			course.waypoints[index].x = cx
			course.waypoints[index].z = cz
			--local offsetX,_,offsetZ = course:worldToWaypointLocal(index, cx, y, cz)
			points[index]= true
			--print(string.format("set %s new",tostring(index)))
			if foundFirst == 0 then
				foundFirst = index
			end
		elseif foundFirst ~= 0 then
			break
		end
	end

	return foundFirst
end

---have we reached the end ?
---@param object front object of the vehicle, example shovel/leveler
---@param Silo the targetSilo for creating the bunkerSiloMap
---@param bestTarget bunkersilo bestTarget part
---@return isAtEnd
function BunkerSiloManager:isAtEnd(object,bunkerSiloMap,bestTarget)
	if not bunkerSiloMap or not bestTarget then 
		return
	end
	
	local targetUnit = bunkerSiloMap[bestTarget.line][bestTarget.column]
	local cx ,cz = targetUnit.cx, targetUnit.cz
	local cy = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, cx, 1, cz);
	local x,y,z = getWorldTranslation(object.rootNode)
	local distance2Target =  courseplay:distance(x,z, cx, cz) --distance from shovel to target
	if distance2Target < 1 then
		if bestTarget.line == #bunkerSiloMap then
			return true
		end
	end
end

--- creating bunkerSiloMap and get the bestTarget, firstLine of the bestTarget
---@param vehicle vehicle of the driver
---@param Silo the targetSilo for creating the bunkerSiloMap
---@param bestTarget bunkersilo bestTarget part
---@param workWidth workWidth of the driver
---@return bunkerSiloMap, bestTarget, firstLine of the bestTarget
function BunkerSiloManager:getBestTargetFillUnitFillUp(vehicle,Silo,bestTarget,workWidth)
	--print(string.format("courseplay:getActualTarget(vehicle) called by %s",tostring(courseplay.utils:getFnCallPath(3))))
	local firstLine = 0
	local bunkerSiloMap = g_bunkerSiloManager:createBunkerSiloMap(vehicle, Silo, workWidth)
	
	if bunkerSiloMap ~= nil then
		local stopSearching = false
		local mostFillLevelAtLine = 0
		local mostFillLevelIndex = 2
		local fillingTarget = {}

		-- find column with most fillLevel and figure out whether it is empty
		for lineIndex, line in pairs(bunkerSiloMap) do
			if stopSearching then
				break
			end
			mostFillLevelAtLine = 0
			for column, fillUnit in pairs(line) do
				if 	mostFillLevelAtLine < fillUnit.fillLevel then
					mostFillLevelAtLine = fillUnit.fillLevel
					mostFillLevelIndex = column
				end
				if column == #line and mostFillLevelAtLine > 0 then
					fillingTarget = {
										line = lineIndex;
										column = mostFillLevelIndex;
										empty = false;
												}
					stopSearching = true
					break
				end
			end
		end
		if mostFillLevelAtLine == 0 then
			fillingTarget = {
										line = 1;
										column = 1;
										empty = true;
												}
		end
		
		bestTarget = fillingTarget
		firstLine = bestTarget.line
	end
	
	return bunkerSiloMap, bestTarget, firstLine
end


--- Are we near the end ?
---@param bunkerSiloMap the bunker/heap map
---@param bestTarget bunkersilo bestTarget part
---@return isNearEnd are we close to the end ?
function BunkerSiloManager:isNearEnd(bunkerSiloMap,bestTarget)
	return bestTarget.line >= #bunkerSiloMap-1
end

--- updating the current silo target part
---@param object front object of the vehicle, example shovel/leveler
---@param bunkerSiloMap the bunker/heap map
---@param bestTarget bunkersilo bestTarget
function BunkerSiloManager:updateTarget(object,bunkerSiloMap,bestTarget)
	local targetUnit = bunkerSiloMap[bestTarget.line][bestTarget.column]
	local cx ,cz = targetUnit.cx, targetUnit.cz
	local cy = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, cx, 1, cz);
	local x,y,z = getWorldTranslation(object.rootNode)
	local distance2Target =  courseplay:distance(x,z, cx, cz) --distance from shovel to target
	if distance2Target < 1 then
		bestTarget.line = math.min(bestTarget.line + 1, #bunkerSiloMap)
	end		
end

BunkerSiloManagerUtil = {}

---drawing the routing of the driver 
---@param vehicle vehicle of the driver
---@param bunkerSiloMap the bunker/heap map
---@param targetSilo bunkersilo target part
---@param bestTarget bunkersilo bestTarget
---@param tempTarget for driving out of the silo
function BunkerSiloManagerUtil.debugRouting(vehicle,bunkerSiloMap,targetSilo,bestTarget,tempTarget)
	if bunkerSiloMap ~= nil and bestTarget ~= nil then

		local fillUnit = bunkerSiloMap[bestTarget.line][bestTarget.column]
		--print(string.format("fillUnit %s; self.cp.actualTarget.line %s; self.cp.actualTarget.column %s",tostring(fillUnit),tostring(self.cp.actualTarget.line),tostring(self.cp.actualTarget.column)))
		local sx,sz = fillUnit.sx,fillUnit.sz
		local wx,wz = fillUnit.wx,fillUnit.wz
		local bx,bz = fillUnit.bx,fillUnit.bz
		local hx,hz = fillUnit.hx +(fillUnit.wx-fillUnit.sx) ,fillUnit.hz +(fillUnit.wz-fillUnit.sz)
		local _,tractorHeight,_ = getWorldTranslation(vehicle.cp.directionNode)
		local y = tractorHeight + 1.5;

		cpDebug:drawLine(sx, y, sz, 1, 0, 0, wx, y, wz);
		cpDebug:drawLine(wx, y, wz, 1, 0, 0, hx, y, hz);
		cpDebug:drawLine(fillUnit.hx, y, fillUnit.hz, 1, 0, 0, sx, y, sz);
		cpDebug:drawLine(fillUnit.cx, y, fillUnit.cz, 1, 0, 1, bx, y, bz);
		cpDebug:drawPoint(fillUnit.cx, y, fillUnit.cz, 1, 1 , 1);

		local bunker = targetSilo
		if bunker ~= nil then
			local sx,sz = bunker.bunkerSiloArea.sx,bunker.bunkerSiloArea.sz
			local wx,wz = bunker.bunkerSiloArea.wx,bunker.bunkerSiloArea.wz
			local hx,hz = bunker.bunkerSiloArea.hx,bunker.bunkerSiloArea.hz
			cpDebug:drawLine(sx,y+2,sz, 0, 0, 1, wx,y+2,wz);
			--drawDebugLine(sx,y+2,sz, 0, 0, 1, hx,y+2,hz, 0, 1, 0);
			--drawDebugLine(wx,y+2,wz, 0, 0, 1, hx,y+2,hz, 0, 1, 0);
			cpDebug:drawLine(sx,y+2,sz, 0, 0, 1, hx,y+2,hz);
			cpDebug:drawLine(wx,y+2,wz, 0, 0, 1, hx,y+2,hz);
		end
		if tempTarget ~= nil then
			local tx,tz = tempTarget.cx,tempTarget.cz
			local fillUnit = bunkerSiloMap[bestTarget.line][bestTarget.column]
			local sx,sz = fillUnit.sx,fillUnit.sz
			cpDebug:drawLine(tx, y, tz, 1, 0, 1, sx, y, sz);
			cpDebug:drawPoint(tx, y, tz, 1, 1 , 1);
		end
	end
end

---drawing the bunkerSiloMap 
---@param bunkerSiloMap the bunker/heap map
---@param targetSilo bunkersilo target part
function BunkerSiloManagerUtil.drawMap(bunkerSiloMap,targetSilo)
	function drawTile(f, r, g, b)
		cpDebug:drawLine(f.sx, f.y + 1, f.sz, r, g, b, f.wx, f.y + 1, f.wz)
		cpDebug:drawLine(f.wx, f.y + 1, f.wz, r, g, b, f.hx, f.y + 1, f.hz)
		cpDebug:drawLine(f.hx, f.y + 1, f.hz, r, g, b, f.sx, f.y + 1, f.sz);
		cpDebug:drawLine(f.cx, f.y + 1, f.cz, 1, 1, 1, f.bx, f.y + 1, f.bz);
	end

	if not bunkerSiloMap then return end
	for _, line in pairs(bunkerSiloMap) do
		for _, fillUnit in pairs(line) do
			drawTile(fillUnit, 1/1 - fillUnit.fillLevel, 1, 0)
		end
	end
	if not targetSilo then return end
	if targetSilo.bunkerSiloArea.start then 
		DebugUtil.drawDebugNode(targetSilo.bunkerSiloArea.start, 'startBunkerNode')
		DebugUtil.drawDebugNode(targetSilo.bunkerSiloArea.width, 'widthBunkerNode')
		DebugUtil.drawDebugNode(targetSilo.bunkerSiloArea.height, 'heightBunkerNode')
	else --for heaps where we have no bunker nodes (start/width/height)
		cpDebug:drawPoint(targetSilo.bunkerSiloArea.sx, 1, targetSilo.bunkerSiloArea.sz, 1, 1, 1)
		cpDebug:drawPoint(targetSilo.bunkerSiloArea.wx, 1, targetSilo.bunkerSiloArea.wz, 1, 1, 1)
		cpDebug:drawPoint(targetSilo.bunkerSiloArea.hx, 1, targetSilo.bunkerSiloArea.hz, 1, 1, 1)
	end
end




---get the closest bunkerSilo or heap
---@param vehicle vehicle of the driver
---@param forcedPoint forces search around waypointIndex=forcedPoint
---@param checkForHeapsActive is using Heaps allowed, for example mode 9
---@return targetSilo either the found BunkerSilo or
--		   a simulated silo by BunkerSiloManagerUtil.getHeapsMinMaxCoords() for Heaps
function BunkerSiloManagerUtil.getTargetBunkerSilo(vehicle,forcedPoint,checkForHeapsActive)
	local pointIndex = 0
	if forcedPoint then
		 pointIndex = forcedPoint;
	else
		pointIndex = vehicle.cp.driver.shovelFillStartPoint+2
	end
	local x,z = vehicle.Waypoints[pointIndex].cx,vehicle.Waypoints[pointIndex].cz			
	local tx,tz = x,z + 0.50
	local p1x,p1z,p2x,p2z,p1y,p2y = 0,0,0,0,0,0
	if g_currentMission.bunkerSilos ~= nil then
		for _, bunker in pairs(g_currentMission.bunkerSilos) do
			local x1,z1 = bunker.bunkerSiloArea.sx,bunker.bunkerSiloArea.sz
			local x2,z2 = bunker.bunkerSiloArea.wx,bunker.bunkerSiloArea.wz
			local x3,z3 = bunker.bunkerSiloArea.hx,bunker.bunkerSiloArea.hz
			bunker.type = "silo"
			if MathUtil.hasRectangleLineIntersection2D(x1,z1,x2-x1,z2-z1,x3-x1,z3-z1,x,z,tx-x,tz-z) then
				return bunker
			end
		end
	end
	--it's not a bunkersSilo, try to find a heap if it is allowed
	if checkForHeapsActive then
		return BunkerSiloManagerUtil.getHeapCoords(vehicle)
	end
end


---check for heaps and simulate a bunkerSiloMap for the found heap
---@param vehicle vehicle of the driver
---return targetSilo a simulated bunkerSilo version of the heap
function BunkerSiloManagerUtil.getHeapCoords(vehicle)
	local p1x,p1z,p2x,p2z,p1y,p2y = 0,0,0,0,0,0

	p1x,p1z = vehicle.Waypoints[vehicle.cp.driver.shovelFillStartPoint].cx,vehicle.Waypoints[vehicle.cp.driver.shovelFillStartPoint].cz;
	p2x,p2z = vehicle.Waypoints[vehicle.cp.driver.shovelFillEndPoint].cx,vehicle.Waypoints[vehicle.cp.driver.shovelFillEndPoint].cz;
	p1y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, p1x, 1, p1z);
	p2y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, p2x, 1, p2z);
	local heapFillType = DensityMapHeightUtil.getFillTypeAtLine(p1x, p1y, p1z, p2x, p2y, p2z, 5)
	
	if not heapFillType or heapFillType == FillType.UNKNOWN then 
		return 
	end
	courseplay:debug(string.format("%s: heap with %s found",nameNum(vehicle),tostring(heapFillType)),10)
	--create temp node 
	local point = createTransformGroup("cpTempHeapFindingPoint");
	link(g_currentMission.terrainRootNode, point);

	-- Rotate it in the right direction
	local dx,_,dz, distance = courseplay:getWorldDirection(p1x,p1y,p1z,p2x,p2y,p2z);
	
	setTranslation(point,p1x,p1y,p1z);
	local yRot = MathUtil.getYRotationFromDirection(dx, dz);
	setRotation(point, 0, yRot, 0);

	--debug line vor search area to be sure, the point is set correctly
	vehicle.cp.tempMOde9PointX,vehicle.cp.tempMOde9PointY,vehicle.cp.tempMOde9PointZ = getWorldTranslation(point)
	vehicle.cp.tempMOde9PointX2,vehicle.cp.tempMOde9PointY2,vehicle.cp.tempMOde9PointZ2 = localToWorld(point,0,0,distance*2)
	
	-- move the line to find out the size of the heap
	
	--find maxX 
	local stepSize = 0.1
	local searchWidth = 0.1
	local maxX = 0
	local tempStartX, tempStartZ,tempHeightX,tempHeightZ = 0,0,0,0;
	for i=stepSize,250,stepSize do
		tempStartX,tempStartY,tempStartZ = localToWorld(point,i,0,0)
		tempHeightX,tempHeightY,tempHeightZ= localToWorld(point,i,0,distance*2)
		local fillType = DensityMapHeightUtil.getFillTypeAtLine(tempStartX, tempStartY, tempStartZ,tempHeightX,tempHeightY,tempHeightZ, searchWidth)
		--print(string.format("fillType:%s distance: %.1f",tostring(fillType),i))	
		if fillType ~= heapFillType then
			maxX = i-stepSize
			courseplay:debug("maxX= "..tostring(maxX),10)
			break
		end
	end
	
	--find minX 
	local minX = 0
	local tempStartX, tempStartZ,tempHeightX,tempHeightZ = 0,0,0,0;
	for i=stepSize,250,stepSize do
		tempStartX,tempStartY,tempStartZ = localToWorld(point,-i,0,0)
		tempHeightX,tempHeightY,tempHeightZ= localToWorld(point,-i,0,distance*2)
		local fillType = DensityMapHeightUtil.getFillTypeAtLine(tempStartX,tempStartY, tempStartZ,tempHeightX,tempHeightY,tempHeightZ, searchWidth)
		--print(string.format("fillType:%s distance: %.1f",tostring(fillType),i))	
		if fillType ~= heapFillType then
			minX = i-stepSize
			courseplay:debug("minX= "..tostring(minX),10)
			break
		end
	end
	
	--find minZ and maxZ
	local foundHeap = false
	local minZ, maxZ = 0,0
	for i=0,250,stepSize do
		tempStartX,tempStartY,tempStartZ = localToWorld(point,maxX,0,i)
		tempHeightX,tempHeightY,tempHeightZ= localToWorld(point,-minX,0,i)
		local fillType = DensityMapHeightUtil.getFillTypeAtLine(tempStartX, tempStartY, tempStartZ,tempHeightX,tempHeightY,tempHeightZ, searchWidth)
		if not foundHeap then
			if fillType == heapFillType then
				foundHeap = true
				minZ = i-stepSize
				courseplay:debug("minZ= "..tostring(minZ),10)
			end
		else
			if fillType ~= heapFillType then
				maxZ = i-stepSize+1
				courseplay:debug("maxZ= "..tostring(maxZ),10)
				break
			end
		end	
	end
	
	--set found values into bunker table and return it
	local bunker = {}
	bunker.bunkerSiloArea = {}
	bunker.bunkerSiloArea.sx,_,bunker.bunkerSiloArea.sz = localToWorld(point,maxX,0,minZ);
	bunker.bunkerSiloArea.wx,_,bunker.bunkerSiloArea.wz = localToWorld(point,-minX,0,minZ)
	bunker.bunkerSiloArea.hx,_,bunker.bunkerSiloArea.hz = localToWorld(point,maxX,0,maxZ)
	bunker.type = "heap"

		
	-- Clean up the temporary node.
	unlink(point);
	delete(point);
	
	
	return bunker
end

---get the best colum to fill
---@param course course of the driver
---@param forcedPoint forcedPoint or 1 to find the next closest bunkersilo
---@return leastColumnIndex best column to fill
function BunkerSiloManagerUtil.getTargetBunkerSiloByPointOnCourse(course,forcedPoint)
	local pointIndex = forcedPoint or 1 ;
	local x,_,z =  course:getWaypointPosition(pointIndex)
	local tx,tz = x,z + 0.50
	local p1x,p1z,p2x,p2z,p1y,p2y = 0,0,0,0,0,0
	if g_currentMission.bunkerSilos ~= nil then
		for _, bunker in pairs(g_currentMission.bunkerSilos) do
			local x1,z1 = bunker.bunkerSiloArea.sx,bunker.bunkerSiloArea.sz
			local x2,z2 = bunker.bunkerSiloArea.wx,bunker.bunkerSiloArea.wz
			local x3,z3 = bunker.bunkerSiloArea.hx,bunker.bunkerSiloArea.hz
			bunker.type = "silo"
			if MathUtil.hasRectangleLineIntersection2D(x1,z1,x2-x1,z2-z1,x3-x1,z3-z1,x,z,tx-x,tz-z) then
				return bunker
			end
		end
	end
end

