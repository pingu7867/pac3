pace.mctrl = {}
local mctrl = pace.mctrl
mctrl.grab_dist = 15
mctrl.angle_pos = 0.5
local cvar_pos_grid = CreateClientConVar("pac_grid_pos_size", "4")
local cvar_ang_grid = CreateClientConVar("pac_grid_ang_size", "45")
local smaller_when_closer = CreateClientConVar("pac_gizmo_smaller_when_closer", "1", true, false)
local rotation_style = CreateClientConVar("pac_gizmo_angle_style", "1", true, false)
local rotation_style_dots = CreateClientConVar("pac_gizmo_angle_style_dots", "1", true, false)

--[[
Give this function the coordinates of a pixel on your screen, and it will return a unit vector pointing
in the direction that the camera would project that pixel in.

Useful for converting mouse positions to aim vectors for traces.

iScreenX is the x position of your cursor on the screen, in pixels.
iScreenY is the y position of your cursor on the screen, in pixels.
iScreenW is the width of the screen, in pixels.
iScreenH is the height of the screen, in pixels.
angCamRot is the angle your camera is at
fFoV is the Field of View (FOV) of your camera in ___radians___
	Note: This must be nonzero or you will get a divide by zero error.
 ]]
local function LPCameraScreenToVector(iScreenX, iScreenY, iScreenW, iScreenH, angCamRot, fFoV)
    --This code works by basically treating the camera like a frustrum of a pyramid.
    --We slice this frustrum at a distance "d" from the camera, where the slice will be a rectangle whose width equals the "4:3" width corresponding to the given screen height.
    local d = 4 * iScreenH / (6 * math.tan(0.5 * fFoV))
    --Forward, right, and up vectors (need these to convert from local to world coordinates
    local vForward = angCamRot:Forward()
    local vRight = angCamRot:Right()
    local vUp = angCamRot:Up()
    --Then convert vec to proper world coordinates and return it

    return (d * vForward + (iScreenX - 0.5 * iScreenW) * vRight + (0.5 * iScreenH - iScreenY) * vUp):GetNormalized()
end

--[[
Give this function a vector, pointing from the camera to a position in the world,
and it will return the coordinates of a pixel on your screen - this is where the world position would be projected onto your screen.

Useful for finding where things in the world are on your screen (if they are at all).

vDir is a direction vector pointing from the camera to a position in the world
iScreenW is the width of the screen, in pixels.
iScreenH is the height of the screen, in pixels.
angCamRot is the angle your camera is at
fFoV is the Field of View (FOV) of your camera in ___radians___
	Note: This must be nonzero or you will get a divide by zero error.

Returns x, y, iVisibility.
	x and y are screen coordinates.
	iVisibility will be:
		1 if the point is visible
		0 if the point is in front of the camera, but is not visible
		-1 if the point is behind the camera
]]
local function VectorToLPCameraScreen(vDir, iScreenW, iScreenH, angCamRot, fFoV)
    --Same as we did above, we found distance the camera to a rectangular slice of the camera's frustrum, whose width equals the "4:3" width corresponding to the given screen height.
    local d = 4 * iScreenH / (6 * math.tan(0.5 * fFoV))
    local fdp = angCamRot:Forward():Dot(vDir)
    --fdp must be nonzero ( in other words, vDir must not be perpendicular to angCamRot:Forward() )
    --or we will get a divide by zero error when calculating vProj below.
    if fdp == 0 then return 0, 0, -1 end
    --Using linear projection, project this vector onto the plane of the slice
    local vProj = (d / fdp) * vDir
    --Dotting the projected vector onto the right and up vectors gives us screen positions relative to the center of the screen.
    --We add half-widths / half-heights to these coordinates to give us screen positions relative to the upper-left corner of the screen.
    --We have to subtract from the "up" instead of adding, since screen coordinates decrease as they go upwards.
    local x = 0.5 * iScreenW + angCamRot:Right():Dot(vProj)
    local y = 0.5 * iScreenH - angCamRot:Up():Dot(vProj)
    --Lastly we have to ensure these screen positions are actually on the screen.
    local iVisibility

    --Simple check to see if the object is in front of the camera
    if fdp < 0 then
        iVisibility = -1
    elseif x < 0 or x > iScreenW or y < 0 or y > iScreenH then
        --We've already determined the object is in front of us, but it may be lurking just outside our field of vision.
        iVisibility = 0
    else
        iVisibility = 1
    end

    return x, y, iVisibility
end

local function LocalToWorldAngle(lang, wang)
    local lm = Matrix()
    lm:SetAngles(lang)
    local wm = Matrix()
    wm:SetAngles(wang)

    return (wm * lm):GetAngles()
end

local function WorldToLocalAngle(lang, wang)
    local lm = Matrix()
    lm:SetAngles(lang)
    local wm = Matrix()
    wm:SetAngles(wang)

    return (wm:GetInverse() * lm):GetAngles()
end

local function cursor_pos()
    local x, y = input.GetCursorPos()

    if mctrl.grab and mctrl.grab.mouse_offset then
        x = x + mctrl.grab.mouse_offset.x
        y = y + mctrl.grab.mouse_offset.y
    end

    return x, y
end

-- pace
do
    mctrl.target = NULL

    function mctrl.SetTarget(part)
        part = part or NULL

        if not part:IsValid() then
            mctrl.target = NULL

            return
        end

        if not part.GetDrawPosition then
            mctrl.target = NULL
        else
            mctrl.target = part
        end
    end

    function mctrl.GetTarget()
        return mctrl.target:IsValid() and not mctrl.target:IsHidden() and mctrl.target or NULL
    end

    function mctrl.GetAxes(ang)
        return ang:Forward(), ang:Right() * -1, ang:Up()
    end

    function mctrl.GetWorldPosition()
        local part = mctrl.GetTarget()
        if not part:IsValid() then return end
        local m = part:GetWorldMatrixWithoutOffsets()

        return m:GetTranslation(), m:GetAngles()
    end

    function mctrl.GetWorldMatrix()
        local part = mctrl.GetTarget()
        if not part:IsValid() then return end

        return part:GetWorldMatrixWithoutOffsets()
    end

    function mctrl.WorldToLocalPosition(pos, ang)
        local part = mctrl.GetTarget()
        if not part:IsValid() then return end
        local wpos, wang = part:GetBonePosition()
        if wpos and wang then return WorldToLocal(pos, ang, wpos, wang) end
    end

    function mctrl.GetCameraFOV()
        if pace.editing_viewmodel or pace.editing_hands then return pac.LocalPlayer:GetActiveWeapon().ViewModelFOV or 55 end

        return pace.GetViewFOV()
    end

    function mctrl.VecToScreen(vec)
        local x, y, vis = VectorToLPCameraScreen((vec - EyePos()):GetNormalized(), ScrW(), ScrH(), EyeAngles(), math.rad(mctrl.GetCameraFOV()))

        return {
            x = x - 1,
            y = y - 1,
            visible = vis == 1
        }
    end

    function mctrl.ScreenToVec(x, y)
        local vec = LPCameraScreenToVector(x, y, ScrW(), ScrH(), EyeAngles(), math.rad(mctrl.GetCameraFOV()))

        return vec
    end

    function mctrl.GetGizmoSize()
        local part = pace.current_part
        if pace.editing_viewmodel or pace.editing_hands then return 5 end

        if part.ClassName == "clip" or part.ClassName == "clip2" then
            part = part.Parent
        end

        if part.ClassName == "camera" then return 30 end
        if part.ClassName == "group" then return 45 end
        if not part:IsValid() or not part.GetWorldPosition then return 3 end
        local dist = (part:GetWorldMatrixWithoutOffsets():GetTranslation():Distance(pace.GetViewPos()) / 50)

		
		
        if dist > 1 then
            dist = 1 / dist
		elseif dist < 0.5 and smaller_when_closer:GetBool() then
			return 37*math.pow(dist, 1.5)
		end
        return 5 * math.rad(pace.GetViewFOV()) / dist
    end

    --@@note mctrl config menu
    function mctrl.OpenConfigMenu()
		--timer.Simple(0, function()
			local menu = DermaMenu()
			menu:SetPos(input.GetCursorPos())
			menu:AddOption("mouse controls config"):SetImage("icon16/star.png")
			menu:AddCVar("Shrink gizmo when up close", "pac_gizmo_smaller_when_closer", "1", "0")
			--[[local styles_submenu, pnlsubmenu = menu:AddSubMenu("styles") pnlsubmenu:SetImage("icon16/star.png")
				styles_submenu:AddOption("Classic", function() end):SetImage("icon16/award_star_gold_1.png")
				styles_submenu:AddOption("CapsAdmin experimental", function() end):SetImage("icon16/award_star_gold_2.png")
				styles_submenu:AddOption("Cedric experimental", function() end):SetImage("icon16/award_star_gold_3.png")]]
			menu:AddOption("Array stuff", pace.OpenArrayingMenu):SetImage("icon16/shape_group.png")
			local astyles_submenu, pnlsubmenu = menu:AddSubMenu("gizmo angle circle style : axes") pnlsubmenu:SetImage("icon16/star.png")
				astyles_submenu:AddOption("None", function() rotation_style:SetInt(0) end):SetImage("icon16/collision_off.png")
				astyles_submenu:AddOption("One circle", function() rotation_style:SetInt(1) end):SetImage("icon16/award_star_gold_1.png")
				astyles_submenu:AddOption("Full axes, full color", function() rotation_style:SetInt(2) end):SetImage("icon16/award_star_gold_2.png")
				astyles_submenu:AddOption("Full axes, grayed inactive axes", function() rotation_style:SetInt(3) end):SetImage("icon16/award_star_gold_3.png")
			local astyles2_submenu, pnlsubmenu = menu:AddSubMenu("gizmo angle circle style : dotted lines") pnlsubmenu:SetImage("icon16/star.png")
				astyles2_submenu:AddOption("Full", function() rotation_style_dots:SetInt(0) end):SetImage("icon16/award_star_gold_1.png")
				astyles2_submenu:AddOption("Dashed", function() rotation_style_dots:SetInt(1) end):SetImage("icon16/award_star_gold_2.png")
				astyles2_submenu:AddOption("Dotted (points)", function() rotation_style_dots:SetInt(2) end):SetImage("icon16/award_star_gold_3.png")
				astyles2_submenu:AddOption("Dotted (circles)", function() rotation_style_dots:SetInt(3) end):SetImage("icon16/award_star_silver_1.png")
		--end)
    end

end

function mctrl.LinePlaneIntersection(pos, normal, x, y)
    local n = normal
    local lp = pace.GetViewPos() - pos
    local ln = mctrl.ScreenToVec(x, y)

    return lp + ln * (-lp:Dot(n) / ln:Dot(n))
end

local function dot2D(x1, y1, x2, y2)
    return x1 * x2 + y1 * y2
end

function mctrl.PointToAxis(pos, axis)
    local x, y = cursor_pos()
    local origin = mctrl.VecToScreen(pos)
    local point = mctrl.VecToScreen(pos + axis * 10)
    local a = math.atan2(point.y - origin.y, point.x - origin.x)
    local d = dot2D(math.cos(a), math.sin(a), point.x - x, point.y - y)

    return point.x + math.cos(a) * -d, point.y + math.sin(a) * -d
end

function mctrl.CalculateMovement()
    local part = mctrl.GetTarget()
    if not part:IsValid() then return end
    local axis = mctrl.grab.axis
    local offset = mctrl.GetGizmoSize()
    local m = mctrl.grab.matrix --part:GetWorldMatrixWithoutOffsets()
    local pos = m:GetTranslation()
    local forward, right, up = m:GetForward(), -m:GetRight(), m:GetUp()
    local world_dir

    if axis == "x" then
        local localpos = mctrl.LinePlaneIntersection(pos, right, mctrl.PointToAxis(pos, forward))
        world_dir = (localpos:Dot(forward) - offset) * forward
    elseif axis == "y" then
        local localpos = mctrl.LinePlaneIntersection(pos, forward, mctrl.PointToAxis(pos, right))
        world_dir = (localpos:Dot(right) - offset) * right
    elseif axis == "z" then
        local localpos = mctrl.LinePlaneIntersection(pos, forward, mctrl.PointToAxis(pos, up))
        world_dir = (localpos:Dot(up) - offset) * up
    elseif axis == "view" then
        world_dir = mctrl.LinePlaneIntersection(pos, pace.GetViewAngles():Forward(), cursor_pos())
    end

    if world_dir then
        local m2 = Matrix()
        m2:SetTranslation(m:GetTranslation() + world_dir)
        local wm = mctrl.grab.bone_matrix:GetInverse() * m2
        local pos = wm:GetTranslation()

        if input.IsKeyDown(KEY_LCONTROL) then
            local num = cvar_pos_grid:GetInt("pac_grid_pos_size")
            pos.x = math.Round(pos.x / num) * num
            pos.y = math.Round(pos.y / num) * num
            pos.z = math.Round(pos.z / num) * num
        end

        pace.Call("VariableChanged", part, "Position", pos, 0.25)

        timer.Create("pace_refresh_properties", 0.1, 1, function()
            pace.PopulateProperties(part)
        end)
    end
end

function mctrl.CalculateRotation()
    local part = mctrl.GetTarget()
    if not part:IsValid() then return end
    local axis = mctrl.grab.axis
    local ang = mctrl.grab.matrix:GetAngles() --part:GetWorldMatrixWithoutOffsets():GetAngles()
    local world_angle

    if axis == "x" then
        local plane_pos = util.IntersectRayWithPlane(EyePos(), mctrl.ScreenToVec(cursor_pos()), mctrl.grab.matrix:GetTranslation(), mctrl.grab.matrix:GetRight())
        if not plane_pos then return end
        local diff_angle = (plane_pos - mctrl.grab.matrix:GetTranslation()):Angle()
        local local_angle = WorldToLocalAngle(diff_angle, ang)
        local p = local_angle.p

        if math.abs(local_angle.y) > 90 then
            p = -p + 180
        end

        p = math.NormalizeAngle(p)
        world_angle = LocalToWorldAngle(Angle(p, 0, 0), ang)
    elseif axis == "y" then
        local plane_pos = util.IntersectRayWithPlane(EyePos(), mctrl.ScreenToVec(cursor_pos()), mctrl.grab.matrix:GetTranslation(), mctrl.grab.matrix:GetUp())
        if not plane_pos then return end
        local diff_angle = (plane_pos - mctrl.grab.matrix:GetTranslation()):Angle()
        local local_angle = WorldToLocalAngle(diff_angle, ang)
        world_angle = LocalToWorldAngle(Angle(0, local_angle.y - 90, 0), ang)
    elseif axis == "z" then
        local plane_pos = util.IntersectRayWithPlane(EyePos(), mctrl.ScreenToVec(cursor_pos()), mctrl.grab.matrix:GetTranslation(), mctrl.grab.matrix:GetForward())
        if not plane_pos then return end
        local diff_angle = (plane_pos - mctrl.grab.matrix:GetTranslation()):Angle()
        diff_angle:RotateAroundAxis(mctrl.grab.matrix:GetForward(), 90)
        local local_angle = WorldToLocalAngle(diff_angle, ang)
        local p = local_angle.p

        if local_angle.y > 0 then
            p = -p + 180
        end

        p = math.NormalizeAngle(p)
        world_angle = LocalToWorldAngle(Angle(0, 0, p), ang)
    end

    if world_angle then
        local ang = WorldToLocalAngle(world_angle, mctrl.grab.bone_matrix:GetAngles())

        if input.IsKeyDown(KEY_LCONTROL) then
            local num = cvar_ang_grid:GetInt("pac_grid_ang_size")
            ang.p = math.Round(ang.p / num) * num
            ang.y = math.Round(ang.y / num) * num
            ang.r = math.Round(ang.r / num) * num
        end

        pace.Call("VariableChanged", part, "Angles", ang, 0.25)

        timer.Create("pace_refresh_properties", 0.1, 1, function()
            pace.PopulateProperties(part)
        end)
    end
end

mctrl.grab = {
    mode = nil,
    axis = nil
}

local GRAB_AND_CLONE = CreateClientConVar("pac_grab_clone", "1", true, false, "Holding shift when moving or rotating a part creates its clone")

function mctrl.IsHoveringSomething()
    local x, y = input.GetCursorPos()
    local pos, ang = mctrl.GetWorldPosition()
    if not pos or not ang then return end
    local forward, right, up = mctrl.GetAxes(ang)
    local r = mctrl.GetGizmoSize()

    -- Movement
    do
        local axis

        for i, v in pairs({
            x = mctrl.VecToScreen(pos + forward * r),
            y = mctrl.VecToScreen(pos + right * r),
            z = mctrl.VecToScreen(pos + up * r),
            view = mctrl.VecToScreen(pos)
        }) do
            local d = math.sqrt((v.x - x) ^ 2 + (v.y - y) ^ 2) --pythagoras between x,y (mouse) and v.x,v.y (the axis' position grabber)

            if d <= mctrl.grab_dist then
                axis = {
                    axis = i,
                    pos = v
                }

                break
            end
        end

        if axis then
            return {"position grabber", axis}
        end
    end

    -- Rotation
    do
        local axis

        for i, v in pairs({
            x = mctrl.VecToScreen(pos + forward * r * mctrl.angle_pos),
            y = mctrl.VecToScreen(pos + right * r * mctrl.angle_pos),
            z = mctrl.VecToScreen(pos + up * r * mctrl.angle_pos)
        }) do
            local d = math.sqrt((v.x - x) ^ 2 + (v.y - y) ^ 2) --pythagoras between x,y (mouse) and v.x,v.y (the axis' position grabber)

            if d <= mctrl.grab_dist then
                axis = {
                    axis = i,
                    pos = v
                }

                break
            end
        end

        if axis then
            return {"angle grabber", axis}
        end
    end
    return nil
end

function mctrl.GUIMousePressed(mc)

    if mc ~= MOUSE_LEFT then
        --actually we wanna try something new
        if mc == MOUSE_RIGHT then mctrl.OpenConfigMenu() end


        return mctrl.IsHoveringSomething()
    end
    
    local target = mctrl.GetTarget()
    if not target:IsValid() then return end
    local x, y = input.GetCursorPos()
    local pos, ang = mctrl.GetWorldPosition()
    if not pos or not ang then return end
    local forward, right, up = mctrl.GetAxes(ang)
    local r = mctrl.GetGizmoSize()

	if pace.angle_gizmo_render == 0 then return end
	if pace.angle_gizmo_render ~= 2 then
		-- Movement
		do
			local axis

			for i, v in pairs({
				x = mctrl.VecToScreen(pos + forward * r),
				y = mctrl.VecToScreen(pos + right * r),
				z = mctrl.VecToScreen(pos + up * r),
				view = mctrl.VecToScreen(pos)
			}) do
				local d = math.sqrt((v.x - x) ^ 2 + (v.y - y) ^ 2)

				if d <= mctrl.grab_dist then
					axis = {
						axis = i,
						pos = v
					}

					break
				end
			end

			if axis then
				mctrl.grab = {}
				mctrl.grab.mode = "move"
				mctrl.grab.axis = axis.axis
				local x, y = input.GetCursorPos()

				mctrl.grab.mouse_offset = {
					x = math.ceil(axis.pos.x - x),
					y = math.ceil(axis.pos.y - y),
				}

				mctrl.grab.matrix = target:GetWorldMatrixWithoutOffsets() * Matrix()
				mctrl.grab.bone_matrix = target:GetBoneMatrix() * Matrix()

				if GRAB_AND_CLONE:GetBool() and input.IsShiftDown() then
					local copy = target:Clone()
					copy:SetParent(copy:GetParent())
				end

				pace.RecordUndoHistory()

				return true
			end
		end
	end
    
    -- Rotation
    do
        local axis

        for i, v in pairs({
            x = mctrl.VecToScreen(pos + forward * r * mctrl.angle_pos),
            y = mctrl.VecToScreen(pos + right * r * mctrl.angle_pos),
            z = mctrl.VecToScreen(pos + up * r * mctrl.angle_pos)
        }) do
            local d = math.sqrt((v.x - x) ^ 2 + (v.y - y) ^ 2) --pythagoras between x,y (mouse) and v.x,v.y (the axis' position grabber)

            if d <= mctrl.grab_dist then
                axis = {
                    axis = i,
                    pos = v
                }

                break
            end
        end

        if axis then
            mctrl.grab = {}
            mctrl.grab.mode = "rotate"
            mctrl.grab.axis = axis.axis
            local x, y = input.GetCursorPos()

            mctrl.grab.mouse_offset = {
                x = math.ceil(axis.pos.x - x) + 0.5,
                y = math.ceil(axis.pos.y - y) + 0.5,
            }

            mctrl.grab.matrix = target:GetWorldMatrixWithoutOffsets() * Matrix()
            mctrl.grab.bone_matrix = target:GetBoneMatrix() * Matrix()
            mctrl.grab.dist = dist

            if GRAB_AND_CLONE:GetBool() and input.IsShiftDown() then
                local copy = target:Clone()
                copy:SetParent(copy:GetParent())
            end

            pace.RecordUndoHistory()

            return true
        end
    end
end

function mctrl.GUIMouseReleased(mc)
    if mc == MOUSE_LEFT then
        mctrl.grab = nil
    end

    pace.RecordUndoHistory()
end

local white = surface.GetTextureID("gui/center_gradient.vtf")

local function DrawLineEx(x1, y1, x2, y2, w, skip_tex)
    w = w or 1

    if not skip_tex then
        surface.SetTexture(white)
    end

    local dx, dy = x1 - x2, y1 - y2
    local ang = math.atan2(dx, dy)
    local dst = math.sqrt((dx * dx) + (dy * dy))
    x1 = x1 - dx * 0.5
    y1 = y1 - dy * 0.5
    surface.DrawTexturedRectRotated(x1, y1, w, dst, math.deg(ang))
end

local function DrawLine(x, y, a, b)
    DrawLineEx(x, y, a, b, 3)
end

local function DrawCircleEx(x, y, rad, res, ...)
    res = res or 16
    local spacing = (res / rad) - 0.1

    for i = 0, res do
        local i1 = ((i + 0) / res) * math.pi * 2
        local i2 = ((i + 1 + spacing) / res) * math.pi * 2
        DrawLineEx(x + math.sin(i1) * rad, y + math.cos(i1) * rad, x + math.sin(i2) * rad, y + math.cos(i2) * rad, ...)
    end
end

function mctrl.LineToBox(origin, point, siz)
    siz = siz or 7
    DrawLine(origin.x, origin.y, point.x, point.y)
    DrawCircleEx(point.x, point.y, siz, 32, 2)
end

function mctrl.RotationLines(pos, dir, dir2, r)
    local pr = mctrl.VecToScreen(pos + dir * r * mctrl.angle_pos)
    local pra = mctrl.VecToScreen(pos + dir * r * (mctrl.angle_pos * 0.9) + dir2 * r * 0.08)
    local prb = mctrl.VecToScreen(pos + dir * r * (mctrl.angle_pos * 0.9) + dir2 * r * -0.08)
    DrawLine(pr.x, pr.y, pra.x, pra.y)
    DrawLine(pr.x, pr.y, prb.x, prb.y)
end

local no_lines = false
function mctrl.RotationCircle(pos, fwd, rad, less)
	if pace.angle_gizmo_render == 0 or pace.angle_gizmo_render == 1 then return end
	local res = 24 --arcs
	local subres = 16 --lines per arc
    local spacing = 0.1
	local thick = 3
	local dot_style = rotation_style_dots:GetInt()
	if dot_style == 2 then thick = 5 subres = 6 end

	local rgt = rad * fwd:Right()
	local fwd = rad * fwd:Forward()
	local original = surface.GetDrawColor()

	for i = 0, res do
		if dot_style == 1 and i%2==0 then continue end

		local base_radian = (i * math.pi * 2) / res
		if dot_style ~= 1 then
			local bpoint = (pos + fwd*math.sin(base_radian) + rgt*math.cos(base_radian)):ToScreen()
			if bpoint.visible then DrawCircleEx(bpoint.x, bpoint.y, 6, 16, 2) end
		end
		if no_lines then continue end
		for j = 0, subres do
			if dot_style ~= 1 and j%2==0 then continue end
			local dot_or_dash_offset = 2
			if dot_style == 2 then dot_or_dash_offset = 0.6 end
			if dot_style == 0 then dot_or_dash_offset = 4 end
			
			local i1 = base_radian + (math.pi * 2) * (j - spacing) / (res * subres)
			local i2 = base_radian + (math.pi * 2) * (j + dot_or_dash_offset + spacing) / (res * subres)

			if dot_style ~= 3 then
				local point = (pos + fwd*math.sin(i1) + rgt*math.cos(i1)):ToScreen()
				local point2 = (pos + fwd*math.sin(i2) + rgt*math.cos(i2)):ToScreen()
				if point.visible and point2.visible then
					DrawLineEx(point.x, point.y, point2.x, point2.y, thick)
				end
			end
		end
	end


	if less then return end
	surface.SetFont(pace.CurrentFont)
	for cardinal = 0, 7 do
		local point = mctrl.VecToScreen(pos - rgt*math.sin(math.rad(cardinal*45)) + fwd*math.cos(math.rad(cardinal*45)))
		
		local w,h = surface.GetTextSize("a")
		surface.SetTextPos(point.x + 10,point.y - h/2)
		surface.SetTextColor(255,255,255, a)
		local offset = 0
		if mctrl.hovered_axis == "y" or mctrl.hovered_axis == "oy" then
			offset = 90
		end
		if (offset + cardinal*45) <= 180 then
			surface.DrawText(offset + cardinal*45)
		else
			surface.DrawText(offset + -180 + (cardinal*45)%180)
		end
	end
	local angle = 0
	local part = mctrl.GetTarget()
	if not part then return end
	if not part.Angles then return end
	if mctrl.hovered_axis == "x" then
		angle = part.Angles.p
	elseif mctrl.hovered_axis == "y" then
		angle = part.Angles.y
	elseif mctrl.hovered_axis == "z" then
		angle = part.Angles.r
	elseif mctrl.hovered_axis == "ox" then
		angle = part.AngleOffset.p
	elseif mctrl.hovered_axis == "oy" then
		angle = part.AngleOffset.y
	elseif mctrl.hovered_axis == "oz" then
		angle = part.AngleOffset.z
	end
	local origin = (pos):ToScreen()
	local point = (pos - 1.25*rgt*math.sin(math.rad(angle)) + 1.25*fwd*math.cos(math.rad(angle))):ToScreen()
	DrawLineEx(origin.x,origin.y,point.x,point.y, 3)
	
	point = (pos - 1.5*rgt*math.sin(math.rad(angle)) + 1.5*fwd*math.cos(math.rad(angle))):ToScreen()

	surface.SetTextColor(original.r,original.g,original.b)
	surface.SetTextPos(point.x,point.y)
	surface.DrawText(math.Round(angle,4))
end

local push_pos
local fwd_raw
local rgt_raw
local up_raw
local chosen_fwd
local pre_render
ang_axes_rendered = {}
pace.angle_gizmo_render = 1
--[[
	0 : none
	1 : lines
	2 : circles
	3 : lines + circles

]]


function mctrl.RotationCircle2D()
	if pace.angle_gizmo_render == 0 or pace.angle_gizmo_render == 1 then return end
	--cam.Start2D()
	--surface.SetDrawColor(255,255,255,255)
	local res = 24 --arcs
	local subres = 16 --lines per arc
	local spacing = 0.1
	local thick = 100
	local w = ScrW()*2 --ok so I need this to be bigger than the screen because ultimately our thick line drawing function relies on surface...
	local dot_style = rotation_style_dots:GetInt()
	if dot_style == 2 then thick = 50 subres = 6 end

	local original = surface.GetDrawColor()

	for i = 0, res do
		if dot_style == 1 and i%2==0 then continue end

		local base_radian = (i * math.pi * 2) / res
		if dot_style ~= 1 then
			local bpoint = {w*math.sin(base_radian), w*math.cos(base_radian)}
			--DrawCircleEx(bpoint[1] + ScrW()/2, bpoint[2] + ScrH()/2, 6, 32, 2)
			--DrawCircleEx(bpoint[1], bpoint[2], 150, 32, 100)
		end

		for j = 0, subres do
			if dot_style ~= 1 and j%2==0 then continue end
			local dot_or_dash_offset = 2
			if dot_style == 2 then dot_or_dash_offset = 0.6 end
			if dot_style == 0 then dot_or_dash_offset = 4 end
			
			local i1 = base_radian + (math.pi * 2) * (j - spacing) / (res * subres)
			local i2 = base_radian + (math.pi * 2) * (j + dot_or_dash_offset + spacing) / (res * subres)

			if dot_style ~= 3 then
				local point = {w*math.sin(i1), w*math.cos(i1)}
				local point2 = {w*math.sin(i2), w*math.cos(i2)}
				--DrawLineEx(point[1] + ScrW()/2, point[2] + ScrH()/2, point2[1] + ScrW()/2, point2[2] + ScrH()/2, thick)
				DrawLineEx(point[1], point[2], point2[1], point2[2], thick)
			end
		end
	end
	--cam.End2D()
end

function mctrl.HUDPaint()
    mctrl.LastThinkCall = FrameNumber()
    if pace.IsSelecting then return end
    local target = mctrl.GetTarget()
    if not target then return end
    local pos, ang = mctrl.GetWorldPosition()
    if not pos or not ang then mctrl.hovered_axis = nil return end
    local forward, right, up = mctrl.GetAxes(ang)
    local radius = mctrl.GetGizmoSize()
    local origin = mctrl.VecToScreen(pos)
	--radius = radius * 0.5
    local forward_point = mctrl.VecToScreen(pos + forward * radius)
    local right_point = mctrl.VecToScreen(pos + right * radius)
    local up_point = mctrl.VecToScreen(pos + up * radius)
	--radius = 2*radius

	ang_axes_rendered = {x = false, y = false, z = false}
    if origin.visible or forward_point.visible or right_point.visible or up_point.visible then
		if pace.angle_gizmo_render ~= 2 and pace.angle_gizmo_render ~= 0 then
			if mctrl.grab and (mctrl.grab.axis == "x" or mctrl.grab.axis == "view") then
				surface.SetDrawColor(255, 200, 0, 255)
			else
				surface.SetDrawColor(255, 80, 80, 255)
			end

			mctrl.LineToBox(origin, forward_point)
			mctrl.RotationLines(pos, forward, up, radius)

			if mctrl.grab and (mctrl.grab.axis == "y" or mctrl.grab.axis == "view") then
				surface.SetDrawColor(255, 200, 0, 255)
			else
				surface.SetDrawColor(80, 255, 80, 255)
			end

			mctrl.LineToBox(origin, right_point)
			mctrl.RotationLines(pos, right, forward, radius)

			if mctrl.grab and (mctrl.grab.axis == "z" or mctrl.grab.axis == "view") then
				surface.SetDrawColor(255, 200, 0, 255)
			else
				surface.SetDrawColor(80, 80, 255, 255)
			end

			mctrl.LineToBox(origin, up_point)
			mctrl.RotationLines(pos, up, right, radius)
			surface.SetDrawColor(255, 200, 0, 255)
			DrawCircleEx(origin.x, origin.y, 4, 32, 2)
		end

		if pace.angle_gizmo_render ~= 1 and pace.angle_gizmo_render ~= 0 and rotation_style:GetInt() ~= 0 then
			local part = mctrl.GetTarget()
       		if not part:IsValid() then return end
        	local m = part:GetBoneMatrix()
			m:Translate(part.Position)
			local wang = m:GetAngles()
			local forward, right, up = mctrl.GetAxes(wang)
			local fwd = forward:AngleEx(right)
			fwd_raw = forward:AngleEx(right)
			rgt_raw = right:AngleEx(up)
			up_raw = up:AngleEx(forward)

			if mctrl.hovered_axis == "x" or mctrl.hovered_axis == "y" or mctrl.hovered_axis == "z" then
				if mctrl.hovered_axis == "x" then
					fwd = forward:AngleEx(right)
					surface.SetDrawColor(255, 80, 80, 255)
					ang_axes_rendered.x = true
				elseif mctrl.hovered_axis == "y" then
					fwd = right:AngleEx(up)
					surface.SetDrawColor(80, 255, 80, 255)
					ang_axes_rendered.y = true
				elseif mctrl.hovered_axis == "z" then
					fwd = up:AngleEx(forward)
					surface.SetDrawColor(80, 80, 255, 255)
					ang_axes_rendered.z = true
				end
				chosen_fwd = fwd
			elseif mctrl.hovered_axis == "ox" or mctrl.hovered_axis == "oy" or mctrl.hovered_axis == "oz" then
				m:Rotate(part.Angles)
				m:Translate(part.PositionOffset)
				local wang = m:GetAngles()
				local forward, right, up = mctrl.GetAxes(wang)

				fwd_raw = forward:AngleEx(right)
				rgt_raw = right:AngleEx(up)
				up_raw = up:AngleEx(forward)
				if mctrl.hovered_axis == "ox" then
					fwd = forward:AngleEx(right)
					surface.SetDrawColor(255, 80, 80, 255)
					ang_axes_rendered.x = true
				elseif mctrl.hovered_axis == "oy" then
					fwd = right:AngleEx(up)
					surface.SetDrawColor(80, 255, 80, 255)
					ang_axes_rendered.y = true
				elseif mctrl.hovered_axis == "oz" then
					fwd = up:AngleEx(forward)
					up_raw = fwd
					surface.SetDrawColor(80, 80, 255, 255)
					ang_axes_rendered.z = true
				end
				chosen_fwd = fwd
			else
				ang_axes_rendered.x = true
				surface.SetDrawColor(150,150,150, 255)
			end

			pos = m:GetTranslation()
			push_pos = pos
			local stime = SysTime()

			mctrl.RotationCircle(pos, fwd, radius)
			if rotation_style:GetInt() == 2 then
				if not ang_axes_rendered.x then
					surface.SetDrawColor(255, 80, 80, 255)
					mctrl.RotationCircle(pos, fwd_raw, radius, true)
				end
				if not ang_axes_rendered.y then
					surface.SetDrawColor(80, 255, 80, 255)
					mctrl.RotationCircle(pos, rgt_raw, radius, true)
				end
				if not ang_axes_rendered.z then
					surface.SetDrawColor(80, 80, 255, 255)
					mctrl.RotationCircle(pos, up_raw, radius, true)
				end
			elseif rotation_style:GetInt() == 3 then
				surface.SetDrawColor(150,150,150, 255)
				if not ang_axes_rendered.x then
					--if mctrl.grab and mctrl.grab.axis ~= "x" and mctrl.grab.axis ~= "ox" then surface.SetDrawColor(150,150,150, 255) end
					mctrl.RotationCircle(pos, fwd_raw, radius, true)
				end
				if not ang_axes_rendered.y then
					--if mctrl.grab and mctrl.grab.axis ~= "y" and mctrl.grab.axis ~= "oy" then surface.SetDrawColor(150,150,150, 255) end
					mctrl.RotationCircle(pos, rgt_raw, radius, true)
				end
				if not ang_axes_rendered.z then
					--if mctrl.grab and mctrl.grab.axis ~= "z" and mctrl.grab.axis ~= "oz" then surface.SetDrawColor(150,150,150, 255) end
					mctrl.RotationCircle(pos, up_raw, radius, true)
				end
			end
			local delta = 1000 * (SysTime() - stime)
			--pace.FlashNotification("delta " .. delta .. " ms")
		end
    end
end
pac.AddHook("PostDrawTranslucentRenderables", "gizmo_angle", function()
	if not pace.IsActive() then return end
	if not pace.IsFocused() then return end
	if not mctrl.GetTarget().Position then return end
	if not mctrl.VecToScreen(mctrl.GetWorldPosition()).visible then return end
	local stime = SysTime()
	if push_pos then
		no_lines = true
		if mctrl.hovered_axis == "x" or mctrl.hovered_axis == "y" or mctrl.hovered_axis == "z" then
			if mctrl.hovered_axis == "x" then
				surface.SetDrawColor(255, 80, 80, 255)
			elseif mctrl.hovered_axis == "y" then
				surface.SetDrawColor(80, 255, 80, 255)
			elseif mctrl.hovered_axis == "z" then
				surface.SetDrawColor(80, 80, 255, 255)
			end
		elseif mctrl.hovered_axis == "ox" or mctrl.hovered_axis == "oy" or mctrl.hovered_axis == "oz" then
			if mctrl.hovered_axis == "ox" then
				surface.SetDrawColor(255, 80, 80, 255)
			elseif mctrl.hovered_axis == "oy" then
				surface.SetDrawColor(80, 255, 80, 255)
			elseif mctrl.hovered_axis == "oz" then
				surface.SetDrawColor(80, 80, 255, 255)
			end
		else
			surface.SetDrawColor(150,150,150, 255)
		end


		local function drawflattened(ang)
			cam.IgnoreZ(true)
			cam.Start3D2D(push_pos, ang, ScrW() * 0.000000137 * mctrl.GetGizmoSize())
					render.CullMode(1)
					mctrl.RotationCircle2D()
					render.CullMode(0)
					mctrl.RotationCircle2D()
			cam.End3D2D()
			cam.IgnoreZ(false)
		end
		drawflattened(chosen_fwd or fwd_raw)

		if rotation_style:GetInt() == 2 then
			if not ang_axes_rendered.x then
				surface.SetDrawColor(255, 80, 80, 255)
				drawflattened(fwd_raw)
			end
			if not ang_axes_rendered.y then
				surface.SetDrawColor(80, 255, 80, 255)
				drawflattened(rgt_raw)
			end
			if not ang_axes_rendered.z then
				surface.SetDrawColor(80, 80, 255, 255)
				drawflattened(up_raw)
			end
		elseif rotation_style:GetInt() == 3 then
			surface.SetDrawColor(150,150,150, 255)
			if not ang_axes_rendered.x then
				--if mctrl.grab and mctrl.grab.axis ~= "x" and mctrl.grab.axis ~= "ox" then surface.SetDrawColor(150,150,150, 255) end
				drawflattened(fwd_raw)
			end
			if not ang_axes_rendered.y then
				--if mctrl.grab and mctrl.grab.axis ~= "y" and mctrl.grab.axis ~= "oy" then surface.SetDrawColor(150,150,150, 255) end
				drawflattened(rgt_raw)
			end
			if not ang_axes_rendered.z then
				--if mctrl.grab and mctrl.grab.axis ~= "z" and mctrl.grab.axis ~= "oz" then surface.SetDrawColor(150,150,150, 255) end
				drawflattened(up_raw)
			end
		end
	end
	local delta = 1000 * (SysTime() - stime)
	--pace.FlashNotification("delta " .. math.Round(delta, 3) .. " ms")
end)

function mctrl.Think()
    if pace.IsSelecting then return end
    if not mctrl.target:IsValid() then return end

	local hover = mctrl.IsHoveringSomething()
	if not hover then mctrl.hovered_axis = nil end
	if hover then
		if hover[1] == "angle grabber" then
			mctrl.hovered_axis = hover[2].axis
		end
	end

    if not mctrl.grab then return end

    if mctrl.grab.axis and mctrl.grab.mode == "move" then
        mctrl.CalculateMovement()
    elseif mctrl.grab.axis and mctrl.grab.mode == "rotate" then
        mctrl.CalculateRotation()
    end
end


pac.AddHook("Think", "pace_mctrl_Think", mctrl.Think)
pace.mctrl = mctrl