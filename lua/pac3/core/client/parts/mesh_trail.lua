local Lerp = Lerp
local tonumber = tonumber
local table_insert = table.insert
local table_remove = table.remove
local math_ceil = math.ceil
local math_abs = math.abs
local math_min = math.min
local render_StartBeam = render.StartBeam
local render_CullMode = render.CullMode
local cam_IgnoreZ = cam.IgnoreZ
local render_EndBeam = render.EndBeam
local render_AddBeam = render.AddBeam
local render_SetMaterial = render.SetMaterial
local Vector = Vector
local RealTime = RealTime
local render_SuppressEngineLighting = render.SuppressEngineLighting

local BUILDER, PART = pac.PartTemplate("base_drawable")

PART.FriendlyName = "mesh trail"
PART.ClassName = "mesh_trail"
PART.Icon = "icon16/chart_curve.png"
PART.Group = "effects"
PART.ProperColorRange = true

BUILDER:StartStorableVars()
	:SetPropertyGroup("Shape")
		:GetSet("Shape", "Rod", {enums = {
			["Rod"] = "Rod",
			["Hoop (16-side)"] = "Hoop",
			["Square Hoop"] = "SquareHoop"
		}})
		:GetSet("StartSize", 50)
		:GetSet("EndSize", 0) --not properly implemented
		:GetSet("FadePower", 1)
		:GetSet("EndPositionSide", 1, {editor_clamp = {-1,1}})

		:GetSet("ResetOnHide", true)
		:GetSet("Stop", true)
		:GetSet("Preview", false)

	:SetPropertyGroup("trail divisions")
		:GetSet("OverallLength", 1)
		:GetSet("LifetimeBasis", "Time", {enums = {
			["Time (s)"] = "Time",
			["Distance (HU)"] = "Distance",
			["Segments (unit)"] = "Segment",
		}})
		:GetSet("EmitFrequency", 120)

	:SetPropertyGroup("Mesh and UV")
		:GetSet("BaseUOffset", 0)
		:GetSet("TipUOffset", 0)
		:GetSet("BaseVOffset", 0)
		:GetSet("TipVOffset", 0)
		:GetSet("TextureStretch", 1)
		--[[:GetSet("TextureStretchBasis", "Time", {enums = {
			["Time (s)"] = "Time",
			["Distance (HU)"] = "Distance",
			["Segments (unit)"] = "Segment",
		}})]]
		--:GetSet("RebuildFrequency", 120) unused
		:GetSetPart("FollowPart")

	:SetPropertyGroup("appearance")
		--[[:GetSet("StartColor", Vector(1, 1, 1), {editor_panel = "color2"})
		:GetSet("EndColor", Vector(1, 1, 1), {editor_panel = "color2"})
		:GetSet("StartAlpha", 1)
		:GetSet("EndAlpha", 0)]] -- unused, not sure if they're possible
		:GetSet("NoLighting", false)
		:GetSet("IgnoreZ", false)
		:GetSet("Material", "trails/laser", {editor_panel = "material"})
		:GetSet("Unlit", true, {description = "make material unlit"})
		:GetSet("Translucent", true)
		:GetSet("Invert", false)
		:GetSet("DoubleFace", true)
	--:GetSet("CenterAttraction", 0)
	--:GetSet("Gravity", Vector(0,0,0))

:EndStorableVars()

PART.LastAdd = 0

function PART:MakeMaterialUnlit()
	if not self.Materialm then return end

	local shader = self.Materialm:GetShader()
	if shader == "VertexLitGeneric" or shader == "Cable" or shader == "LightmappedGeneric" then
		self.Materialm = pac.MakeMaterialUnlitGeneric(self.Materialm, self.Id)
	end
end

function PART:SetMaterial(var)
	self.Material = var or ""

	if not pac.Handleurltex(self, var, function(mat)
		self.Materialm = mat
		self:MakeMaterialUnlit()
	end) then
		if isstring(var) then
			self.Materialm = pac.Material(var, self)
			self:CallRecursive("OnMaterialChanged")
		elseif type(var) == "IMaterial" then
			self.Materialm = var
			self:CallRecursive("OnMaterialChanged")
		end
		if self.Unlit then self:MakeMaterialUnlit() end
	end
end

function PART:SetUnlit(b)
	self.Unlit = b
	self:SetMaterial(self.Material)
end

