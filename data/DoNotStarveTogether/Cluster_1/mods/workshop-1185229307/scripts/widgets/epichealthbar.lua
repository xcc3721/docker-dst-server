local Widget = require "widgets/widget"
local Text = require "widgets/text"
local Image = require "widgets/image"
local UIAnim = require "widgets/uianim"

local SCALE = 0.875
local HIDDEN_Y = 55.55555 * SCALE
local SHOWN_Y = -49.48571 * SCALE
local HEADER_SIZE = 30.5
local HEADER_WIDTH = 300
local NUMBER_SIZE = 24.71875 / SCALE
local METER_WIDTH = 490
local METER_HEIGHT = 20
local SCISSOR_WIDTH = METER_WIDTH + 10
local SCISSOR_HEIGHT = METER_HEIGHT + 10
local MOVE_TIME = 0.4
local METER_TINT_TIME = 0.5
local METER_BURST_TIME = 2
local BURST_ATTACK_WINDOW = 0.3
local OUT_OF_DATE_COLOUR = { 243 / 255, 95 / 255, 121 / 255, 1 }
local OUT_OF_DATE_DURATION = 10
local TINY_DAMAGE = 10
local HUGE_DAMAGE = 200
local MIN_BRIGHTNESS = 0.6
local MAX_BRIGHTNESS = 1.1

local DROPS_SCALE = 2
local DROPS_PRESETS = {}
for x = -200, 200, 50 do
	table.insert(DROPS_PRESETS, { pos = Vector3(x, 90 + 7.5 * UnitRand()), time = math.random() })
end

local TARGET_BIAS = 0.6
local ENGAGED_DIST = 20
local DISENGAGED_DIST = 30
local FRUSTUM_BIAS = 10
local FRUSTUM_LIMIT = 77.29
local DANGER_DURATION = 10
local DANGER_FADEOUT = 5 * FRAMES
local DANGER_COOLDOWN = 1.5

local COMBAT_RANGE = 10
local COMBAT_TAGS = { "_combat" }

local function RGBA(r, g, b, a)
	if type(r) == "table" then
		return { r = r[1] or 1, g = r[2] or 1, b = r[3] or 1, a = r[4] or 1 }
	else
		return { r = r or 1, g = g or 1, b = b or 1, a = a or 1 }
	end
end

local function commanumber(value)
	local count = nil
	repeat value, count = string.gsub(value, "^(-?%d+)(%d%d%d)", "%1,%2") until count == 0
	return value
end

local function canceltintto(widget)
	widget.inst.components.uianim.tint_t = nil
end

local function timeclamp(table, key, dt, min)
	local time = table[key]
	if time ~= nil then
		time = time - dt
		if min ~= nil then
			time = math.min(min, time)
		end
		if time > 0 then
			table[key] = time
			return true
		else
			table[key] = nil
		end
	end
	return false
end

local Meter = Class(UIAnim, function(self)
	UIAnim._ctor(self)

	self:SetScissor(SCISSOR_WIDTH / -2, SCISSOR_HEIGHT / -2, SCISSOR_WIDTH, SCISSOR_HEIGHT)

	self:GetAnimState():SetBank("quagmire_hangry_bar")
	self:GetAnimState():SetBuild("epichealthbar")
	self:GetAnimState():PlayAnimation("bar", true)
	self:GetAnimState():AnimateWhilePaused(false)
end)

function Meter:SetTint(r, g, b)
	self.tint = { r, g, b, 1 }
	self:GetAnimState():SetMultColour(r, g, b, 1)
end

local MeterResist = Class(Widget, function(self)
	Widget._ctor(self, "MeterResist")

	self:SetScissor(SCISSOR_WIDTH / -2, SCISSOR_HEIGHT / -2, SCISSOR_WIDTH, SCISSOR_HEIGHT)

	self.alpha = 0.6
	self.time = 0
	self.intensity = 1
	self.frequency = 1000
	self.minspeed = 0
	self.maxspeed = 30
	self.speed = 0
	self._speed = 1

	self.img = self:AddChild(Image("images/global.xml", "square.tex"))
	self.img:ScaleToSize(METER_WIDTH, METER_WIDTH)
	self.img:SetRotation(45)
	self.img:SetBlendMode(BLENDMODE.AlphaAdditive)
	self.img:SetTint(0, 0, 0, 0)
	self.img:SetEffect("shaders/overheat.ksh")
	self.img:SetEffectParams(self.time, self.intensity, self.frequency, self._speed)

	self:Hide()
end)

MeterResist.OnHide = MeterResist.StopUpdating
MeterResist.OnShow = MeterResist.StartUpdating

function MeterResist:ShowResist(tint, resist)
	self.speed = Lerp(self.minspeed, self.maxspeed, resist)
	self.img:SetTint(tint[1], tint[2], tint[3], self.alpha)
	self.img:TintTo(RGBA(self.img.tint), RGBA(tint[1], tint[2], tint[3], 0), METER_BURST_TIME)
	self:Show()
end

