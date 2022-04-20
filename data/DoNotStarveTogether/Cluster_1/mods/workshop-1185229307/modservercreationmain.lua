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
}

--------------------------------------------------------------------------

local locale = LanguageTranslator ~= nil and LanguageTranslator.defaultlang or TheNet:GetLanguageCode()
if type(locale) == "string" then
	modinfo.SetLocale(locale, modinfo)
end

local success, ModConfigurationScreen = pcall(require, "screens/redux/modconfigurationscreen")

if success and not ModConfigurationScreen._epichealthbarpatched then
	ModConfigurationScreen._epichealthbarpatched = true

	Tykvesh.Branch(ModConfigurationScreen, "_ctor", function(ctor, self, _modname, client_config, ...)
		if _modname == modname and not client_config then
			self._epichealthbardirty = true
			client_config = true
		end
		return ctor(self, _modname, client_config, ...)
	end)

	Tykvesh.Parallel(ModConfigurationScreen, "Apply", function(self)
		if self._epichealthbardirty then
			KnownModIndex:SaveConfigurationOptions(Tykvesh.Dummy, self.modname, self:CollectSettings(), false)
		end
	end)
end