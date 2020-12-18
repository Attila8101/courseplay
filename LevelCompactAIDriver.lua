--[[
This file is part of Courseplay (https://github.com/Courseplay/courseplay)
Copyright (C) 2019 Thomas Gaertner

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

--[[
handles "mode10": level and compact
--------------------------------------
0)  Course setup:
	a) Start in the silo
	b) drive forward, set waiting point on parking postion out fot the way
	c) drive to the last point which should be alligned with the silo center line and be outside the silo



]]

---@class LevelCompactAIDriver : AIDriver

LevelCompactAIDriver = CpObject(AIDriver)

LevelCompactAIDriver.myStates = {
	DRIVE_TO_PARKING = {checkForTrafficConflict = true},
	WAITING_FOR_FREE_WAY = {},
	CHECK_SILO = {},
	CHECK_SHIELD = {},
	DRIVE_IN_SILO = {},
	DRIVE_SILOFILLUP ={},
	DRIVE_SILOLEVEL ={},
	DRIVE_SILOCOMPACT = {},
	PUSH = {},
	PULLBACK = {}
}

--- Constructor
function LevelCompactAIDriver:init(vehicle)
	courseplay.debugVehicle(11,vehicle,'LevelCompactAIDriver:init') 
	AIDriver.init(self, vehicle)
	self:initStates(LevelCompactAIDriver.myStates)
	self.mode = courseplay.MODE_BUNKERSILO_COMPACTER
	self.debugChannel = 10
	self.refSpeed = 10
	self:setHudContent()
	self.fillUpState = self.states.PUSH
	self.stoppedCourseplayers = {}
	self:setLevelerWorkWidth()
--	self.unloaderAIDrivers = nil
end

function LevelCompactAIDriver:setHudContent()
	courseplay.hud:setLevelCompactAIDriverContent(self.vehicle)
end

function LevelCompactAIDriver:start(startingPoint)
	AIDriver.start(self,startingPoint)
	self:changeLevelState(self.states.CHECK_SILO)
	self.fillUpState = self.states.PUSH
	self.alphaList = nil
	self.lastDrivenColumn = nil
	-- reset target silo in case we want to work on a different one...
	self.targetSilo = nil
	self.bestTarget = nil
	self.bunkerSiloMap = nil
	self.tempCourse = nil
	self:setLevelerWorkWidth()
end

function LevelCompactAIDriver:drive(dt)
	-- update current waypoint/goal point
	self:drawMap()
	self.allowedToDrive = true
	if self:foundUnloaderInRadius(self.vehicle.cp.mode10.searchRadius,not self:isWaitingForUnloaders()) then 
		self.hasFoundUnloaders = true
	end	
	
	if self.levelState == self.states.DRIVE_TO_PARKING then
		self:moveShield('up',dt)
		self.ppc:update()
		AIDriver.driveCourse(self, dt)
	elseif self.levelState == self.states.WAITING_FOR_FREE_WAY then
		self:stopAndWait(dt)

		if not self.hasFoundUnloaders then
			self:changeLevelState(self.states.DRIVE_TO_PARKING)
			self:clearInfoText('WAITING_FOR_UNLOADERS')
		else 
			self:setInfoText('WAITING_FOR_UNLOADERS')
		end
	elseif self.levelState == self.states.CHECK_SILO then
		self:stopAndWait(dt)
		if self:checkSilo() then
			self:changeLevelState(self.states.CHECK_SHIELD)
		end
	elseif self.levelState == self.states.CHECK_SHIELD then
		self:stopAndWait(dt)
		if self:checkShield() then
			self:selectMode()
		end
	elseif self.levelState == self.states.DRIVE_SILOFILLUP then
		self:driveSiloFillUp(dt)
	elseif self.levelState == self.states.DRIVE_SILOLEVEL then
		self:driveSiloLevel(dt)
	elseif self.levelState == self.states.DRIVE_SILOCOMPACT then
		self:driveSiloCompact(dt)
	end
end

