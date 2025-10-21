local LerpAngle = LerpAngle

local BUILDER, PART = pac.PartTemplate("base_movable")

PART.ClassName = "camera"
PART.Group = 'entity'
PART.Icon = 'icon16/camera.png'

PART.ImplementsDoubleClickSpecified = true

BUILDER:StartStorableVars()
	BUILDER:GetSet("EyeAnglesLerp", 1)
	BUILDER:GetSet("DrawViewModel", false)

	BUILDER:GetSet("NearZ", -1)
	BUILDER:GetSet("FarZ", -1)
	BUILDER:GetSet("FOV", -1)
	BUILDER:GetSet("RT", false)
	BUILDER:GetSet("Preview", false)
	BUILDER:GetSet("Hack", false)
BUILDER:EndStorableVars()

local ASPECT_RATIO = ScrW() / ScrH()

for i, ply in ipairs(player.GetAll()) do
	ply.pac_cameras = nil
end

pac.client_camera_parts = {}

local function CheckCamerasAgain(ply)
	local cams = ply.pac_cameras or {}
	local fpos, fang, ffov, fnearz, ffarz

	for _, part in pairs(cams) do
		if (not part.inactive or part.priority) and not part:IsHidden() then
			return true
		end
	end
end

function pac.RebuildCameras(restricted_search)
	local found_cams = false
	pac.LocalPlayer.pac_cameras = {}
	pac.client_camera_parts = {}
	local parts_to_check
	if restricted_search then parts_to_check = pac.client_camera_parts else parts_to_check = pac.GetLocalParts() end
	if table.IsEmpty(pac.client_camera_parts) then
		parts_to_check = pac.GetLocalParts()
	end
	for _,part in pairs(parts_to_check) do
		if part:IsValid() then
			part.inactive = nil
			if part.ClassName == "camera" then
				pac.nocams = false
				found_cams = true
				pac.client_camera_parts[part.UniqueID] = part
				if not part.inactive or not part:IsHidden() or part.priority then
					pac.LocalPlayer.pac_cameras[part] = part
				end
			end
			
		end
	end
	if not found_cams then
		pac.nocams = true
	end
end

function PART:CameraTakePriority(then_view)
	self:GetPlayerOwner().pac_cameras = self:GetPlayerOwner().pac_cameras or {}
	for _, part in pairs(self:GetPlayerOwner().pac_cameras) do
		if part ~= self then
			part.priority = false
			part.inactive = true
			part:RemoveSmallIcon()
		end
	end
	self.priority = true
	self.inactive = false
	timer.Simple(0.02, function()
		self.priority = true
	end)
	if then_view then
		pace.old_ViewAngles = pace.ViewAngles
		pace.old_ViewPos = pace.ViewPos

		--it should be relative if we use camera follow entity
		pace.old_ViewPos_delta = pace.ViewPos - pace.GetViewEntity():GetPos()

		timer.Simple(0.2, function() pace.CameraPartSwapView(true) end)
	end
end

function PART:OnShow()
	local owner = self:GetPlayerOwner()
	if not owner:IsValid() then return end
	self.inactive = false

	owner.pac_cameras = owner.pac_cameras or {}
	owner.pac_cameras[self] = self

	--the policy is that a shown camera takes priority over all others
	self:CameraTakePriority()
end

function PART:OnHide()
	local owner = self:GetPlayerOwner()
	if not owner:IsValid() then return end

	owner.pac_cameras = owner.pac_cameras or {}

	--this camera cedes priority to others that may be active
	for _, part in pairs(owner.pac_cameras) do
		if part ~= self and not part:IsHidden() then
			part.priority = true
		end
	end
	self.inactive = true
	self.priority = false
	owner.pac_cameras[self] = nil
	pac.TryToAwakenDormantCameras()
end