function MeterResist:OnUpdate(dt)
	if self.img.tint[4] > 0 then
		self.time = self.time + self.speed * dt
		self.img:SetEffectParams(self.time, self.intensity, self.frequency, self._speed)
	else
		self:Hide()
	end
end

local MeterDrops = Class(Widget, function(self)
	Widget._ctor(self, "MeterDrops")

	self.width = METER_WIDTH / DROPS_SCALE
	self.height = METER_HEIGHT / DROPS_SCALE

	self:SetScale(DROPS_SCALE)
	self:SetScissor(self.width / -2, self.height / -2, self.width, self.height)

	self:Hide()
end)

function MeterDrops:ShowDrops(wet, instant, tint)
	if instant then
		canceltintto(self)
		if wet then
			self:Show()
			self:SetTint(tint[1], tint[2], tint[3], 1)
		else
			self:Hide()
		end
	else
		if wet then
			self:Show()
			self:TintTo(RGBA(self.tint), RGBA(tint[1], tint[2], tint[3], 1), METER_TINT_TIME)
			self.inst.components.uianim:OnWallUpdate(0)
		elseif self.shown then
			self:TintTo(RGBA(self.tint), RGBA(0, 0, 0, 0), METER_TINT_TIME, function() self:Hide() end)
		end
	end
end

function MeterDrops:SetTint(r, g, b, a)
	self.tint = { r, g, b, a }
	for anim in pairs(self.children) do
		anim:GetAnimState():SetMultColour(1, 1, 1, a)
		anim:GetAnimState():SetAddColour(r, g, b, 1)
	end
end

function MeterDrops:OnShow()
	if next(self.children) == nil then
		for i, v in ipairs(DROPS_PRESETS) do
			local anim = self:AddChild(UIAnim())
			anim:SetScale(i % 2 == 1 and -0.37 or 0.37, 0.37)
			anim:SetPosition(v.pos)
			anim:GetAnimState():SetBuild("paddle_over")
			anim:GetAnimState():SetBank("paddle_over")
			anim:GetAnimState():PlayAnimation("over", true)
			anim:GetAnimState():SetTime(anim:GetAnimState():GetCurrentAnimationLength() * v.time)
			anim:GetAnimState():AnimateWhilePaused(false)
		end
	end
end

function MeterDrops:OnHide()
	self:KillAllChildren()
	self:SetTint(0, 0, 0, 0)
end

function MeterDrops:SetEmptyPercent(percent)
	self:SetScissor(self.width / -2 + self.width * percent, self.height / -2, self.width * (1 - percent), self.height)
end

local PopupNumber = Class(Widget, function(self, value, colour, damaged, burst, huge, stimuli, wet, fxroot)
	Widget._ctor(self, "PopupNumber")

	self.size = 44 + ((burst or not damaged) and not huge and -2 or 0)
	self.value = math.max(1, math.floor(value + 0.5))
	self.colour = colour
	self.pop = burst or huge or not damaged
	self.burst = burst
	self.xoffs = (burst and 16 or 4) * UnitRand()
	self.yoffs = 10 * UnitRand()
	self.xoffs2 = 0
	self.yoffs2 = 0
	self.dir = self.xoffs < 0 and -1 or 1
	self.rise = 8
	self.drop = damaged and 24 or -8
	self.speed = 68
	self.progress = 0
	self.dtscale = math.clamp((damaged and 1000 or 100) / value, 0.3, 1)
	self.fxroot = fxroot

	if burst then
		self.speed = self.speed + self.speed * math.random()
		self.drop = self.drop * math.random()
		self.rise = self.rise * UnitRand()
		self.colour = {}
		for i, v in ipairs(colour) do
			self.colour[i] = v + 0.03 * UnitRand()
		end
	elseif huge then
		self.speed = self.speed + self.speed * 0.5 * math.random()
	end

	self.stimuli = stimuli
	if stimuli == "electric" then
		self.colour1 = shallowcopy(colour)
		self.colour2 = self:AddColour(TUNING.EPICHEALTHBAR.ELECTRIC2_ADDCOLOUR)
		self.colour3 = self:AddColour(TUNING.EPICHEALTHBAR.ELECTRIC3_ADDCOLOUR)
		self.colour = wet and self:AddColour(TUNING.EPICHEALTHBAR.ELECTRIC1_ADDCOLOUR) or self.colour2
	end

	self.text = self:AddChild(Text(NUMBERFONT, self.size, self.value, self.colour))

	self:StartUpdating()
	self:OnUpdate(0)
end)

function PopupNumber:AddColour(addcolour)
	local colour = { [4] = self.colour[4] }
	for i, v in ipairs(addcolour) do
		if self.colour[i] + v > 1.1 then
			colour[i] = self.colour[i] - v * 0.5
		else
			colour[i] = self.colour[i] + v
		end
	end
	return colour
end

function PopupNumber:FastForward()
	if not self.fastforward then
		self.fastforward = true

		local colour = self.text.colour
		self.text.SetTint = self.text.SetColour
		self.text:TintTo(RGBA(colour), RGBA(colour[1], colour[2], colour[3], 0), 0.2, function() self:Kill() end)
	end
end

