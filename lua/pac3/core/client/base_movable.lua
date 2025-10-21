local pac = pac
local Vector = Vector
local Angle = Angle
local NULL = NULL
local Matrix = Matrix

local default = "0"
if game.SinglePlayer() then default = "1" end
local allow_NL = CreateConVar("pac_sv_nearest_life", default, {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Enables nearest_life aimparts and bones, abusable for aimbot-type setups (which would already be possible with CS lua)")
local NL_allow_sampling_anywhere = CreateConVar("pac_sv_nearest_life_allow_sampling_from_parts", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Restricts nearest_life aimparts and bones search to the player itself to prevent sampling from arbitrary positions\n0=sampling can only start from the player itself")
local allow_NL_bone = CreateConVar("pac_sv_nearest_life_allow_bones", default, {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Restricts nearest_life bones, preventing placement on external entities' position")
local NL_allow_target_players = CreateConVar("pac_sv_nearest_life_allow_targeting_players", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Restricts nearest_life aimparts and bones to forbid targeting players\n0=no target players")
local NL_max_distance = CreateConVar("pac_sv_nearest_life_max_distance", "5000", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Restricts the radius for nearest_life aimparts and bones")

local BUILDER, PART = pac.PartTemplate("base")

PART.ClassName = "base_movable"
PART.BaseName = PART.ClassName

BUILDER
	:StartStorableVars()
		:SetPropertyGroup("orientation")
			:GetSet("Bone", "head")
			:GetSet("Position", Vector(0,0,0))
			:GetSet("Angles", Angle(0,0,0))
			:GetSet("EyeAngles", false)
			:GetSet("PositionOffset", Vector(0,0,0))
			:GetSet("AngleOffset", Angle(0,0,0))
			:GetSetPart("AimPart")
			:GetSet("AimPartName", "", {enums = {
				["local eyes"] = "LOCALEYES",
				["player eyes"] = "PLAYEREYES",
				["local eyes yaw"] = "LOCALEYES_YAW",
				["local eyes pitch"] = "LOCALEYES_PITCH",
				["nearest npc or player (torso-level)"] = "NEAREST_LIFE",
				["nearest npc or player (entity position)"] = "NEAREST_LIFE_POS",
				["nearest npc or player (yaw only)"] = "NEAREST_LIFE_YAW"
			}})
			:GetSetPart("Parent")
		:SetPropertyGroup("advanced")
			:GetSet("NearestLifeIndex", 1, {description = "specialized setting for NPC/player target tracking.\nwhen 'nearest life' aimparts and bones search entities, they are sorted by distance\nthis selects which one will be used, if it exists\nOtherwise there are fallback options: hide, get the furthest, back to self\nIf it's 0, it'll go to self (parent owner)", editor_onchange = function(self, val) return math.Clamp(math.floor(val),0,50) end})
			:GetSet("NearestLifeFreeze", false, {description = "specialized setting for NPC/player target tracking.\nwhen 'nearest life' aimparts and bones search entities, they are sorted by distance\nthis stops refreshes, allowing a stable target selection."})
			:GetSet("AimPartNameStrength", 1)
			:GetSet("AimPartStrength", 1)
	:EndStorableVars()

do -- bones
	function PART:SetBone(val)
		self.Bone = val
		pac.ResetBoneCache(self:GetOwner())
		if (val == "camera" or val == "player_eyes") and pac.LocalPlayer == self:GetPlayerOwner() then
			self:SetWarning("WARNING. If you're using the camera bone for screen effects, please either:\n\na) use the viewed_by_owner event to show this part only for yourself, or\n\nb) properly implement a fading system using a part_distance-based proxy\ne.g. clamp(1 - part_distance(\"head_position\")/400,0,1)\nwhere you have a part named head_position on your own player instead of on the camera bone")
		end
		self.nearest_life_bone_params = nil
		if pac.StringFind(val, "NEAREST_LIFE") then
			if not allow_NL:GetBool() then self:SetWarning("nearest_life isn't allowed in this server\npac_sv_nearest_life") return end
			if not allow_NL_bone:GetBool() then self:SetWarning("nearest_life bones aren't allowed in this server\npac_sv_nearest_life_allow_bones") return end
			self.nearest_life_bone_params = pac.ParseNearestLifeString(self, val)
		end
	end

	function PART:GetBonePosition()
		local parent = self:GetParent()
		if parent:IsValid() then
			if parent.ClassName == "jiggle" or parent.ClassName == "interpolated_multibone" then
				return parent.pos, parent.ang
			elseif
				not parent.is_model_part and
				not parent.is_entity_part and
				not parent.is_bone_part and
				not self.is_bone_part and
				parent.WorldMatrix
			then
				return parent:GetWorldPosition(), parent:GetWorldAngles()
			end
		end

		local owner = self:GetParentOwner()
		if owner:IsValid() then
			-- if there is no parent, default to owner bones
			pac.bone_requesting_part = self
			return pac.GetBonePosAng(owner, self.BoneOverride or self.Bone)
		end

		return Vector(), Angle()
	end

	function PART:GetBoneMatrix()
		local parent = self:GetParent()
		if IsValid(parent) then
			if parent.ClassName == "jiggle" or parent.ClassName == "interpolated_multibone" then
				local bone_matrix = Matrix()
				if parent.pos then
					bone_matrix:SetTranslation(parent.pos)
					bone_matrix:SetAngles(parent.ang)
				end
				return bone_matrix
			elseif
				not parent.is_model_part and
				not parent.is_entity_part and
				not parent.is_bone_part and
				not self.is_bone_part and
				parent.WorldMatrix
			then
				return parent.WorldMatrix
			end
		end

		local bone_matrix = Matrix()
		local owner = self:GetParentOwner()
		if owner:IsValid() then
			-- if there is no parent, default to owner bones
			pac.bone_requesting_part = self
			local pos, ang = pac.GetBonePosAng(owner, self.BoneOverride or self.Bone)
			bone_matrix:SetTranslation(pos)
			bone_matrix:SetAngles(ang)
		end

		return bone_matrix
	end

	function PART:GetModelBones()
		return pac.GetModelBones(self:GetOwner())
	end

	function PART:GetModelBoneIndex()
		local bones = self:GetModelBones()
		local owner = self:GetOwner()
		if not owner:IsValid() then return end

		local name = self.Bone

		if bones[name] and not bones[name].is_special then
			return owner:LookupBone(bones[name].real)
		end

		return nil
	end
end

function PART:BuildWorldMatrix(with_offsets)
	local local_matrix = Matrix()
	local_matrix:SetTranslation(self.Position)
	local_matrix:SetAngles(self.Angles)

	local m = self:GetBoneMatrix() * local_matrix

	m:SetAngles(self:CalcAngles(m:GetAngles(), m:GetTranslation()))

	if with_offsets then
		m:Translate(self.PositionOffset)
		m:Rotate(self.AngleOffset)
	end

	return m
end

function PART:GetWorldMatrixWithoutOffsets()
	-- this is only used by the editor, no need to cache
	return self:BuildWorldMatrix(false)
end

function PART:GetWorldMatrix()
	if not self.WorldMatrix or pac.FrameNumber ~= self.last_framenumber then
		self.last_framenumber = pac.FrameNumber
		self.WorldMatrix = self:BuildWorldMatrix(true)
	end

	return self.WorldMatrix
end

function PART:GetWorldAngles()
	return self:GetWorldMatrix():GetAngles()
end

function PART:GetWorldPosition()
	return self:GetWorldMatrix():GetTranslation()
end

function PART:GetDrawPosition()
	return self:GetWorldPosition(), self:GetWorldAngles()
end


function PART:GetOrFindCachedPart(uid_or_name)
	local part = nil
	self.erroring_cached_parts = {}
	self.found_cached_parts = self.found_cached_parts or {}
	if self.found_cached_parts[uid_or_name] then self.erroring_cached_parts[uid_or_name] = nil return self.found_cached_parts[uid_or_name] end
	if self.erroring_cached_parts[uid_or_name] then return end

	local owner = self:GetPlayerOwner()
	part = pac.GetPartFromUniqueID(pac.Hash(owner), uid_or_name) or pac.FindPartByPartialUniqueID(pac.Hash(owner), uid_or_name)
	if not part:IsValid() then
		part = pac.FindPartByName(pac.Hash(owner), uid_or_name, self)
	else
		self.found_cached_parts[uid_or_name] = part
		return part
	end
	if not part:IsValid() then
		self.erroring_cached_parts[uid_or_name] = true
	else
		self.found_cached_parts[uid_or_name] = part
		return part
	end
	return part
end
do -- nearest life stuff

	function pac.NLAllowed(ply)
		--conditions
		--cvar allowed
		if not allow_NL:GetBool() then return false end
		--players can only run so many NL searches per frame
		if pac.NL_calls_left[ply] == 0 then return false end
		return true
	end

	function pac.FindNearestLifeEntity(part, tbl, wpos, parent)
		if not part then return end
		if not tbl then return end

		--rate limit
		local ply = part:GetPlayerOwner()
		--optimization
		if tbl.shared_list_partid then
			local shared_part = part:GetOrFindCachedPart(tbl.shared_list_partid)
			if not shared_part then return end
			tbl.shared_part = shared_part
			local tbl2 = shared_part.nearest_life_params or shared_part.nearest_life_bone_params
			if tbl2 then
				tbl.distance_sort_list = tbl2.distance_sort_list
				tbl.request_reindex = tbl2.request_reindex
			else
				return
			end
		else
			pac.NL_calls_left[ply] = pac.NL_calls_left[ply] - 1
		end

		local allowed = pac.NLAllowed(ply)
		if not allowed then return end
		if part:IsHidden() then
			if tbl.positioning_fallback ~= "HIDE" then return end
		end

		if not NL_allow_sampling_anywhere:GetBool() then tbl.force_self = true end
		if tbl.distance > NL_max_distance:GetInt() then tbl.distance = NL_max_distance:GetInt() end
		if not NL_allow_target_players:GetBool() then tbl.no_players = true end

		if tbl.request_reindex and tbl.distance_sort_list and tbl.distance_sort_list[tbl.NearestLifeIndex] then
			local ent = tbl.distance_sort_list[tbl.NearestLifeIndex][1]
			if IsValid(ent) then
				part.nearest_life_ent = ent
				tbl.request_reindex = false
			end
		end

		local player_owner = part:GetPlayerOwner()
		if part.freeze_NL or part.NearestLifeFreeze and IsValid(part.nearest_life_ent) then
			if tbl.no_self and part.nearest_life_ent == player_owner then
				part.nearest_life_ent = nil
				return nil
			end
			return part.nearest_life_ent
		end

		tbl.distance = math.min(tbl.distance or NL_max_distance:GetInt())

		if tbl.force_self then wpos = part:GetPlayerOwner():GetPos() end
		if parent then
			wpos = part:GetParentOwner():GetPos()
		end

		if part.nearest_life_next_scan < CurTime() then
			tbl.distance_sort_list = nil
			if not tbl.refresh_rate then
				part.nearest_life_next_scan = CurTime() + 0.2 + math.random()*0.1
			else
				part.nearest_life_next_scan = CurTime() + (1 / math.max(tbl.refresh_rate, 0.01))
			end
		elseif tbl.shared_part and tbl.shared_part.nearest_life_next_scan < CurTime() then
			tbl.distance_sort_list = nil
			if not tbl.refresh_rate then
				part.nearest_life_next_scan = CurTime() + 0.2 + math.random()*0.1
			else
				part.nearest_life_next_scan = CurTime() + (1 / math.max(tbl.refresh_rate, 0.01))
			end
		end

		local nearest_ent = part:GetRootPart():GetOwner()
		local nearest_dist = math.huge
		local owner_ent = part:GetRootPart():GetOwner()
		local distance_sort_list = {}

		if not tbl.distance_sort_list and not (tbl.shared_part) then
			local ents_in_sphere = ents.FindInSphere(wpos, tbl.distance)
			if table.IsEmpty(ents_in_sphere) then return nil end

			for i = 1, #ents_in_sphere do
				local ent = ents_in_sphere[i]
				local is_npc = ent:IsNPC()
				local is_nextbot = ent:IsNextBot()
				local is_ply = ent:IsPlayer()
				if tbl.no_self and ent == player_owner then continue end
				if not is_npc and not is_ply and not is_nextbot then continue end
				if tbl.filterin then
					for i,kw in ipairs(tbl.filterin_keywords) do
						if not string.find(ent:GetClass(), kw) then continue end
					end
				end
				if tbl.filterout then
					for i,kw in ipairs(tbl.filterout_keywords) do
						if string.find(ent:GetClass(), kw) then continue end
					end
				end
				if is_npc and (not tbl.npcfilter or tbl.no_npcs) then continue end
				if is_ply and (not tbl.playerfilter or tbl.no_players) then continue end
				if is_nextbot and (not tbl.nextbotfilter or tbl.no_nextbots) then continue end
				
				if (is_npc or is_ply or is_nextbot) and ((ent ~= owner_ent) or tbl.find_self) then
					if is_ply and (ent ~= owner_ent) and tbl.no_players then continue end
					local dist = (wpos - ent:GetPos()):LengthSqr()
					table.insert(distance_sort_list, {ent, dist})
					if dist < nearest_dist then
						nearest_ent = ent
						nearest_dist = dist
					end
				end
			end

			table.sort(distance_sort_list, function(a,b) return a[2] < b[2] end)
			tbl.distance_sort_list = distance_sort_list
			part.nearest_life_ent = nearest_ent
		end

		if tbl.use_order_of_ents and tbl.distance_sort_list then
			local final_determined_ent = part.nearest_life_ent
			if not tbl.distance_sort_list then return end
			if part.NearestLifeIndex ~= 1 then
				tbl.NearestLifeIndex = part.NearestLifeIndex
			end
			if tbl.NearestLifeIndex == 0 then final_determined_ent = part:GetParentOwner() elseif table.IsEmpty(tbl.distance_sort_list) then return end
			--not enough entities means we can't select at our chosen index, but we must still select an entity, so that would be the furthest in the list
			if #tbl.distance_sort_list < tbl.NearestLifeIndex then
				final_determined_ent = tbl.distance_sort_list[#tbl.distance_sort_list][1]
			--lots of entities means we can select an entity at our chosen index
			elseif tbl.distance_sort_list[tbl.NearestLifeIndex] then
				final_determined_ent = tbl.distance_sort_list[tbl.NearestLifeIndex][1]
			end
			part.nearest_life_ent = final_determined_ent
		end
		local fallback = not IsValid(part.nearest_life_ent)
		if tbl.distance_sort_list then
			if #tbl.distance_sort_list < (tbl.NearestLifeIndex or part.NearestLifeIndex) then fallback = true end
		end
		if fallback then
			if tbl.positioning_fallback == "BACKTOSELF" then
				part.nearest_life_ent = part:GetParentOwner()
			elseif tbl.positioning_fallback == "HIDE" then
				part:SetEventTrigger(part, true) part.NL_hide = true
			end
		elseif part.NL_hide then
			part:SetEventTrigger(part, false) part.NL_hide = false
		end
		return part.nearest_life_ent or part.fallback_nearest_life_ent
	end

	local function NL_getpos(ent, tbl)
		if not tbl then return Vector() end
		if not IsValid(ent) then return Vector() end
		if tbl.relative_position == "POS" then
			return ent:GetPos()
		elseif tbl.relative_position == "HEAD" then
			return (ent:GetBonePosition(ent:LookupBone("ValveBiped.Bip01_Head1") or 1) or Vector(0,0,0)) + Vector(0,0,4) --a little bit more up to center the head
		else
			return ent:GetPos() + Vector(0,0,(ent:WorldSpaceCenter() - ent:GetPos()).z * 1.5)
		end
	end

	local function NL_getmiddle(part)
		local tbl = part.nearest_life_params
		local midpoint = Vector()
		local max = math.min(tbl.use_middle_position_of_ents_count, #tbl.distance_sort_list)
		for i=1,max,1 do
			if i > #tbl.distance_sort_list then break end
			if tbl.distance_sort_list[i][1] then
				part.nearest_life_midpoint_ents[i] = tbl.distance_sort_list[i][1]
				--rolling average
				midpoint = midpoint + NL_getpos(part.nearest_life_midpoint_ents[i], tbl) * (1 / max)
				part.nearest_life_midpoint_pos = midpoint
			end
		end
	end
	
	local selected_NL_part
	pac.AddHook("HUDPaint", "NL_dump", function()
		if not pace.IsActive() then return end
		local part = pace.current_part
		if not part then return end
		if not part.nearest_life_params and not part.nearest_life_bone_params then return end

		local tbl = part.nearest_life_params or part.nearest_life_bone_params
		if tbl.use_order_of_ents and tbl.shared_part then
			local tbl2 = tbl.shared_part.nearest_life_params or tbl.shared_part.nearest_life_bone_params
			if tbl2 then
				tbl.distance_sort_list = tbl2.distance_sort_list
			end
		end
		local y = 15
		for k,v in pairs(tbl) do
			surface.SetFont("ChatFont")
			surface.SetTextColor(Color(255,255,255))
			surface.SetTextPos(ScrW() - 500, y)
			surface.DrawText(k .. " " .. tostring(v))
			y = y + 15
			if istable(v) then
				for i,v2 in ipairs(v) do
					surface.SetTextColor(Color(255,255,255))
					surface.SetTextPos(ScrW() - 500, y)
					if isentity(v2[1]) and IsValid(v2[1]) then
						if tbl.use_order_of_ents and tbl.NearestLifeIndex and tbl.distance_sort_list and tbl.distance_sort_list[tbl.NearestLifeIndex] then
							if v2[1] == tbl.distance_sort_list[tbl.NearestLifeIndex][1] then
								surface.SetTextColor(Color(0,255,0))
							end
						end
						surface.DrawText(" -->" .. i .. " " .. tostring(v2[1]) .. " " .. string.StripExtension(string.GetFileFromFilename(v2[1]:GetModel())))
					else
						surface.DrawText(" -->" .. i .. " " .. tostring(v2))
					end
					
					y = y + 15
				end
			end
		end
	end)

	function pac.GetNearestLifeResultingPosition(part, tbl, ent)
		if not part then return Vector() end

		if not tbl then return Vector() end
		if not ent then return Vector() end

		local final_determined_ent = ent

		if tbl.use_middle_position_of_ents_count then
			if not tbl.distance_sort_list then return Vector() end
			local midpoint = Vector()
			local max = math.min(tbl.use_middle_position_of_ents_count, #tbl.distance_sort_list)
			for i=1,max,1 do
				if i > #tbl.distance_sort_list then break end
				if tbl.distance_sort_list[i][1] then
					part.nearest_life_midpoint_ents[i] = tbl.distance_sort_list[i][1]
					--rolling average
					midpoint = midpoint + NL_getpos(part.nearest_life_midpoint_ents[i], tbl) * (1 / max)
					part.nearest_life_midpoint_pos = midpoint
				end
			end
			return midpoint
		end
		if final_determined_ent:IsValid() then
			if tbl.relative_position == "POS" then
				return final_determined_ent:GetPos()
			elseif tbl.relative_position == "HEAD" then
				return (final_determined_ent:GetBonePosition(final_determined_ent:LookupBone("ValveBiped.Bip01_Head1") or 1) or Vector(0,0,0)) + Vector(0,0,4) --a little bit more up to center the head
			else
				return final_determined_ent:GetPos() + Vector(0,0,(final_determined_ent:WorldSpaceCenter() - final_determined_ent:GetPos()).z * 1.5)
			end
		end

		return Vector()
	end

	function pac.ParseNearestLifeString(part, str)
		local tbl = {}
		if not string.find(str, "NEAREST_LIFE") then return nil end
		str = string.gsub(str, "^NEAREST_LIFE", "")
		if part.NL_hide then
			part:SetEventTrigger(part, false)
		end

		local ply = part:GetPlayerOwner()
		pac.NL_calls_left = pac.NL_calls_left or {}
		pac.NL_calls_left[ply] = 25

		--refresh next time
		part.nearest_life_next_scan = 0
		part.nearest_life_ent = nil
		part.nearest_life_midpoint_ents = {}
		part.nearest_life_midpoint_pos = nil

		local pre_processed_args = string.Split(str,"_")
		local more_classes = false
		local not_class = false
		local current_class = ""
		local classes = nil
		for i,v in ipairs(pre_processed_args) do
			if v == "POS" then
				tbl.relative_position = "POS"
				not_class = true
			elseif v == "HEAD" then
				tbl.relative_position = "HEAD"
				not_class = true
			elseif v == "YAW" then
				tbl.yawonly = true
				not_class = true
			elseif v == "NPC" then
				tbl.npcfilter = true
				tbl.filter = true
				not_class = true
			elseif v == "NONPC" then
				tbl.no_npcs = true
				not_class = true
			elseif v == "NEXTBOT" then
				tbl.nextbotfilter = true
				tbl.filter = true
				not_class = true
			elseif v == "NONEXTBOTS" then
				tbl.no_nextbots = true
				not_class = true
			elseif v == "PLAYER" then
				tbl.playerfilter = true
				tbl.filter = true
				not_class = true
			elseif v == "NOPLAYERS" then
				tbl.no_players = true
				not_class = true
			elseif v == "NOSELF" then
				tbl.no_self = true
				not_class = true
			elseif v == "FINDSELF" then
				tbl.find_self = true
				not_class = true
			elseif v == "FROMSELF" then
				tbl.force_self = true
				not_class = true
			elseif pac.StringFind(v, "DISTANCE=") then
				local str_num = string.gsub(v,"DISTANCE=","")
				tbl.distance = tonumber(str_num) or NL_max_distance:GetInt()
				not_class = true
			elseif pac.StringFind(v, "RADIUS=") then
				local str_num = string.gsub(v,"RADIUS=","")
				tbl.distance = tonumber(str_num) or NL_max_distance:GetInt()
				not_class = true
			elseif pac.StringFind(v, "BONEANG=") then
				tbl.bone_ang = string.gsub(v,"BONEANG=","")
				not_class = true
			elseif pac.StringFind(v, "MEANOF=") then
				local str_num = string.gsub(v,"MEANOF=","")
				tbl.use_middle_position_of_ents = true
				tbl.use_middle_position_of_ents_count = tonumber(str_num) or 1
				not_class = true
			elseif pac.StringFind(v, "SELECT=") then
				local str_num = string.gsub(v,"SELECT=","")
				tbl.use_order_of_ents = true
				tbl.use_order_of_ents_initial_index = tonumber(str_num) or 0
				tbl.NearestLifeIndex = tonumber(str_num) or 0
				not_class = true
			elseif pac.StringFind(v, "SHARELIST=") then
				local str = string.gsub(v,"SHARELIST=","")
				tbl.shared_list_partid = string.Trim(str, "\"")
				not_class = true
			elseif pac.StringFind(v, "FALLBACK=") then
				local str = string.gsub(v,"FALLBACK=","")
				tbl.positioning_fallback = str
				not_class = true
			elseif pac.StringFind(v, "REFRESHRATE=") then
				local str_num = string.gsub(v,"REFRESHRATE=","")
				tbl.refresh_rate = tonumber(str_num) or 10
				not_class = true
			elseif pac.StringFind(v, "EXCLUDEKEYWORDS=") then
				not_class = false
				tbl.filterout = true
				classes = {}
				tbl.filterout_keywords = classes
				more_classes = true
				
				current_class = string.sub(v, #"EXCLUDEKEYWORDS=" + 1)
			elseif pac.StringFind(v, "INCLUDEKEYWORDS=") then
				not_class = false
				tbl.filterin = true
				classes = {}
				tbl.filterin_keywords = classes
				more_classes = true

				current_class = string.sub(v, #"INCLUDEKEYWORDS=" + 1)
			elseif more_classes then
				v = string.Trim(v, "=")
				local strs = string.Split(v, ";")
				if #strs ~= 1 then
					for i,v2 in ipairs(strs) do
						if i == 1 then
							if current_class ~= "" then
								current_class = current_class .. "_" .. v2
							end
							table.insert(classes, current_class)
						else
							current_class = v2
						end
					end
				else
					current_class = current_class .. "_" .. v
				end
				not_class = false
			end
			if not_class then more_classes = false end
		end
		--at the end
		if current_class ~= "" then
			table.insert(classes, current_class)
		end

		tbl.distance = tbl.distance or NL_max_distance:GetInt()
		tbl.distance = math.Clamp(tbl.distance, 0, NL_max_distance:GetInt())
		tbl.NearestLifeIndex = part.NearestLifeIndex
		if tbl.filter then
			if not tbl.npcfilter then tbl.no_npcs = true end
			if not tbl.playerfilter then tbl.no_players = true end
			if not tbl.nextbotfilter then tbl.no_nextbots = true end
		else
			tbl.npcfilter = true
			tbl.playerfilter = true
			tbl.nextbotfilter = true
		end

		return tbl
	end

	local NL_params = {
		--orientation
		{"LEVEL", "combobox", "Whether the relative position should be the head, the entity's position or torso. Default is torso", {"TORSO", "HEAD", "POS"}},
		{"BONEANG=", "combobox", "For bones, whether to realign the part so it points relative to you or the found target", {"BONEANG=nil", "BONEANG=entyaw", "BONEANG=owner", "BONEANG=owneryaw"}},
		{"YAW", "bool", "Limit angles to yaw only"},
		{"FALLBACK", "combobox", "If no NL entity is found or attempting over-indexed positioning, hide or not.\nHIDE will hide the part\nBACKTOSELF will bring the part back to you\nLISTTOPPER will get the highest in the list e.g. if only 5 entities make the list, a SELECT=7 or NearestLifeIndex = 7 will do 7 -> 5", {"FALLBACK=HIDE", "FALLBACK=BACKTOSELF", "FALLBACK=LISTTOPPER"}},
		
		--filters
		{"PLAYERS", "bool", "enables filtering, allows players"},
		{"NOPLAYERS", "bool", "blocks players"},
		{"NPC", "bool", "enables filtering, allows NPCs"},
		{"NONPC", "bool", "blocks NPCs"},
		{"NEXTBOT", "bool", "enables filtering, allows nextbots"},
		{"NONEXTBOTS", "bool", "blocks nextbots"},
		{"NOSELF", "bool", "blocks yourself"},
		{"FINDSELF", "bool", "allows to find yourself"},
		{"INCLUDEKEYWORDS=", "list", "only allows these entity class keywords, separated by semicolons", "e.g. npc_combine_s;npc_metropolice"},
		{"EXCLUDEKEYWORDS=", "list", "blocks these entity class keywords, separated by semicolons", "e.g. npc_citizen;npc_monk"},

		--selection
		{"FROMSELF", "bool", "start the search relative to your player"},
		{"RADIUS=", "number", "how far to search. Default is " .. NL_max_distance:GetInt(), "radius in HU."},
		{"MEANOF=", "number", "get the middle position between this number of entities", "number of entities"},
		{"SELECT=", "number", "select the n-th entity by distance. Default is to take the 1st entity", "the n-th entity"},
		{"REFRESHRATE=", "number", "how often per second to sort the nearest entities", "refreshes per second"},
		{"SHARELIST=", "list", "part UID to share entity list with for optimization purposes", "part UID"}
	}
	local NL_params_reverse = {
		relative_position = "LEVEL",
		yawonly = "YAW",
		npcfilter = "NPC",
		no_npcs = "NONPC",
		nextbotfilter = "NEXTBOT",
		no_nextbots = "NONEXTBOT",
		playerfilter = "PLAYERS",
		no_players = "NOPLAYERS",
		no_self = "NOSELF",
		find_self = "FINDSELF",
		force_self = "FROMSELF",
		filterout_keywords = "EXCLUDEKEYWORDS=",
		filterin_keywords = "INCLUDEKEYWORDS=",
		distance = "RADIUS=",
		bone_ang = "BONEANG=",
		use_order_of_ents_initial_index = "SELECT=",
		use_middle_position_of_ents_count = "MEANOF=",
		share_search = "SHARELIST=",
		positioning_fallback = "FALLBACK"
	}

	function pac.ConfigureNearestLifeMenu()
		local part = pace.current_part
		local existing_data = pac.ParseNearestLifeString(pace.current_part, part[pace.NL_config_key])

		local frame = vgui.Create("DFrame")
		frame:SetSize(600, 600) frame:SetPos(ScrW()/2 + 200, ScrH()/2 - 300) frame:MakePopup()
		frame:SetTitle("Nearest life config : " .. pace.NL_config_key)

		local lines = 0
		local added_params = {}
		local added_params_keyed = {}
		local function insert_keyvalue_pair(name, panel_type, tooltip, choices)
			local line = vgui.Create("DPanel", frame)
			local text_color = line:GetSkin().Colours.Category.Line.Text
			line:SetSize(598, 24) line:SetPos(1, 25 + lines*24)
			local label = vgui.Create("DLabel", line)
			label:SetSize(110, 24) label:SetPos(2,2) label:SetText(name)

			local chk = vgui.Create("DCheckBoxLabel", line)
			chk:SetText("use")
			chk:SetSize(40, 24) chk:SetPos(120, 0)
			local pnl = chk
			if panel_type == "string" then
				pnl = vgui.Create("DTextEntry", line)
				pnl:SetSize(390,20) pnl:SetPos(200, 2)

				pnl:SetPlaceholderText(choices)
			elseif panel_type == "list" then
				pnl = vgui.Create("DTextEntry", line)
				pnl:SetSize(390,20) pnl:SetPos(200, 2)

				pnl:SetPlaceholderText(choices)
			elseif panel_type == "number" then
				pnl = vgui.Create("DTextEntry", line)
				pnl:SetSize(390,20) pnl:SetPos(200, 2)

				pnl:SetPlaceholderText(choices)
				function pnl:EditText(val)
					if not isnumber(tonumber(val)) then
						self:SetTextColor(Color(150,0,0))
						
						pnl.ok = false
					else
						pnl:SetTextColor(text_color)
						pnl.ok = true
					end
				end
			elseif panel_type == "combobox" then
				pnl = vgui.Create("DComboBox", line)
				pnl:SetText("select option...")
				pnl:SetSize(390,20) pnl:SetPos(200, 2)
				for i,v in ipairs(choices) do
					pnl:AddChoice(v)
				end
			elseif panel_type == "bool" then
				pnl = chk
			end
			added_params_keyed[name] = pnl
			pnl.ok = true
			pnl.panel_type = panel_type
			pnl.key = name
			pnl.chk = chk
			label:SetTextColor(text_color)
			chk:SetTextColor(text_color)
			pnl:SetTextColor(text_color)
			line:SetTooltip(tooltip)

			lines = lines + 1
			line.label = label
			line.pnl = pnl
			line.chk = chk
			table.insert(added_params, {name, line.pnl})
		end
		for i,tbl in ipairs(NL_params) do
			insert_keyvalue_pair(tbl[1], tbl[2], tbl[3], tbl[4])
		end

		local checkout = vgui.Create("DButton", frame)
		checkout:SetSize(200, 40) checkout:SetImage("icon16/accept.png")
		checkout:SetPos(200, 30 + lines*24)
		checkout:SetText("Apply")
		function checkout:DoClick()
			local str = "NEAREST_LIFE"
			for i, param in ipairs(added_params) do
				local val = param[2]:GetValue()
				if param[2].panel_type == "bool" then
					if param[2]:GetChecked() then
						str = str .. "_" .. param[1]
					end
				elseif param[2].panel_type == "combobox" then
					if val ~= "select option..." then
						str = str .. "_" .. val
					end
				elseif val ~= ""and param[2].ok then
					str = str .. "_" .. param[1] .. val
				end
			end
			if IsValid(part) then
				if pace.NL_config_key == "Bone" then
					part:SetBone(str)
				elseif pace.NL_config_key == "AimPartName" then
					part:SetAimPartName(str)
				end
				pace.PopulateProperties(part)
			end
		end
		if existing_data then
			for key,value in pairs(existing_data) do
				local pnl = added_params_keyed[NL_params_reverse[key]]
				if NL_params_reverse[key] and pnl and pac.StringFind(part[pace.NL_config_key], NL_params_reverse[key]) then
					pnl.chk:SetChecked(true)
					pnl:SetValue(value)
				end
			end
		end
	end

end

function PART:SetAimPartName(str)
	self.AimPartName = str
	self.nearest_life_params = nil
	if pac.StringFind(str, "NEAREST_LIFE") then
		if not allow_NL:GetBool() then self:SetWarning("nearest_life isn't allowed in this server") end
		self.nearest_life_params = pac.ParseNearestLifeString(self, str)
	end
end

function PART:SetNearestLifeIndex(val)
	self.NearestLifeIndex = val
	if self.nearest_life_params then
		self.nearest_life_params.NearestLifeIndex = math.Clamp(math.floor(val),0,50)
		self.nearest_life_params.request_reindex = true
	end
	if self.nearest_life_bone_params then
		self.nearest_life_bone_params.NearestLifeIndex = math.Clamp(math.floor(val),0,50)
		self.nearest_life_bone_params.request_reindex = true
	end
end

function PART:CalcAngles(ang, wpos)
	wpos = wpos or self.WorldMatrix and self.WorldMatrix:GetTranslation()
	if not wpos then return ang end

	local owner = self:GetRootPart():GetOwner()

	local function aimpartname_angle()
		local ang = ang
		if pac.StringFind(self.AimPartName, "LOCALEYES_YAW", true, true) then
			ang = (pac.EyePos - wpos):Angle()
			ang.p = 0
			return self.Angles + ang
		end
	
		if pac.StringFind(self.AimPartName, "LOCALEYES_PITCH", true, true) then
			ang = (pac.EyePos - wpos):Angle()
			ang.y = 0
			return self.Angles + ang
		end
	
		if pac.StringFind(self.AimPartName, "LOCALEYES", true, true) then
			return self.Angles + (pac.EyePos - wpos):Angle()
		end
	
	
		if pac.StringFind(self.AimPartName, "PLAYEREYES", true, true) then
			local ent = owner.pac_traceres and owner.pac_traceres.Entity or NULL
	
			if ent:IsValid() then
				return self.Angles + (ent:EyePos() - wpos):Angle()
			end
	
			return self.Angles + (pac.EyePos - wpos):Angle()
		end

		if pac.StringFind(self.AimPartName, "NEAREST_LIFE", true, true) then
			if not allow_NL:GetBool() then return ang + self.Angles end

			if not self.nearest_life_params then return ang + self.Angles end

			local ent = pac.FindNearestLifeEntity(self, self.nearest_life_params, wpos)
			self.fallback_nearest_life_ent = ent or self.fallback_nearest_life_ent
			if not ent then
				if self.nearest_life_params.no_self then
					return ang + self.Angles
				else
					ent = self:GetRootPart():GetOwner()
				end
			end
			local pos = pac.GetNearestLifeResultingPosition(self, self.nearest_life_params, ent)
			local ang = (pos - wpos):Angle()

			if self.nearest_life_params.yawonly then
				return Angle(0,ang.y,0) + self.Angles
			else
				return ang + self.Angles
			end
		end
		return ang
	end
	if self.AimPartName and self.AimPartName ~= "" then
		if self.AimPartNameStrength ~= 1 then
			local dir = aimpartname_angle():Forward()
			if self.AimPartNameStrength < 0 then dir:Mul(-1) end
			return LerpAngle(math.abs(self.AimPartNameStrength), ang, dir:Angle())
		end
		return aimpartname_angle()
	end
	
	--[[if pac.StringFind(self.AimPartName, "NEAREST_LIFE_YAW", true, true) then
		local nearest_ent = get_nearest_ent(self, self.nearest_life_params, wpos)
		if not IsValid(nearest_ent) then return ang or Angle(0,0,0) end
		local ang = (nearest_ent:GetPos() - wpos):Angle()
		return Angle(0,ang.y,0) + self.Angles
	end

	if pac.StringFind(self.AimPartName, "NEAREST_LIFE_POS", true, true) then
		local nearest_ent = get_nearest_ent(self, self.nearest_life_params, wpos)
		if not IsValid(nearest_ent) then return ang or Angle(0,0,0) end
		return self.Angles + (nearest_ent:GetPos() - wpos):Angle()
	end

	if pac.StringFind(self.AimPartName, "NEAREST_LIFE", true, true) then
		local nearest_ent = get_nearest_ent(self, self.nearest_life_params, wpos)
		if not IsValid(nearest_ent) then return ang or Angle(0,0,0) end
		return self.Angles + ( nearest_ent:GetPos() + Vector(0,0,(nearest_ent:WorldSpaceCenter() - nearest_ent:GetPos()).z * 1.5) - wpos):Angle()
	end]]

	if self.AimPart:IsValid() and self.AimPart.GetWorldPosition then
		--if true then return (self.AimPart:GetWorldPosition() - wpos):Angle() end
		if self.AimPartStrength ~= 1 then
			local dir = (self.AimPart:GetWorldPosition() - wpos)
			if self.AimPartStrength < 0 then dir:Mul(-1) end
			return LerpAngle(math.abs(self.AimPartStrength), ang, self.Angles + dir:Angle())
		end
			
		return self.Angles + (self.AimPart:GetWorldPosition() - wpos):Angle()
	end

	if self.EyeAngles then
		if owner:IsPlayer() then
			return self.Angles + ((owner.pac_hitpos or owner:GetEyeTraceNoCursor().HitPos) - wpos):Angle()
		elseif owner:IsNPC() then
			return self.Angles + ((owner:EyePos() + owner:GetForward() * 100) - wpos):Angle()
		end
	end

	return ang or Angle(0,0,0)
end

BUILDER:Register()