--[[design:
	not yet implemented: the part should have different lineages i.e. separate meshes i.e. trail segments
	self.meshes = {
		a trail lineage is a set of linked shape segments
		{
			a shape segment is a set of lines. rod has 1, squarehoop has 4, etc.
			{
				if rod:
				[1] = {
					part info: basepos = pos, length = startsize, etc.
					vert1 = pos
					vert2 = pos + forward
				}
			}
		}
	}


	we will keep a table of index ranges because the trail can be interrupted, building meshes will be done one at a time using these min max


	self.current_segment
	to build up the mesh, we need to know which shape segment was last created and connect each new vertex in a cross to the old ones
]]

function PART:SetEmitFrequency(var)
	self.EmitFrequency = var
	if self.EmitFrequency ~= 0 then
		self.next_add = RealTime() + (1 / self.EmitFrequency)
	else
		self.next_add = RealTime()
	end
end

function PART:StartMesh()
	local newmesh = {}
	table.insert(self.meshes, newmesh)
	self.segment_index_ranges[newmesh] = {}
	self.v_coord = 0
	return newmesh
end

function PART:ClearMeshes()
	if self.meshes == nil then return end
	for i,mesh in ipairs(self.meshes) do
		if mesh then
			if IsValid(mesh) then
				mesh:Destroy()
			end
		end
		table.remove(self.meshes, i)
	end
	self.meshes = {}
	self.segments = {}
	self.current_segment = nil
	self.emitting_end_segment_index = 1
	self.trailing_end_segment_index = 1
end

--ok maybe keep track of index but just don't remove the stuff from table? or constantly lower indices?
function PART:CleanUpSegments(thorough)
	local start_index = 0
	local end_index = 0
	if thorough then
		start_index = self.emitting_end_segment_index
		end_index = self.trailing_end_segment_index
	end
	rtime = RealTime()

	local for_breaker_count = 50
	for segment_index = end_index, start_index, 1 do
		local segment = self.segments[segment_index] if not segment then continue end
		if segment.time + self.OverallLength < rtime then
			table.remove(self.segments, segment_index)
			self.trailing_end_segment_index = segment_index + 1
		else
			for_breaker_count = for_breaker_count - 1
			if for_breaker_count == 0 then break end
		end
	end
end


function PART:AppendSegment(pos, ang)
	if self.killed then return end
	local base = {pos = pos, u = 0 + self.BaseUOffset, v = self.v_coord + self.BaseVOffset}
	local tippos = pos + ang:Forward() * self.StartSize
	local tip = {pos = tippos, u = 1 + self.TipUOffset, v = self.v_coord + self.TipVOffset}
	local previous_segment = self.current_segment or {}
	previous_segment.basepos = previous_segment.basepos or pos
	local dist_from_previous = previous_segment.basepos:Distance(pos)

	local new_shape_segment = {
		time = RealTime(),
		index = self.emitting_end_segment_index,
		basepos = pos,
		tippos = tippos,
		baseang = ang,
		length = self.StartSize,
		endsize = self.EndSize,
		target_frac = 0.5 + 0.5*self.EndPositionSide,
		target_frac_pos = LerpVector(0.5 + 0.5*self.EndPositionSide, pos, tippos),
		previous_segment = previous_segment,
		dist_from_previous = dist_from_previous,
		reference_v1 = base,
		reference_v2 = tip
	}
	self.segments[self.emitting_end_segment_index] = new_shape_segment
	self.emitting_end_segment_index = self.emitting_end_segment_index + 1
	self.current_segment = new_shape_segment
	self.v_coord = RealTime() * self.TextureStretch
end

function PART:ConnectSegments(meshverts, segment1, segment2)
	if not segment2 or not segment1 then return end
	if self.Shape == "Rod" then
		local fade_frac = math.pow(math.Clamp((RealTime() - segment1.time) / self.OverallLength,0,1),self.FadePower)
		--compute the fading positions
		segment1.new_v1 = {
			pos = LerpVector(fade_frac, segment1.basepos, segment1.target_frac_pos) + self.pos_offset,
			u = segment1.reference_v1.u, v = segment1.reference_v1.v
		}
		segment1.new_v2 = {
			pos = LerpVector(fade_frac, segment1.tippos, segment1.target_frac_pos) + self.pos_offset,
			u = segment1.reference_v2.u, v = segment1.reference_v2.v
		}
		--CW
		table.insert(meshverts,segment1.new_v1)
		table.insert(meshverts,segment2.new_v2 or segment2.reference_v2)
		table.insert(meshverts,segment1.new_v2)
		table.insert(meshverts,segment1.new_v1)
		table.insert(meshverts,segment2.new_v1 or segment2.reference_v1)
		table.insert(meshverts,segment2.new_v2 or segment2.reference_v2)
	end