function LevelCompactAIDriver:foundUnloaderInRadius(r,setWaiting)
	if g_currentMission then
		for _, vehicle in pairs(g_currentMission.vehicles) do
			if vehicle ~= self.vehicle then
				local d = calcDistanceFrom(self.vehicle.rootNode, vehicle.rootNode)
				if d < r then
					if courseplay:isAIDriverActive(vehicle) and vehicle.cp.driver.triggerHandler:isNearBunkerSilo() then --CombineUnloadAIDriver,GrainTransportAIDriver,UnloadableFieldworkAIDriver
						if setWaiting then 
							vehicle.cp.driver.triggerHandler:setWaitingForUnloadReady()
						else 
							vehicle.cp.driver.triggerHandler:resetWaitingForUnloadReady()
						end
						return true
				--		self.unloaderAIDrivers[#self.unloaderAIDrivers+1] = vehicle
					elseif vehicle.getIsEntered and vehicle:getIsEntered() and AIDriverUtil.getImplementWithSpecialization(vehicle, Trailer) ~= nil then --player ??
						return true
					elseif vehicle.spec_autodrive and vehicle.spec_autodrive.HoldDriving then --autodrive
						if setWaiting then
							vehicle.spec_autodrive.HoldDriving(vehicle)
						end
						return true
					end
				end
			end
		end
	end
end

function LevelCompactAIDriver:isWaitingForUnloaders()
	return self.levelState == self.states.WAITING_FOR_FREE_WAY
end 

function LevelCompactAIDriver:isTrafficConflictDetectionEnabled()
	return self.trafficConflictDetectionEnabled and self.levelState and self.levelState.properties.checkForTrafficConflict
end

function LevelCompactAIDriver:checkShield()
	
	local leveler = AIDriverUtil.getImplementWithSpecialization(self.vehicle, Leveler)
	if leveler then
		if self:getIsModeFillUp() or self:getIsModeLeveling() then
			--record alphaList if not existing
			if self.alphaList == nil then
				self:setIsAlphaListrecording()
			end
			if self:getIsAlphaListrecording() then
				self:recordAlphaList()
			else
				return true
			end
		else
			courseplay:setInfoText(self.vehicle, 'COURSEPLAY_WRONG_TOOL');
		end
	else
		local compactor = AIDriverUtil.getImplementWithSpecialization(self.vehicle, BunkerSiloCompacter)
		if compactor then
			if self:getIsModeCompact() then
				return true
			else
				courseplay:setInfoText(self.vehicle, 'COURSEPLAY_WRONG_TOOL');
			end
		end
	end		
end


function LevelCompactAIDriver:selectMode()
	if self:getIsModeFillUp() then
		self:debug("self:getIsModeFillUp()")
		self:changeLevelState(self.states.DRIVE_SILOFILLUP)
	elseif self:getIsModeLeveling() then
		self:debug("self:getIsModeLeveling()")
		self:changeLevelState(self.states.DRIVE_SILOLEVEL)
	elseif self:getIsModeCompact()then
		self:debug("self:isModeCompact()")
		self:changeLevelState(self.states.DRIVE_SILOCOMPACT)
	end
	self.fillUpState = self.states.PUSH
end

function LevelCompactAIDriver:driveSiloCompact(dt)
	if self.fillUpState == self.states.PUSH then
		--initialize first target point
		if self.bestTarget == nil then
			self.bestTarget, self.firstLine, self.targetHeight = self:getBestTargetFillUnitLeveling(self.targetSilo,self.lastDrivenColumn)
		end

		self:drivePush(dt)
		self:lowerImplements()
		if self:isAtEnd() then
			if self.hasFoundUnloaders then
				self:changeLevelState(self.states.DRIVE_TO_PARKING)
				local ix = self.course:getStartingWaypointIx(AIDriverUtil.getDirectionNode(self.vehicle), StartingPointSetting.START_AT_NEXT_POINT)
				AIDriver.startCourseWithAlignment(self,self.course, ix)
				self:deleteBestTarget()
				self:raiseImplements()
				return
			else
				self.fillUpState = self.states.PULLBACK
			end
		end
	
	elseif self.fillUpState == self.states.PULLBACK then
		if self:drivePull(dt) then
			self.fillUpState = self.states.PUSH
			self:deleteBestTargetLeveling()
			self:raiseImplements()
		end
	end
end

function LevelCompactAIDriver:driveSiloLevel(dt)
	if self.fillUpState == self.states.PUSH then
		--initialize first target point
		if self.bestTarget == nil then
			self.bestTarget, self.firstLine, self.targetHeight = self:getBestTargetFillUnitLeveling(self.targetSilo,self.lastDrivenColumn)
		end
		renderText(0.2,0.395,0.02,"self:drivePush(dt)")

		self:drivePush(dt)
		self:moveShield('down',dt,self:getDiffHeightforHeight(self.targetHeight))
	
		if self:isAtEnd()
		or self:hasShieldEmpty()
		or self:isStuck()
		then
			if self.hasFoundUnloaders then
				self:changeLevelState(self.states.DRIVE_TO_PARKING)
				local ix = self.course:getStartingWaypointIx(AIDriverUtil.getDirectionNode(self.vehicle), StartingPointSetting.START_AT_NEXT_POINT)
				AIDriver.startCourseWithAlignment(self,self.course, ix)
				self:deleteBestTarget()
				return
			else
				self.fillUpState = self.states.PULLBACK
			end
		end
	
	
	elseif self.fillUpState == self.states.PULLBACK then
		renderText(0.2,0.365,0.02,"self:drivePull(dt)")
		self:moveShield('up',dt)
		if self:isStuck() then
			self.fillUpState = self.states.PUSH
		end
		if self:drivePull(dt) then
			self.fillUpState = self.states.PUSH
			self:deleteBestTargetLeveling()
		end
	end
end

function LevelCompactAIDriver:driveSiloFillUp(dt)
--	self:drawMap()
	if self.fillUpState == self.states.PUSH then
		--initialize first target point
		if self.bestTarget == nil then
			self.bestTarget, self.firstLine = g_bunkerSiloManager:getBestTargetFillUnitFillUp(self.bunkerSiloMap,self.bestTarget)
		end		
		self:drivePush(dt)
		self:moveShield('down',dt,0)
		--self:moveShield('down',dt,self:getDiffHeightforHeight(0))
		if self:lastLineFillLevelChanged()
		or self:isStuck()
		or self:hasShieldEmpty()
		then
			self.tempCourse = nil
			if self.hasFoundUnloaders then
				self:changeLevelState(self.states.DRIVE_TO_PARKING)
				local ix = self.course:getStartingWaypointIx(AIDriverUtil.getDirectionNode(self.vehicle), StartingPointSetting.START_AT_NEXT_POINT)
				AIDriver.startCourseWithAlignment(self,self.course, ix)
				self:deleteBestTarget()
				return
			else
				self.fillUpState = self.states.PULLBACK
			end
		end	
	elseif self.fillUpState == self.states.PULLBACK then
		self:moveShield('up',dt)
		if self:drivePull(dt) or self:getHasMovedToFrontLine(dt) then
			self.fillUpState = self.states.PUSH
			self:deleteBestTarget()
		end
	end
end	
	
function LevelCompactAIDriver:drivePush(dt)
	local vehicle = self.vehicle
	local fwd = false
	local allowedToDrive = true
	local refSpeed = 15
	local cx, cy, cz = 0,0,0
	--get coords of the target point
	local targetUnit = self.bunkerSiloMap[self.bestTarget.line][self.bestTarget.column]
	if self.tempCourse == nil then 
		local node = courseplay.createNode("temp", targetUnit.bx, targetUnit.y, targetUnit.bz)
		local lx,ly,lz = getRotation(self.targetSilo.bunkerSiloArea.start)
		setRotation(node,lx,ly,lz)
		self.tempCourse = Course.createFromNode(self.vehicle, node, 0, 0, 10, 2, true)
	--	localToWorld(tempNode.node,x, y, z)
		AIDriver.startCourseWithAlignment(self,self.tempCourse, 1)
	end
	
	
--	cx ,cz = targetUnit.cx, targetUnit.cz
--	cy = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, cx, 1, cz);
	--check whether its time to change the target point	
	self:updateTarget()
	--speed
	if self:isNearEnd() then
		refSpeed = math.min(10,vehicle.cp.speeds.bunkerSilo)
	else
		refSpeed = math.min(20,vehicle.cp.speeds.bunkerSilo)
	end		
	--drive
