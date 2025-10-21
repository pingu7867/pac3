local SysTime = SysTime
local pairs = pairs
local Color = Color
local tostring = tostring
local cam_Start2D = cam.Start2D
local cam_IgnoreZ = cam.IgnoreZ
local Vector = Vector
local math_Clamp = math.Clamp
local EyePos = EyePos
local surface_SetFont = surface.SetFont
local surface_GetTextSize = surface.GetTextSize
local draw_DrawText = draw.DrawText
local string_format = string.format
local input_GetCursorPos = input.GetCursorPos
local vgui_CursorVisible = vgui.CursorVisible
local ScrW = ScrW
local ScrH = ScrH
local input_LookupBinding = input.LookupBinding
local LocalPlayer = LocalPlayer
local input_IsMouseDown = input.IsMouseDown
local cam_End2D = cam.End2D

local max_render_time_cvar = CreateClientConVar("pac_max_render_time", 0)

jit.on()

function pac.IsRenderTimeExceeded(ent)
	return ent.pac_render_time_exceeded
end

function pac.ResetRenderTime(ent)
	ent.pac_rendertime = ent.pac_rendertime or {}

	for key in pairs(ent.pac_rendertime) do
		ent.pac_rendertime[key] = 0
	end
end

function pac.RecordRenderTime(ent, type, start)
	ent.pac_rendertime = ent.pac_rendertime or {}
	ent.pac_rendertime[type] = (ent.pac_rendertime[type] or 0) + (SysTime() - start)

	local max_render_time = max_render_time_cvar:GetFloat()

	if max_render_time > 0 then
		local total_time = 0

		for k,v in pairs(ent.pac_rendertime) do
			total_time = total_time + v
		end

		total_time = total_time * 1000

		if total_time > max_render_time then
			if pac.visualising_rendertimes then return end
			pac.Message(Color(255, 50, 50), tostring(ent) .. ": max render time exceeded!")
			ent.pac_render_time_exceeded = total_time
			if not ent.pac_render_monitoring then pac.HideEntityParts(ent) end
		end
	end
end

local frame_index = 0
pac.profiling_frameend = 0
local frames_recorded = {}
--[[table structure
{frames
	{classes
		["model2"] = time
		... next class
	}
	... next frame recording
}
]]
local frames_recorded_raw_index = {}
function pac.StartProfiling(ent, parts)
	frames_recorded_raw_index = {}
	if parts then ent_parts[ent] = parts end
	pac.profiling_framestart = FrameNumber()
	pac.profiling_frameend = FrameNumber()
	frame_index = FrameNumber()
end
function pac.StopProfiling()
	pac.profiling_framestart = nil
	frames_recorded_raw_index = nil
end

local function extract_table(tbl, extra)
	if not tbl then return end
	local output_tbl = {}
	if istable(extra) then --more args
		if not extra.class then return {} end
		local start_index = extra.start_index or pac.profiling_framestart
		local end_index = extra.end_index or pac.profiling_frameend
		for i=1,end_index-start_index,1 do
			if not tbl[i] then return output_tbl end
			table.insert(output_tbl,tbl[i][extra.class])
		end
		return output_tbl
	end
	return {}
end

local function get_average(tbl)
	local sum = 0
	for i,v in ipairs(tbl) do
		sum = sum + v
	end
	return sum / #tbl
end

local function get_median(tbl)
	local count = #tbl
	table.sort(tbl)
	if count == 0 then return 0 end
	if (count % 2) == 1 then
		return tbl[math.floor(count/2) + 1]
	else
		return (tbl[count/2] + tbl[count/2 + 1]) / 2
	end
end

local function part_count(class, hidden)
	local count = 0
	for i,v in pairs(pac.GetLocalParts()) do
		if v.ClassName == class then
			if not hidden then
				count = count + 1
			elseif v:IsHidden() then
				count = count + 1
			end
			
		end
	end
	return count
end

function pac.GetCurrentFrameTimeData(frame)
	local frame = frame or pac.profiling_frameend
	pac.GetRenderCostsPerClass()
	return frames_recorded[frame]
end
function pac.GetFrameTimeData(frame)
	if not frame then return frames_recorded end
	frame = pac.profiling_frameend
	return frames_recorded[frame]
end

function pac.PrintCurrentFrameTimeData()
	local frame = pac.profiling_frameend
	local ent = LocalPlayer()
	print("=========the frame is " .. frame .. "=========")
	pac.GetRenderCostsPerClass()
	PrintTable(frames_recorded[frame])
