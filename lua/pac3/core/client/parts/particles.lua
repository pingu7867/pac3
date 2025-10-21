local cam_IgnoreZ = cam.IgnoreZ
local vector_origin = vector_origin
local FrameTime = FrameTime
local angle_origin = Angle(0,0,0)
local WorldToLocal = WorldToLocal

local BUILDER, PART = pac.PartTemplate("base_drawable")

PART.ClassName = "particles"
PART.Group = 'effects'
PART.Icon = 'icon16/water.png'

BUILDER:StartStorableVars()
	BUILDER:SetPropertyGroup("generic")
		BUILDER:PropertyOrder("Name")
		BUILDER:PropertyOrder("Hide")
		BUILDER:PropertyOrder("ParentName")
		BUILDER:GetSet("Follow", false)
		BUILDER:GetSet("Additive", false)
		BUILDER:GetSet("DieTime", 3)
		BUILDER:GetSet("StartSize", 2)
		BUILDER:GetSet("EndSize", 20)
		BUILDER:GetSet("StartLength", 0)
		BUILDER:GetSet("EndLength", 0)
		BUILDER:GetSet("AddFrametimeLife", false, {description = "extends the die time by the frame time "})

	BUILDER:SetPropertyGroup("particle emit frequency")
		BUILDER:GetSet("FireDelay", 0.2)
		BUILDER:GetSet("FireOnce", false)
		BUILDER:GetSet("NumberParticles", 1, {editor_onchange = function(self,num) return math.Clamp(num,0,2000) end})
		BUILDER:GetSet("FireDuration", 0, {description = "how long to fire particles\n0 = infinite"})
		BUILDER:GetSet("Decay", 0, {description = "rate of decay for particle count\n0 = no decay\na positive number means simple decay starting at showtime\na negative number means delayed decay so that it reaches 0 at the time of 'fire duration'"})
		BUILDER:GetSet("FractionalChance", false, {description = "If 'number particles' has decimals, there is a chance to emit another particle\ne.g. 0.5 is 50% chance to emit a particle\ne.g. 1.25 is 25% chance to fire two / 75% to fire one particle)"})

	BUILDER:SetPropertyGroup("position spread")
		BUILDER:GetSet("LegacyPositionSpread", true, {description = "Use the old method of position spread which can drift off with high particle counts"})
		BUILDER:GetSet("PositionSpreadType", "SphereHollow", {enums = {
			["Box"] = "Box",
			["Hollow sphere"] = "SphereHollow",
			["Filled sphere"] = "SphereFilled",
			["Hollow disc"] = "DiscHollow",
			["Filled disc"] = "DiscFilled",
		}})
		BUILDER:GetSet("PositionSpread", 0)
		BUILDER:GetSet("PositionSpread2", Vector(0,0,0))
	BUILDER:SetPropertyGroup("spread")
		BUILDER:GetSet("MinAngle", 0, {description = "applies to disc-related spreads and position spreads"})
		BUILDER:GetSet("MaxAngle", 360, {description = "applies to disc-related spreads and position spreads"})
		BUILDER:GetSet("SpreadType", "Legacy", {enums = {
			["Legacy"] = "Legacy",
			["Square cone"] = "SquareCone",
			["Flat cone"] = "FlatCone",
			["Cone"] = "Cone",
			["Disc"] = "Disc",
		}})
		BUILDER:GetSet("Spread", 0.1)
		BUILDER:GetSet("SpreadVector", Vector(0,0,0))
		BUILDER:GetSet("SpreadAngle", 0)
	BUILDER:SetPropertyGroup("stick")
		BUILDER:GetSet("AlignToSurface", true, {description = "requires 3D set to true"})
		BUILDER:GetSet("StickToSurface", true, {description = "requires 3D set to true, and sliding set to false"})
		BUILDER:GetSet("StickLifetime", 2)
		BUILDER:GetSet("StickStartSize", 20)
		BUILDER:GetSet("StickEndSize", 0)
		BUILDER:GetSet("StickStartAlpha", 255)
		BUILDER:GetSet("StickEndAlpha", 0)
	BUILDER:SetPropertyGroup("appearance")
		BUILDER:GetSet("Material", "effects/slime1")
		BUILDER:GetSet("StartAlpha", 255)
		BUILDER:GetSet("EndAlpha", 0)
		BUILDER:GetSet("Translucent", true)
		BUILDER:GetSet("Color2", Vector(255, 255, 255), {editor_panel = "color"})
		BUILDER:GetSet("Color1", Vector(255, 255, 255), {editor_panel = "color"})
		BUILDER:GetSet("HSVMode", false)
		BUILDER:GetSet("HSV1", Vector(360, 1, 1), {editor_friendly = "HSV1"})
		BUILDER:GetSet("HSV2", Vector(360, 1, 1), {editor_friendly = "HSV2"})
		BUILDER:GetSet("RandomColor", false)
		BUILDER:GetSet("Lighting", true)
		BUILDER:GetSet("3D", false, {description = "The particles are oriented relative to the part instead of the viewer.\nYou might want to set zero angle to false if you use this."})
		BUILDER:GetSet("DoubleSided", true)
		BUILDER:GetSet("DrawManual", false)
	BUILDER:SetPropertyGroup("rotation")
		BUILDER:GetSet("ParticleAngle", Angle(0,0,0))
		BUILDER:GetSet("ZeroAngle", false, {description = "A workaround for non-3D particles' roll with certain oriented textures. Forces 0,0,0 angles when the particle is emitted\nWith round textures you don't notice, but the same cannot be said of textures which need to be upright rather than having strangely tilted copies."})
		BUILDER:GetSet("RandomRollSpeed", 0)
		BUILDER:GetSet("RollDelta", 0)
		BUILDER:GetSet("ParticleAngleVelocity", Vector(0, 0, 0))
		BUILDER:GetSet("FireDirectionToAngle", false)
		BUILDER:GetSet("PositionSpreadToAngle", false)
	BUILDER:SetPropertyGroup("orientation")
	BUILDER:SetPropertyGroup("movement")
		BUILDER:GetSet("Velocity", 250)
		BUILDER:GetSet("AirResistance", 5)
		BUILDER:GetSet("Bounce", 5)
		BUILDER:GetSet("Gravity", Vector(0,0, -50))
		BUILDER:GetSet("Collide", true)
		BUILDER:GetSet("RemoveOnCollide", false)
		BUILDER:GetSet("Sliding", true)
		--BUILDER:GetSet("AddVelocityFromOwner", false)
		BUILDER:GetSet("OwnerVelocityMultiplier", 0)
	BUILDER:SetPropertyGroup("particle function")
		BUILDER:GetSet("ThinkFunction", "", {enums = {
			["none"] = "",
			["brownian"] = "brownian",
			["SpriteCard"] = "SpriteCard",
			["sine_alpha"] = "",
			["inject_proxy"] = "inject_proxy"
		}})
		BUILDER:GetSet("ThinkTime", 0)
		BUILDER:GetSet("PropertyName", "")
		BUILDER:GetSetPart("LinkedPart")
		BUILDER:GetSet("BrownianStrength", 0)

