local L = pace.LanguageString

-- load only when hovered above
local function add_expensive_submenu_load(pnl, callback, subdir)

	local old = pnl.OnCursorEntered
	pnl.OnCursorEntered = function(...)
		callback(subdir)
		pnl.OnCursorEntered = old
		return old(...)
	end
end

file.CreateDir("pac3")
file.CreateDir("pac3/__backup/")
file.CreateDir("pac3/__backup_save/")

function pace.SaveParts(name, prompt_name, override_part, overrideAsUsual)
	if not name or prompt_name then
		Derma_StringRequest(
			L"save parts",
			L"filename:",
			prompt_name or pace.LastSaveName or "autoload",

			function(name)
				pace.LastSaveName = name
				pace.SaveParts(name, nil, override_part, overrideAsUsual)

				pace.RefreshFiles()
			end
		)

		return
	end

	pac.dprint("saving parts %s", name)

	local data = {}

	if not overrideAsUsual then
		if pace.use_current_part_for_saveload and pace.current_part:IsValid() then
			override_part = pace.current_part
		end
		
		if istable(override_part) then
			data = override_part:ToSaveTable()
		end
	elseif override_part then
		table.insert(data, override_part:ToSaveTable())
		override_part = nil
	end

	if #data == 0 then
		for key, part in pairs(pac.GetLocalParts()) do
			if not part:HasParent() and part:GetShowInEditor() then
				table.insert(data, part:ToSaveTable())
			end
		end
	end

	data = pac.CallHook("pace.SaveParts", data) or data

	if not override_part and #file.Find("pac3/sessions/*", "DATA") > 0 and not name:find("/") then
		pace.luadata.WriteFile("pac3/sessions/" .. name .. ".txt", data)
	else
		if file.Exists("pac3/" .. name .. ".txt", "DATA") then
			local date = os.date("%y-%m-%d-%H_%M_%S")
			local read = file.Read("pac3/" .. name .. ".txt", "DATA")
			file.Write("pac3/__backup_save/" .. name .. "_" .. date .. ".txt", read)

			local files, folders = file.Find("pac3/__backup_save/*", "DATA")

			if #files > 30 then
				local targetFiles = {}

				for i, filename in ipairs(files) do
					local time = file.Time("pac3/__backup_save/" .. filename, "DATA")
					table.insert(targetFiles, {"pac3/__backup_save/" .. filename, time})
				end

				table.sort(targetFiles, function(a, b)
					return a[2] > b[2]
				end)

				for i = 31, #files do
					file.Delete(targetFiles[i][1])
				end
			end
		end

		pace.luadata.WriteFile("pac3/" .. name .. ".txt", data)
	end

	pace.Backup(data, name)
end

local last_backup
local maxBackups = CreateConVar("pac_backup_limit", "100", {FCVAR_ARCHIVE}, "Maximal amount of backups")
local autoload_prompt = CreateConVar("pac_prompt_for_autoload", "1", {FCVAR_ARCHIVE}, "Whether to ask before loading autoload. The prompt can let you choose to not load, pick autoload or the newest backup")
local auto_spawn_prop = CreateConVar("pac_autoload_preferred_prop", "2", {FCVAR_ARCHIVE}, "When loading a pac with an owner name suggesting a prop, notify you and then wait before auto-applying the outfit next time you spawn a prop.\n"..
																								"0 : do not check\n1 : check if only 1 such group is present\n2 : check if multiple such groups are present and queue one group at a time")
local lazy_mode = CreateConVar("pac_load_lazymode", 1, FCVAR_ARCHIVE, "Whether the editor load function should decode parts for outfits only as needed, that is revealing parts after one second hovering over an outfit file")
local compact_mode = CreateConVar("pac_load_compactmode", 0, FCVAR_ARCHIVE, "Whether the editor load function should compact the derma menu by moving each new submenu leftward by 75 pixels, at the cost of text readability\nYou could use that if you have deep folders or tree structures.")