end

local total_averages = {}
function pac.GetRenderCostsPerClass(ent, parts, frame)
	if not ent or not parts then ent = LocalPlayer() parts = pac.GetLocalParts() end
	local tbl = {}
	--if frame then 
		for key,part in pairs(parts) do
			if not part.frametimes then
				part.frametimes = {}
				continue
			end
			tbl[part.ClassName] = tbl[part.ClassName] or 0
			tbl[part.ClassName] = tbl[part.ClassName] + (part.frametimes[pac.profiling_frameend] or part.frametimes[pac.profiling_frameend-1] or 0)
		end
	--end
	frames_recorded[pac.profiling_frameend] = tbl
	table.insert(frames_recorded_raw_index,tbl)
	if #frames_recorded_raw_index > 100 then
		table.remove(frames_recorded_raw_index,1)
		pac.profiling_framestart = pac.profiling_framestart + 1
	end
	return tbl
end

function pac.RecordPartRenderTime(part, punch)
	--print("record ", part)
	if not pac.profiling_framestart then return end
	local ent = part:GetRootPart():GetOwner()
	local stime = SysTime()
	part.frametimes = part.frametimes or {}
	part.frametimes[FrameNumber()] = part.frametimes[FrameNumber()] or 0
	if not punch then
		part.frame_rec_in = stime
	else
		if not part.frame_rec_in then return end
		part.frame_rec_out = stime
		part.frametimes[FrameNumber()] = part.frametimes[FrameNumber()] + (stime - part.frame_rec_in)
		pac.profiling_frameend = FrameNumber()
		part.frame_rec_in = nil
		--frames_recorded[FrameNumber()] = frames_recorded[FrameNumber()] or {}
		--frames_recorded[FrameNumber()][ent] = frames_recorded[FrameNumber()][ent] or {}
	end
end

function pac.DrawRenderTimeExceeded(ent)
	cam_Start2D()
	cam_IgnoreZ(true)
		local pos_3d = ent:NearestPoint(ent:EyePos() + ent:GetUp()) + Vector(0,0,5)
		local alpha = math_Clamp(pos_3d:Distance(EyePos()) * -1 + 500, 0, 500) / 500
		if alpha > 0 then
			local pos_2d = pos_3d:ToScreen()
			surface_SetFont("ChatFont")
			local _, h = surface_GetTextSize("|")

			draw_DrawText(
				string_format(
					"pac3 outfit took %.2f/%i ms to render",
					ent.pac_render_time_exceeded,
					max_render_time_cvar:GetFloat()
				),
				"ChatFont",
				pos_2d.x,
				pos_2d.y,
				Color(255,255,255,alpha * 255),
				1
			)
			local x, y = pos_2d.x, pos_2d.y + h

			local mx, my = input_GetCursorPos()
			if not vgui_CursorVisible() then
				mx = ScrW() / 2
				my = ScrH() / 2
			end
			local dist = 200
			local hovering = mx > x - dist and mx < x + dist and my > y - dist and my < y + dist

			local button = vgui_CursorVisible() and "click" or ("press " .. input_LookupBinding("+use"))
			draw_DrawText(button .. " here to try again", "ChatFont", x, y, Color(255,255,255,alpha * (hovering and 255 or 100) ), 1)

			if hovering and LocalPlayer():KeyDown(IN_USE) or (vgui_CursorVisible() and input_IsMouseDown(MOUSE_LEFT)) then
				ent.pac_render_time_exceeded = nil
			end
		end

	cam_IgnoreZ(false)
	cam_End2D()
end


