local BUILDER, PART = pac.PartTemplate("base_drawable")

PART.ClassName = "interpolated_multibone"
PART.FriendlyName = "interpolator"
PART.Group = 'advanced'
PART.Icon = 'icon16/table_multiple.png'
PART.is_model_part = false

PART.ManualDraw = true
PART.HandleModifiersManually = false

BUILDER:StartStorableVars()
	:SetPropertyGroup("test")
		:GetSet("Preview", false)
		:GetSet("UseMorphTable", false)
		:GetSet("MorphingTable", "", {editor_panel = "generic_multiline"})
		--example camera FOV morpher
		--[["TableToKeyValues"
		{
			1
			{
				FOV = 75
			}

			2
			{
				FOV = 33
			}

			3
			{
				FOV = 120
			}
		}]]
		:GetSetPart("PropertyMorphTarget")
		:GetSet("FreezeNearestLifeNodes", false, {description = "freeze refreshes for nodes if they have compatibility with nearest_life aimparts and bones"})
	:SetPropertyGroup("Interpolation")
		:GetSet("LerpValue",0)
		:GetSet("Mode", "LinearPath", {enums = {
			["Linear path"] = "LinearPath",
			["Attractor web"] = "Web",
			["Bezier"] = "Bezier",
			["Spline"] = "Spline",
			}})
		:GetSet("Power",1)
		:GetSet("SplineMix", 1)
		:GetSet("BezierIgnoreSelf", true)
		:GetSet("StartSpline", 0)
		:GetSet("EndSpline", 0)
		:GetSet("InterpolatePosition", true)
		:GetSet("InterpolateAngles", true)
	:SetPropertyGroup("Nodes")
		:GetSetPart("MultipleNodes", {editor_panel = "generic_multiline"})
		:GetSetPart("Node1", {editor_friendly = "part 1"})
		:GetSetPart("Node2", {editor_friendly = "part 2"})
		:GetSetPart("Node3", {editor_friendly = "part 3"})
		:GetSetPart("Node4", {editor_friendly = "part 4"})
		:GetSetPart("Node5", {editor_friendly = "part 5"})
		:GetSetPart("Node6", {editor_friendly = "part 6"})
		:GetSetPart("Node7", {editor_friendly = "part 7"})
		:GetSetPart("Node8", {editor_friendly = "part 8"})
		:GetSetPart("Node9", {editor_friendly = "part 9"})
		:GetSetPart("Node10", {editor_friendly = "part 10"})
		:GetSetPart("Node11", {editor_friendly = "part 11"})
		:GetSetPart("Node12", {editor_friendly = "part 12"})
		:GetSetPart("Node13", {editor_friendly = "part 13"})
		:GetSetPart("Node14", {editor_friendly = "part 14"})
		:GetSetPart("Node15", {editor_friendly = "part 15"})
		:GetSetPart("Node16", {editor_friendly = "part 16"})
		:GetSetPart("Node17", {editor_friendly = "part 17"})
		:GetSetPart("Node18", {editor_friendly = "part 18"})
		:GetSetPart("Node19", {editor_friendly = "part 19"})
		:GetSetPart("Node20", {editor_friendly = "part 20"})
:EndStorableVars()

function PART:OnRemove()
	SafeRemoveEntityDelayed(self.Owner,0.1)
end

function PART:GetNiceName()
	if self.Name ~= "" then return self.Name end

	if not self.valid_nodes then return self.FriendlyName end
	local has_valid_node = false
	for i,b in ipairs(self.valid_nodes) do
		if b then has_valid_node = true end
	end
	if not has_valid_node then return self.FriendlyName end

	local str = "Interpolator: "
	local firstnodecounted = false
	for i=1,self.max_nodes,1 do
		if IsValid(self["Node"..i]) then
			str = str .. (firstnodecounted and "; " or "") .. "[" .. i .. "]" .. (self["Node"..i].Name ~= "" and self["Node"..i].Name or  self["Node"..i].ClassName)
			firstnodecounted = true
		end
	end
	return str
end