function PopupNumber:OnUpdate(dt)
	if self.progress < 1 then
		self.progress = math.min(1, self.progress + dt * 8)

		local k = 1 - math.min(1, self.progress / 0.75)
		k = k * k
		if not self.fastforward then
			self.text:SetColour(self.colour[1], self.colour[2], self.colour[3], self.colour[4] * (1 - k * k))
		end

		k = 1 - self.progress
		k = k * k
		k = 1 - k * k
		self.xoffs2 = self.xoffs2 + dt * self.dir * self.speed
		self.yoffs2 = k * self.rise

		if self.pop then
			self:SetScale(2 - k)
		end
	elseif self.progress < 2 then
		dt = dt * self.dtscale

		self.progress = math.min(2, self.progress + dt * 3)

		if self.stimuli == "electric" then
			if self.progress <= 1.5 then
				local time = self.progress % 0.5
				if time <= 0.3 then
					self.colour = self.colour1
				elseif time <= 0.4 then
					self.colour = self.colour2
				else
					self.colour = self.colour3
				end
			else
				self.colour = self.colour1
			end
		end

		local k = math.max(0, self.progress - 1.1) / 0.9
		if not self.fastforward then
			self.text:SetColour(self.colour[1], self.colour[2], self.colour[3], self.colour[4] * (1 - k * k))
		end

		k = self.progress - 1
		self.xoffs2 = self.xoffs2 + dt * self.dir * self.speed
		self.yoffs2 = self.rise - self.drop * k * k
	else
		self:Kill()
		return
	end

	self.text:SetPosition(self.xoffs + self.xoffs2, self.yoffs + self.yoffs2)

	if self.burst and not self.fastforward and self.text.colour[4] > 0.5 then
		local time = 0.4
		local alpha = self.text.colour[4] * time
		local fx = self.fxroot:AddChild(Text(SMALLNUMBERFONT, self.text.size, self.text.string))
		fx.SetTint = fx.SetColour
		fx:SetTint(self.colour[1], self.colour[2], self.colour[3], alpha)
		fx:TintTo(RGBA(self.colour[1], self.colour[2], self.colour[3], alpha), RGBA(self.colour[1], self.colour[2], self.colour[3], 0), time)
		fx:SetPosition(self:GetPosition() + self.text:GetPosition())
		fx:ScaleTo(1, 0, time, function() fx:Kill() end)
	end
end

local function hasmusic(inst)
	return inst._playingmusic ~= nil or inst._musictask ~= nil
end

local function istarget(inst, target)
	return inst ~= target
		and (inst.replica.combat ~= nil and inst.replica.combat:GetTarget() == target)
		and (inst.replica.health ~= nil and not inst.replica.health:IsDead())
end

local function isincombat(inst)
	if inst.epichealth.lastwasdamagedtime == GetTime() or inst.replica.combat:IsValidTarget(inst.replica.combat:GetTarget()) then
		return true
	end
	for i, v in ipairs(AllPlayers) do
		if istarget(v, inst) then
			return true
		end
	end
	return FindEntity(inst, COMBAT_RANGE, istarget, COMBAT_TAGS, Tykvesh.InLimbo) ~= nil
end

local function isattackedbygroup(inst)
	local pos = inst:GetPosition()
	local rad = inst:GetPhysicsRadius(0)
	local num_attackers = 0
	for i, v in ipairs(TheSim:FindEntities(pos.x, 0, pos.z, COMBAT_RANGE, COMBAT_TAGS, Tykvesh.InLimbo)) do
		local range = TARGET_BIAS + rad + v.replica.combat:GetAttackRangeWithWeapon()
		if istarget(v, inst) and (v:HasTag("attack") or pos:Dist(v:GetPosition()) < range) then
			num_attackers = num_attackers + 1
			if num_attackers > 1 then
				return true
			end
		end
	end
	return false
end

local function ondanger(self, danger, olddanger)
	if danger ~= olddanger then
		if danger ~= nil and olddanger ~= nil then
			self.dangercooldown = not danger and DANGER_COOLDOWN or nil
		else
			self.dangercooldown = nil
		end
	end
end

local function ontarget(self, target, oldtarget)
	if target ~= nil and target ~= oldtarget then
		self.outdatedtimeleft = nil

		self.meter_resist:Hide()
		self.meter_burst:Hide()

		self._name = nil
		self.build = nil
		self.wet = nil
		self.stimuli = nil
		self.lastwasdamagedtime = nil
		self.percent = nil
		self.maxhealth = nil
		self.currenthealth = nil
		self.theme = TUNING.EPICHEALTHBAR.THEMES[target.prefab:upper()] or TUNING.EPICHEALTHBAR.METER_COLOUR

		for root in pairs(self.popuproot.children) do
			for popupnumber in pairs(root.children) do
				if popupnumber.FastForward ~= nil then
					popupnumber:FastForward()
				end
			end
		end
	end
end

local function onname(self, name, oldname)
	if name ~= nil and name ~= oldname then
		self.name_text:SetTruncatedString(name, HEADER_WIDTH, nil, true)
		self:ResetHeader()
	end
end