--	local lx, lz = AIVehicleUtil.getDriveDirection(self.vehicle.cp.directionNode, cx,cy,cz);
--	if not fwd then
--		lx, lz = -lx,-lz
--	end
	self:debugRouting()
--	self:drawMap()
--	self:driveInDirection(dt,lx,lz,fwd,refSpeed,allowedToDrive)
	AIDriver.driveCourse(self, dt)
end	

function LevelCompactAIDriver:drivePull(dt)
	local pullDone = false
	local fwd = true
	local refSpeed = math.min(20,self.vehicle.cp.speeds.bunkerSilo)
	local allowedToDrive = true 
	local cx,cy,cz = self.course:getWaypointPosition(self.course:getNumberOfWaypoints())
	local lx, lz = AIVehicleUtil.getDriveDirection(self.vehicle.cp.directionNode, cx,cy,cz);
	self:driveInDirection(dt,lx,lz,fwd,refSpeed,allowedToDrive)
	--end if I moved over the last way point
	if lz < 0 then
		pullDone = true
	end
--	self:drawMap()
	return pullDone
end

function LevelCompactAIDriver:getHasMovedToFrontLine(dt)
	local startUnit = self.bunkerSiloMap[self.firstLine][1]
	local _,ty,_ = getWorldTranslation(self.vehicle.cp.directionNode);
	local _,_,z = worldToLocal(self.vehicle.cp.directionNode, startUnit.cx , ty , startUnit.cz);
	if z < -15 then
		return true;			
	end
	return false;