function PART:OnRemove()
	local owner = self:GetPlayerOwner()

	if LocalPlayer() == owner then
		owner.pac_cameras = owner.pac_cameras or {}
		pac.client_camera_parts[self.UniqueID] = nil
		local other_visible_cameras = 0
		--this camera cedes priority to others that may be active
		for _, part in pairs(owner.pac_cameras) do
			if part.UniqueID ~= self.UniqueID and not part:IsHidden() then
				part.priority = true
				other_visible_cameras = other_visible_cameras + 1
			end
		end
		owner.pac_cameras[self] = nil
		if not pace.hack_camera_part_donot_treat_wear_as_creating_part and not pace.is_still_loading_wearing then
			timer.Simple(0.2, function()
				pace.EnableView(true)
			end)
			timer.Simple(0.4, function()
				pace.ResetView()
				pace.CameraPartSwapView(true)
			end)
		end
		if pac.active_camera == self then pac.active_camera = nil end
		if pac.active_camera_manual == self then pac.active_camera_manual = nil end
		pac.RebuildCameras()
	end
end

local doing_calcshowhide = false

function PART:PostOnCalcShowHide(hide)
	if doing_calcshowhide then return end
	doing_calcshowhide = true
	timer.Simple(0.3, function()
		doing_calcshowhide = false
	end)
	if hide then
		if pac.active_camera_manual == self then --we're force-viewing this camera on the editor, assume we want to swap
			pace.ManuallySelectCamera(self, false)
		elseif not pac.awakening_dormant_cameras then
			pac.TryToAwakenDormantCameras(self)
		end
		self:SetSmallIcon("event")
	else
		if pac.active_camera_manual then --we're force-viewing another camera on the editor, since we're showing a new camera, assume we want to swap
			pace.ManuallySelectCamera(self, true)
		end
		self:SetSmallIcon("event")
	end
end

--these hacks are outsourced instead of being on base part
function PART:SetEventTrigger(event_part, enable)
	if enable then
		if not self.active_events[event_part] then
			self.active_events[event_part] = event_part
			self.active_events_ref_count = self.active_events_ref_count + 1
			self:CallRecursive("CalcShowHide", false)
		end

	else
		if self.active_events[event_part] then
			self.active_events[event_part] = nil
			self.active_events_ref_count = self.active_events_ref_count - 1
			self:CallRecursive("CalcShowHide", false)
		end
	end

	if pac.LocalPlayer == self:GetPlayerOwner() then
		if event_part.Event == "command" then
			pac.camera_linked_command_events[string.Split(event_part.Arguments,"@@")[1]] = true
		end

		self:PostOnCalcShowHide(enable)
	end
end

function PART:CalcShowHide(from_rendering)
	local b = self:IsHidden()

	if b ~= self.last_hidden then
		if b then
			self:OnHide(from_rendering)
		else
			self:OnShow(from_rendering)
		end
		if pac.LocalPlayer == self:GetPlayerOwner() then
			self:PostOnCalcShowHide(b)
		end
	end

	self.last_hidden = b
end