function pace.Backup(data, name)
	name = name or ""

	if not data then
		data = {}
		for key, part in pairs(pac.GetLocalParts()) do
			if not part:HasParent() and part:GetShowInEditor()  then
				table.insert(data, part:ToSaveTable())
			end
		end
	end

	local sorted_files = {}
	if #data > 0 then

		local files, folders = file.Find("pac3/__backup/*", "DATA")

		if #files > maxBackups:GetInt() then
			local temp = {}
			for key, name in pairs(files) do
				local time = file.Time("pac3/__backup/" .. name, "DATA")
				local size = file.Size("pac3/__backup/" .. name, "DATA")
				table.insert(temp, {path = "pac3/__backup/" .. name, time = time, size = size})
			end

			table.sort(temp, function(a, b)
				return a.time > b.time
			end)
			sorted_files = temp

			for i = maxBackups:GetInt() + 1, #files do
				if temp[i+1] then
				--guard against deleting major differences (assume that we follow the same lineage if it's within kilobytes)
					if math.abs(temp[i].size - temp[i+1].size) > 50000 then
						print("[save backup guard] delta is considerable")
					end
				else
					file.Delete(temp[i].path, "DATA")
				end
			end
		end

		local date = os.date("%y-%m-%d-%H_%M_%S")
		local str = pace.luadata.Encode(data)

		if str ~= last_backup then
			pace.newest_backup = date
			file.Write("pac3/__backup/" .. (name == "" and name or (name .. "_")) .. date .. ".txt", str)
			last_backup = str
			pace.newest_backup_size = string.NiceSize(file.Size("pac3/__backup/" .. (name=="" and name or (name..'_')) .. date .. ".txt", "DATA"))
		end
	end
	pace.backup_notification_lines = {newest = pace.newest_backup, lines = sorted_files, notify_time = CurTime()}
end

local backup_notify_mode = CreateClientConVar("pac_backup_notification", "1", true, false, "display notification when autosaves are saved")

pac.AddHook("DrawOverlay", "backup_cursor_info", function()
	if backup_notify_mode:GetInt() == 1 or backup_notify_mode:GetInt() == 0 then return end
	if not pace then return end
	if not pace.IsFocused() then return end
	if not pace.IsActive() then return end
	if not pace.backup_notification_lines then return end
	local mx, my = input.GetCursorPos()

	local faded_a = 255*math.Clamp(2 - (CurTime() - pace.backup_notification_lines.notify_time),0,1)
	local base_y = my + 8

	surface.SetFont("BudgetLabel")
	surface.SetDrawColor(255,255,255, faded_a)
	surface.SetMaterial(Material("icon16/group_add.png"))
	surface.DrawTexturedRect(mx + 10, base_y, 16, 16)
	draw.DrawText(
		pace.newest_backup .. " " .. pace.newest_backup_size,
		"BudgetLabel",
		mx + 12 + 16, base_y,
		Color(100,255,100, faded_a)
	)

	base_y = base_y + 16
	local data = pace.backup_notification_lines
	for i,v in ipairs(data.lines) do
		surface.SetMaterial(Material("icon16/group.png"))
		surface.DrawTexturedRect(mx + 10, base_y, 16, 16)
		local this_name = string.sub(v.path, 15, #v.path - 4)
		draw.DrawText(
			this_name .. " " .. string.NiceSize(v.size),
			"BudgetLabel",
			mx + 12 + 16, base_y,
			Color(255,255,255, faded_a)
		)
		base_y = base_y + 16
	end
end)

pac.AddHook("DrawOverlay", "backup_editor_notification", function()
	if backup_notify_mode:GetInt() == 0 or backup_notify_mode:GetInt() == 2 then return end
	if not pace then return end
	if not pace.IsFocused() then return end
	if not pace.IsActive() then return end
	if not pace.backup_notification_lines then return end

	local faded_a = 255*math.Clamp(2 - (CurTime() - pace.backup_notification_lines.notify_time),0,1)
	local y = 5 + 32*math.pow(math.Clamp(0.25*(CurTime() - pace.backup_notification_lines.notify_time),0,1),0.5)
	local x = pace.Editor:IsLeft() and (pace.Editor:GetPos() + pace.Editor:GetWide()) or pace.Editor:GetPos() - 300

	surface.SetFont("BudgetLabel")
	surface.SetDrawColor(255,255,255, faded_a)
	surface.SetMaterial(Material(pace.MiscIcons.save))
	surface.DrawTexturedRect(x + 10, y, 16, 16)
	draw.DrawText(
		"autosaved! " .. pace.newest_backup .. " " .. pace.newest_backup_size,
		"BudgetLabel",
		x + 12 + 16, y,
		Color(255,255,255, faded_a)
	)
end)


local latestprop
local latest_uid
if game.SinglePlayer() then
	LocalPlayer().pac_propload_queuedparts = {}
	function pac.wearqueue(ply, ent)
		if ent:EntIndex() <= 0 then return end
		if not IsValid(ply) then return end
		if not IsValid(ent) then return end
		if not ply.pac_propload_queuedparts then return end
		if table.IsEmpty(ply.pac_propload_queuedparts) then return end
		ent:EmitSound( "buttons/button4.wav" )
		local root = ply.pac_propload_queuedparts[1]
		if root == nil then table.remove(ply.pac_propload_queuedparts,1) return end
		root.self.OwnerName = ent:EntIndex()
		latest_uid = tostring(root.self.UniqueID)
		pace.LoadPartsFromTable(root, false, false)
		table.remove(ply.pac_propload_queuedparts,1)
		latestprop = ent
		--[[if table.IsEmpty(ply.pac_propload_queuedparts) then
			net.Start("pac_demand_prop_spawn")
			net.WriteBool(GetConVar("pac_spawnmenu_props_spawn_as_parts"):GetBool())
			net.SendToServer()
		end]]
	end
	--[[net.Receive("pac_entity_created_for_singleplayer", function(len)
		local ent = net.ReadEntity()
		local ply = net.ReadEntity()
		--pac.wearqueue(LocalPlayer(), ent)
	end)]] 
	pac.AddHook("OnEntityCreated", "queue_proppacs", function( ent )
		if not ent:CreatedByMap() and LocalPlayer().pac_propload_queuedparts then
			pac.wearqueue(LocalPlayer(), ent)
		end
	end)
end


function pace.LoadParts(name, clear, override_part)
	pace.ExtendWearTracker(5)

	if not name then
		local frm = vgui.Create("DFrame")
		frm:SetTitle(L"parts")
		local pnl = pace.CreatePanel("browser", frm)

		pnl.OnLoad = function(node)
			pace.LoadParts(node.FileName, clear, override_part)
		end

		if #file.Find("pac3/sessions/*", "DATA") > 0 then
			pnl:SetDir("sessions/")
		else
			pnl:SetDir("")
		end

		pnl:Dock(FILL)

		frm:SetSize(300, 500)
		frm:MakePopup()
		frm:Center()

		local btn = vgui.Create("DButton", frm)
		btn:Dock(BOTTOM)
		btn:SetText(L"load from url")
		btn.DoClick = function()
			Derma_StringRequest(
				L"load part",
				L"pastebin urls also work!",
				"",
				function(name)
					pace.LoadParts(name, clear, override_part)
				end
			)
		end

	else
		if name ~= "autoload.txt" and not string.find(name, "pac3/__backup") then
			if file.Exists("pac3/" .. name..".txt", "DATA") then
				cookie.Set( "pac_last_loaded_outfit", name .. ".txt" )
			end
		end
		if hook.Run("PrePACLoadOutfit", name) == false then
			return
		end

		pac.dprint("loading Parts %s", name)

		if name:find("https?://") then
			local function callback(str)
				if string.find( str, "<!DOCTYPE html>" ) then
					pace.MessagePrompt("Invalid URL, .txt expected, but the website returned a HTML file. If you're using Github then use the RAW option.", "URL Failed", "OK")
					return
				end

				local data, err = pace.luadata.Decode(str)
				if not data then
					local message = string.format("Failed to load pac3 outfit from url: %s : %s\n", name, err)
					pace.MessagePrompt(message, "URL Failed", "OK")
					return
				end

				pace.LoadPartsFromTable(data, clear, override_part)
			end

			pac.HTTPGet(name, callback, function(err)
				pace.MessagePrompt(err, "HTTP Request Failed for " .. name, "OK")
			end)
		else
			name = name:gsub("%.txt", "")

			local data,err = pace.luadata.ReadFile("pac3/" .. name .. ".txt")
			local has_possible_prop_pacs = false

			if data and istable(data) then
				for i,part in pairs(data) do
					if part.self then
						if isnumber(tonumber(part.self.OwnerName)) then has_possible_prop_pacs = true end
					end
				end
			end

			--queue up prop pacs for the next prop or npc you spawn when in singleplayer
			if (auto_spawn_prop:GetInt() == 2 or (auto_spawn_prop:GetInt() == 1 and #data == 1)) and game.SinglePlayer() and has_possible_prop_pacs then
				if clear then pace.ClearParts() end

				--check all root parts from data. format: each data member is a {self, children} table of the part and the list of children
				for i,part in pairs(data) do
					local possible_prop_pac = isnumber(tonumber(part.self.OwnerName))
					if part.self.ClassName == "group" and possible_prop_pac then

						part.self.ModelTracker = part.self.ModelTracker or ""
						part.self.ClassTracker = part.self.ClassTracker or ""
						local str = ""
						if part.self.ClassTracker == "" or part.self.ClassTracker == "" then
							str = "But the class or model is unknown"
						else
							str = part.self.ClassTracker .. " : " .. part.self.ModelTracker
						end
						--notify which model / entity should be spawned with the class tracker
						notification.AddLegacy( "You have queued a pac part (" .. i .. ":" .. part.self.Name .. ") for a prop or NPC! " .. str, NOTIFY_HINT, 10 )
						LocalPlayer().pac_propload_queuedparts = LocalPlayer().pac_propload_queuedparts or {}
						LocalPlayer().pac_propload_queuedparts[i] = part
						net.Start("pac_demand_prop_spawn")
						net.WriteBool(true)
						net.SendToServer()

					else
						pace.LoadPartsFromTable(part, false, false)
					end
				end

			else
				if name == "autoload" and (not data or not next(data)) then
					local err
					data,err = pace.luadata.ReadFile("pac3/sessions/" .. name .. ".txt",nil,true)
					if not data then
						if err then
							pace.MessagePrompt(err, "Autoload failed", "OK")
						end
						return
					end
				elseif not data then
					pace.MessagePrompt(err, ("Decoding %s failed"):format(name), "OK")
					return
				end

				pace.LoadPartsFromTable(data, clear, override_part)
			end
		end
	end
end

concommand.Add("pac_load_url", function(ply, cmd, args)
	if not args[1] then return print("[PAC3] No URL specified") end
	local url = args[1]:Trim()
	if not url:find("https?://") then return print("[PAC3] Invalid URL specified") end
	pac.Message("Loading specified URL")
	if args[2] == nil then args[2] = '1' end
	pace.LoadParts(url, tobool(args[2]))
end)

function pace.LoadPartsFromTable(data, clear, override_part)
	pace.ExtendWearTracker(5)
	if pace.use_current_part_for_saveload and pace.current_part:IsValid() then
		override_part = pace.current_part
	end

	if clear then
		pace.ClearParts()
		pace.ClearUndo()
	else
		--pace.RecordUndoHistory()
	end

	local partsLoaded = {}

	local copy_id = tostring(data)

	if data.self then
		local part

		if override_part then
			part = override_part
			part:SetTable(data)
		else
			part = override_part or pac.CreatePart(data.self.ClassName, nil, data, pac.GetPartFromUniqueID(pac.Hash(pac.LocalPlayer), data.self.UniqueID):IsValid() and copy_id)
		end

		table.insert(partsLoaded, part)
	else
		data = pace.FixBadGrouping(data)
		data = pace.FixUniqueIDs(data)

		for key, tbl in pairs(data) do
			local part = pac.CreatePart(tbl.self.ClassName, nil, tbl, pac.GetPartFromUniqueID(pac.Hash(pac.LocalPlayer), tbl.self.UniqueID):IsValid() and copy_id)
			table.insert(partsLoaded, part)
		end
	end

	pace.RefreshTree(true)

	for i, part in ipairs(partsLoaded) do
		part:CallRecursive("OnOutfitLoaded")
		part:CallRecursive("PostApplyFixes")
	end

	pac.LocalPlayer.pac_fix_show_from_render = SysTime() + 1

	pace.RecordUndoHistory()

	if IsValid(pace.mirroring_display_panel) then
		pace.mirroring_display_already_active = true
		pac.MirrorMyPac()
		pac.ApplyPACMirror()
	end
end

local function add_files(tbl, dir, cheap)
	local files, folders = file.Find("pac3/" .. dir .. "/*", "DATA")

	if folders then
		for key, folder in pairs(folders) do
			if folder == "__backup" or folder == "objcache" or folder == "__animations" or folder == "__backup_save" then continue end
			tbl[folder] = {}
			add_files(tbl[folder], dir .. "/" .. folder, cheap)
		end
	end

	if files then
		for i, name in pairs(files) do
			if name:find("%.txt") then
				local path = "pac3/" .. dir .. "/" .. name

				if file.Exists(path, "DATA") then
					local data = {}
						data.Name = name:gsub("%.txt", "")
						data.FileName = name
						data.Size = string.NiceSize(file.Size(path, "DATA"))
						local time = file.Time(path, "DATA")
						data.LastModified = os.date("%m/%d/%Y %H:%M", time)
						data.Time = file.Time(path, "DATA")
						data.Path = path
						data.RelativePath = (dir .. "/" .. data.Name):sub(2)

					if not cheap then
						local dat,err=pace.luadata.ReadFile(path)
							data.Content = dat
						if dat then
							table.insert(tbl, data)
						else
							pac.dprint(("Decoding %s failed: %s\n"):format(path,err))
							chat.AddText(("Could not load: %s\n"):format(path))
						end
					else
						table.insert(tbl, data)
					end
				end
			end
		end
	end

	table.sort(tbl, function(a,b)
		if a.Time and b.Time then
			return a.Name < b.Name
		end

		return true
	end)
end

function pace.GetSavedParts(dir)
	if pace.CachedFiles then
		return pace.CachedFiles
	end

	local out = {}

	add_files(out, dir or "", false)

	pace.CachedFiles = out

	return out
end

function pace.GetSavedOutfits(dir)
	
	local out = {}

	add_files(out, dir or "", true)

	return out
end


local function get_name(part)
	local name = part.Name or ""

	if name == "" then
		name = part.ClassName .. " (no name)"
		if (part.ClassName == "model2" or part.ClassName == "entity2") and part.Model ~= "" then
			name = string.GetFileFromFilename(part.Model)
		elseif part.ClassName == "event" then
			name = "event : " .. part.Event .. " " .. part.Arguments
		end
	end
	return name
end
function pac.GetPartIcon(part)
	if part.ClassName == "model2" or part.ClassName == "entity2" then
		if part.Model ~= "" then
			if file.Exists("materials/spawnicons/"..string.gsub(part.Model, ".mdl", "")..".png", "GAME") then
				return "materials/spawnicons/"..string.gsub(part.Model, ".mdl", "")..".png"
			end
		end
	elseif part.ClassName == "event" then
		return part.Invert and "icon16/clock_red.png" or "icon16/clock.png"
	end
	return pac.registered_parts[part.ClassName] and pac.registered_parts[part.ClassName].Icon
end

local function install_hovers(self, parentsubmenu, delay, hovered_complete_func)
	function self:Think()
		if self:IsHovered() or self.completed_hover then
			if not self.hovering_start then
				if not self.completed_hover then
					self.hovering_start = CurTime()
				end
			end
			self.hovering_start = self.hovering_start or CurTime()
			if (CurTime() > self.hovering_start + delay) or input.IsShiftDown() then
				if not self.completed_hover then
					if hovered_complete_func then hovered_complete_func() end
					if not parentsubmenu.was_compacted and compact_mode:GetBool() then
						parentsubmenu:MoveBy(-math.max(parentsubmenu:GetParent():GetWide(), 75) + 75,0,0.3)
					end
					self.compacted = true
					self.completed_hover = true
					self.hovering_start = nil
				end
			end
		else self.hovering_start = nil self.was_compacted = self.compacted end
	end
end

local function populate_part(menu, part, override_part, clear)
	local name = get_name(part.self)
	local icon = pac.GetPartIcon(part.self)

	if #part.children > 0 then
		local menu, pnl = menu:AddSubMenu("[" .. #part.children .."] " .. name, function()
			pace.LoadPartsFromTable(part, nil, override_part)
		end)
		pnl:SetImage(icon)
		if part.self.Notes ~= "" then
			pnl:SetTooltip(part.self.Notes)
		else
			pnl:SetTooltip("<" .. #part.children .. " children>")
		end

		menu:SetDeleteSelf(false)
		local old = menu.Open
		menu.Open = function(...)
			if compact_mode:GetBool() then
				install_hovers(pnl, menu, 0.2)
			end
			if not menu.pac_opened then
				for key, part in pairs(part.children) do
					populate_part(menu, part, override_part, clear)
				end
				menu.pac_opened = true
			end

			return old(...)
		end
		local old2 = menu.Close menu.Close = function(...) menu.was_compacted = menu.compacted return old2(...) end
	else
		local pnl = menu:AddOption(name, function()
			pace.LoadPartsFromTable(part, clear, override_part)
		end)
		pnl:SetImage(icon)
		if part.self.Notes ~= "" then
			pnl:SetTooltip(part.self.Notes)
		else
			pnl:SetTooltip("")
		end
	end
end

local function populate_parts(menu, tbl, override_part, clear)
	for key, data in pairs(tbl) do
		if not data.Path then
			local menu, pnl = menu:AddSubMenu(key, function()end, data)
			pnl:SetImage(pace.MiscIcons.load)
			menu:SetDeleteSelf(false)
			local old = menu.Open
			menu.Open = function(...)
				if compact_mode:GetBool() then

						menu:MoveBy(-math.max(menu:GetParent():GetWide(), 75) + 75,0,1,0.3)

					menu.was_compacted = true
				end
				if not menu.pac_opened then
					populate_parts(menu, data, override_part, clear)
					menu.pac_opened = true
				end
				return old(...)
			end
			local old2 = menu.Close menu.Close = function(...) menu.was_compacted = menu.compacted return old2(...) end
		else
			local icon = pace.MiscIcons.outfit
			local parts = data.Content

			if parts.self then
				icon = parts.self.Icon
				parts = {parts}
			end

			local outfit, pnl = menu:AddSubMenu(data.Name, function()
				pace.LoadParts(data.RelativePath .. ".txt", clear, override_part)
			end)
			pnl:SetImage(icon)
			outfit:SetDeleteSelf(false)

			local old = outfit.Open
			outfit.Open = function(...)
				if not outfit.pac_opened then
					for key, part in pairs(parts) do
						populate_part(outfit, part, override_part, clear)
					end
					outfit.pac_opened = true
				end

				return old(...)
			end
		end
	end
end

--override_part is the relative path
local function populate_outfits(menu, tbl, dir, override_part, clear, for_save_menu)
	if for_save_menu then
		menu:AddOption(L"new file", function() pace.SaveParts(nil, string.sub(dir,6) .. "/") end)
		:SetImage("icon16/page_add.png")

		menu:AddOption(L"new directory", function()
			Derma_StringRequest(
				L"new directory",
				L"name:",
				"",

				function(name)
					file.CreateDir(dir .. "/" .. name)
					pace.RefreshFiles()
				end
			)
		end)
		:SetImage("icon16/folder_add.png")

		menu:AddOption(L"to clipboard", function()
			local data = {}
			for key, part in pairs(pac.GetLocalParts()) do
				if not part:HasParent() and part:GetShowInEditor() then
					table.insert(data, part:ToSaveTable())
				end
			end
			SetClipboardText(pace.luadata.Encode(data):sub(1, -1))
		end)
		:SetImage(pace.MiscIcons.copy)

		menu:AddSpacer()
	end
	
	local files = {}
	local folders = {}
	local sorted_tbl = {}
	for k,v in pairs(tbl) do
		if isstring(k) then
			folders[k] = v
		elseif isnumber(k) then
			files[k] = v
		end
	end

	for k,v in ipairs(files) do table.insert(sorted_tbl, {k,v}) end
	for k,v in SortedPairs(folders) do table.insert(sorted_tbl, {k,v}) end

	--for key, data in pairs(tbl) do
	for i, tab in ipairs(sorted_tbl) do
		local key = tab[1]
		local data = tab[2]
		if not data.Path then
			local menu, pnl = menu:AddSubMenu(key, function() end, data)
			--that's a folder submenu
			pnl:SetImage(pace.MiscIcons.load)
			menu:SetDeleteSelf(false)
			local old = menu.Open
			menu.Open = function(...)
				if compact_mode:GetBool() then
					install_hovers(pnl, menu, 0.2)
				end
				if not menu.pac_opened then
					populate_outfits(menu, data, dir .. "/" .. key, override_part, clear, for_save_menu) --that's a sub element, usually pac files but it's recursive it can be a folder
					menu.pac_opened = true
				end

				return old(...)
			end
		else
			if not for_save_menu then
				local icon = pace.MiscIcons.outfit
				local outfit, pnl = menu:AddSubMenu(data.Name, function()
					pace.LoadParts(data.RelativePath .. ".txt", clear, override_part)
				end)
				pnl:SetImage(icon)
				outfit:SetDeleteSelf(false)
				install_hovers(pnl, outfit, 0.5, function()
					if not outfit.built_parts then
						local dat,err=pace.luadata.ReadFile(data.Path)
						if dat then
							data.Content = dat
							local parts = data.Content
							for key, part in pairs(parts) do
								if part.self then
									populate_part(outfit, part, override_part, clear)
									outfit.built_parts = true
								end
							end
						else
							pac.dprint(("Decoding %s failed: %s\n"):format(path,err))
							chat.AddText(("Could not load: %s\n"):format(path))
						end
					end
				end, compact_mode:GetBool())
			else
				local icon = pace.MiscIcons.outfit
				local outfit, pnl = menu:AddSubMenu(data.Name, function()
					pace.SaveParts(nil, data.RelativePath, override_part)
				end)
				pnl:SetImage(icon)
				outfit:SetDeleteSelf(false)
				outfit:AddOption(L"delete", function()
					Derma_Query("Are you sure you want to delete outfit " .. data.RelativePath .. "? This cannot be undone!", "Deletion",
					"delete", function() file.Delete("pac3/" .. data.RelativePath .. ".txt", "DATA") pace.RefreshFiles() end,
					"cancel")
				end):SetImage(pace.MiscIcons.clear)
			end
			
		end
	end
end

function pace.AddOneDirectorySavedPartsToMenu(menu, subdir, nicename)
	if not subdir then return end
	local subdir_head = subdir .. "/"

	local exp_submenu, pnl = menu:AddSubMenu(L""..subdir)
	pnl:SetImage(pace.MiscIcons.load)
	exp_submenu:SetDeleteSelf(false)
	subdir = "pac3/" .. subdir
	if nicename then exp_submenu:SetText(nicename) end

	add_expensive_submenu_load(pnl, function(subdir)
		local files = file.Find(subdir.."/*", "DATA")
		local files2 = {}
		--PrintTable(files)
		for i, filename in ipairs(files) do
			table.insert(files2, {filename, file.Time(subdir .. filename, "DATA")})
		end

		table.sort(files2, function(a, b)
			return a[2] > b[2]
		end)

		for _, data in pairs(files2) do
			local name = data[1]
			local full_path = subdir .. "/" .. name
			--print(full_path)
			local friendly_name = name .. " " .. string.NiceSize(file.Size(full_path, "DATA"))
			exp_submenu:AddOption(friendly_name, function() pace.LoadParts(subdir_head .. name, true) end)
			:SetImage(pace.MiscIcons.outfit)
		end
	end, subdir)
end

function pace.AddSavedPartsToMenu(menu, clear, override_part)

	menu:SetDeleteSelf(false)

	--outfit searching
	local basepnl = menu:AddOption(L"Search", function()
		local outfit_searcher_base = vgui.Create("EditablePanel")
		outfit_searcher_base:SetSize(600, 800)
		outfit_searcher_base:MakePopup()
		outfit_searcher_base:SetPos(menu:GetX(), menu:GetY())
		local edit = outfit_searcher_base:Add("DTextEntry")
		edit:Dock(TOP)
		edit:SetTall(20)
		edit:RequestFocus()
		edit:SetUpdateOnType(true)
		local result = outfit_searcher_base:Add("DScrollPanel")
		result:Dock(FILL)

		local results = {}

		local function Match(dir, filename, keywords)
			local full_match = false
			filename = string.lower(filename)
			dir = string.lower(dir)
			for i, keyword in ipairs(string.Split(keywords, " ")) do
				local dirmatch = string.find(dir, string.lower(keyword)) ~= nil
				local filematch = string.find(filename, string.lower(keyword)) ~= nil
				if dirmatch or filematch then
					full_match = true
				elseif (not filematch and not filematch) then
					return false
				end
			end
			return full_match
		end

		local function add_recursive(basetbl, dir)
			if dir == "pac3/__animations" then return end
			local files, dirs = file.Find(dir .. "/*", "DATA")
			for i, filename in ipairs(files) do
				if string.GetExtensionFromFilename(filename) == "txt" then
					table.insert(basetbl, {filename = filename, dir = dir:sub(6)})
				end
			end

			for i, dir2 in ipairs(dirs) do
				add_recursive(basetbl, dir .. "/" .. dir2)
			end
		end

		function edit:OnValueChange(str)
			result:Clear()
			results = {}
			local all_files = {}
			add_recursive(all_files, "pac3")
			for i,v in ipairs(all_files) do
				if Match(v.dir, v.filename, str) then
					--print(i, v.filename, v.dir)
					table.insert(results, v)
					local line = result:Add("DButton")
					line:SetText("")
					line:SetTall(20)
					local btn = line:Add("DImageButton")
					btn:SetSize(16, 16)
					btn:SetPos(4,0)
					btn:SetMouseInputEnabled(false)
					btn:SetIcon("icon16/group.png")
					local label = line:Add("DLabel")
					label:SetTextColor(label:GetSkin().Colours.Category.Line.Text)
					label:SetText("[" .. i .. "] " .. v.dir .. "/" .. v.filename)
					line.label = label
					
					label:SetMouseInputEnabled(false)
					label:SetSize(584,16)
					label:SetPos(24,0)

					line.DoClick = function()
						pace.LoadParts(v.dir .. "/" .. v.filename .. ".txt", clear, override_part)
						outfit_searcher_base:Remove()
					end
					v.line = line

					line:Dock(TOP)
				end
			end
		end

		function edit:OnEnter()
			if results[1] then
				results[1].line:DoClick()
			end
		end
		edit:OnValueChange("")

		pac.AddHook("VGUIMousePressed", "search_outfits_menu", function(pnl, code)
			if not IsValid(outfit_searcher_base) then pac.RemoveHook("VGUIMousePressed", "search_outfits_menu") return end
			if code == MOUSE_LEFT or code == MOUSE_RIGHT then
				if not outfit_searcher_base:IsOurChild(pnl) then
					outfit_searcher_base:Remove()
					pac.RemoveHook("VGUIMousePressed", "search_outfits_menu")
				end
			end
		end)
	end) basepnl:SetImage("icon16/zoom.png")


	menu:AddOption(L"load from url", function()
		Derma_StringRequest(
			L"load parts",
			L"Some indirect urls from on pastebin, dropbox, github, etc are handled automatically. Pasting the outfit's file contents into the input field will also work.",
			"",

			function(name)
				pace.LoadParts(name, clear, override_part)
			end
		)
	end):SetImage(pace.MiscIcons.url)

	menu:AddOption(L"load from clipboard", function()
		pace.MultilineStringRequest(
			L"load parts from clipboard",
			L"Paste the outfits content here.",
			"",

			function(name)
				local data,err = pace.luadata.Decode(name)
				if data then
					pace.LoadPartsFromTable(data, clear, override_part)
				end
			end
		)
	end):SetImage(pace.MiscIcons.paste)

	if not override_part and pace.example_outfits then
		local examples, pnl = menu:AddSubMenu(L"examples")
		pnl:SetImage(pace.MiscIcons.help)
		examples:SetDeleteSelf(false)

		local sorted = {}
		for k,v in pairs(pace.example_outfits) do sorted[#sorted + 1] = {k = k, v = v} end
		table.sort(sorted, function(a, b) return a.k < b.k end)

		for _, data in pairs(sorted) do
			examples:AddOption(data.k, function() pace.LoadPartsFromTable(data.v) end)
			:SetImage(pace.MiscIcons.outfit)
		end
	end

	menu:AddCVar("lazy mode", "pac_load_lazymode", "1", "0", function() menu:Clear() pace.AddSavedPartsToMenu(menu, clear, override_part) end)
	menu:AddCVar("compact mode", "pac_load_compactmode", "1", "0", function() menu:Clear() pace.AddSavedPartsToMenu(menu, clear, override_part) end)

	menu:AddSpacer()
	local tbl = {}
	if lazy_mode:GetBool() then
		tbl = pace.GetSavedOutfits()
		populate_outfits(menu, tbl, "pac3", override_part, clear)
	else
		tbl = pace.GetSavedParts()
		populate_parts(menu, tbl, override_part, clear)
	end

	menu:AddSpacer()

	local backups, pnl = menu:AddSubMenu(L"backups")
	pnl:SetImage(pace.MiscIcons.clone)
	backups:SetDeleteSelf(false)

	local subdir = "pac3/__backup/*"

	add_expensive_submenu_load(pnl, function(subdir)

		local files = file.Find("pac3/__backup/*", "DATA")
		local files2 = {}

		for i, filename in ipairs(files) do
			table.insert(files2, {filename, file.Time("pac3/__backup/" .. filename, "DATA")})
		end

		table.sort(files2, function(a, b)
			return a[2] > b[2]
		end)

		for _, data in pairs(files2) do
			local name = data[1]
			local full_path = "pac3/__backup/" .. name
			local friendly_name = os.date("%m/%d/%Y %H:%M:%S ", file.Time(full_path, "DATA")) .. string.NiceSize(file.Size(full_path, "DATA"))
			backups:AddOption(friendly_name, function() pace.LoadParts("__backup/" .. name, true) end)
			:SetImage(pace.MiscIcons.outfit)
		end
	end, subdir)

	local backups, pnl = menu:AddSubMenu(L"outfit backups")
	pnl:SetImage(pace.MiscIcons.clone)
	backups:SetDeleteSelf(false)

	subdir = "pac3/__backup_save/*"
	add_expensive_submenu_load(pnl, function()
		local files = file.Find(subdir, "DATA")
		local files2 = {}

		for i, filename in ipairs(files) do
			table.insert(files2, {filename, file.Time("pac3/__backup_save/" .. filename, "DATA")})
		end

		table.sort(files2, function(a, b)
			return a[2] > b[2]
		end)

		for _, data in pairs(files2) do
			local name = data[1]
			local stamp = data[2]
			local nicename = name
			local date = os.date("_%y-%m-%d-%H_%M_%S", stamp)

			if nicename:find(date, 1, true) then
				nicename = nicename:Replace(date, os.date(" %m/%d/%Y %H:%M:%S", stamp))
			end

			backups:AddOption(nicename:Replace(".txt", "") .. " (" .. string.NiceSize(file.Size("pac3/__backup_save/" .. name, "DATA")) .. ")",
				function()
					pace.LoadParts("__backup_save/" .. name, true)
				end)
			:SetImage(pace.MiscIcons.outfit)
		end
	end, subdir)
end

concommand.Add("pac_open_load_menu", function()
	local menu = DermaMenu()
	menu:SetPos(ScrW()/3,100)
	gui.EnableScreenClicker(true)
	pace.AddSavedPartsToMenu(menu, true)
	menu:SetDeleteSelf(true)
	menu.OnRemove = function() gui.EnableScreenClicker(false) end
end)

local function populate_parts(menu, tbl, dir, override_part)
	dir = dir or ""
	menu:AddOption(L"new file", function() pace.SaveParts(nil, dir .. "/", override_part) end)
	:SetImage("icon16/page_add.png")

	menu:AddOption(L"new directory", function()
		Derma_StringRequest(
			L"new directory",
			L"name:",
			"",

			function(name)
				file.CreateDir("pac3/" .. dir .. "/" .. name)
				pace.RefreshFiles()
			end
		)
	end)
	:SetImage("icon16/folder_add.png")

	menu:AddOption(L"to clipboard", function()
		local data = {}
		for key, part in pairs(pac.GetLocalParts()) do
			if not part:HasParent() and part:GetShowInEditor() then
				table.insert(data, part:ToSaveTable())
			end
		end
		local str = pace.luadata.Encode(data):sub(1, -1)
		SetClipboardText(str)
	end)
	:SetImage(pace.MiscIcons.copy)

	menu:AddSpacer()
	local files = {}
	local folders = {}
	local sorted_tbl = {}
	for k,v in pairs(tbl) do
		if isstring(k) then
			folders[k] = v
		elseif isnumber(k) then
			files[k] = v
		end
	end

	for k,v in ipairs(files) do table.insert(sorted_tbl, {k,v}) end
	for k,v in SortedPairs(folders) do table.insert(sorted_tbl, {k,v}) end

	--for key, data in pairs(tbl) do
	for i, tab in ipairs(sorted_tbl) do
		local key = tab[1]
		local data = tab[2]
		if not data.Path then
			local menu, pnl = menu:AddSubMenu(key, function()end, data)
			pnl:SetImage(pace.MiscIcons.load)
			menu:SetDeleteSelf(false)
			populate_parts(menu, data, dir .. "/" .. key, override_part)
		else
			local parts = data.Content

			if parts[1] then
				local menu, pnl = menu:AddSubMenu(data.Name, function() pace.SaveParts(nil, data.RelativePath, override_part) end)
				menu:SetDeleteSelf(false)
				pnl:SetImage(pace.MiscIcons.outfit)

				menu:AddOption(L"delete", function()
					Derma_Query("Are you sure you want to delete outfit " .. data.RelativePath .. "? This cannot be undone!", "Deletion",
					"delete", function() file.Delete("pac3/" .. data.RelativePath .. ".txt", "DATA") pace.RefreshFiles() end,
					"cancel")
				end):SetImage(pace.MiscIcons.clear)

				pnl:SetImage(pace.MiscIcons.outfit)
			elseif parts.self then
				menu:AddOption(data.Name, function() pace.SaveParts(nil, data.RelativePath, override_part)  end)
				:SetImage(parts.self.Icon)
			end
		end
	end

	if dir ~= "" then
		menu:AddSpacer()

		menu:AddOption(L"delete directory", function()
			Derma_Query(
				L"Are you sure you want to delete data/pac3" .. dir .. "/* and all its files?\nThis cannot be undone!",
				L"delete directory",

				L"yes", function()
					local function delete_directory(dir)
						local files, folders = file.Find(dir .. "*", "DATA")

						for k,v in ipairs(files) do
							file.Delete(dir .. v)
						end

						for k,v in ipairs(folders) do
							delete_directory(dir .. v .. "/")
						end

						if file.Find(dir .. "*", "DATA")[1] then
							Derma_Message("Cannot remove the directory.\nMaybe it contains hidden files?", "unable to remove directory", L"ok")
						else
							file.Delete(dir)
						end
					end
					delete_directory("pac3/" .. dir .. "/")
					pace.RefreshFiles()
				end,

				L"no", function()

				end
			)
		end):SetImage("icon16/folder_delete.png")
	end
end

function pace.AddSaveMenuToMenu(menu, override_part)
	menu:SetDeleteSelf(false)

	if not override_part then
		menu:AddOption(L"auto load (your spawn outfit)", function()
			pace.SaveParts("autoload", nil, override_part)
			pace.RefreshFiles()
		end)
		:SetImage(pace.MiscIcons.autoload)
		menu:AddSpacer()
	end

	local tbl = pace.GetSavedOutfits()
	populate_outfits(menu, tbl, "pac3", override_part, true, true)
end

-- this fixes parts that are using the same uniqueid as other parts because of some bugs in older versions
function pace.FixUniqueIDs(data)
	local ids = {}

	local function iterate(part)
		ids[part.self.UniqueID] = ids[part.self.UniqueID] or {}

		table.insert(ids[part.self.UniqueID], part)

		for key, part in pairs(part.children) do
			iterate(part)
		end
	end

	for key, part in pairs(data) do
		iterate(part)
	end

	for key, val in pairs(ids) do
		if #val > 1 then
			for key, part in pairs(val) do
				pac.dprint("Part (%s using model %s) named %q has %i other parts with the same unique id. Fixing!", part.self.ClassName, part.self.Name, part.self.Model or "", #val)
				part.self.UniqueID = pac.Hash()
			end
		end
	end

	return data
end

-- this is for fixing parts that are not in a group

function pace.FixBadGrouping(data)
	local parts = {}
	local other = {}

	for key, part in pairs(data) do
		if part.self.ClassName ~= "group" then
			table.insert(parts, part)
		else
			table.insert(other, part)
		end
	end

	if #parts > 0 then
		local out = {
			{
				["self"] = {
					["EditorExpand"] = true,
					["ClassName"] = "group",
					["UniqueID"] = pac.Hash(),
					["Name"] = "automatic group",
				},

				["children"] = parts,
			},
		}

		for k,v in pairs(other) do
			table.insert(out, v)
		end

		return out
	end

	return data
end