local function onwet(self, wet, oldwet)
	if wet ~= nil and wet ~= oldwet then
		local wet = wet and TUNING.EPICHEALTHBAR.WETNESS_METER
		local instant = oldwet == nil
		self.meter_drops:ShowDrops(wet, instant, self.metertint)
		self.meter_bg_drops:ShowDrops(wet, instant, self.bgtint)
	end
end

local function onbuild(self, build, oldbuild)
	if build ~= nil and build ~= oldbuild then
		local theme = shallowcopy(self.theme[build:upper()] or self.theme.GENERIC or self.theme)

		theme[4] = 1

		self.metertint = theme

		local brightness = theme[1] + theme[2] + theme[3]
		if brightness >= MIN_BRIGHTNESS then
			self.bgtint = TUNING.EPICHEALTHBAR.BACKGROUND1_COLOUR
			self.effecttint = theme
			if brightness >= MAX_BRIGHTNESS then
				self.popuptint = theme
			else
				local mult = Remap(brightness, MIN_BRIGHTNESS, MAX_BRIGHTNESS, MAX_BRIGHTNESS / MIN_BRIGHTNESS, 1)
				self.popuptint = {}
				for i, v in ipairs(theme) do
					self.popuptint[i] = v * mult
				end
			end
		else
			self.bgtint = TUNING.EPICHEALTHBAR.BACKGROUND2_COLOUR
			self.effecttint = TUNING.EPICHEALTHBAR.DAMAGE_COLOUR
			self.popuptint = TUNING.EPICHEALTHBAR.DAMAGE_COLOUR
		end

		if oldbuild == nil then
			canceltintto(self.meter_bg)
			canceltintto(self.meter)
			self.meter_bg:SetTint(unpack(self.bgtint))
			self.meter:SetTint(unpack(theme))
		else
			self.meter_bg:TintTo(RGBA(self.meter_bg.tint), RGBA(self.bgtint), METER_TINT_TIME)
			self.meter:TintTo(RGBA(self.meter.tint), RGBA(theme), METER_TINT_TIME)
			if self.wet then
				onwet(self, self.wet, not self.wet)
			end
		end
	end
end

local function onlastwasdamagedtime(self, lastwasdamagedtime, oldlastwasdamagedtime)
	if lastwasdamagedtime ~= oldlastwasdamagedtime then
		self.burst = lastwasdamagedtime ~= nil
			and oldlastwasdamagedtime ~= nil
			and lastwasdamagedtime - oldlastwasdamagedtime <= BURST_ATTACK_WINDOW
			or isattackedbygroup(self.target)
	end
end

local function onpercent(self, percent, oldpercent)
	if percent ~= nil and percent ~= oldpercent then
		local meter_width = METER_WIDTH * (1 - percent)
		if meter_width > 0 then
			local meter_x = (METER_WIDTH - meter_width) / 2
			self.meter_bg:ScaleToSize(meter_width, METER_HEIGHT)
			self.meter_bg:SetPosition(meter_x, 0)
			self.meter_bg:Show()
		else
			self.meter_bg:Hide()
		end

		self.meter_bg_drops:SetEmptyPercent(percent)

		if oldpercent ~= nil then
			self:ShowBurst(oldpercent, percent)
		end
	end
end

local function onmaxhealth(self, maxhealth, oldmaxhealth)
	if maxhealth ~= nil and maxhealth ~= oldmaxhealth then
		self.maxhealth_text:SetString(commanumber(math.ceil(maxhealth)))

		self:RebuildPhases()

		if oldmaxhealth ~= nil then
			if maxhealth > oldmaxhealth then
				self:ShowBurst(0, self.percent)
			else
				self:ShowBurst(self.percent, 0)
			end
		end
	end
end

local function oncurrenthealth(self, currenthealth, oldcurrenthealth)
	if currenthealth ~= nil and currenthealth ~= oldcurrenthealth then
		self.currenthealth_text:SetString(commanumber(math.ceil(currenthealth)))

		if oldcurrenthealth ~= nil and TUNING.EPICHEALTHBAR.DAMAGE_NUMBERS then
			local delta = currenthealth - oldcurrenthealth
			local value = math.abs(delta)
			if currenthealth <= 0 then
				value = math.ceil(value)
			end
			self:ShowPopupNumber(value, delta < 0)
		end
	end
end

local function onoutdatedtimeleft(self, outdatedtimeleft, oldoutdatedtimeleft)
	if outdatedtimeleft ~= oldoutdatedtimeleft then
		local time = outdatedtimeleft or 0
		local percent = time / OUT_OF_DATE_DURATION

		if oldoutdatedtimeleft == nil then
			self.meter:SetTint(unpack(OUT_OF_DATE_COLOUR))
			self.meter_bg:SetTint(unpack(TUNING.EPICHEALTHBAR.BACKGROUND1_COLOUR))
		end
		self.meter_resist:ShowResist(OUT_OF_DATE_COLOUR, -1)

		onwet(self, false)
		onpercent(self, percent)
		onmaxhealth(self, time)
		oncurrenthealth(self, time)
	end
end

