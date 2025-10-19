concommand.Add("pac_in_editor", function(ply, _, args)
	ply:SetNWBool("in pac3 editor", tonumber(args[1]) == 1)
end)

function pace.SpawnPart(ply, model)
	if pace.suppress_prop_spawn then return end
	if model then
		if IsValid(ply) and ply:GetNWBool("in pac3 editor") then
			if ply:GetInfoNum("pac_spawnmenu_props_spawn_as_parts", 0) == 0 then
				return
			end
			net.Start("pac_spawn_part")
				net.WriteString(model)
			net.Send(ply)
			if not ply.pac_dont_suppress_spawn_prop or (ply:GetInfoNum("pac_spawnmenu_props_spawn_as_parts", 0) == 1) then
				return false
			end
		end
	end
end

util.AddNetworkString("pac_demand_prop_spawn")
net.Receive("pac_demand_prop_spawn", function(len, ply)
	ply.pac_dont_suppress_spawn_prop = net.ReadBool()
end)

pac.AddHook( "PlayerSpawnProp", "pac_PlayerSpawnProp", pace.SpawnPart)
pac.AddHook( "PlayerSpawnRagdoll", "pac_PlayerSpawnRagdoll", pace.SpawnPart)
pac.AddHook( "PlayerSpawnEffect", "pac_PlayerSpawnEffect", pace.SpawnPart)

util.AddNetworkString("pac_spawn_part")