end

function LevelCompactAIDriver:isNearEnd()
	return g_bunkerSiloManager:isNearEnd(self.bunkerSiloMap,self.bestTarget)
end


function LevelCompactAIDriver:lastLineFillLevelChanged()
	local vehicle = self.vehicle
	local newSx = self.bunkerSiloMap[#self.bunkerSiloMap][1].sx 
	local newSz = self.bunkerSiloMap[#self.bunkerSiloMap][1].sz 
	local newWx = self.bunkerSiloMap[#self.bunkerSiloMap][#self.bunkerSiloMap[#self.bunkerSiloMap]].wx
	local newWz = self.bunkerSiloMap[#self.bunkerSiloMap][#self.bunkerSiloMap[#self.bunkerSiloMap]].wz
	local newHx = self.bunkerSiloMap[#self.bunkerSiloMap][1].hx
	local newHz = self.bunkerSiloMap[#self.bunkerSiloMap][1].hz
	local wY = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, newWx, 1, newWz); 
	local hY = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, newHx, 1, newHz);

	local fillType = DensityMapHeightUtil.getFillTypeAtLine(newWx, wY, newWz, newHx, hY, newHz, 5)
	local newFillLevel = DensityMapHeightUtil.getFillLevelAtArea(fillType, newSx, newSz, newWx, newWz, newHx, newHz )

	if self.savedLastLineFillLevel == nil then
		self.savedLastLineFillLevel = newFillLevel 
	end
	
	if self.savedLastLineFillLevel ~= newFillLevel then
		self.savedLastLineFillLevel = nil
		self:debug("dropout fillLevel")
		return true
		
	end	
end


function LevelCompactAIDriver:isStuck()
	if self:doesNotMove() then
		if self.vehicle.cp.timers.slipping == nil or self.vehicle.cp.timers.slipping == 0 then
			courseplay:setCustomTimer(self.vehicle, 'slipping', 3);
			--courseplay:debug(('%s: setCustomTimer(..., "slippingStage", 3)'):format(nameNum(self.vehicle)), 10);
		elseif courseplay:timerIsThrough(self.vehicle, 'slipping') then
			--courseplay:debug(('%s: timerIsThrough(..., "slippingStage") -> return isStuck(), reset timer'):format(nameNum(self.vehicle)), 10);
			courseplay:resetCustomTimer(self.vehicle, 'slipping');
			self:debug("dropout isStuck")
			return true
		end;
	else
		courseplay:resetCustomTimer(self.vehicle, 'slipping');
	end

end

function LevelCompactAIDriver:doesNotMove()
	-- giants supplied last speed is in mm/s;
	-- does not move if we are less than 1km/h
	return math.abs(self.vehicle.lastSpeedReal) < 1/3600 and self.bestTarget.line > self.firstLine+1
end

function LevelCompactAIDriver:hasShieldEmpty()
	--return self.vehicle.cp.workTools[1]:getFillUnitFillLevel(1) < 100 and self.bestTarget.line > self.firstLine
	local tool = self:getValidFrontImplement()
	if tool:getFillUnitFillLevel(1) < 100 then
		if self.vehicle.cp.timers.bladeEmpty == nil or self.vehicle.cp.timers.bladeEmpty == 0 then
			courseplay:setCustomTimer(self.vehicle, 'bladeEmpty', 3);
		elseif courseplay:timerIsThrough(self.vehicle, 'bladeEmpty') and self.bestTarget.line > self.firstLine + 1 then
			courseplay:resetCustomTimer(self.vehicle, 'bladeEmpty');
			self:debug("dropout bladeEmpty")
			return true
		end;
	else
		courseplay:resetCustomTimer(self.vehicle, 'bladeEmpty');
	end
end

function LevelCompactAIDriver:updateTarget()
	return g_bunkerSiloManager:updateTarget(self:getValidFrontImplement(),self.bunkerSiloMap,self.bestTarget)
end

function LevelCompactAIDriver:isAtEnd()
	return g_bunkerSiloManager:isAtEnd(self:getValidFrontImplement(),self.bunkerSiloMap,self.bestTarget)
end

function LevelCompactAIDriver:deleteBestTarget()
	self.lastDrivenColumn = nil
	self.bestTarget = nil
end

function LevelCompactAIDriver:deleteBestTargetLeveling()
	self.lastDrivenColumn = self.bestTarget.column
	self.bestTarget = nil
end


function LevelCompactAIDriver:getIsModeFillUp()
	return not self.vehicle.cp.mode10.leveling
end

function LevelCompactAIDriver:getIsModeLeveling()
	return self.vehicle.cp.mode10.leveling and not self.vehicle.cp.mode10.drivingThroughtLoading
end

function LevelCompactAIDriver:getIsModeCompact()
	return self.vehicle.cp.mode10.leveling and self.vehicle.cp.mode10.drivingThroughtLoading
end

function LevelCompactAIDriver:onWaypointPassed(ix)
	if self.course:isWaitAt(ix) then
		self:changeLevelState(self.states.WAITING_FOR_FREE_WAY)
	end
	AIDriver.onWaypointPassed(self, ix)
end

function LevelCompactAIDriver:continue()
	self:changeLevelState(self.states.DRIVE_TO_PARKING)
end

function LevelCompactAIDriver:stopAndWait(dt)
	self:driveInDirection(dt,0,1,true,0,false)
end

function LevelCompactAIDriver:driveInDirection(dt,lx,lz,fwd,speed,allowedToDrive)
	AIVehicleUtil.driveInDirection(self.vehicle, dt, self.vehicle.cp.steeringAngle, 1, 0.5, 10, allowedToDrive, fwd, lx, lz, speed, 1)
end

function LevelCompactAIDriver:onEndCourse()
	self.ppc:initialize(1)
	self:changeLevelState(self.states.CHECK_SILO)
end

function LevelCompactAIDriver:updateLastMoveCommandTime()
	self:resetLastMoveCommandTime()
end

function LevelCompactAIDriver:changeLevelState(newState)
	self.levelState = newState
end

function LevelCompactAIDriver:getSpeed()
	local speed = 0
	if self.levelState == self.states.DRIVE_TO_PARKING then
		speed = AIDriver.getRecordedSpeed(self)
	else
		speed = self.refSpeed
	end	
	return speed
end

function LevelCompactAIDriver:debug(...)
	courseplay.debugVehicle(10, self.vehicle, ...)
end

function LevelCompactAIDriver:checkSilo()
	if self.targetSilo == nil then
		self.targetSilo = BunkerSiloManagerUtil.getTargetBunkerSilo(self.vehicle,1)
	end
	if self.targetSilo then 
		self.bunkerSiloMap = g_bunkerSiloManager:createBunkerSiloMap(self.vehicle,self.targetSilo,self:getWorkWidth())
	end
	if not self.targetSilo or not self.bunkerSiloMap then
		courseplay:setInfoText(self.vehicle, courseplay:loc('COURSEPLAY_MODE10_NOSILO'));
	else
		return true
	end
end

function LevelCompactAIDriver:lowerImplements()
	for _, implement in pairs(self.vehicle:getAttachedImplements()) do
		if implement.object.aiImplementStartLine then
			implement.object:aiImplementStartLine()
		end
	end
	self.vehicle:raiseStateChange(Vehicle.STATE_CHANGE_AI_START_LINE)
end

function LevelCompactAIDriver:raiseImplements()
	for _, implement in pairs(self.vehicle:getAttachedImplements()) do
		if implement.object.aiImplementEndLine then
			implement.object:aiImplementEndLine()
		end
	end
	self.vehicle:raiseStateChange(Vehicle.STATE_CHANGE_AI_END_LINE)
end


function LevelCompactAIDriver:moveShield(moveDir,dt,fixHeight)
	local leveler = self:getValidFrontImplement()
	local moveFinished = false
	if leveler.spec_attacherJointControl ~= nil then
		local spec = leveler.spec_attacherJointControl
		local jointDesc = spec.jointDesc
		if moveDir == "down" then
			
			--move attacherJoint down
			if spec.heightController.moveAlpha ~= jointDesc.lowerAlpha then
				spec.heightTargetAlpha = jointDesc.lowerAlpha
			else
				local newAlpha = self:getClosestAlpha(fixHeight)
				leveler:controlAttacherJoint(spec.controls[2],newAlpha)				
				moveFinished = true
			end

		elseif moveDir == "up" then
			if spec.heightController.moveAlpha ~= spec.jointDesc.upperAlpha then
				spec.heightTargetAlpha = jointDesc.upperAlpha
				if not fixHeight then
					leveler:controlAttacherJoint(spec.controls[2], spec.controls[2].moveAlpha + 0.1)
				end
			else
				moveFinished = true
			end			
		end
	end;
	return moveFinished
end

function LevelCompactAIDriver:getClosestAlpha(height)
	local closestIndex = 99
	local closestValue = 99
	for indexHeight,_ in pairs (self.alphaList) do
		--print("try "..tostring(indexHeight))
		local diff = math.abs(height-indexHeight)
		if closestValue > diff then
			--print(string.format("%s is closer- set as closest",tostring(closestValue)))
			closestIndex = indexHeight
			closestValue = diff
		end				
	end
	return self.alphaList[closestIndex]
end

function LevelCompactAIDriver:getIsAlphaListrecording()
	return self.isAlphaListrecording;
end

function LevelCompactAIDriver:resetIsAlphaListrecording()
	self.isAlphaListrecording = nil
end
function LevelCompactAIDriver:setIsAlphaListrecording()
	self.isAlphaListrecording = true
	self.alphaList ={}
end
function LevelCompactAIDriver:getDiffHeightforHeight(targetHeight)
	local blade = self:getValidFrontImplement()
	local bladeX,bladeY,bladeZ = getWorldTranslation(self:getLevelerNode(blade))
	local bladeTerrain = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, bladeX,bladeY,bladeZ);
	local _,_,offSetZ = worldToLocal(self.vehicle.rootNode,bladeX,bladeY,bladeZ)
	local _,projectedTractorY,_  = localToWorld(self.vehicle.rootNode,0,0,offSetZ)

	return targetHeight- (projectedTractorY-bladeTerrain)
end


function LevelCompactAIDriver:recordAlphaList()
	local blade = self:getValidFrontImplement()
	local spec = blade.spec_attacherJointControl
	local jointDesc = spec.jointDesc
	local bladeX,bladeY,bladeZ = getWorldTranslation(self:getLevelerNode(blade))
	local bladeTerrain = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, bladeX,bladeY,bladeZ);
	local _,_,offSetZ = worldToLocal(self.vehicle.rootNode,bladeX,bladeY,bladeZ)
	local _,projectedTractorY,_  = localToWorld(self.vehicle.rootNode,0,0,offSetZ) 
	local tractorToGround = courseplay:round(projectedTractorY-bladeTerrain,3)
	local bladeToGound = courseplay:round(bladeY-bladeTerrain,3)
	
	if spec.heightController.moveAlpha ~= jointDesc.lowerAlpha then
		spec.heightTargetAlpha = jointDesc.lowerAlpha
		blade:controlAttacherJoint(spec.controls[2], spec.controls[2].moveAlpha + 0.1)
	else
		blade:controlAttacherJoint(spec.controls[2], spec.controls[2].moveAlpha - 0.005)
		
		--record the related alphas to the alpha list
		local alphaEntry = courseplay:round(bladeToGound-tractorToGround,3)
		if self.alphaList[alphaEntry] ~= nil then
			self:debug("resetIsAlphaListrecording")
			self:resetIsAlphaListrecording()
		else
			self:debug(string.format("self.alphaList[%s] = %s",tostring(alphaEntry),tostring(spec.controls[2].moveAlpha)))
			self.alphaList[alphaEntry] = spec.controls[2].moveAlpha 
		end	
	end
end

function LevelCompactAIDriver:getLevelerNode(blade)
	for _, levelerNode in pairs (blade.spec_leveler.nodes) do
		if levelerNode.node ~= nil then
			return levelerNode.node
		end
	end
end

function LevelCompactAIDriver:printMap()
	if courseplay.debugChannels[10] and self.bunkerSiloMap then
		for _, line in pairs(self.bunkerSiloMap) do
			local printString = ""
			for _, fillUnit in pairs(line) do
				if fillUnit.fillLevel > 10000 then
					printString = printString.."[XXX]"
				elseif fillUnit.fillLevel > 1000 then
					printString = printString.."[ XX]"
				elseif fillUnit.fillLevel > 0 then
					printString = printString.."[ X ]"
				else
					printString = printString.."[   ]"
				end
			end
			self:debug(printString)
		end
	end
end

-- TODO: create a BunkerSiloMap class ...
-- Find the first row in the map where this column is not empty
function LevelCompactAIDriver:findFirstNonEmptyRow(map, column)
	for i, row in ipairs(map) do
		if row[column].fillLevel > 0 then
			return i
		end
	end
	return #map
end

function LevelCompactAIDriver:getBestTargetFillUnitLeveling(Silo, lastDrivenColumn)
	local firstLine = 1
	local targetHeight = 0.5
	local vehicle = self.vehicle
	local newApproach = lastDrivenColumn == nil 
	local newBestTarget = {}
	if self.bunkerSiloMap ~= nil then
		local newColumn = math.ceil(#self.bunkerSiloMap[1]/2)
		if newApproach then
			newBestTarget, firstLine = g_bunkerSiloManager:getBestTargetFillUnitFillUp(self.bunkerSiloMap,self.bestTarget)
			self:debug('Best leveling target at line %d, column %d, height %d, first line %d (fist approach)',
					newBestTarget.line, newBestTarget.column, targetHeight, firstLine)
			return newBestTarget, firstLine, targetHeight
		else
			newColumn = lastDrivenColumn + 1;
			if newColumn > #self.bunkerSiloMap[1] then
				newColumn = 1;
			end
			firstLine = self:findFirstNonEmptyRow(self.bunkerSiloMap, newColumn)
			newBestTarget= {
							line = firstLine;
							column = newColumn;							
							empty = false;
							}
		end
		targetHeight = self:getColumnsTargetHeight(newColumn)
	end
	self:debug('Best leveling target at line %d, column %d, height %d, first line %d',
			newBestTarget.line, newBestTarget.column, targetHeight, firstLine)
	return newBestTarget, firstLine, targetHeight
end

function LevelCompactAIDriver:getColumnsTargetHeight(newColumn)
	local totalArea = 0
	local totalFillLevel = 0
	for i=1,#self.bunkerSiloMap do
		--calculate the area without first and last line
		if i~= 1 and i~= #self.bunkerSiloMap then
			totalArea = totalArea + self.bunkerSiloMap[i][newColumn].area
		end
		totalFillLevel = totalFillLevel + self.bunkerSiloMap[i][newColumn].fillLevel
	end
	local newHeight = math.max(0.6,(totalFillLevel/1000)/totalArea)
	self:debug("getTargetHeight: totalFillLevel:%s; totalArea:%s Height%s",tostring(totalFillLevel),tostring(totalArea),tostring(newHeight))
	return newHeight
	
end

function LevelCompactAIDriver:debugRouting()
	if self:isDebugActive() then
		--BunkerSiloManagerUtil.debugRouting(vehicle,bunkerSiloMap,targetSilo,bestTarget,tempTarget)
		BunkerSiloManagerUtil.debugRouting(self.vehicle,self.bunkerSiloMap,self.targetSilo,self.bestTarget,self.tempTarget)
	end
end

function LevelCompactAIDriver:drawMap()
	if self:isDebugActive() then
		BunkerSiloManagerUtil.drawMap(self.bunkerSiloMap,self.targetSilo)
	end
end


function LevelCompactAIDriver:setLightsMask(vehicle)
	vehicle:setLightsTypesMask(courseplay.lights.HEADLIGHT_FULL)
end

function LevelCompactAIDriver:setLevelerWorkWidth()
	self.workWidth = 3
	self.leveler = AIDriverUtil.getImplementWithSpecialization(self.vehicle, Leveler)
	if not self.leveler then
		self:debug('No leveler found, using default width %.1f', self.workWidth)
		return
	end
	local spec = self.leveler.spec_leveler
	-- find the outermost leveler nodes
	local maxLeftX, minRightX = -math.huge, math.huge
	for _, levelerNode in pairs(spec.nodes) do
		local leftX, _, _ = localToLocal(levelerNode.node, self.vehicle.rootNode, -levelerNode.width, 0, levelerNode.maxDropDirOffset)
		local rightX, _, _ = localToLocal(levelerNode.node, self.vehicle.rootNode, levelerNode.width, 0, levelerNode.maxDropDirOffset)
		maxLeftX = math.max(maxLeftX, leftX)
		minRightX = math.min(minRightX, rightX)
	end
	self.workWidth = -minRightX + maxLeftX
	self:debug('Leveler width = %.1f (left %.1f, right %.1f)', self.workWidth, maxLeftX, -minRightX)
end

function LevelCompactAIDriver:getWorkWidth()
	return math.max(self.workWidth,self.vehicle.cp.workWidth)
end

function LevelCompactAIDriver:getValidFrontImplement()
	if self.frontImplement == nil then
		self.frontImplement = AIDriverUtil.getFirstAttachedImplement(self.vehicle)
	end
	return self.leveler or self.frontImplement
end

function LevelCompactAIDriver:isDebugActive()
	return courseplay.debugChannels[10]
end