function PART:BuildFrustrum(obj, pos, ang)
	local tris = {}
	local verttip = {pos = pos, u = 0, v = 0 }
	local scale = 50
	local deg_fov = self.FOV
	if self.FOV < 0 then deg_fov = self:GetPlayerOwner():GetFOV() end

	local fov = math.rad(deg_fov)
	--local v_fov = h_fov

	local up = math.tan(0.5*fov) * scale * ang:Up()
	local right = math.tan(0.5*fov) * scale * ASPECT_RATIO * ang:Right()
	local forward = scale * ang:Forward()

	--up side
	table.insert(tris, verttip)
	table.insert(tris, {pos = pos + forward + up, u = 0, v = 0})
	table.insert(tris, {pos = pos + forward + up + right, u = 0, v = 0})

	table.insert(tris, verttip)
	table.insert(tris, {pos = pos + forward + up, u = 0, v = 0})
	table.insert(tris, {pos = pos + forward + up - right, u = 0, v = 0})

	--down side
	table.insert(tris, verttip)
	table.insert(tris, {pos = pos + forward - up, u = 0, v = 0})
	table.insert(tris, {pos = pos + forward - up + right, u = 0, v = 0})

	table.insert(tris, verttip)
	table.insert(tris, {pos = pos + forward - up, u = 0, v = 0})
	table.insert(tris, {pos = pos + forward - up - right, u = 0, v = 0})

	--left side
	table.insert(tris, verttip)
	table.insert(tris, {pos = pos + forward - right, u = 0, v = 0})
	table.insert(tris, {pos = pos + forward + up - right, u = 0, v = 0})

	table.insert(tris, verttip)
	table.insert(tris, {pos = pos + forward - right, u = 0, v = 0})
	table.insert(tris, {pos = pos + forward - up - right, u = 0, v = 0})

	--right side
	table.insert(tris, verttip)
	table.insert(tris, {pos = pos + forward + right, u = 0, v = 0})
	table.insert(tris, {pos = pos + forward + up + right, u = 0, v = 0})

	table.insert(tris, verttip)
	table.insert(tris, {pos = pos + forward + right, u = 0, v = 0})
	table.insert(tris, {pos = pos + forward - up + right, u = 0, v = 0})

	obj:BuildFromTriangles( tris )
end

function PART:OnThink()

	local owner = self:GetPlayerOwner()
	local eyeang = owner:EyeAngles()

	local pos, ang = self:GetDrawPosition(nil, true)
	ang = LerpAngle(self.EyeAnglesLerp, ang, eyeang)

	if self.RT then
		-- Start drawing onto our render target
		render.PushRenderTarget( self.render_target )
			render.Clear( 0, 0, 0, 200, true, true )
			cam.Start3D( 
				pos, ang, self.FOV, 0, 0, 512, 512
			)
				render.RenderView({
					origin = pos,
					angles = ang,
					drawviewmodel = false,
					x = 0,
					y = 0,
					w = 512,
					h = 512,
					viewid = 2,
					fov = self.FOV,
					znear = (self.NearZ == -1 and 1 or self.NearZ), zfar = (self.FarZ == -1 and 20000 or self.FarZ)
				})
			cam.End3D()
		render.PopRenderTarget()
		hook.Add( "HUDPaint", "ExampleDraw", function()
			surface.SetDrawColor( 255, 255, 255, 255 )
			surface.SetMaterial( self.render_target_mat )
			surface.DrawTexturedRect( ScrW()-512, 0, 256,256 )
		end )
	else
		hook.Remove( "HUDPaint", "ExampleDraw")
	end
	if self:GetPlayerOwner() == pac.LocalPlayer then
		if self == pace.current_part then
			if not self.selected_time then
				self.selected_time = CurTime()
				self.cam_preview_remove = CurTime() + 5
			end
			pac.AddHook("PostDrawOpaqueRenderables", "camera_preview", function()
				if not IsValid(self) then pac.RemoveHook("PostDrawOpaqueRenderables", "camera_preview") return end
				if self:IsHidden() then pac.RemoveHook("PostDrawOpaqueRenderables", "camera_preview") return end
				if not pace.IsActive() then pac.RemoveHook("PostDrawOpaqueRenderables", "camera_preview") return end
				local pos, ang = self:GetDrawPosition(nil, true)
				ang = LerpAngle(self.EyeAnglesLerp, ang, eyeang)
				render.Model({
					model = "models/editor/camera.mdl", pos = pos - 11 * ang:Forward(), angle = ang
				})
				render.SetMaterial( Material( "models/wireframe" ) )
				local obj = Mesh()
				self:BuildFrustrum(obj, pos, ang)
				
				local mat = Matrix()
				cam.PushModelMatrix( mat )
				render.CullMode(MATERIAL_CULLMODE_CW)
				obj:Draw()
				render.CullMode(MATERIAL_CULLMODE_CCW)
				obj:Draw()
				cam.PopModelMatrix()
			end)
			if not self.Preview then
				if self.cam_preview_remove < CurTime() then
					pac.RemoveHook("PostDrawOpaqueRenderables", "camera_preview")
				end
			end
		else
			self.selected_time = nil
			if not self.Preview then
				pac.RemoveHook("PostDrawOpaqueRenderables", "camera_preview")
			end
		end
	end