--sourcing from the default render metrics (overall rendertime divided by render type)
function pac.VisualiseRenderTimes()
	local keys = {
		hands = true,
		opaque = true,
		translucent = true,
		update = true,
		update_legacy_bones = true,
		viewmodel = true
	}
	if pac.visualising_rendertimes then
		pac.RemoveHook("HUDPaint", "draw_rendertimes")
		for i,ent in ipairs(ents.GetAll()) do
			ent.pac_render_monitoring = nil
			ent.pac_rendertime_total_records = {}
		end
	else
		for i,ent in ipairs(ents.GetAll()) do
			ent.pac_render_monitoring = true
			ent.pac_rendertime = nil
		end
		local color1 = Color(255,255,255)
		local color2 = Color(255,255,100)
		local color3 = Color(255,150,0)
		local color4 = Color(255,0,0)
		local color5 = Color(150,150,150)
		pac.AddHook("HUDPaint", "draw_rendertimes", function()
			local main_y = 0
			local main_x = ScrW() - 500
			local function format(num)
				num = num + 0.0005
				return tostring(num):sub(1,4)
			end
			local function draw_renderinfo(ent, x,y)
				local total_ms = 0
				for k,v in pairs(ent.pac_rendertime) do
					total_ms = total_ms + v
				end
				total_ms = total_ms*1000
				local main_color = color1
				local exceeded = (max_render_time_cvar:GetFloat() > 0) and (max_render_time_cvar:GetFloat() < total_ms)
				draw.DrawText(tostring(ent) .. ": " .. format(total_ms) .. "ms, average " .. format(ent.pac_rendertime_average*1000) .. "ms", "DebugOverlay", x, y, main_color)
				y = y + 12
				if exceeded then
					main_color = color5
					draw.DrawText("Exceeds max render time of " .. max_render_time_cvar:GetFloat() .. " ms", "DebugOverlay", x, y, color4:Lerp(color5, 0.5 + 0.5*math.sin(8*RealTime())))
					y = y + 12
				end
				for k,v in pairs(ent.pac_rendertime) do
					local ms = 1000*v
					if ms ~= 0 then
						local color = color1
						if ms > 50 then
							color = color4
						elseif ms > 30 then
							color = color3
						elseif ms > 15 then
							color = color2
						end
						draw.DrawText(k .. " " .. format(ms) .. "ms", "DebugOverlay", x + 30, y, color)
						y = y + 12
					end
				end
			end

			for i,ent in ipairs(ents.GetAll()) do
				if ent.pac_rendertime then
					
					ent.pac_rendertime_total_records = ent.pac_rendertime_total_records or {}
					local total = 0
					for k,v in pairs(ent.pac_rendertime) do
						total = total + v
					end
					table.insert(ent.pac_rendertime_total_records, total)

					local sum = 0
					for _,sample in ipairs(ent.pac_rendertime_total_records) do
						sum = sum + sample
					end
					ent.pac_rendertime_average = sum / math.max(1,#ent.pac_rendertime_total_records)

					draw_renderinfo(ent, main_x,main_y)
					main_y = main_y + 90
					local pos2d = ent:GetPos():ToScreen()
					draw_renderinfo(ent, pos2d.x,pos2d.y)
				end
				
			end
		end)
	end
	pac.visualising_rendertimes = not pac.visualising_rendertimes
end


if pac.piecircle then pac.piecircle:Remove() end
pac.piecircle = ClientsideModel("models/pac/circle.mdl")
pie_circle = pac.piecircle
pie_circle:SetNoDraw(true)

local function transform_ang(ang, rotation)
	local x = ang:Right()
	local y = ang:Up()
	local sin = math.sin(math.rad(rotation))
	local cos = math.cos(math.rad(rotation))
	return (x*cos + y*sin):GetNormalized()
end

local half = 0
local function DrawPieChart(x,y, w,h, data)
	if not data then return end
	pie_circle:SetNoDraw(false)
	--pac.EyePos, pac.EyeAng
	local pos = pac.EyePos + 50*gui.ScreenToVector(x,y):GetNormalized()
	local ang = pac.EyeAng
	--local pos = pace.ViewPos + pace.ViewAngles:Forward()*50
	pie_circle:SetPos(pos) pie_circle:SetAngles((-ang:Forward()):Angle())
	--pie_circle:SetPos()
	--[[data = {
		{theta = 5},
		{theta = 15},
		{theta = 25},
		{theta = 45},
		--{theta = 45},
		--{theta = 45},
	}]]
	data2 = {}
	local sum = 0
	local highest_index = 0
	for i,slice in ipairs(data) do
		sum = sum + slice.theta
		if slice.theta > half then
			highest_index = i
			local half_slice = table.Copy(slice) half_slice.theta = half
			slice.theta = slice.theta - half
			table.insert(data2, half_slice)
			table.insert(data2, slice)
		else
			table.insert(data2, slice)
		end
	end
	--if a slice is more than 180 degrees, obtuse angle can't be achieved with clipping
	data = data2
	
	for i,slice in ipairs(data) do
		slice.theta = 360 * slice.theta / sum
	end
	local data_right = {}
	local data_left = {}

	render.SuppressEngineLighting(true)
	render.EnableClipping(true)

	local deg = 0
	--print("\n\n max index = " .. highest_index)
	local start = 1
	if data and data[1] then
		if data[1].theta == 180 then
			start = 2
			local clip_ang = -transform_ang(ang, 180)
			local slice = data[1] or {} local i = 1

			cam.Start3D() cam.IgnoreZ(true)
			render.SetBlend( 0.2 )
				render.PushCustomClipPlane( clip_ang, clip_ang:Dot(pos) ) render.PushCustomClipPlane( clip_ang, clip_ang:Dot(pos) )
					local col = HSVToColor((CurTime()*40) % 360,1,1)
					if i == highest_index then col = HSVToColor((CurTime()*40 + (i-1)*45) % 360,1,1) end
					render.SetColorModulation(col.r / 255,col.g / 255,col.b / 255)
					pie_circle:DrawModel()
					render.SetColorModulation(1,1,1)
					local deg_mid = 90
					deg = deg + 180
				render.PopCustomClipPlane() render.PopCustomClipPlane()
			render.SetBlend( 1 )
			cam.IgnoreZ(false) cam.End3D()

			surface.SetMaterial(Material(slice.icon or "icon16/calculator.png"))
			surface.DrawTexturedRect(
				x - 16 + (20 + w/2) * math.cos(math.rad(-90 + deg_mid)),
				y - 16 + (20 + w/2) * math.sin(math.rad(-90 + deg_mid)),
			32, 32)
		end
		
		for i=start, #data,1 do
			local slice = data[i]
			local clip_ang = transform_ang(ang, -deg)
			local clip_ang2 = -transform_ang(ang, -deg - slice.theta)
			if i ~= start then
				surface.SetDrawColor(Color(255,255,255))
				surface.DrawLine(x,y,x + math.cos(math.rad(-90 + deg)) * w/2,y + math.sin(math.rad(-90 + deg)) * h/2)
			end


			cam.Start3D() cam.IgnoreZ(true)
			render.SetBlend( 0.2 )
				render.PushCustomClipPlane( clip_ang, clip_ang:Dot(pos) ) render.PushCustomClipPlane( clip_ang2, clip_ang2:Dot(pos) )
					local col = HSVToColor((CurTime()*40 + i*45) % 360,1,1)
					if i == start then col = HSVToColor((CurTime()*40 + (i-1)*45) % 360,1,1) end
					render.SetColorModulation(col.r / 255,col.g / 255,col.b / 255)
					pie_circle:DrawModel()
					render.SetColorModulation(1,1,1)
					local deg_mid = deg + 0.5 * slice.theta
					deg = deg + slice.theta
				render.PopCustomClipPlane() render.PopCustomClipPlane()
			render.SetBlend( 1 )
			cam.IgnoreZ(false) cam.End3D()

			surface.SetMaterial(Material(slice.icon or "icon16/calculator.png"))
			if i ~= start then
				surface.DrawLine(x,y,x + math.cos(math.rad(-90 + deg)) * w/2,y + math.sin(math.rad(-90 + deg)) * h/2)
				surface.DrawTexturedRect(
					x - 16 + (20 + w/2) * math.cos(math.rad(-90 + deg_mid)),
					y - 16 + (20 + w/2) * math.sin(math.rad(-90 + deg_mid)),
				32, 32)
			end
		end
	end


	render.EnableClipping(false)
	pie_circle:SetNoDraw(true)
	render.SuppressEngineLighting(false)
	
end

local function DrawBarChart(x,y, w,h, data)

	if not data then return end
	local data2 = {}

	local sum = 0
	local highest_index = 0
	for i,slice in ipairs(data) do
		sum = sum + slice.theta
		table.insert(data2, slice)
	end
	for i,slice in ipairs(data2) do
		local slice_w = w * slice.theta / sum
		local slice_x = x
		local col = HSVToColor((CurTime()*40 + i*45) % 360,1,1) col.a = 100
		surface.SetDrawColor(col)
		surface.DrawRect(math.floor(slice_x),y,math.ceil(slice_w),h)

		surface.SetDrawColor(Color(255,255,255))
		surface.DrawLine(math.floor(slice_x),y - 1,math.floor(slice_x),y+h-1)

		surface.SetMaterial(Material(slice.icon or "icon16/calculator.png"))
		surface.DrawTexturedRect(x,y,math.min(32,slice_w), math.min(32,slice_w))
		surface.SetFont("DebugOverlay")
		surface.SetTextPos(x + 40, y)
		if slice.theta / sum < 0.005 then continue end
		surface.DrawText(math.Round(slice.theta,2) .. " ms") surface.SetTextPos(x + 40, y + 15)
		surface.DrawText(math.Round(100*slice_w/w,1) .. "%")
		
		x = x + slice_w
	end
end

--sourcing from part class-specific data
function pac.VisualiseRenderTimesPerClass()
	if pac.visualising_rendertimes then
		pac.StopProfiling()
		pac.RemoveHook("RenderScreenspaceEffects", "draw_rendertimes")
	else
		pac.StartProfiling()
		total_averages = {}
		local color1 = Color(255,255,255)
		local color2 = Color(255,255,100)
		local color3 = Color(255,150,0)
		local color4 = Color(255,0,0)
		local color5 = Color(150,150,150)
		pac.AddHook("RenderScreenspaceEffects", "draw_rendertimes", function()
			
			local main_y = 0
			local main_x = ScrW() - 500
			local x = 0
			if pace.IsActive() and pace.IsFocused() then
				if pace.Editor:IsLeft() then
					x = pace.Editor:GetX() + pace.Editor:GetWide()
				end
			end
			local y = 0
			local function format(num)
				num = num + 0.0005
				return tostring(num):sub(1,4)
			end

			local tbl = pac.GetCurrentFrameTimeData()
			local class_readouts = {}
			for class,v in pairs(tbl) do
				class_readouts[class] = 0
			end
			local tbl_i = {}

			for i,v in pairs(tbl) do
				table.insert(tbl_i, {i,v})
			end
			table.sort(tbl_i, function(a,b) return a[2] > b[2] end)

			local total_ms = 0
			local non_averaged_total_ms = 0
			for i,v in ipairs(tbl_i) do
				total_ms = total_ms + 1000*v[2]
			end
			non_averaged_total_ms = total_ms
			table.insert(total_averages, total_ms)

			local mode = "median"
			draw.DrawText("[" .. (#frames_recorded_raw_index) .. " frames recorded] total " .. mode .. ": " .. format(total_ms) .. "ms", "DebugOverlay", x + 10, y, color)
			y = y + 15
			local sorted_class_readouts = {}
			if mode == "" then --direct readouts
				sorted_class_readouts = tbl_i
				total_ms = non_averaged_total_ms
			elseif mode == "average" or mode == "median" then
				if mode == "average" then
					total_ms = get_average(total_averages)
				elseif mode == "median" then
					total_ms = get_median(total_averages)
				end
				
				for class,v in pairs(class_readouts) do
					if mode == "average" then
						local ms = get_average(extract_table(frames_recorded_raw_index, {class = class}))
						class_readouts[class] = ms
					elseif mode == "median" then
						local ms = get_median(extract_table(frames_recorded_raw_index, {class = class}))
						class_readouts[class] = ms
					end
				end
				for i,v in pairs(class_readouts) do
					table.insert(sorted_class_readouts, {i,v})
				end
				table.sort(sorted_class_readouts, function(a,b) return a[2] > b[2] end)
			end

			local piechart_data = {}
			local sum = 0
			for i,v in ipairs(sorted_class_readouts) do
				local class = v[1]
				
				local ms = 1000*v[2]
				sum = sum + ms
				if ms ~= 0 then
					local color = color1
					if ms > 30 then
						color = color4
					elseif ms > 15 then
						color = color3
					elseif ms > 5 then
						color = color2
					end
					local count = part_count(class)
					local count_hid = part_count(class,"hidden")
					local count_div = 1 --0.7 + count * 0.005
					table.insert(piechart_data, {
						theta = ms,
						icon = pac.PartTemplates[class].PART.Icon
					})
					draw.DrawText("[" .. i .. "] " .. class .. " " .. format(ms) .. "ms {" .. count .. " parts (" .. count_hid .." hidden)}", "DebugOverlay", x + 30, y, color)
					surface.SetDrawColor(color)
					surface.DrawLine(x + 30, y + 12, x + 30 + 1000*(ms / (total_ms * count_div)), y + 12)
					y = y + 12
				end
			end
			
			local w = 400
			half = sum / 2
			--DrawPieChart(x + w + 200, w/2 + 50, w,w, piechart_data)
			DrawBarChart(x,y + 15, 800,60, piechart_data)
		end)
	end
	pac.visualising_rendertimes = not pac.visualising_rendertimes
end

jit.off()