local function OnTriggeredEvent(self, data)
	if data ~= nil and data.name ~= nil then
		self.triggeredevents[data.name] = data.duration or DANGER_DURATION
		if self.triggeredevent and not self:IsEventSource(self.target, data.name) then
			self._eventaliases[self.target.prefab] = data.name
		end
	end
end

local function OnEpicTargetResisted(self, data)
	if self.target == data.target and TUNING.EPICHEALTHBAR.DAMAGE_RESISTANCE then
		self.meter_resist:ShowResist(self.effecttint, data.resist)
	end
end

local function OnEnableDynamicMusic(self, enabled)
	self.dangerdisabled = not enabled
end

local EpicHealthbar = Class(Widget, function(self, owner, version)
	Widget._ctor(self, "EpicHealthbar")

	self.owner = owner
	self.version = version
	self.triggeredevents = {}
	self._eventaliases = {}
	self._eventtriggers = {}

	self.root = self:AddChild(Widget("root"))
	self.root:SetScale(SCALE)
	self.root:SetPosition(Vector3(TUNING.EPICHEALTHBAR.HORIZONTAL_OFFSET, HIDDEN_Y))

	local mouseover = self.root:AddChild(Image("images/ui.xml", "blank.tex"))
	mouseover:ScaleToSize(350, 40)
	mouseover:SetPosition(0, 30)

	local mouseover = self.root:AddChild(Image("images/ui.xml", "blank.tex"))
	mouseover:ScaleToSize(SCISSOR_WIDTH, SCISSOR_HEIGHT)

	local mouseover = self.root:AddChild(Image("images/ui.xml", "blank.tex"))
	mouseover:ScaleToSize(110, 90)

	self.barroot = self.root:AddChild(Widget("barroot"))
	self.barroot:SetClickable(false)

	self.meter = self.barroot:AddChild(Meter())

	self.meter_resist = self.barroot:AddChild(MeterResist())

	self.meter_drops = self.barroot:AddChild(MeterDrops())

	self.meter_bg = self.barroot:AddChild(Image("images/global.xml", "square.tex"))
	self.meter_bg:SetBlendMode(BLENDMODE.Disabled)
	self.meter_bg:Hide()

	self.meter_bg_drops = self.barroot:AddChild(MeterDrops())

	self.meter_burst = self.barroot:AddChild(Image("images/global.xml", "square.tex"))
	self.meter_burst:SetBlendMode(BLENDMODE.AlphaBlended)
	self.meter_burst:Hide()

	self.meter_fg = self.barroot:AddChild(Image("images/hud/epichealthbar.xml", "meter_fg.tex"))
	self.meter_fg:ScaleToSize(METER_WIDTH, METER_HEIGHT)

	self.frame = self.barroot:AddChild(Image("images/hud/epichealthbar.xml", "frame.tex"))
	self.frame:SetPosition(0, -2)
	self.frame:SetTint(unpack(TUNING.EPICHEALTHBAR.FRAME_COLOUR))

	self.frame_phases = self.barroot:AddChild(Widget("frame_phases"))
	self.frame_phases:SetPosition(0, 0.5)

	self.name_text = self.barroot:AddChild(Text(TALKINGFONT, HEADER_SIZE))
	self.name_text:SetPosition(1, 28)

	self.currenthealth_text = self.barroot:AddChild(Text(NUMBERFONT, NUMBER_SIZE))
	self.currenthealth_text:SetPosition(1.5, -29)

	self.maxhealth_text = self.barroot:AddChild(Text(self.currenthealth_text.font, self.currenthealth_text.size))
	self.maxhealth_text:SetPosition(self.currenthealth_text:GetPosition())
	self.maxhealth_text:Hide()

	self.popuproot = self:AddChild(Widget("popuproot"))
	self.popuproot:SetScale(SCALE)
	self.popuproot:SetClickable(false)

	self.popupfxroot = self.popuproot:AddChild(Widget("popupfxroot"))
	self.tinydamageroot = self.popuproot:AddChild(Widget("tinydamageroot"))
	self.damageroot = self.popuproot:AddChild(Widget("damageroot"))
	self.hugedamageroot = self.popuproot:AddChild(Widget("hugedamageroot"))
	self.healroot = self.popuproot:AddChild(Widget("healroot"))

	self:Hide()

	self.inst:ListenForEvent("newepictarget", function(owner, target) self:StartUpdating() end, owner)
	self.inst:ListenForEvent("triggeredevent", function(owner, data) OnTriggeredEvent(self, data) end, owner)
	self.inst:ListenForEvent("epictargetresisted", function(owner, data) OnEpicTargetResisted(self, data) end, owner)
	self.inst:ListenForEvent("enabledynamicmusic", function(world, enabled) OnEnableDynamicMusic(self, enabled) end, TheWorld)

	if self:HasTargets() then
		self:StartUpdating()
	end
end,
{
	danger = ondanger,
	target = ontarget,
	_name = onname,
	build = onbuild,
	wet = onwet,
	lastwasdamagedtime = onlastwasdamagedtime,
	percent = onpercent,
	maxhealth = onmaxhealth,
	currenthealth = oncurrenthealth,
	outdatedtimeleft = onoutdatedtimeleft,
})