end
function PART:OnSelected()
	--[[if not self.selected_time then
		self.selected_time = CurTime()
		self.cam_preview_remove = CurTime() + 5
	end
	pac.AddHook("PostDrawOpaqueRenderables", "camera_preview", function()
		if not IsValid(self) then pac.RemoveHook("PostDrawOpaqueRenderables", "camera_preview") end
		local pos, ang = self:GetDrawPosition(nil, true)
		ang = LerpAngle(self.EyeAnglesLerp, ang, eyeang)
		render.Model({
			model = "models/editor/camera.mdl", pos = pos - 11 * ang:Forward(), angle = ang
		})
		render.SetMaterial( Material( "models/wireframe" ) )
		local obj = Mesh()
		self:BuildFrustrum(obj, pos, ang)
		
		local mat = Matrix()
		cam.PushModelMatrix( mat )
		render.CullMode(MATERIAL_CULLMODE_CW)
		obj:Draw()
		render.CullMode(MATERIAL_CULLMODE_CCW)
		obj:Draw()
		cam.PopModelMatrix()
	end)]]
end

function PART:GetNiceName()
	return "camera [FOV:" .. self.FOV .. "]"
end

function PART:SetFOV(val)
	self.FOV = val
	if self.last_fov ~= self.FOV then
		if IsValid(self.pace_tree_node) then
			self.pace_tree_node:SetText(self:GetNiceName())
		end
	end
	self.last_fov = self.FOV
end

function PART:Initialize()
	if pac.LocalPlayer == self:GetPlayerOwner() then
		pac.nocams = false
		pac.client_camera_parts[self.UniqueID] = self
	end
	self.render_target = GetRenderTarget( "RT_"..self.UniqueID, 512, 512 )
	local pre_existing_mat = Material("!RT_"..self.UniqueID)
	self.render_target_mat = CreateMaterial( "RT_"..self.UniqueID, "UnlitGeneric", {
		["$basetexture"] = self.render_target:GetName(),
		["$translucent"] = 1,
		["$vertexcolor"] = 1
	} )
	--print(self.render_target_mat, self.render_target_mat:GetName())
	--self.render_target_tex = self.render_target_mat:GetTexture()
end

--[[function PART:OnHide()
	--only stop the part if explicitly set to hidden.
	if not self.Hide and not self:IsHidden() then return end
end]]

function PART:CalcView(_, _, eyeang, fov, nearz, farz)
	local pos, ang = self:GetDrawPosition(nil, true)

	ang = LerpAngle(self.EyeAnglesLerp, ang, eyeang)

	if self.NearZ > 0 then
		nearz = self.NearZ
	end

	if self.FarZ > 0 then
		farz = self.FarZ
	end

	if self.FOV > 0 then
		fov = self.FOV
	end

	return pos, ang, fov, nearz, farz
end

BUILDER:Register()


local temp = {}
local remaining_camera = false
local remaining_camera_time_buffer = CurTime()


function pac.TryToAwakenDormantCameras(calling_part)
	if pace.still_loading_wearing then return end
	if pace.Editor:IsValid() then return end
	if pac.awakening_dormant_cameras then return end

	if not isbool(calling_part) then
		pac.RebuildCameras()
	end
	pac.awakening_dormant_cameras = true
	for _,part in pairs(pac.client_camera_parts) do
		if part:IsValid() then
			if part.ClassName == "camera" and part ~= calling_part then
				part:GetRootPart():CallRecursive("Think")
			end
		end
	end
	timer.Simple(1, function()
		pac.awakening_dormant_cameras = nil
	end)

	pace.EnableView(false)