BUILDER:EndStorableVars()

function PART:Initialize()
	self.number_particles = 0
end

function PART:GetNiceName()
	local str = (self:GetMaterial()):match(".+/(.+)") or ""
	--return pac.PrettifyName("/".. str) or "error"
	return "[".. math.Round(self.display_number_particles or 0,2) .. "] " .. str
end

local function RemoveCallback(particle)
	particle:SetLifeTime(0)
	particle:SetDieTime(0)

	particle:SetStartSize(0)
	particle:SetEndSize(0)

	particle:SetStartAlpha(0)
	particle:SetEndAlpha(0)
end

local function SlideCallback(particle, hitpos, normal)
	particle:SetBounce(1)
	local vel = particle:GetVelocity()
	vel.z = 0
	particle:SetVelocity(vel)
	particle:SetPos(hitpos + normal)
end

local function StickCallback(particle, hitpos, normal)
	particle:SetAngleVelocity(Angle(0, 0, 0))

	if particle.Align then
		local ang = normal:Angle()
		ang:RotateAroundAxis(normal, particle:GetAngles().y)
		particle:SetAngles(ang + particle.ParticleAngle + (particle.is_doubleside == true and Angle(180,0,0) or Angle(0,0,0)))
	end

	if particle.Stick then
		particle:SetVelocity(Vector(0, 0, 0))
		particle:SetGravity(Vector(0, 0, 0))
	end

	particle:SetLifeTime(0)
	particle:SetDieTime(particle.StickLifeTime or 0)

	particle:SetStartSize(particle.StickStartSize or 0)
	particle:SetEndSize(particle.StickEndSize or 0)

	particle:SetStartAlpha(particle.StickStartAlpha or 0)
	particle:SetEndAlpha(particle.StickEndAlpha or 0)