function EpicHealthbar:OnGainFocus()
	self:ResetHeader()
	self.currenthealth_text:Hide()
	self.maxhealth_text:Show()
end

function EpicHealthbar:OnLoseFocus()
	self:ResetHeader()
	self.currenthealth_text:Show()
	self.maxhealth_text:Hide()
end

function EpicHealthbar:ResetHeader()
	if self.updatetext ~= nil then
		if self.focus or self.target == nil then
			self.name_text:Hide()
			self.updatetext:Show()
		else
			self.name_text:Show()
			self.updatetext:Hide()
		end
	else
		self.name_text:Show()
	end
end

function EpicHealthbar:MakeOutdated()
	if self.updateicon ~= nil then
		return
	end

	self.updateicon = self.barroot:AddChild(Image("images/frontend.xml", "circle_red.tex"))
	self.updateicon:SetScale(0.65)
	self.updateicon:SetPosition(160, 60)
	self.updateicon:MoveTo(self.updateicon:GetPosition(), Vector3(160, 30), MOVE_TIME)
	self.updateicon.icon = self.updateicon:AddChild(Image("images/button_icons.xml", "update.tex"))
	self.updateicon.icon:SetScale(0.15)
	self.updateicon.icon:SetPosition(-1, 0)

	local string = Tykvesh.Browse(STRINGS, "UI", "MAINSCREEN", "MOTD_NEW_UPDATE")
	if string ~= nil then
		self.updatetext = self.barroot:AddChild(Text(BODYTEXTFONT, HEADER_SIZE * 1.05, nil, OUT_OF_DATE_COLOUR))
		self.updatetext:SetTruncatedString(string:sub(0, string:find("\n")), HEADER_WIDTH, nil, true)
		self.updatetext:SetPosition(0, 32)
		self:ResetHeader()

		if not self.active
			and not TheNet:GetServerLANOnly()
			and TheNet:GetServerMaxPlayers() ~= 1
			and TheNet:GetAllowIncomingConnections()
			and (TheNet:GetIsServerAdmin() or not TheNet:GetServerHasPresentAdmin()) then

			local PersistentData = require "util/persistentdata"
			local OutdatedVersion = PersistentData("epichealthbar_version")

			if OutdatedVersion:Get() ~= self.version then
				OutdatedVersion:Set(self.version)

				self.outdatedtimeleft = OUT_OF_DATE_DURATION
				self:StartUpdating()
			end
		end
	end
end

function EpicHealthbar:RebuildPhases()
	self.frame_phases:KillAllChildren()

	if self.target ~= nil and TUNING.EPICHEALTHBAR.FRAME_PHASES then
		local phases = TUNING.EPICHEALTHBAR.PHASES[self.target.prefab:upper()]
		if type(phases) == "function" then
			phases = phases(self.target)
		end
		if phases ~= nil then
			for i, v in ipairs(phases) do
				local phase = self.frame_phases:AddChild(Image("images/hud/epichealthbar.xml", "phase.tex"))
				phase:SetPosition(METER_WIDTH / -2 - 1.5 + (METER_WIDTH + 1) * v, 0)
				phase:SetTint(unpack(self.frame.tint))
			end
		end
	end
end

function EpicHealthbar:GetEffectTint(damaged, override)
	return (not damaged and TUNING.EPICHEALTHBAR.HEAL_COLOUR)
		or (self.stimuli == "fire" and TUNING.EPICHEALTHBAR.FIRE_COLOUR)
		or (override or TUNING.EPICHEALTHBAR.DAMAGE_COLOUR)
end

function EpicHealthbar:ShowBurst(from, to)
	local burst_width = METER_WIDTH * (from - to)
	local burst_x = -METER_WIDTH / 2 + METER_WIDTH * to + burst_width / 2
	local r, g, b = unpack(self:GetEffectTint(from > to))
	self.meter_burst:ScaleToSize(burst_width, METER_HEIGHT)
	self.meter_burst:SetPosition(burst_x, 0)
	self.meter_burst:SetTint(r, g, b, 0.8)
	self.meter_burst:TintTo(RGBA(self.meter_burst.tint), RGBA(r, g, b, 0), METER_BURST_TIME, function() self.meter_burst:Hide() end)
	self.meter_burst:Show()
end

function EpicHealthbar:ShowPopupNumber(value, damaged)
	if self.shown then
		local huge = value >= HUGE_DAMAGE
		local colour = self:GetEffectTint(damaged, self.popuptint)
		local parent = damaged and (huge and self.hugedamageroot or value <= TINY_DAMAGE and self.tinydamageroot or self.damageroot) or self.healroot
		local pos = Vector3(-METER_WIDTH / 2 + METER_WIDTH * self.percent, self:GetHeight())
		local popupnumber = parent:AddChild(PopupNumber(value, colour, damaged, damaged and self.burst, huge, self.stimuli, self.wet, self.popupfxroot))
		popupnumber:SetPosition(pos)
		if self:IsMoving() then
			popupnumber:MoveTo(pos, Vector3(pos.x, SHOWN_Y), self:GetMoveTime(true))
		end
	end
