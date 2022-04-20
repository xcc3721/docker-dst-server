for i, v in ipairs({ "_G", "setmetatable", "rawget" }) do
	env[v] = GLOBAL[v]
end

setmetatable(env,
{
	__index = function(table, key) return rawget(_G, key) end
})

--------------------------------------------------------------------------

local mem = setmetatable({}, { __mode = "v" })
local function argtostring(...) local key = ""; for i, v in ipairs(arg) do key = key .. tostring(v) end; return key end
local function memset(...) return mem[argtostring(...)] end
local function memget(value, ...) mem[argtostring(...)] = value end

Tykvesh =
{
	Dummy = function() end,
	InLimbo = { "INLIMBO" },

	Parallel = function(root, key, fn, nopriority)
		if type(root) == "table" then
			local oldfn = root[key]
			local newfn = oldfn and memset("PARALLEL", oldfn, fn)
			if not oldfn or newfn then
				root[key] = newfn or fn
			else
				if nopriority then
					root[key] = function(...) oldfn(...) return fn(...) end
				else
					root[key] = function(...) fn(...) return oldfn(...) end
				end
				memget(root[key], "PARALLEL", oldfn, fn)
			end
		end
	end,

	Branch = function(root, key, fn)
		if type(root) == "table" then
			local oldfn = root[key]
			if oldfn then
				local newfn = memset("BRANCH", oldfn, fn)
				if newfn then
					root[key] = newfn
				else
					root[key] = function(...) return fn(oldfn, ...) end
					memget(root[key], "BRANCH", oldfn, fn)
				end
			end
		end
	end,

	GetUpvalue = function(fn, ...)
		local prevfn, i
		for _, name in ipairs(arg) do
			for _i = 1, math.huge do
				local _name, _upvalue = debug.getupvalue(fn, _i)
				if _upvalue == nil then
					return
				elseif _name == name then
					fn, i, prevfn = _upvalue, _i, fn
					break
				end
			end
		end
		return fn, i, prevfn
	end,

	SetUpvalue = function(fn, ...)
		local upvalue = table.remove(arg)
		local fn, i, prevfn = Tykvesh.GetUpvalue(fn, unpack(arg))
		debug.setupvalue(prevfn, i, upvalue)
	end,

	BranchUpvalue = function(fn, ...)
		local upvalue = table.remove(arg)
		local fn, i, prevfn = Tykvesh.GetUpvalue(fn, unpack(arg))
		if type(fn) ~= "function" then
			debug.setupvalue(prevfn, i, upvalue(fn))
		else
			debug.setupvalue(prevfn, i, function(...) return upvalue(fn, ...) end)
		end
	end,

	Browse = function(table, ...)
		for i, v in ipairs(arg) do
			if type(table) ~= "table" then
				return
			end
			table = table[v]
		end
		return table
	end,

	OnEntityReplicated = function(inst, fn, nopriority)
		if TheWorld.ismastersim or inst.Network == nil then
			StartThread(fn, inst.GUID, inst)
		else
			Tykvesh.Parallel(inst, "OnEntityReplicated", fn, nopriority)
		end
	end,
}

if rawget(_G, "Tykvesh") == nil then
	rawset(_G, "Tykvesh", Tykvesh)
else
	for name, data in pairs(Tykvesh) do
		_G["Tykvesh"][name] = data
	end
	Tykvesh = _G["Tykvesh"]
end

--------------------------------------------------------------------------

PrefabFiles = {}
Assets = {}

function AddPrefab(file) table.insert(PrefabFiles, file) end
function AddAsset(type, file, param) table.insert(Assets, Asset(type, file, param)) end

postinitfns.PrefabPreInit = {}

function AddPrefabPreInit(name, fn)
	if postinitfns.PrefabPreInit[name] == nil then
		postinitfns.PrefabPreInit[name] = {}
	end
	table.insert(postinitfns.PrefabPreInit[name], fn)
end

AddPrefabPostInit("world", function(inst)
	for name, fns in pairs(postinitfns.PrefabPreInit) do
		local prefab = _G.Prefabs[name]
		if prefab ~= nil then
			Tykvesh.Branch(prefab, "fn", function(fn, ...)
				for i, v in ipairs(fns) do
					v(fn)
				end
				prefab.fn = fn
				return fn(...)
			end)
		end
	end
	postinitfns.PrefabPreInit = {}
end)

--------------------------------------------------------------------------

local MODULES =
{
	"epichealthbar",
	"epicfixes",
}

for index, module in ipairs(MODULES) do
	local result = kleiloadlua(MODROOT .. "scripts/" .. module .. ".lua")
	if type(result) == "function" then
		RunInEnvironment(result, env)
	end
end