end

function PART:GetEmitter()
	if not self.emitter then
		self.NextShot = 0
		self.Created = pac.RealTime + 0.1
		self.emitter = ParticleEmitter(vector_origin, self:Get3D())
	end

	return self.emitter
end

function PART:OnRemove()
	if IsValid(self.emitter) then
		self.emitter:Finish()
	end
end

function PART:SetDrawManual(b)
	self.DrawManual = b
	self:GetEmitter():SetNoDraw(b)
end

local max_active_particles = CreateClientConVar("pac_limit_particles_per_emitter", "8000")
local max_emit_particles = CreateClientConVar("pac_limit_particles_per_emission", "100")
function PART:SetNumberParticles(num)
	local max = max_emit_particles:GetInt()
	if num > max or num > 100 then self:SetWarning("You're trying to set the number of particles beyond the pac_limit_particles_per_emission limit, the default limit is 100.\nFor reference, the default max active particles for the emitter is around 8000 but can be further limited with pac_limit_particles_per_emitter") else self:SetWarning() end
	self.NumberParticles = math.Clamp(num, 0, max)
end

function PART:Set3D(b)
	self["3D"] = b
	self.emitter = nil
end

function PART:OnShow(from_rendering)
	self.number_particles = self.NumberParticles
	self.CanKeepFiring = true
	self.FirstShot = true
	self.FirstShotTime = RealTime()
	if not from_rendering then
		self.NextShot = 0
		local pos, ang = self:GetDrawPosition()
		self:EmitParticles(self.Follow and vector_origin or pos, self.Follow and angle_origin or ang, ang)
	end
end

function PART:OnDraw()
	self.number_particles = self.NumberParticles or 0
	if not self.FireOnce then
		if self.Decay == 0 then
			self.number_particles = self.NumberParticles or 0
		elseif self.Decay > 0 then
			self.number_particles = math.Clamp(self.NumberParticles - (RealTime() - self.FirstShotTime) * self.Decay,0,self.NumberParticles)
		else
			self.number_particles = math.Clamp(-self.FireDuration * self.Decay + self.NumberParticles - (RealTime() - self.FirstShotTime) * self.Decay,0,self.NumberParticles)
		end
		if self.FireDuration <= 0 then
			self.CanKeepFiring = true
		else
			if RealTime() > self.FirstShotTime + self.FireDuration then self.number_particles = 0 end
		end
	end
	local pos, ang = self:GetDrawPosition()
	local emitter = self:GetEmitter()

	emitter:SetPos(pos)
	if self.DrawManual or self.IgnoreZ or self.Follow or self.BlendMode ~= "" then

		if not self.nodraw then
			emitter:SetNoDraw(true)
			self.nodraw = true
		end

		if self.Follow then
			cam.Start3D(WorldToLocal(EyePos(), EyeAngles(), pos, ang))
			if self.IgnoreZ then cam.IgnoreZ(true) end
			emitter:Draw()
			if self.IgnoreZ then cam.IgnoreZ(false) end
			cam.End3D()
		else
			emitter:Draw()
		end
	else
		if self.nodraw then
			self:SetDrawManual(self:GetDrawManual())
			self.nodraw = false
		end
	end
	self:EmitParticles(self.Follow and vector_origin or pos, self.Follow and angle_origin or ang, ang)
end

function PART:SetAdditive(b)
	self.Additive = b

	self:SetMaterial(self:GetMaterial())
end

function PART:SetMaterial(var)
	var = var or ""

	if not pac.Handleurltex(self, var, function(mat)
		mat:SetFloat("$alpha", 0.999)
		mat:SetInt("$spriterendermode", self.Additive and 5 or 1)
		self.Materialm = mat
		self:CallRecursive("OnMaterialChanged")
	end, "Sprite") then
		if var == "" then
			self.Materialm = nil
		else
			self.Materialm = pac.Material(var, self)
			self:CallRecursive("OnMaterialChanged")
		end
	end

	self.Material = var
end


local function brownian(self)
	self:SetVelocity(self:GetVelocity() + VectorRand(-self.part.BrownianStrength,self.part.BrownianStrength))
	self:SetNextThink(CurTime() + self.thinktime)
end