end

function EpicHealthbar:GetHeight()
	return self.root:GetPosition().y
end

function EpicHealthbar:GetMoveTime(active)
	if active == nil then
		active = self.active
	end
	local current_y = self:GetHeight()
	local min_y = active and SHOWN_Y or HIDDEN_Y
	local max_y = active and HIDDEN_Y or SHOWN_Y
	return Remap(current_y, min_y, max_y, 0, MOVE_TIME)
end

function EpicHealthbar:GetClampTime()
	if not self.owner.HUD.shown and self.owner:HasTag("busy") then
		return self.owner.AnimState:GetCurrentAnimationLength() - 0.5
	end
end

function EpicHealthbar:IsMoving()
	return self.root.inst.components.uianim.pos_t ~= nil
end

function EpicHealthbar:IsTimeout()
	return self.timeleft == nil
end

function EpicHealthbar:HasTargets()
	return next(self.targets) ~= nil
end

function EpicHealthbar:Appear()
	if not self.active then
		self.active = true

		self:Show()

		local pos = Vector3(TUNING.EPICHEALTHBAR.HORIZONTAL_OFFSET, SHOWN_Y)
		if self.owner.HUD.shown then
			self.root:MoveTo(self.root:GetPosition(), pos, self:GetMoveTime())
		else
			self.root:CancelMoveTo()
			self.root:SetPosition(pos)
		end
	end
end

function EpicHealthbar:Disappear()
	if self.active then
		self.active = false

		if self.owner.HUD.shown then
			self.root:MoveTo(self.root:GetPosition(), Vector3(TUNING.EPICHEALTHBAR.HORIZONTAL_OFFSET, HIDDEN_Y), self:GetMoveTime())
		else
			self:Hide()
		end
	end

	if self.shown and not self:IsMoving() then
		for root in pairs(self.popuproot.children) do
			if next(root.children) ~= nil then
				return self:OnHide()
			end
		end
		self:Hide()
	end

	if not self.shown and not self:HasTargets() then
		self.triggeredevents = {}
		self.danger = nil
		self.highlight = nil
		self:StopUpdating()
	end
end

EpicHealthbar.OnShow = EpicHealthbar.MoveToFront

function EpicHealthbar:OnHide()
	self.target = nil
end

function EpicHealthbar:IsEventSource(target, name)
	return target.prefab == name
		or target:HasTag(name)
		or self._eventaliases[target.prefab] == name
end

function EpicHealthbar:GetMusicTimeLeft(target, ignoretest)
	if ignoretest or hasmusic(target) and not self.dangerdisabled then
		for name, time in pairs(self.triggeredevents) do
			if self:IsEventSource(target, name) then
				return time
			end
		end
	end
end

function EpicHealthbar:PushMusic(target)
	if self.dangercooldown == nil and not self.dangerdisabled and not TUNING.EPICHEALTHBAR.NOEPIC then
		self.dangercooldown = FRAMES

		if not hasmusic(target) then
			if self._startdanger ~= false then
				if self._startdanger == nil then
					local listeners = Tykvesh.Browse(TheWorld, "event_listening", "attacked", self.owner)
					if listeners ~= nil then
						for i, v in ipairs(listeners) do
							if Tykvesh.GetUpvalue(v, "StartDanger") then
								self._startdanger = v
								break
							end
						end
					end
				end

				self._startdanger = self._startdanger ~= nil and pcall(self._startdanger, self.owner, { attacker = target }) and self._startdanger
			end
		elseif self._eventtriggers[target.prefab] ~= false then
			self.triggeredevent = true

			target._playingmusic = true

			if target._musictask ~= nil then
				if target._musictask.arg ~= nil then
					self._eventtriggers[target.prefab] = pcall(target._musictask.fn, unpack(target._musictask.arg))
				else
					self._eventtriggers[target.prefab] = pcall(target._musictask.fn)
				end
			elseif self._eventtriggers[target.prefab] ~= true then
				local fn = self._eventtriggers[target.prefab]

				if fn == nil then
					fn = Tykvesh.GetUpvalue(Prefabs[target.prefab].fn, "PushMusic")

					if fn == nil and target.pendingtasks ~= nil then
						for task in pairs(target.pendingtasks) do
							if task.period == 1 and task.limit == nil and task.arg ~= nil and task.arg[1] == target and #task.arg == 1 then
								fn = task.fn
								break
							end
						end
					end
				end

				self._eventtriggers[target.prefab] = fn ~= nil and pcall(fn, target) and fn
			end

			self.triggeredevent = nil

			if target.epichealth.maxfrustumdist ~= FRUSTUM_LIMIT
				and (target._playingmusic == false or not self:GetMusicTimeLeft(target, true))
				and target.entity:FrustumCheck() then

				local old = target.epichealth.maxfrustumdist or 0
				local new = TheCamera.currentpos:Dist(target:GetPosition()) + FRUSTUM_BIAS
				target.epichealth.maxfrustumdist = math.clamp(new, old, FRUSTUM_LIMIT)
			end
		end
	end
end

