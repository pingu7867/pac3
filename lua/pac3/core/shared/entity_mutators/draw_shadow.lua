local MUTATOR = {}

MUTATOR.ClassName = "draw_shadow"

function MUTATOR:WriteArguments(b)
	--assert(b != true and b != false, "invalid argument")
	net.WriteBool(b)
end

function MUTATOR:ReadArguments()
	return net.ReadBool(b)
end

if SERVER then
	function MUTATOR:StoreState()
		return true
	end

	function MUTATOR:Mutate(b)
		self.Entity:DrawShadow(b)
	end
end

pac.emut.Register(MUTATOR)