end

pac.nocams = true
pac.nocam_counter = 0

function pac.HandleCameraPart(ply, pos, ang, fov, nearz, farz)
	local chosen_part
	local fpos, fang, ffov, fnearz, ffarz
	local ply = pac.LocalPlayer
	if pac.nocams then return end
	ply.pac_cameras = ply.pac_cameras or {}

	local warning_state = ply.pac_cameras == nil
	if not warning_state then warning_state = table.IsEmpty(ply.pac_cameras) end
	if ply:GetViewEntity() ~= ply then return end

	remaining_camera = false
	remaining_camera_time_buffer = remaining_camera_time_buffer or CurTime()
	pace.delaymovement = RealTime() + 1 --we need to do that so that while testing cameras, you don't fly off when walking and end up far from your character
	if warning_state then
		pac.RebuildCameras(true)
		pac.nocam_counter = pac.nocam_counter + 1
		--go back to early returns to avoid looping through localparts when no cameras are active checked 500 times
		if pac.nocam_counter > 500 then pac.nocams = true return end
	else
		if not IsValid(pac.active_camera) then pac.active_camera = nil pac.RebuildCameras(true) end
		pac.nocam_counter = 0
		local chosen_camera
		for _, part in pairs(ply.pac_cameras) do
			if part.ClassName ~= "camera" then
				ply.pac_cameras[part] = nil
			end
			if part.ClassName == "camera" and part:IsValid() then
				if not part:IsHidden() then
					remaining_camera = true
					remaining_camera_time_buffer = CurTime() + 0.1
				end

				part:CalcShowHide()
				if not part.inactive then
					--calculate values ahead of the return, used as a fallback just in case
					fpos, fang, ffov, fnearz, ffarz = part:CalcView(_,_,ply:EyeAngles())

					--wouldn't you know... but it's hacky and still jitters just a little bit
					if part.Hack then fpos = fpos + 1.3 * FrameTime() * part:GetPlayerOwner():GetVelocity() end

					temp.origin = fpos
					temp.angles = fang
					temp.fov = ffov
					temp.znear = fnearz
					temp.zfar = ffarz
					temp.drawviewer = false

					if not part:IsHidden() and not part.inactive and part.priority then
						pac.active_camera = part
						temp.drawviewer = not part.DrawViewModel
						chosen_camera = part
						break
					end
				end
			else
				ply.pac_cameras[part] = nil
			end
		end

		
		if chosen_camera then
			chosen_camera:SetSmallIcon("icon16/eye.png")
			return temp
		end
	end

	if not pac.active_camera then
		pac.RebuildCameras()
	end
	if remaining_camera or CurTime() < remaining_camera_time_buffer then
		return temp
	end

	--final fallback, just give us any valid pac camera to preserve the view! priority will be handled elsewhere
	if CheckCamerasAgain(ply) then
		return temp
	end
	--only time to return to first person is if all camera parts are hidden AFTER we pass the buffer time filter
	--until we make reversible first person a thing, letting some non-drawable parts think, this is the best solution I could come up with
end

function PART:OnDoubleClickSpecified()
	if self ~= pac.active_camera then
		self:CameraTakePriority(true)
	else
		pac.active_camera = nil
		self.priority = false
		self:RemoveSmallIcon()
		pace.CameraPartSwapView()
	end
end

function pac.HasRemainingCameraPart()
	pac.RebuildCameras()
	return table.Count(pac.LocalPlayer.pac_cameras) ~= 0
end

pac.AddHook("CalcView", "camera_part", function(ply, pos, ang, fov, nearz, farz)
	pac.HandleCameraPart(ply, pos, ang, fov, nearz, farz)
end)