function PART:Initialize()
	self.max_nodes = 20
	self.nodes = {}
	self.valid_nodes = {}
	
	self.nodes["Node"..0] = self
	self.valid_nodes[0] = true

	self.Owner = pac.CreateEntity("models/pac/default.mdl")
	self.Owner:SetNoDraw(true)
	self.valid_time = CurTime() + 1
	self.last_lerp = self.LerpValue
end

function PART:SetMorphingTable(str)
	self.MorphingTable = str
	self.MorphingTable_tbl = util.KeyValuesToTable(str, false, true)
	if self.MorphingTable_tbl == nil then print("error!") print(str) return end
	--PrintTable(self.MorphingTable_tbl)
	self.number_of_properties = {}
	self.morph_fallbacks = {}
	self.known_properties = {}
	local max = #self.MorphingTable_tbl
	for i,tbl in ipairs(self.MorphingTable_tbl) do
		if i > max then break end
		self.MorphingTable_tbl[i] = self.MorphingTable_tbl[i] or {}
		self.MorphingTable_tbl[i-1] = self.MorphingTable_tbl[i-1] or {}
		self.MorphingTable_tbl[i+1] = self.MorphingTable_tbl[i+1] or {}

		self.morph_fallbacks[i] = self.morph_fallbacks[i] or {}
		self.number_of_properties[i] = table.Count(self.MorphingTable_tbl[i])
		for key,value in pairs(tbl) do
			self.known_properties[key] = key
			if self.MorphingTable_tbl[i-1] and self.MorphingTable_tbl[i-1][key] then
				self.morph_fallbacks[i][key] = value
			else
				self.morph_fallbacks[i][key] = self.MorphingTable_tbl[i+1][key]
			end
		end
	end
	if self.MorphingTable_tbl then PrintTable(self.MorphingTable_tbl) end
end

function PART:OnShow()
	self.valid_time = CurTime()
end

function PART:OnHide()
	pac.RemoveHook("PostDrawOpaqueRenderables", "Multibone_draw"..self.UniqueID)

end

function PART:OnRemove()
	pac.RemoveHook("PostDrawOpaqueRenderables", "Multibone_draw"..self.UniqueID)
end
--NODES			self	1		2		3
--STAGE			0		1		2		3
--PROPORTION	0	0.5	0	0.5	0	0.5	3
function PART:OnDraw()
	self:UpdateNodes()
	if self.valid_time > CurTime() then return end

	self.pos = self.pos or self:GetWorldPosition()
	self.ang = self.ang or self:GetWorldAngles()

	if not self.Preview then pac.RemoveHook("PostDrawOpaqueRenderables", "Multibone_draw"..self.UniqueID) end

	local stage = math.max(0,math.floor(self.LerpValue))
	local proportion = math.max(0,self.LerpValue) % 1

	if self.Preview then
		pac.AddHook("PostDrawOpaqueRenderables", "Multibone_draw"..self.UniqueID, function()
			render.DrawLine(self.pos,self.pos + self.ang:Forward()*50, Color(255,0,0))
			render.DrawLine(self.pos,self.pos - self.ang:Right()*50, Color(0,255,0))
			render.DrawLine(self.pos,self.pos + self.ang:Up()*50, Color(0,0,255))
			render.DrawWireframeSphere(self.pos, 8 + 2*math.sin(5*RealTime()), 15, 15, Color(255,255,255), true)
			local origin_pos = self:GetWorldPosition():ToScreen()
			draw.DrawText("0 origin", "DermaDefaultBold", origin_pos.x, origin_pos.y)

			for i=1,self.max_nodes,1 do

				if i == 1 and self.valid_nodes[i] then
					local startpos = self:GetWorldPosition()
					local endpos = self.nodes["Node"..i]:GetWorldPosition()
					local endang = self.nodes["Node"..i]:GetWorldAngles()
					local screen_endpos = endpos:ToScreen()
					render.DrawLine(endpos,endpos + endang:Forward()*4, Color(255,0,0))
					render.DrawLine(endpos,endpos - endang:Right()*4, Color(0,255,0))
					render.DrawLine(endpos,endpos + endang:Up()*4, Color(0,0,255))
					render.DrawLine(self:GetWorldPosition(),self.nodes["Node"..i]:GetWorldPosition(), Color(255,255,255))
				elseif self.valid_nodes[i - 1] and self.valid_nodes[i] then
					local startpos = self.nodes["Node"..i-1]:GetWorldPosition()
					local endpos = self.nodes["Node"..i]:GetWorldPosition()
					local endang = self.nodes["Node"..i]:GetWorldAngles()
					local screen_endpos = endpos:ToScreen()
					render.DrawLine(endpos,endpos + endang:Forward()*4, Color(255,0,0))
					render.DrawLine(endpos,endpos - endang:Right()*4, Color(0,255,0))
					render.DrawLine(endpos,endpos + endang:Up()*4, Color(0,0,255))
					render.DrawLine(self.nodes["Node"..i-1]:GetWorldPosition(),self.nodes["Node"..i]:GetWorldPosition(), Color(255,255,255))
				end

			end
		end)
	end
	self:Interpolate(stage,proportion)
	if self.UseMorphTable and self.MorphingTable_tbl and self.LerpValue ~= self.last_lerp then self:InterpolateMorphTable(stage, proportion) end