function EpicHealthbar:GetDistance(target)
	return self.playerpos:Dist(target:GetPosition())
end

function EpicHealthbar:IsNear(target, dist)
	return self:GetDistance(target) <= dist
end

function EpicHealthbar:IsBusy(target)
	if target:HasTag("attack") then
		return false
	elseif target:HasTag("flight") then
		return target:HasTag("busy")
	elseif target:HasTag("noattack") then
		return target.epichealth.invincible
			or target:HasTag("NOCLICK")
			or not target:HasTag("locomotor")
	end
	return false
end

function EpicHealthbar:IsValidTarget(target)
	return self.targets[target]
		and (target:HasTag("epic") or TUNING.EPICHEALTHBAR.NOEPIC and not target:HasTag("INLIMBO"))
		and (target.epichealth.currenthealth ~= 0 and target.epichealth.maxhealth > (TUNING.EPICHEALTHBAR.NOEPIC and 1 or 100))
		and (target.replica.health ~= nil and not target.replica.health:IsDead())
		and target.replica.combat ~= nil
		and not self:IsBusy(target)
end

function EpicHealthbar:ProximityCheck(target)
	return self.highlight == target
		or target.entity:FrustumCheck()
		or (not hasmusic(target) and self.target == target and self:IsNear(target, DISENGAGED_DIST))
		or (target.epichealth.maxfrustumdist ~= nil and self:IsNear(target, target.epichealth.maxfrustumdist))
end

function EpicHealthbar:IsEngagedTarget(target)
	if not self:IsValidTarget(target) then
		return false
	elseif hasmusic(target) then
		if target._isengaged ~= nil and not target._isengaged:value() then
			return false
		elseif self:GetMusicTimeLeft(target, true) then
			return true
		end
	end
	return self:ProximityCheck(target)
		and (self.danger or CanEntitySeeTarget(self.owner, target))
		and isincombat(target)
end

function EpicHealthbar:GetNextTarget()
	if self:IsEngagedTarget(self.highlight) then
		return self.highlight
	elseif self.owner.replica.combat ~= nil and not self.owner:HasTag("playerghost") then
		local target = self.owner.replica.combat:GetTarget()
		if self:IsEngagedTarget(target) then
			return target
		end

		local act = self.owner:GetBufferedAction()
		if act ~= nil and act.action == ACTIONS.ATTACK and self:IsEngagedTarget(act.target) then
			return act.target
		end

		if self.owner.player_classified ~= nil then
			local target = self.owner.player_classified.lastcombattarget:value()
			local range = self.owner.replica.combat:GetAttackRangeWithWeapon() + TARGET_BIAS
			if self:IsEngagedTarget(target) and self:IsNear(target, range) then
				return target
			end
		end
	end

	local mindist = ENGAGED_DIST
	local closest = nil

	for target in pairs(self.targets) do
		if self:IsEngagedTarget(target) then
			local dist = self:GetDistance(target)
			local physdist = dist - target:GetPhysicsRadius(0)
			if physdist <= mindist or closest == nil
				and (hasmusic(target) and not self.dangerdisabled
				or dist <= DISENGAGED_DIST and target.entity:FrustumCheck()) then

				mindist = physdist - TARGET_BIAS
				closest = target
			end
		end
	end

	if closest ~= nil then
		return closest
	elseif self:IsEngagedTarget(self.target) then
		return self.target
	end
end

function EpicHealthbar:OnUpdate(dt)
	if not TheNet:IsServerPaused() then
		timeclamp(self, "timeleft", dt, self:GetClampTime())
		timeclamp(self, "dangercooldown", dt)
		for name in pairs(self.triggeredevents) do
			timeclamp(self.triggeredevents, name, dt)
		end
	end

	self.refresh = false
	self.danger = TheFocalPoint.SoundEmitter:PlayingSound("danger")

	if self:HasTargets() then
		self.playerpos = self.owner:GetPosition()
		self.highlight = self.owner.components.playercontroller.highlight_guy

		local target = self:GetNextTarget()
		if target ~= nil then
			if self.target == target or self.target == nil or self:IsValidTarget(self.target) then
				self.target = target
				self.refresh = true
			end
			self:PushMusic(target)
			self.timeleft = (self:GetMusicTimeLeft(target) or DANGER_DURATION) + DANGER_FADEOUT
		end

		if self.target ~= nil and self.target:IsValid() then
			local epichealth = self.target.epichealth
			self._name = self.target:GetBasicDisplayName()
			self.build = self.target.AnimState:GetBuild()
			self.wet = self.target:GetIsWet()
			self.stimuli = epichealth.stimuli
			self.lastwasdamagedtime = epichealth.lastwasdamagedtime
			self.percent = epichealth.currenthealth / epichealth.maxhealth
			self.maxhealth = epichealth.maxhealth
			self.currenthealth = epichealth.currenthealth
		end
	end

	if self.refresh or timeclamp(self, "outdatedtimeleft", dt) then
		self:Appear()
	elseif not self:IsTimeout() and self:IsValidTarget(self.target) then
		self:Appear()
	else
		self:Disappear()
	end
end

return EpicHealthbar