local function alpha_sin(self)
	self:SetStartAlpha(150 * (0.5 + 0.5*math.sin(self.birth + CurTime() * 5)))
	self:SetEndAlpha(150 * (0.5 + 0.5*math.sin(self.birth + CurTime() * 5)))
	self:SetNextThink(CurTime() + self.thinktime)
end

local function inject_proxy(self)
	if self.valid_part then
		local num = (self.part.LinkedPart.feedback[1] or 0)
		if self.part.PropertyName == "StartSize" or self.part.PropertyName == "EndSize" then
			self:SetStartSize(num)
			self:SetEndSize(num)
		elseif self["Set" .. self.part.PropertyName] then
			
		end
	end
	self:SetNextThink(CurTime() + self.thinktime)
end

local function spritecard(self)
	if CurTime() > self.next_frame then self.frame = self.frame + 1 end
	self:SetNextThink(CurTime() + self.thinktime)
end

local expanded_mats_pool = {}

local function spritecard2(self)
	self.next_frame = self.next_frame or CurTime() + 0.1
	self.mat_series = expanded_mats_pool[self.mat_name]
	if CurTime() > self.next_frame then
		self.frame = self.frame + 1
		self.clamp_frame = math.Clamp(self.frame, 1, #self.mat_series)
		self.next_frame = CurTime() + 0.1
	end
	self.clamp_frame = self.clamp_frame or self.frame
	if self.mat_series == nil then return end

	self:SetMaterial(self.mat_series[self.clamp_frame])
	if self.frame > 10 then
		self:SetMaterial("models/wireframe")
	end
	self:SetNextThink(CurTime() + self.thinktime)
end


function PART:SetThinkFunction(str)
	self.particle_think_function = nil
	if str == "brownian" then
		self.particle_think_function = brownian
	elseif str == "alpha_sin" then
		self.particle_think_function = alpha_sin
	elseif str == "inject_proxy" then
		self.particle_think_function = inject_proxy
	elseif str == "SpriteCard" then
		self.particle_think_function = spritecard
	elseif str == "SpriteCard2" then
		self.particle_think_function = spritecard2
	end
	self.ThinkFunction = str
end

local half_turn = Angle(0,180,0)
local function NonZero(num)
	if num == 0 then return 0.01 else return num end
end
function PART:EmitParticles(pos, ang, real_ang)
	self:SetThinkFunction(self.ThinkFunction)
	if pace.still_loading_wearing then return end
	if self.Hide or self:IsHidden() then return end
	self.number_particles = self.number_particles or 0
	self.display_number_particles = self.number_particles
	if self.number_particles == 0 then return end
	local original_pos = pos
	if self.FireOnce and not self.FirstShot then self.CanKeepFiring = false end
	local emt = self:GetEmitter()
	if not IsValid(emt) then return end

	if self.NextShot < pac.RealTime and self.CanKeepFiring then
		local nonzero_vel = NonZero(self.Velocity)
		if self.Material == "" then return end
		if self.Velocity == 500.01 then return end

		local originalAng = ang
		local originalAng_norm_forward = originalAng:Forward():GetNormalized()
		local originalAng_norm_right = originalAng:Right():GetNormalized()
		local originalAng_norm_up = originalAng:Up():GetNormalized()
		ang = ang:Forward()

		local double = 1
		if self.DoubleSided then
			double = 2
		end

		local free_particles = math.max(max_active_particles:GetInt() - emt:GetNumActiveParticles(),0)
		local max = math.min(free_particles, max_emit_particles:GetInt())
		--self.number_particles is self.NumberParticles with optional decay applied
		local fractional_chance = 0
		if self.FractionalChance then
			--e.g. treat 0.5 as 50% chance to emit or not
			local delta = self.number_particles - math.floor(self.number_particles)
			if math.random() < delta then
				self.number_particles = self.number_particles + 1
			end
		end
		local mats = self.Material:Split(";")
		for _ = 1, math.min(self.number_particles,max) do
			if not self.LegacyPositionSpread then pos = original_pos end
			if #mats > 1 then
				self.Materialm = pac.Material(table.Random(mats), self)
				self:CallRecursive("OnMaterialChanged")
			end
			local vec = Vector()
			local alt_vec_dir = nil
			local added_dir_rotation = Angle(0,0,0)

			if self.Spread ~= 0 then
				if self.SpreadType == "Legacy" then
					--SIN AND COS USE RADIANS THOUGH??
					vec = Vector(
						math.sin(math.Rand(0, 360)) * math.Rand(-self.Spread, self.Spread),
						math.cos(math.Rand(0, 360)) * math.Rand(-self.Spread, self.Spread),
						math.sin(math.random()) * math.Rand(-self.Spread, self.Spread)
					)
				end
			end
			if self.SpreadType ~= "Legacy" then
				--[[
					["Legacy"] = "Legacy",
					["Square cone"] = "SquareCone",
					["Flat cone"] = "FlatCone",
					["Cone"] = "Cone",
					["Disc"] = "Disc",
				]]
				if self.SpreadType == "Disc" then --flat disc, depth can be done with Spread Angle
					local angle = math.rad(math.Rand(self.MinAngle,self.MaxAngle))
					local depth_spread = math.Rand(-1,1)*math.tan(math.rad(self.SpreadAngle/2)) * math.max(self.SpreadVector.y,self.SpreadVector.z)
					alt_vec_dir = Vector(
						self.SpreadVector.x + depth_spread,
						self.SpreadVector.y*math.cos(angle),
						self.SpreadVector.z*math.sin(angle)
					)
					added_dir_rotation = AngleRand(-self.SpreadAngle / 4, self.SpreadAngle / 4)
				elseif self.SpreadType == "FlatCone" then --cone with a flat base
					local angle = math.rad(math.Rand(self.MinAngle,self.MaxAngle))
					local radius = math.random()
					alt_vec_dir = Vector(
						0,
						radius*self.SpreadVector.y*math.cos(angle),
						radius*self.SpreadVector.z*math.sin(angle)
					)
				elseif self.SpreadType == "SquareCone" then
					alt_vec_dir = Vector(
						math.Rand(-1,1)*self.SpreadVector.x,
						math.Rand(-1,1)*self.SpreadVector.y,
						math.Rand(-1,1)*self.SpreadVector.z
					)
				elseif self.SpreadType == "Cone" then --cone projected on the sphere
					alt_vec_dir = Vector(1,0,0)
					added_dir_rotation = AngleRand(-self.SpreadAngle / 2, self.SpreadAngle / 2)
				end
			end

			local color

			if self.RandomColor then
				if self.HSVMode then
					local col = HSVToColor(
						math.random(math.min(self.HSV1.x, self.HSV2.x), math.max(self.HSV1.x, self.HSV2.x)),
						math.random(math.min(self.HSV1.y, self.HSV2.y), math.max(self.HSV1.y, self.HSV2.y)),
						math.random(math.min(self.HSV1.z, self.HSV2.z), math.max(self.HSV1.z, self.HSV2.z))
					)
					color = {col.r,col.g,col.b}
				else
					color =
				{
					math.random(math.min(self.Color1.r, self.Color2.r), math.max(self.Color1.r, self.Color2.r)),
					math.random(math.min(self.Color1.g, self.Color2.g), math.max(self.Color1.g, self.Color2.g)),
					math.random(math.min(self.Color1.b, self.Color2.b), math.max(self.Color1.b, self.Color2.b))
				}
				end
				
			else
				if self.HSVMode then
					local col = HSVToColor(self.HSV1.x,self.HSV1.y,self.HSV1.z)
					color = {col.r,col.g,col.b}
				else
					color = {self.Color1.r, self.Color1.g, self.Color1.b}
				end
			end

			local roll = math.Rand(-self.RollDelta, self.RollDelta)

			if self.PositionSpread ~= 0 then
				if self.PositionSpreadType == "SphereHollow" then
					pos = pos + Angle(math.Rand(-180, 180), math.Rand(-180, 180), math.Rand(-180, 180)):Forward() * self.PositionSpread
				elseif self.PositionSpreadType == "SphereFilled" then
					pos = pos + Angle(math.Rand(-180, 180), math.Rand(-180, 180), math.Rand(-180, 180)):Forward() * math.random() * self.PositionSpread
				elseif self.PositionSpreadType == "Box" then
					pos = pos + Vector(math.Rand(-self.PositionSpread, self.PositionSpread), math.Rand(-self.PositionSpread, self.PositionSpread), math.Rand(-self.PositionSpread, self.PositionSpread))
				end
			end
			if self.PositionSpreadType == "DiscFilled" then
				local angle = math.rad(math.Rand(self.MinAngle,self.MaxAngle))
				local right = originalAng_norm_right * self.PositionSpread2.y*math.cos(angle)*math.random()
				local up = originalAng_norm_up * self.PositionSpread2.z*math.sin(angle)*math.random()
				pos = pos + right + up + Angle(math.Rand(-180, 180), math.Rand(-180, 180), math.Rand(-180, 180)):Forward() * math.random() * self.PositionSpread
				pos = pos + Angle(math.Rand(-180, 180), math.Rand(-180, 180), math.Rand(-180, 180)):Forward() * math.random() * self.PositionSpread
			elseif self.PositionSpreadType == "DiscHollow" then
				local angle = math.rad(math.Rand(self.MinAngle,self.MaxAngle))
				--local forward = originalAng_norm_forward * alt_vec_dir.x
				local right = originalAng_norm_right * self.PositionSpread2.y*math.cos(angle)
				local up = originalAng_norm_up * self.PositionSpread2.z*math.sin(angle)
				pos = pos + right + up + Angle(math.Rand(-180, 180), math.Rand(-180, 180), math.Rand(-180, 180)):Forward() * math.random() * self.PositionSpread
			else
				do
					local vecAdd = Vector(
						math.Rand(-self.PositionSpread2.x, self.PositionSpread2.x),
						math.Rand(-self.PositionSpread2.x, self.PositionSpread2.y),
						math.Rand(-self.PositionSpread2.z, self.PositionSpread2.z)
					)
					vecAdd:Rotate(originalAng)
					pos = pos + vecAdd
				end
			end

			local ang_2d = Angle(math.rad(self.ParticleAngle.r),0,0)
			local angvel_2d = Angle(math.rad(self.ParticleAngleVelocity.z),0,0)
			--seems like 2D particles are radian-based, but users want degrees to have comparable angles and speeds
			--I think the convention is that this sort of rotation is roll though, so we'll use z instead of x
			for i = 1, double do
				local particle
				local material = self.Materialm or self.Material
				local basematerial = self.Materialm or self.Material
				if self.ThinkFunction == "SpriteCard2" then
					local matname = basematerial:GetName()
					local kvs = basematerial:GetKeyValues()
					if not expanded_mats_pool[matname] or self.FireOnce then
						expanded_mats_pool[matname] = {}
						for i=1, basematerial:GetTexture("$basetexture"):GetNumAnimationFrames(), 1 do
							expanded_mats_pool[matname][i] = pac.CreateMaterial(basematerial:GetName() .. "_" .. i, "UnlitGeneric", kvs)
							expanded_mats_pool[matname][i]:SetTexture("$basetexture", basematerial:GetTexture("$basetexture"))
							expanded_mats_pool[matname][i]:SetInt("$frame", i)
						end
					end

					particle = emt:Add(expanded_mats_pool[matname][1], pos)
					particle.frame = 1
					particle.mat_name = matname
					particle.mat_series = expanded_mats_pool[matname]
				else
					material = basematerial
					particle = emt:Add(material, pos)
				end
				
				if self.particle_think_function ~= nil and isfunction(self.particle_think_function) then
					particle:SetNextThink(CurTime())
					particle.thinktime = self.ThinkTime
					particle.birth = CurTime()
					particle.part = self

					particle:SetThinkFunction(self.particle_think_function)
					particle.material = material
				end

				if self.OwnerVelocityMultiplier ~= 0 then
					local owner = self:GetRootPart():GetOwner()
					if owner:IsValid() then
						vec = vec + (owner:GetVelocity() * self.OwnerVelocityMultiplier)
					end
				end

				local final_vec
				if alt_vec_dir then
					local forward = originalAng_norm_forward * alt_vec_dir.x
					local right = originalAng_norm_right * alt_vec_dir.y
					local up = originalAng_norm_up * alt_vec_dir.z
					--print(up:Length())
					local consolidated_spread_ang = (forward + right + up)
					
					local ang2 = originalAng:Forward()
					ang2:Rotate(added_dir_rotation)
					final_vec = (ang2 + (consolidated_spread_ang + ang2) / nonzero_vel)
					local velocity = nonzero_vel
					--if self.Velocity then velocity = self.SpreadVector.x end
					particle:SetVelocity((ang2 + (consolidated_spread_ang + ang2) / nonzero_vel) * velocity)
				else
					final_vec = (vec + ang)
					particle:SetVelocity(final_vec * self.Velocity)
				end

				particle:SetColor(unpack(color))
				particle:SetColor(unpack(color))

				local life = math.Clamp(self.DieTime, 0.0001, 50)
				if self.AddFrametimeLife then
					life = life + FrameTime()
				end
				particle:SetDieTime(life)

				particle:SetStartAlpha(self.StartAlpha)
				particle:SetEndAlpha(self.EndAlpha)
				particle:SetStartSize(self.StartSize)
				particle:SetEndSize(self.EndSize)
				particle:SetStartLength(self.StartLength)
				particle:SetEndLength(self.EndLength)

				if self.RandomRollSpeed ~= 0 then
					particle:SetRoll(self.RandomRollSpeed * 36)
				end

				if self.RollDelta ~= 0 then
					particle:SetRollDelta(self.RollDelta + roll)
				end

				particle:SetAirResistance(self.AirResistance)
				particle:SetBounce(self.Bounce)
				particle:SetGravity(self.Gravity)
				local rotation_matrix = Matrix()
				if self["3D"] then
					if self.ZeroAngle then
						particle:SetAngles(Angle(0,0,0) + self.ParticleAngle)
					else
						rotation_matrix:Rotate(originalAng)
						local post_rotation
						if self.FireDirectionToAngle then
							--final_vec = (particle:GetAngles() + self.ParticleAngle + final_vec:Angle())
							post_rotation = (self.ParticleAngle + particle:GetVelocity():Angle())
							rotation_matrix:Rotate(self.ParticleAngle + particle:GetVelocity():Angle())
						elseif self.PositionSpreadToAngle then
							post_rotation = self.ParticleAngle + (pos - original_pos):Angle()
							rotation_matrix:Rotate(self.ParticleAngle + (pos - original_pos):Angle())
						else
							post_rotation = particle:GetAngles() + self.ParticleAngle
							rotation_matrix:Rotate(self.ParticleAngle)
						end
						if double == 2 and i == 2 then
							rotation_matrix:Rotate(half_turn)
							particle:SetAngles(rotation_matrix:GetAngles())
						else
							particle:SetAngles(rotation_matrix:GetAngles())
						end
					end
					--[[if double == 2 then
						local ang_
						if i == 1 then
							ang_ = (ang * -1):Angle()
						elseif i == 2 then
							ang_ = ang:Angle()
						end
	
						particle:SetAngles(ang_)
					else
						particle:SetAngles(ang:Angle())
					end]]
				else
					ang_ = ang_2d
					particle:SetAngles(ang_2d)
				end

				particle:SetLighting(self.Lighting)

				if not self.Follow then
					particle:SetCollide(self.Collide)
				end

				if self.Sliding then
					particle:SetCollideCallback(SlideCallback)
				end

				if self["3D"] then
					if not self.Sliding then
						if i == 1 and not self.StickToSurface then
							particle:SetCollideCallback(RemoveCallback)
						else
							if i == 1 then
								particle:SetCollideCallback(StickCallback)
							else
								particle.is_doubleside = true
								particle:SetCollideCallback(StickCallback)
							end
						end
					end
					rotation_matrix:Identity()
					--rotation_matrix:Rotate(-originalAng)
					rotation_matrix:Rotate(Angle(self.ParticleAngleVelocity.x, self.ParticleAngleVelocity.y, self.ParticleAngleVelocity.z))
					
					--particle:SetAngleVelocity(rotation_matrix:GetAngles())
					particle:SetAngleVelocity(Angle(self.ParticleAngleVelocity.x, self.ParticleAngleVelocity.y, self.ParticleAngleVelocity.z))
					

					particle.ParticleAngle = self.ParticleAngle
					particle.Align = self.AlignToSurface
					particle.Stick = self.StickToSurface
					particle.StickLifeTime = self.StickLifetime
					particle.StickStartSize = self.StickStartSize
					particle.StickEndSize = self.StickEndSize
					particle.StickStartAlpha = self.StickStartAlpha
					particle.StickEndAlpha = self.StickEndAlpha
				else
					if self.RemoveOnCollide then particle:SetCollideCallback(RemoveCallback) end
					--maybe we can still use particle angle velocity on 2D ones
					if self.ParticleAngleVelocity.x ~= 50 then --but why for the love of god did we decide to default it to 50 50 50
						--everyone will have their particles spinning out of control unless I exclude this value specifically
						particle:SetAngleVelocity(angvel_2d)
					end
				end

			end
		end


		self.NextShot = pac.RealTime + self.FireDelay
	end
	self.FirstShot = false
end

BUILDER:Register()