end

function PART:UpdateNodes()
	for i=1,self.max_nodes,1 do
		self.nodes["Node"..i] = self["Node"..i]
		self.valid_nodes[i] = IsValid(self["Node"..i]) and self["Node"..i].GetWorldPosition
		if self.Translucent and self.valid_nodes[i] then self.nodes["Node"..i].force_translucent = true end
		if self.valid_nodes[i] then
			self.nodes["Node"..i].freeze_NL = self.FreezeNearestLifeNodes
		end
	end
end

function PART:SetWorldPos(x,y,z)
	self.pos.x = x
	self.pos.y = y
	self.pos.z = z
end

--adapted from proxy code
local extra_dynamic = CreateClientConVar("pac_special_property_update_dynamically", "1", true, false, "Whether proxies should refresh the properties, and some booleans may show more information.")
local function set(self, part, key, x, y, z)
	local val = part:GetProperty(key)
	local original_x
	local T = type(val)
	local vector_type = false

	if val and T then
		if T == "boolean" then
			x = x or val == true and 1 or 0
			local b = tonumber(x) > 0
			part:SetProperty(key, b)
		elseif T == "number" then
			original_x = x
			x = x or val
			part:SetProperty(key, tonumber(x) or 0)
			self.using_x = true
		else
			vector_type = true
			if self.Axis ~= "" and val[self.Axis] then
				val = val * 1
				val[self.Axis] = x or 0
				if T == "Angle" then
					self.using_x = self.Axis == "p" or self.Axis == "x" or self.Axis == "pitch"
					self.using_y = self.Axis == "y" or self.Axis == "y" or self.Axis == "yaw"
					self.using_z = self.Axis == "r" or self.Axis == "z" or self.Axis == "roll"
				elseif T == "Vector" then
					self.using_x = self.Axis == "x"
					self.using_y = self.Axis == "y"
					self.using_z = self.Axis == "z"
				end
			else
				self.using_x = x ~= nil
				self.using_y = y ~= nil
				self.using_z = z ~= nil
				if T == "Angle" then
					val = val * 1
					val.p = x or val.p
					val.y = y or val.y
					val.r = z or val.r
				elseif T == "Vector" then
					val = val * 1
					val.x = x or val.x
					val.y = y or val.y
					val.z = z or val.z
				end
			end

			part:SetProperty(self.VariableName, val)
		end
	end

	--update the property if this is the current part
	if not extra_dynamic:GetBool() then return end
	if pace:IsActive() then
		if self:GetPlayerOwner() ~= pac.LocalPlayer then return end
		if part ~= pace.current_part then return end
		local property_pnl = part["pac_property_panel_"..key]
		if IsValid(property_pnl) then
			local container = property_pnl:GetParent()
			if vector_type then
				if self.using_x then
					property_pnl.used_by_proxy = true
					container = property_pnl.left
					property_pnl.left.used_by_proxy = true
					local num = x or 0
					property_pnl.left:SetValue(math.Round(tonumber(num),4))
					container:SetTooltip("LOCKED: Used by interpolator:\n"..self:GetName())
				end
				if self.using_y then
					property_pnl.used_by_proxy = true
					container = property_pnl.middle
					property_pnl.middle.used_by_proxy = true
					local num = y or x or 0
					property_pnl.middle:SetValue(math.Round(tonumber(num),4))
					container:SetTooltip("LOCKED: Used by interpolator:\n"..self:GetName())
				end
				if self.using_z then
					property_pnl.used_by_proxy = true
					container = property_pnl.right
					property_pnl.right.used_by_proxy = true
					local num = z or x or 0
					property_pnl.right:SetValue(math.Round(tonumber(num),4))
					container:SetTooltip("LOCKED: Used by interpolator:\n"..self:GetName())
				end
			elseif T == "boolean" then
				if x ~= nil then
					property_pnl.used_by_proxy = true
					property_pnl:SetValue(tonumber(x) > 0)
					container:SetTooltip("LOCKED: Used by interpolator:\n"..self:GetName())
				end
			elseif original_x ~= nil then
				property_pnl.used_by_proxy = true
				property_pnl:SetValue(math.Round(tonumber(x) or 0,4))
				container:SetTooltip("LOCKED: Used by interpolator:\n"..self:GetName())
			end
			
			
		end
	end
