--------------------------------------------------------------------------
--[[ Dynamic Music ]]
--------------------------------------------------------------------------

if not TheNet:IsDedicated() then
	local MUSIC_VOLUME_OVERRIDES =
	{
		["dontstarve/music/music_danger_winter"] = 0.5,
	}

	AddComponentPostInit("dynamicmusic", function(self, inst)
		local _soundemitter = nil
		local _triggeredevent = nil
		local _triggeredlevel = nil

		local OnPlayerActivated = nil
		local StartTriggeredDanger = nil

		local function StartTriggeredDangerEX(player, data, ...)
			local name = data ~= nil and data.name or "default"
			local level = data ~= nil and data.level or 1
			if _triggeredevent == name or _triggeredlevel == level or not Tykvesh.GetUpvalue(StartTriggeredDanger, "_triggeredlevel") then
				_triggeredevent = name
				_triggeredlevel = level
				return StartTriggeredDanger(player, data, ...)
			end
		end

		local function _OnPlayerActivated(inst, player)
			inst:RemoveEventCallback("playeractivated", _OnPlayerActivated)

			for i, v in ipairs(inst.event_listening.playeractivated[inst]) do
				local StartPlayerListeners = Tykvesh.GetUpvalue(v, "StartPlayerListeners")
				if StartPlayerListeners ~= nil then
					StartTriggeredDanger = Tykvesh.GetUpvalue(StartPlayerListeners, "StartTriggeredDanger")
					if StartTriggeredDanger ~= nil then
						OnPlayerActivated = v
						break
					end
				end
			end

			if StartTriggeredDanger ~= nil then
				inst:RemoveEventCallback("triggeredevent", StartTriggeredDanger, player)
				inst:ListenForEvent("triggeredevent", StartTriggeredDangerEX, player)

				Tykvesh.SetUpvalue(OnPlayerActivated, "StartPlayerListeners", "StartTriggeredDanger", StartTriggeredDangerEX)
				Tykvesh.SetUpvalue(OnPlayerActivated, "StopPlayerListeners", "StartTriggeredDanger", StartTriggeredDangerEX)
			end
		end

		local SoundEmitterProxy = setmetatable(
		{
			PlaySound = function(self, sound, type, volume, ...)
				return _soundemitter:PlaySound(sound, type, volume or MUSIC_VOLUME_OVERRIDES[sound], ...)
			end,
		},
		{
			__index = function(table, key)
				table[key] = function(self, ...)
					return _soundemitter[key](_soundemitter, ...)
				end
				return table[key]
			end,
		})

		local function onsoundemitter(soundemitter)
			_soundemitter = soundemitter
			return SoundEmitterProxy
		end

		inst:ListenForEvent("playeractivated", _OnPlayerActivated)
		inst:ListenForEvent("playeractivated", function(inst, player)
			if OnPlayerActivated ~= nil then
				Tykvesh.BranchUpvalue(OnPlayerActivated, "StartSoundEmitter", "_soundemitter", onsoundemitter)
			end
		end)
	end)
end

--------------------------------------------------------------------------
--[[ Crab King ]]
--------------------------------------------------------------------------

if not TheNet:GetIsServer() then
	local function PushMusicEX(PushMusic, inst, ...)
		if not inst:HasTag("epic") then
			inst._playingmusic = false
		else
			PushMusic(inst, ...)
		end
	end

	AddPrefabPreInit("crabking", function(fn)
		pcall(Tykvesh.BranchUpvalue, fn, "PushMusic", PushMusicEX)
	end)
end

--------------------------------------------------------------------------
--[[ Shadow Pieces ]]
--------------------------------------------------------------------------

if not TheNet:IsDedicated() then
	local function UsePointFiltering(inst)
		inst.AnimState:UsePointFiltering(true)
	end

	AddPrefabPostInit("shadow_rook", UsePointFiltering)
	AddPrefabPostInit("shadow_knight", UsePointFiltering)
	AddPrefabPostInit("shadow_bishop", UsePointFiltering)
	AddPrefabPostInit("shadow_bishop_fx", UsePointFiltering)
end

--[[!]] if not TheNet:GetIsServer() then return end

--------------------------------------------------------------------------
--[[ Malbatross ]]
--------------------------------------------------------------------------

AddStategraphPostInit("malbatross", function(sg)
	local function MakeShadowTweener(inst)
		if inst.components.shadowtweener == nil then
			inst:AddComponent("shadowtweener")
			inst.components.shadowtweener:SetSize(6, 2)
		end
	end

	local function ClearTween(inst)
		inst.components.shadowtweener:ClearTween()
	end

	Tykvesh.Parallel(sg.states.arrive, "onexit", ClearTween)
	Tykvesh.Parallel(sg.states.arrive, "onenter", function(inst)
		MakeShadowTweener(inst)
		inst.components.shadowtweener:StartTween(Vector3(0, 0), Vector3(6, 2), 30 * FRAMES)
	end, true)

	Tykvesh.Parallel(sg.states.depart, "onexit", ClearTween)
	Tykvesh.Parallel(sg.states.depart, "onenter", function(inst)
		MakeShadowTweener(inst)
		inst.components.shadowtweener:StartTween(Vector3(6, 2), Vector3(0, 0), 20 * FRAMES, 30 * FRAMES)
	end, true)
end)

--------------------------------------------------------------------------
--[[ Eye of Terror ]]
--------------------------------------------------------------------------

AddStategraphPostInit("eyeofterror", function(sg)
	local function DisableShadow(inst)
		inst.DynamicShadow:Enable(false)
	end

	local function EnableShadow(inst)
		inst.DynamicShadow:Enable(true)
	end

	Tykvesh.Parallel(sg.states.arrive_delay, "onenter", DisableShadow)
	Tykvesh.Parallel(sg.states.arrive_delay, "onexit", EnableShadow)
	Tykvesh.Parallel(sg.states.flyback_delay, "onenter", DisableShadow)
	Tykvesh.Parallel(sg.states.flyback_delay, "onexit", EnableShadow)

	local function MakeShadowTweener(inst)
		if inst.components.shadowtweener == nil then
			inst:AddComponent("shadowtweener")
			inst.components.shadowtweener:SetSize(6, 2)
		end
	end

	local function ClearTween(inst)
		inst.components.shadowtweener:ClearTween()
	end

	Tykvesh.Parallel(sg.states.arrive, "onexit", ClearTween)
	Tykvesh.Parallel(sg.states.arrive, "onenter", function(inst)
		MakeShadowTweener(inst)
		inst.components.shadowtweener:StartTween(Vector3(0, 0), Vector3(4.5, 1.75), 7 * FRAMES, 36 * FRAMES, function(inst)
			inst.components.shadowtweener:StartTween(Vector3(4.5, 1.75), Vector3(6, 2), 10 * FRAMES, 73 * FRAMES)
		end)
	end, true)

	Tykvesh.Parallel(sg.states.flyaway, "onexit", ClearTween)
	Tykvesh.Parallel(sg.states.flyaway, "onenter", function(inst)
		MakeShadowTweener(inst)
		inst.components.shadowtweener:StartTween(Vector3(6, 2), Vector3(0, 0), 25 * FRAMES, 18 * FRAMES)
	end, true)

	Tykvesh.Parallel(sg.states.flyback, "onexit", ClearTween)
	Tykvesh.Parallel(sg.states.flyback, "onenter", function(inst)
		MakeShadowTweener(inst)
		inst.components.shadowtweener:StartTween(Vector3(0, 0), Vector3(6, 2), 30 * FRAMES)
	end, true)
end)