end

function PART:BuildMesh(mesh, start_segment_index, end_segment_index)

	local base_delta = self:GetWorldMatrixWithoutOffsets()
	local base_delta_pos = base_delta:GetTranslation()

	--how the fuck do I do follow part
	--the basepos needs to be expressed in terms of the locality from the get go?
	if self.FollowPart then
		if self.FollowPart.GetDrawPosition then
			local m = self.FollowPart:GetWorldMatrixWithoutOffsets()
			local pos2,ang2 = m:GetTranslation(), m:GetAngles()
			self.followpos = pos2 - self.pos
			self.followang = ang2 - self.ang
		else
			self.followpos = Vector(0,0,0) self.followang = Angle(0,0,0)
		end
	else
		self.followpos = Vector(0,0,0) self.followang = Angle(0,0,0)
	end
	self.pos_offset = self.followpos

	local meshverts = {}
	for segment_index=start_segment_index, end_segment_index, -1 do
		self:ConnectSegments(meshverts, self.segments[segment_index], self.segments[segment_index + 1])
	end
	mesh:BuildFromTriangles(meshverts)
end

function PART:OnShow()
	self.killed = false
	pac.RemoveHook("PostDrawOpaqueRenderables", "meshtrail_leftover_" .. self.UniqueID)
	self:AppendSegment(self:GetDrawPosition())
end

function PART:OnRemove()
	self:ClearMeshes()
	pac.RemoveHook("PostDrawOpaqueRenderables", "meshtrail_leftover_" .. self.UniqueID)
end

function PART:OnHide()
	if self.ResetOnHide then
		self:ClearMeshes()
	else
		self.killed = true
		self.killtime = RealTime() + self.OverallLength
		pac.AddHook("PostDrawOpaqueRenderables", "meshtrail_leftover_" .. self.UniqueID, function()
			if RealTime() > self.killtime then
				self:ClearMeshes()
				pac.RemoveHook("PostDrawOpaqueRenderables", "meshtrail_leftover_" .. self.UniqueID)
			end
			self:OnDraw()
		end)
	end
end

function PART:OnThink()
	if self.Stop then self:CleanUpSegments(true) return end
	if self.gonna_cleanup then
		if self.gonna_cleanup < RealTime() then
			self:CleanUpSegments(true)
			self.gonna_cleanup = false
		end
	else
		self.gonna_cleanup = RealTime() + 0.5
	end
	
end

function PART:OnDraw()
	local pos, ang = self:GetDrawPosition()
	self.pos = pos
	self.ang = ang

	if self.Preview then
		render.DrawLine(pos, pos + ang:Forward() * self.StartSize, Color(255,255,255), false)
	end
	if RealTime() > self.next_add then
		self:AppendSegment(pos, ang)
		if self.EmitFrequency ~= 0 then
			self.next_add = RealTime() + (1 / self.EmitFrequency)
		else
			self.next_add = RealTime()
		end
	end

	local drawmesh = Mesh()
	if self.Material == "" then self:SetError("invalid material") return end
	self:BuildMesh(drawmesh, self.emitting_end_segment_index, self.trailing_end_segment_index)
	render.SetMaterial(self.Materialm)
	if self.NoLighting then render_SuppressEngineLighting(true) end
	
	if self.DoubleFace then
		render_CullMode(MATERIAL_CULLMODE_CW)
		self.meshes[1] = drawmesh
		for i,mesh in ipairs(self.meshes) do
			mesh:Draw()
		end
	end
	
	if self.Invert then
		if self.DoubleFace then
			render_CullMode(MATERIAL_CULLMODE_CW)
		else
			render_CullMode(MATERIAL_CULLMODE_CCW)
		end
	else
		render_CullMode(MATERIAL_CULLMODE_CCW)
	end
	self.meshes[1] = drawmesh
	for i,mesh in ipairs(self.meshes) do
		mesh:Draw()
	end
	render_SuppressEngineLighting(false)
end

function PART:Initialize()
	self:ClearMeshes()
	self:SetMaterial(self.Material)
	self.pos_offset = Vector(0,0,0)
	self.ang_offset = Angle(0,0,0)
	self.meshes = {} --real IMeshes
	self.current_mesh = nil
	self.segment_index_ranges = {}
	self.segments = {} --pac-compliant segment information, before vertices are built
	self.next_add = 0
	self.current_segment = nil
	self.emitting_end_segment_index = 1
	self.trailing_end_segment_index = 1
	self.v_coord = 0
end

BUILDER:Register()