end

function PART:InterpolateMorphTable(stage, proportion, part1, part2, inner)
	if self.last_lerp == self.LerpValue then return end

	local function lookback(morphtable, index, key)
		for i=index,1,-1 do
			if morphtable[i] and morphtable[i-1] then
				if morphtable[i][key] and morphtable[i-1][key] then
					return i-1
				end
			end
		end
	end
	proportion = math.pow(proportion,self.Power)
	nextstage = stage + 1
	if not self.valid_nodes[nextstage] then nextstage = 0 end
	local firstnode = part1 or self

	if stage <= 0 then
		firstnode = self
	else
		firstnode = self.nodes["Node"..stage] or self
	end
	local target = IsValid(self.PropertyMorphTarget) and self.PropertyMorphTarget or self:GetChildrenList()[1]

	local secondnode = self.nodes["Node"..nextstage]
	if firstnode == nil or firstnode == NULL or not firstnode.GetWorldPosition then firstnode = self end
	if secondnode == nil or secondnode == NULL or not secondnode.GetWorldPosition then secondnode = self end

	--[[if (self.number_of_properties[stage]) ~= (self.number_of_properties[stage-1]) then
		PrintTable(self.MorphingTable_tbl[stage-1])
		PrintTable(self.MorphingTable_tbl[stage])
		print("\n\n")
		if self.MorphingTable_tbl[stage-1] then
			for key,value in pairs(self.MorphingTable_tbl[stage-1]) do
				if self.MorphingTable_tbl[stage-1] and (not self.MorphingTable_tbl[stage]) then
					set(self, target, key, tonumber(self.MorphingTable_tbl[stage-1][key]) or self.morph_fallbacks[stage][key] or 0, y, z)
				elseif (not self.MorphingTable_tbl[stage-1]) and self.MorphingTable_tbl[stage] then
					set(self, target, key, tonumber(self.MorphingTable_tbl[stage][key]) or self.morph_fallbacks[stage+1][key] or 0, y, z)
				end
				
			end
		end
	end]]

	--[[if (self.MorphingTable_tbl[stage] and self.MorphingTable_tbl[nextstage]) then
		for key,value in pairs(self.MorphingTable_tbl[nextstage]) do
			local previous_value = tonumber(self.MorphingTable_tbl[stage][key]) or 0
			local lerp = Lerp(proportion, previous_value, tonumber(value) or 0)
			set(self, target, key, lerp, y, z)
		end
	elseif (stage%1 == 0) then
		for key,value in pairs(self.MorphingTable_tbl[stage]) do
			local value = tonumber(self.MorphingTable_tbl[stage][key]) or 0
			set(self, target, key, value, y, z)
		end
	end]]

	--for each key
	for _,key in pairs(self.known_properties) do
		local first_index = lookback(self.MorphingTable_tbl, stage + 1, key) or stage --try to find an existing previous data checkpoint
		local second_index = first_index + 1
		if first_index == nil then
			if (proportion%1 == 0) then
				--print("whole. branch of nil")
				local value = tonumber(self.MorphingTable_tbl[second_index][key]) or 0
				set(self, target, key, value, y, z)
			end
			continue
		else
			if (proportion%1 == 0) then
				--print("whole. branch" .. first_index, "should be ", self.MorphingTable_tbl[stage][key])
				local value = tonumber(self.MorphingTable_tbl[stage][key]) or 0
				set(self, target, key, value, y, z)
			elseif first_index == stage then
				--print("frac. branch" .. first_index, "should be ", self.MorphingTable_tbl[first_index][key])
				if self.MorphingTable_tbl[first_index] and self.MorphingTable_tbl[second_index] then
					local previous_value = tonumber(self.MorphingTable_tbl[first_index][key]) or 0
					local next_value = tonumber(self.MorphingTable_tbl[second_index][key]) or 0
					local lerp = Lerp(proportion, previous_value, next_value)
					set(self, target, key, lerp, y, z)
				end
			end
		end

		
	end
	self.last_lerp = self.LerpValue
end


local function gather_points(self, start_i, end_i)
	local tbl = {}
	for i=start_i, end_i, 1 do
		if self.valid_nodes[i] then
			table.insert(tbl, self.nodes["Node"..i]:GetWorldPosition())
		else
			return tbl
		end
	end
	return tbl
end
function PART:Interpolate(stage, proportion)
	local bez_pos = self.pos
	local lin_pos = self.pos

	local spline = false
	local linear = true

	if self.Mode == "Bezier" then
		spline = true
		local final_proportion = self.BezierIgnoreSelf and self.LerpValue/4 or self.LerpValue/4 - 0.25
		local pos0, pos1, pos2, pos3
		if self.valid_nodes[self.StartSpline + 0] then
			pos0 = self.nodes["Node"..self.StartSpline + 0]
		else
			pos0 = self.nodes["Node"..0]
		end
		if self.valid_nodes[self.StartSpline + 1] then
			pos1 = self.nodes["Node"..self.StartSpline + 1]
		else
			pos1 = self.nodes["Node"..self.StartSpline + 0]
		end
		if self.valid_nodes[self.StartSpline + 2] then
			pos2 = self.nodes["Node"..self.StartSpline + 2]
		else
			pos2 = self.nodes["Node"..self.StartSpline + 1]
		end
		if self.valid_nodes[self.StartSpline + 3] then
			pos3 = self.nodes["Node"..self.StartSpline + 3]
		else
			pos3 = self.nodes["Node"..self.StartSpline + 2]
		end
		
		bez_pos = math.CubicBezier(final_proportion, pos0:GetWorldPosition(), pos1:GetWorldPosition(), pos2:GetWorldPosition(), pos3:GetWorldPosition())
	elseif self.Mode == "Spline" then
		spline = true
		local points = gather_points(self, self.StartSpline, self.EndSpline)
		bez_pos = math.BSplinePoint(
			self.BezierIgnoreSelf and self.LerpValue or self.LerpValue + 1,
			points, self.EndSpline
		)
	end
	
	local firstnode
	if stage <= 0 then
		firstnode = self
	else
		firstnode = self.nodes["Node"..stage] or self
	end


	local secondnode = self.nodes["Node"..stage+1]
	if firstnode == nil or firstnode == NULL or not firstnode.GetWorldPosition then firstnode = self end
	if secondnode == nil or secondnode == NULL or not secondnode.GetWorldPosition then secondnode = self end

	proportion = math.pow(proportion,self.Power)
	if secondnode ~= nil and secondnode ~= NULL then
		if self.InterpolatePosition then
			lin_pos = LerpVector(proportion,firstnode:GetWorldPosition(), secondnode:GetWorldPosition())
		else lin_pos = self:GetWorldPosition() end
		if self.InterpolateAngles then
			self.ang = LerpAngle(proportion, firstnode:GetWorldAngles(), secondnode:GetWorldAngles())
		else self.ang = self:GetWorldAngles() end
	end

	if self.SplineMix == 0 then spline = false end
	if self.SplineMix == 1 then
		if self.Mode ~= "LinearPath" then
			linear = false
		end
	end
	if self.Mode == "LinearPath" then linear = true spline = false end
	if spline and linear then
		self.pos = LerpVector(self.SplineMix, lin_pos, bez_pos or lin_pos)
	elseif spline then
		self.pos = bez_pos
	elseif linear then
		self.pos = lin_pos
	end
	if self.pos and self.ang then
		self.Owner:SetPos(self.pos)
		self.Owner:SetAngles(self.ang)
	end

end

function GetClosestAngleMidpoint(a1, a2, proportion)
	--print(a1)
	--print(a2)
	local axes = {"p","y","r"}
	local ang_delta_candidate1
	local ang_delta_candidate2
	local ang_delta_candidate3
	local ang_delta_final
	local final_ang = Angle()
	for _,ax in pairs(axes) do
		ang_delta_candidate1 = a2[ax] - a1[ax]
		ang_delta_candidate2 = (a2[ax] + 360) - a1[ax]
		ang_delta_candidate3 = (a2[ax] - 360) - a1[ax]
		ang_delta_final = 180
		if math.abs(ang_delta_candidate1) < math.abs(ang_delta_final) then
			ang_delta_final = ang_delta_candidate1
		end
		if math.abs(ang_delta_candidate2) < math.abs(ang_delta_final) then
			ang_delta_final = ang_delta_candidate2
		end
		if math.abs(ang_delta_candidate3) < math.abs(ang_delta_final) then
			ang_delta_final = ang_delta_candidate3
		end
		--print("at "..ax.." 1:"..ang_delta_candidate1.." 2:"..ang_delta_candidate2.." 3:"..ang_delta_candidate3.." pick "..ang_delta_final)
		final_ang[ax] = a1[ax] + proportion * ang_delta_final
	end

	return final_ang
end

function PART:GoTo(part)
	self.pos = part:GetWorldPosition() or self:GetWorldPosition()
	self.ang = part:GetWorldAngles() or self:GetWorldAngles()
end

--we need to know the stage and proportion (progress)
--e.g. lerp 0.5 is stage 0, proportion 0.5 because it's 50% toward Node 1
--e.g. lerp 2.2 is stage 2, proportion 0.2 because it's 20% toward Node 3
function PART:GetInterpolationParameters()
	stage = math.max(0,math.floor(self.LerpValue))
	proportion = math.max(0,self.LerpValue) % 1
	--print("Calculated the stage. We are at stage " .. stage .. " between nodes " .. stage .. " and " .. (stage + 1))
	--print("proportion is " .. proportion)
	return stage, proportion
end

function PART:GetNodeAngle(nodenumber)
	--print("node" .. nodenumber .. " angle " .. self.__['Node'..nodenumber].Angles)
	--print("node" .. nodenumber .. " world angle " .. self.__['Node'..nodenumber]:GetWorldAngles())

	--return self.Node1:GetWorldAngles()
end

function PART:GetNodePosition(nodenumber)
	--print("node" .. nodenumber .. " position " .. self.__['Node'..nodenumber].Position)
	--print("node" .. nodenumber .. " world position " .. self.__['Node'..nodenumber]:GetWorldPosition())
	--return self.Node1:GetWorldPosition()
end

function PART:InterpolateFromLerp(lerp)
end

function PART:InterpolateFromNodes(firstnode, secondnode, proportion)
	--position_interpolated = InterpolateFromStage("position", stage, self.Lerp)
end

function PART:InterpolateFromStage(stage, proportion)
	self:InterpolateFromNodes(stage, stage + 1)
end

function PART:InterpolateAngle()

end


function PART:SetInterpolatePosition(b)
	--print(type(b).." "..b)
	self.InterpolatePosition = b
end

function PART:SetInterpolateAngles(b)
	--print(type(b).." "..b)
	self.InterpolateAngles = b
end




BUILDER:Register()
