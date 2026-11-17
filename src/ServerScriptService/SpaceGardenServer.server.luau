-- Space Garden | authoritative gameplay and persistence
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local Studio = RunService:IsStudio()
local Shared = ReplicatedStorage:WaitForChild("SpaceGarden")
local Config = require(Shared:WaitForChild("Config"))
local DecorCatalog=require(Shared:WaitForChild("DecorCatalog"))
local Decorations=require(ServerStorage:WaitForChild("SpaceGardenDecorations"))
local BlueprintModule=require(ServerStorage:WaitForChild("SpaceGardenBlueprints"))
local Action = Shared:FindFirstChild("Action") or Instance.new("RemoteFunction")
Action.Name = "Action"
Action.Parent = Shared
local World = require(ServerStorage:WaitForChild("SpaceGardenWorldBuilder")).Build()
local Farms = World:WaitForChild("Farms")
local Profiles, Assigned, Throttles = {}, {}, {}
local Store
local BlueprintStore
if not Studio then
	local ok, result = pcall(function() return DataStoreService:GetDataStore(Config.DataStoreName) end)
	if ok then Store = result else warn("Space Garden DataStore unavailable", result) end
	local blueOk,blueStore=pcall(function()return DataStoreService:GetDataStore(Config.DataStoreName.."_Blueprints")end)
	if blueOk then BlueprintStore=blueStore end
end
local function blueprintBudget(write)
	local ok,value=pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.StandardRead)>=4 and (not write or DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.StandardWrite)>=4)
	end)
	return ok and value
end
local BlueprintService=BlueprintModule.new(BlueprintStore,Decorations.Validate,{CanRead=function()return blueprintBudget(false)end})
local SessionToken = game.JobId .. ":" .. HttpService:GenerateGUID(false)
local Closing = false
local ServerHarvests = 0
local ServerSeasonHarvests = 0
local ServerSeasonKey = os.date("!%Y-%m", os.time())
-- Add only keys already created/published in Creator Hub, e.g.
-- ["Seed_Cosmo_Price"] = true. Empty manifest uses the catalog without probing
-- missing engine keys; ConfigSnapshot currently has no public key enumeration.
local PUBLISHED_TUNING_KEYS = {}
local SnapshotConfigValues = {}
local VALUE_CAP, INVENTORY_CAP = 1000000000, 1000000
local GlobalModule = require(ServerStorage:WaitForChild("SpaceGardenGlobal"))
local GlobalService = GlobalModule.new({Studio = Studio, Config = Config})
GlobalService:Start()

task.spawn(function()
	if next(PUBLISHED_TUNING_KEYS) == nil then return end
	local ok, snapshot = pcall(function() return game:GetService("ConfigService"):GetConfigAsync() end)
	if ok and snapshot then
		local function readPublishedValues()
			local values = {}
			for key, published in pairs(PUBLISHED_TUNING_KEYS) do
				if published == true then
					local readOk, value = pcall(function() return snapshot:GetValue(key) end)
					if readOk and type(value) == "number" and value == value and value > -math.huge and value < math.huge then values[key] = value end
				end
			end
			SnapshotConfigValues = values
		end
		readPublishedValues()
		snapshot.UpdateAvailable:Connect(function()
			local refreshed = pcall(function() snapshot:Refresh() end)
			if refreshed then readPublishedValues() end
		end)
	end
end)

local function tuning(key, fallback, low, high)
	local value = fallback
	local result = SnapshotConfigValues[key]
	if type(result) == "number" then value = result end
	return math.clamp(value, low or 0, high or 100000000)
end
local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for k, v in pairs(value) do result[k] = copy(v) end
	return result
end
local function integer(n, low, high)
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge and n % 1 == 0 and n >= low and n <= high
end
local function numberOr(n, fallback, low, high)
	return integer(n, low or 0, high or 9007199254740991) and n or fallback
end
local function clampedNumber(n, fallback, low, high)
	if type(n) ~= "number" or n ~= n or n <= -math.huge or n >= math.huge then return fallback end
	return math.floor(math.clamp(n, low, high))
end
local function grantCredits(d, amount)
	local before = d.credits
	d.credits = clampedNumber(d.credits + amount, before, 0, VALUE_CAP)
	return d.credits - before
end
local function activeForeignLease(record, ownToken)
	local lock = record and record.lock
	if lock == nil then return false end
	if type(lock) ~= "table" then return true end
	if ownToken and lock.token == ownToken then return false end
	-- Unix timestamps already exceed 1e9. Validate against the exact-integer
	-- range rather than a gameplay wallet cap, and fail closed if malformed.
	if not integer(lock.expires, 0, 9007199254740991) then return true end
	return lock.expires > os.time()
end
local function seedBalance(seedKey)
	local seed = Config.Seeds[seedKey]
	return {
		Price = math.floor(tuning("Seed_" .. seedKey .. "_Price", seed.Price, 1, 1000000)),
		GrowTime = math.floor(tuning("Seed_" .. seedKey .. "_GrowTime", seed.GrowTime, 3, 604800)),
		Yield = math.floor(tuning("Seed_" .. seedKey .. "_Yield", seed.Yield, 1, 100000)),
	}
end
local function upgradeCost(key, current)
	return math.floor(tuning("Upgrade_" .. key .. "_Cost", Config.GetUpgradeCost(key, current), 1, 10000000))
end
local function day() return math.floor(os.time() / 86400) end
local function seasonKey() return os.date("!%Y-%m", os.time()) end
local function level(data) return 1 + math.floor(data.xp / 100) end
local function newData()
	return {
		version = Config.SaveVersion, credits = Config.StartCredits, xp = 0, harvested = 0,
		inventory = copy(Config.StartSeeds), upgrades = {Lamp = 0, Beds = 0, Yield = 0},
		beds = {}, selectedSeed = "Cosmo", dailyLast = -1, streak = 0,
		questDay = day(), questProgress = 0, questClaimed = false,
		giftLast = -1, outbox = {}, giftReceipts = {}, purchaseReceipts = {},
		seasonKey = seasonKey(), seasonProgress = 0, seasonClaimed = false, globalSeasonClaimed = false, theme = "Aurora", entitlements = {}, boostTokens = 0,
		decorations={designs={},stands={}},blueprintDay=day(),blueprintsToday=0,blueprintLastAt=0,blueprintOutbox={},lastBlueprintCode=nil,
	}
end
local function sanitize(raw)
	local d = newData()
	if type(raw) ~= "table" then return d end
	for _, key in ipairs({"credits", "xp", "harvested", "questProgress", "seasonProgress", "boostTokens"}) do d[key] = clampedNumber(raw[key], d[key], 0, VALUE_CAP) end
	d.streak = clampedNumber(raw.streak, 0, 0, 365)
	if type(raw.seasonKey) == "string" and raw.seasonKey:match("^%d%d%d%d%-%d%d$") then d.seasonKey = raw.seasonKey end
	for _, key in ipairs({"dailyLast", "questDay", "giftLast"}) do d[key] = numberOr(raw[key], d[key], -1, 1000000) end
	for _, key in ipairs({"questClaimed", "seasonClaimed", "globalSeasonClaimed"}) do d[key] = raw[key] == true end
	for _, seed in ipairs(Config.SeedOrder) do d.inventory[seed] = clampedNumber(type(raw.inventory) == "table" and raw.inventory[seed], d.inventory[seed] or 0, 0, INVENTORY_CAP) end
	for _, key in ipairs(Config.UpgradeOrder) do d.upgrades[key] = clampedNumber(type(raw.upgrades) == "table" and raw.upgrades[key], 0, 0, Config.Upgrades[key].MaxLevel) end
	if Config.Seeds[raw.selectedSeed] then d.selectedSeed = raw.selectedSeed end
	if Config.Themes[raw.theme] then d.theme = raw.theme end
	for index = 1, Config.MaxBeds do
		local bed = type(raw.beds) == "table" and raw.beds[tostring(index)]
		if type(bed) == "table" and Config.Seeds[bed.seed] and integer(bed.plantedAt, 0, os.time() + 86400) and integer(bed.readyAt, bed.plantedAt, os.time() + 31536000) then
			d.beds[tostring(index)] = {seed = bed.seed, plantedAt = bed.plantedAt, readyAt = bed.readyAt, watered = bed.watered == true}
		end
	end
	-- Receipts are only accepted from our persisted server data, never from clients.
	for _, key in ipairs({"giftReceipts", "purchaseReceipts"}) do
		if type(raw[key]) == "table" then
			for id, timestamp in pairs(raw[key]) do
				if type(id) == "string" and #id <= 150 and integer(timestamp, 0, os.time() + 86400) then d[key][id] = timestamp end
			end
		end
	end
	if type(raw.outbox) == "table" then
		for id, tx in pairs(raw.outbox) do
			if type(id) == "string" and #id <= 100 and type(tx) == "table" and integer(tx.target, 1, 9007199254740991) and Config.Seeds[tx.seed] and integer(tx.created, 0, os.time() + 86400) then
				d.outbox[id] = {target = tx.target, seed = tx.seed, created = tx.created, bonus = numberOr(tx.bonus, Config.GiftBonus, 0, 100000)}
			end
		end
	end
	if type(raw.entitlements) == "table" then
		for _, k in ipairs({"ExtraBeds", "StarterPack"}) do d.entitlements[k] = raw.entitlements[k] == true end
	end
	d.decorations=Decorations.SanitizeProfile(raw.decorations)
	d.blueprintDay=numberOr(raw.blueprintDay,day(),0,1000000)
	d.blueprintsToday=clampedNumber(raw.blueprintsToday,0,0,Config.BlueprintsPerDay)
	d.blueprintLastAt=math.min(os.time(),numberOr(raw.blueprintLastAt,0,0,9007199254740991))
	d.lastBlueprintCode=BlueprintModule.NormalizeCode(raw.lastBlueprintCode)
	if type(raw.blueprintOutbox)=="table"then
		local count=0
		for code,tx in pairs(raw.blueprintOutbox)do
			local normalized=BlueprintModule.NormalizeCode(code)
			local design=type(tx)=="table"and Decorations.Validate(tx.design)
			if normalized and design and integer(tx.createdAt,0,os.time()+86400)and count<3 then
				d.blueprintOutbox[normalized]={design=design,createdAt=tx.createdAt};count+=1
			end
		end
	end
	return d
end
local function resetDay(d)
	if d.blueprintDay~=day()then d.blueprintDay=day();d.blueprintsToday=0 end
	if d.questDay ~= day() then d.questDay = day(); d.questProgress = 0; d.questClaimed = false end
	if d.seasonKey ~= seasonKey() then d.seasonKey = seasonKey(); d.seasonProgress = 0; d.seasonClaimed = false; d.globalSeasonClaimed = false end
	if ServerSeasonKey ~= seasonKey() then ServerSeasonKey = seasonKey(); ServerSeasonHarvests = 0 end
end
local function bedCount(d)
	return math.min(Config.MaxBeds, Config.InitialBeds + d.upgrades.Beds * 2 + (d.entitlements.ExtraBeds and 2 or 0))
end
local function keyFor(userId) return "p_" .. tostring(userId) end
local function persist(s, candidate, release)
	if not s.durable then return false, "Brak trwałego zapisu." end
	local ok, result = pcall(function()
		return Store:UpdateAsync(keyFor(s.player.UserId), function(record)
			if type(record) ~= "table" or type(record.lock) ~= "table" or record.lock.token ~= s.token then return nil end
			local updated = {data = copy(candidate)}
			if not release then updated.lock = {token = s.token, expires = os.time() + Config.SessionLease} end
			return updated
		end)
	end)
	if ok and result then
		s.saveStatus = "Saved"
		s.lastSave = os.time()
		-- Global projections are derived exclusively from acknowledged durable
		-- checkpoints; Submit coalesces without yielding or touching DataStores.
		GlobalService:Submit(s.player.UserId, candidate.harvested, candidate.seasonKey, candidate.seasonProgress)
		return true
	end
	s.saveStatus = "Unavailable"
	if ok and not result then
		s.lostLease = true
		task.defer(function() if s.player.Parent then s.player:Kick("Sesję otwarto na innym serwerze. Dołącz ponownie, aby chronić postęp.") end end)
	end
	return false, "Zapis jest chwilowo niedostępny. Spróbuj ponownie."
end
local function load(player)
	local s = {player = player, token = SessionToken .. ":" .. player.UserId .. ":" .. HttpService:GenerateGUID(false), busy = true, durable = false, saveStatus = Studio and "Studio" or "Unavailable", data = newData(), render = {}, friends = {}}
	if Studio then s.busy = false; return s end
	local locked = false
	local ok, record = pcall(function()
		return Store:UpdateAsync(keyFor(player.UserId), function(old)
			if old ~= nil and (type(old) ~= "table" or type(old.data) ~= "table" or (tonumber(old.data.version) or 0) > Config.SaveVersion) then error("Unrecognized profile schema") end
			if old and activeForeignLease(old, s.token) then locked = true; return nil end
			local data = old and sanitize(old.data) or newData()
			return {data = data, lock = {token = s.token, expires = os.time() + Config.SessionLease}}
		end)
	end)
	if not ok or not record then
		player:Kick(locked and "Twój ogród jest otwarty na innym serwerze. Spróbuj za chwilę." or "Nie można bezpiecznie wczytać ogrodu. Spróbuj ponownie za chwilę.")
		return nil
	end
	s.data = sanitize(record.data); s.durable = true; s.saveStatus = "Loaded"; s.lastSave = os.time(); s.busy = false
	GlobalService:Submit(player.UserId, s.data.harvested, s.data.seasonKey, s.data.seasonProgress)
	return s
end

local function part(parent, name, size, cf, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name; p.Anchored = true; p.CanCollide = false; p.CanTouch = false; p.CanQuery = false
	p.Size = size; p.CFrame = cf; p.Color = color; p.Material = material or Enum.Material.SmoothPlastic
	if shape then p.Shape = shape end
	p.Parent = parent
	return p
end
local function renderBed(s, index)
	local pad = s.farm.Beds:FindFirstChild("Bed" .. index)
	if not pad or not pad:IsA("BasePart") then return end
	local crop = s.data.beds[tostring(index)]
	local unlocked = index <= bedCount(s.data)
	local now = os.time()
	local stage = crop and (now >= crop.readyAt and 3 or (now - crop.plantedAt) / math.max(1, crop.readyAt - crop.plantedAt) >= 0.45 and 2 or 1) or 0
	local stamp = tostring(crop and crop.seed or "") .. ":" .. stage .. ":" .. tostring(unlocked)
	pad:SetAttribute("OwnerUserId", s.player.UserId)
	pad:SetAttribute("Seed", crop and crop.seed or "")
	pad:SetAttribute("ReadyAt", crop and crop.readyAt or 0)
	pad:SetAttribute("Unlocked", unlocked)
	local prompt = pad:FindFirstChild("GardenPrompt")
	if prompt then
		prompt.Enabled = unlocked
		prompt.ObjectText = crop and Config.Seeds[crop.seed].Name or "Pusta grządka " .. index
		prompt.ActionText = crop and (stage == 3 and "Zbierz" or "Podlej") or "Posadź: " .. Config.Seeds[s.data.selectedSeed].Name
	end
	if s.render[index] == stamp then return end
	s.render[index] = stamp
	local old = pad:FindFirstChild("Crop"); if old then old:Destroy() end
	if not crop then return end
	local model = Instance.new("Model"); model.Name = "Crop"
	local c = Config.Seeds[crop.seed].Color
	local scale = ({0.38, 0.70, 1})[stage] * 1.5
	local base = pad.CFrame * CFrame.new(0, pad.Size.Y / 2 + 0.1, 0)
	part(model, "Stem", Vector3.new(2.8, 0.45, 0.45) * scale, base * CFrame.new(0, 1.4 * scale, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(51, 137, 131), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	local order = table.find(Config.SeedOrder, crop.seed) or 1
	for leaf = 1, 3 + (order % 3) do
		local angle = leaf * math.pi * 2 / (3 + (order % 3))
		local cf = base * CFrame.new(math.cos(angle) * 0.9 * scale, (1.2 + leaf * 0.22) * scale, math.sin(angle) * 0.9 * scale) * CFrame.Angles(0, -angle, math.rad(30))
		part(model, "AlienPetal", Vector3.new(1.7, 0.38, 0.8) * scale, cf, c:Lerp(Color3.fromRGB(67, 220, 171), 0.25), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	end
	local head = part(model, "Core", Vector3.new(1.6, 1.6 + order * 0.15, 1.6) * scale, base * CFrame.new(0, 3 * scale, 0), c, Enum.Material.SmoothPlastic, order % 2 == 0 and Enum.PartType.Ball or Enum.PartType.Block)
	if crop.seed == "Prism" or crop.seed == "Void" then head.CFrame *= CFrame.Angles(0, math.rad(45), math.rad(45)) end
	-- Each species has its own recognizable silhouette, using original geometry.
	local function orb(name, position, size, color)
		local material=(name=="StarlightBud"or name=="Dewdrop")and Enum.Material.Neon or Enum.Material.SmoothPlastic
		return part(model, name, size * scale, base * CFrame.new(position * scale), color or c, material, Enum.PartType.Ball)
	end
	local function stalk(a, b, width, color)
		local pa, pb = (base * CFrame.new(a * scale)).Position, (base * CFrame.new(b * scale)).Position
		return part(model, "Branch", Vector3.new(width * scale, width * scale, (pb-pa).Magnitude), CFrame.lookAt((pa+pb)/2,pb), color or c, Enum.Material.SmoothPlastic)
	end
	if crop.seed == "Cosmo" then
		head.Shape = Enum.PartType.Ball; head.Size = Vector3.new(1.4,2.3,1.4)*scale
		for _, side in ipairs({-1,1}) do
			stalk(Vector3.new(0,1.5,0),Vector3.new(side*1.25,1.5,0),.55,c)
			orb("CactusArm",Vector3.new(side*1.25,2.05,0),Vector3.new(.7,1.6,.7))
			orb("StarlightBud",Vector3.new(side*1.25,2.8,0),Vector3.new(.35,.45,.35),Color3.fromRGB(210,255,134))
		end
	elseif crop.seed == "Lunar" then
		head.Size = Vector3.new(2.4,1.3,2.4)*scale
		for j=1,5 do local a=j*math.pi*2/5
			orb("BellPetal",Vector3.new(math.cos(a)*.7,2.45,math.sin(a)*.7),Vector3.new(.65,1.2,.65),c:Lerp(Color3.new(1,1,1),.22))
		end
	elseif crop.seed == "Prism" then
		for j=1,6 do local a=j*math.pi/3
			part(model,"CrystalPetal",Vector3.new(.8,2.15,.65)*scale,base*CFrame.new(math.cos(a)*1.25*scale,3*scale,math.sin(a)*1.25*scale)*CFrame.Angles(.4,a,math.pi/4),c,Enum.Material.Glass)
		end
	elseif crop.seed == "Solar" then
		head.Size = Vector3.new(1,1,1)*scale
		for j=1,5 do local a=j*math.pi*2/5;local tip=Vector3.new(math.cos(a)*1.45,2.6+(j%2)*.75,math.sin(a)*1.45)
			stalk(Vector3.new(0,1.3,0),tip,.35,Color3.fromRGB(235,140,70));orb("SolarBud",tip,Vector3.new(.85,1.15,.85))
		end
	elseif crop.seed == "Nebula" then
		head.Shape=Enum.PartType.Ball
		head.Size = Vector3.new(3.2,.95,3.2)*scale
		for j=1,7 do local a=j*math.pi*2/7;local last=Vector3.new(math.cos(a)*1.15,2.8,math.sin(a)*1.15)
			for segment=1,3 do local v=Vector3.new(math.cos(a+segment*.2)*(1.15-segment*.1),2.8-segment*.6,math.sin(a+segment*.2)*(1.15-segment*.1));stalk(last,v,.14,c);last=v end
			orb("Dewdrop",last,Vector3.new(.22,.32,.22),Color3.fromRGB(190,234,255))
		end
	elseif crop.seed == "Void" then
		head.Shape=Enum.PartType.Block
		head.Color = Color3.fromRGB(81,58,142)
		for ring=1,2 do
			local rotation=base*CFrame.new(0,3*scale,0)*CFrame.Angles(math.rad(ring==1 and 25 or 110),0,math.rad(20))
			for j=1,16 do local a,b=j*math.pi/8,(j+1)*math.pi/8
				local pa=(rotation*CFrame.new(math.cos(a)*1.75*scale,0,math.sin(a)*1.75*scale)).Position
				local pb=(rotation*CFrame.new(math.cos(b)*1.75*scale,0,math.sin(b)*1.75*scale)).Position
				part(model,"OrbitalRing",Vector3.new(.1*scale,.1*scale,(pb-pa).Magnitude+.03),CFrame.lookAt((pa+pb)/2,pb),c,Enum.Material.Neon)
			end
		end
	end
	if stage == 3 then
		local light = Instance.new("PointLight"); light.Color = c; light.Brightness = 0.2; light.Range = 6; light.Parent = head
		local particles=Instance.new("ParticleEmitter");particles.Name="RipeStardust";particles.Texture="rbxasset://textures/particles/sparkles_main.dds"
		particles.Color=ColorSequence.new(c);particles.Size=NumberSequence.new(.15);particles.Rate=1.5;particles.Lifetime=NumberRange.new(.8,1.3)
		particles.Speed=NumberRange.new(.2,.5);particles.SpreadAngle=Vector2.new(180,180);particles.LightEmission=.5;particles.Parent=head
	end
	model.Parent = pad
end
local function render(s)
	if not s.farm then return end
	for i = 1, Config.MaxBeds do renderBed(s, i) end
	local _,decorError=Decorations.Render(s.farm,s.data.decorations)
	if decorError and s.decorError~=decorError then warn("Space Garden decorations",decorError)end
	s.decorError=decorError
	local color = Config.Themes[s.data.theme].Color
	for _, p in ipairs(s.farm:GetDescendants()) do
		if p:IsA("BasePart") and p:GetAttribute("ThemeAccent") then p.Color = color end
	end
	local stats = s.player:FindFirstChild("leaderstats")
	if stats then stats.Kredyty.Value = s.data.credits; stats.Zbiory.Value = s.data.harvested; stats.Poziom.Value = level(s.data) end
end
local function snapshot(s)
	local d = s.data
	local currentQuest = d.questDay == day()
	local currentSeason = d.seasonKey == seasonKey()
	local beds, playerList, catalog, upgradeCosts = {}, {}, {}, {}
	for _, seedKey in ipairs(Config.SeedOrder) do
		local balance = seedBalance(seedKey)
		balance.EffectiveGrowTime = math.max(3, math.floor(balance.GrowTime * math.max(0.45, 1 - 0.12 * d.upgrades.Lamp)))
		balance.EffectiveYield = math.floor(balance.Yield * (1 + 0.20 * d.upgrades.Yield))
		catalog[seedKey] = balance
	end
	for _, upgrade in ipairs(Config.UpgradeOrder) do upgradeCosts[upgrade] = upgradeCost(upgrade, d.upgrades[upgrade]) end
	for i = 1, Config.MaxBeds do
		local crop = d.beds[tostring(i)]
		local row = crop and copy(crop) or {}
		row.index = i; row.unlocked = i <= bedCount(d); beds[i] = row
	end
	for player, other in pairs(Profiles) do
		table.insert(playerList, {userId = player.UserId, name = player.Name, displayName = player.DisplayName, harvested = other.data.harvested, isFriend = s.friends[player.UserId] == true})
	end
	table.sort(playerList, function(a, b) return a.harvested > b.harvested end)
	local global = GlobalService:Snapshot(playerList, ServerSeasonKey == seasonKey() and ServerSeasonHarvests or 0)
	local decor=Decorations.SanitizeProfile(d.decorations)
	local designRows,standRows={},{}
	for slot=1,DecorCatalog.MaxDesigns do designRows[slot]={slot=slot,design=copy(decor.designs[tostring(slot)])}end
	for stand=1,DecorCatalog.MaxStands do standRows[stand]={stand=stand,designSlot=decor.stands[tostring(stand)]}end
	return {
		credits = d.credits, xp = d.xp, level = level(d), harvested = d.harvested,
		inventory = copy(d.inventory), upgrades = copy(d.upgrades), beds = beds,
		entitlements = copy(d.entitlements), bedCount = bedCount(d), maxBeds = Config.MaxBeds,
		selectedSeed = d.selectedSeed, farmIndex = s.farmIndex, theme = d.theme,
		daily = {available = d.dailyLast < day(), streak = d.streak, nextAt = (d.dailyLast + 1) * 86400},
		quest = {progress = currentQuest and d.questProgress or 0, goal = Config.DailyQuestGoal, claimed = currentQuest and d.questClaimed or false},
		gift = {available = d.giftLast < day() and s.durable and not next(d.outbox), enabled = s.durable, nextAt = (d.giftLast + 1) * 86400, pending = next(d.outbox) ~= nil, reason = not s.durable and "Prezenty wymagają opublikowanej gry i trwałego zapisu." or nil},
		season = {name = "Uprawy na Marsie", period = seasonKey(), scope = global.season.scope, progress = currentSeason and d.seasonProgress or 0, goal = Config.SeasonGoal, claimed = currentSeason and d.seasonClaimed or false,
			sharedProgress = global.season.total, sharedGoal = Config.GlobalSeasonGoal or 10000, globalAvailable = global.season.available,
			globalUpdatedAt = global.season.updatedAt, globalClaimed = currentSeason and d.globalSeasonClaimed or false,
			globalReward = Config.GlobalSeasonReward or 300, participationRequired = Config.GlobalSeasonParticipation or 8},
		globalRanking = global.globalRanking,
		saveStatus = s.saveStatus, players = playerList, serverHarvests = ServerHarvests,
		premiumAvailable = (Config.Products.SeedPack or 0) > 0 or (Config.Products.GrowthBoost or 0) > 0 or (Config.Passes.ExtraBeds or 0) > 0 or (Config.Passes.StarterPack or 0) > 0,
		serverTime = os.time(),
		boostTokens = d.boostTokens,
		catalog = catalog, upgradeCosts = upgradeCosts,
		decorations={designs=designRows,stands=standRows,blueprint=d.lastBlueprintCode,pending=next(d.blueprintOutbox)~=nil,publishedToday=d.blueprintDay==day()and d.blueprintsToday or 0,sharingEnabled=s.durable and BlueprintService.Available},
		lastBlueprintCode=d.lastBlueprintCode,
	}
end
local function harvest(s, index)
	local key = tostring(index)
	local crop = s.data.beds[key]
	if not crop or crop.readyAt > os.time() then return false end
	local seed = Config.Seeds[crop.seed]
	local yield = math.floor(seedBalance(crop.seed).Yield * (1 + 0.20 * s.data.upgrades.Yield))
	s.data.beds[key] = nil
	local awarded = grantCredits(s.data, yield)
	s.data.xp = math.min(VALUE_CAP, s.data.xp + seed.XP); s.data.harvested = math.min(VALUE_CAP, s.data.harvested + 1)
	resetDay(s.data); s.data.questProgress = math.min(VALUE_CAP, s.data.questProgress + 1); s.data.seasonProgress = math.min(VALUE_CAP, s.data.seasonProgress + 1)
	ServerHarvests += 1; ServerSeasonHarvests += 1
	return true, awarded
end
local function plant(s, index, seedKey)
	local seed = Config.Seeds[seedKey]
	if not seed then return false, "Wybierz nasiono." end
	if index > bedCount(s.data) then return false, "Odblokuj grządkę w badaniach." end
	if s.data.beds[tostring(index)] then return false, "Ta grządka jest zajęta." end
	if level(s.data) < seed.UnlockLevel then return false, "Wymagany poziom " .. seed.UnlockLevel .. "." end
	if (s.data.inventory[seedKey] or 0) < 1 then return false, "Brak nasion. Odwiedź sklep." end
	s.data.inventory[seedKey] -= 1
	local now = os.time()
	s.data.beds[tostring(index)] = {seed = seedKey, plantedAt = now, readyAt = now + math.max(3, math.floor(seedBalance(seedKey).GrowTime * math.max(0.45, 1 - 0.12 * s.data.upgrades.Lamp))), watered = false}
	s.data.selectedSeed = seedKey
	return true, "Posadzono: " .. seed.Name
end
local function water(s, index)
	local crop = s.data.beds[tostring(index)]
	if not crop then return false, "Najpierw posadź nasiono." end
	if crop.readyAt <= os.time() then return false, "Roślina jest już gotowa do zbioru." end
	if crop.watered then return false, "Ta roślina została już podlana." end
	if os.clock() - (s.lastWater or -100) < Config.WaterCooldown then return false, "Konewka ładuje się. Spróbuj za chwilę." end
	crop.watered = true; crop.readyAt = math.max(os.time(), crop.readyAt - Config.WaterReduction); s.lastWater = os.clock()
	return true, "Nawodniono! Wzrost przyspieszony."
end

-- Durable gift saga: deduct + reserve day in sender profile first. Delivery is
-- idempotent in recipient profile. Sender bonus is committed only after delivery.
-- A pending outbox is replayed on rejoin and cannot duplicate recipient grants.
local function deliverGift(source, id, tx)
	local targetPlayer = Players:GetPlayerByUserId(tx.target)
	local target = targetPlayer and Profiles[targetPlayer]
	if target and (target.busy or not target.durable or target.lostLease) then return false end
	if target then target.busy = true end
	local awarded
	if target then
		local candidate = copy(target.data)
		if not candidate.giftReceipts[id] then
			if (candidate.inventory[tx.seed] or 0) >= INVENTORY_CAP then target.busy = false; return false end
			candidate.inventory[tx.seed] = (candidate.inventory[tx.seed] or 0) + 1
			grantCredits(candidate, tx.bonus); candidate.giftReceipts[id] = os.time()
		end
		awarded = persist(target, candidate, false)
		if awarded then target.data = candidate; render(target) end
		target.busy = false
	else
		local ok, record = pcall(function()
			return Store:UpdateAsync(keyFor(tx.target), function(old)
				if type(old) ~= "table" or type(old.data) ~= "table" then return nil end
				if activeForeignLease(old) then return nil end
				local d = sanitize(old.data)
				if not d.giftReceipts[id] then
					if (d.inventory[tx.seed] or 0) >= INVENTORY_CAP then return nil end
					d.inventory[tx.seed] = (d.inventory[tx.seed] or 0) + 1
					grantCredits(d, tx.bonus); d.giftReceipts[id] = os.time()
				end
				return {data = d}
			end)
		end)
		awarded = ok and record ~= nil
	end
	if not awarded then return false end
	local candidate = copy(source.data)
	if candidate.outbox[id] then
		candidate.outbox[id] = nil; grantCredits(candidate, tx.bonus)
		if persist(source, candidate, false) then source.data = candidate; render(source); return true end
	end
	return false
end
local function recoverGifts(s)
	if not s.durable or s.busy or s.lostLease or not next(s.data.outbox) then return end
	s.busy = true
	for id, tx in pairs(copy(s.data.outbox)) do deliverGift(s, id, tx) end
	s.busy = false
end
local function gift(s, args)
	if not s.durable then return false, "Prezenty wymagają opublikowanej gry i trwałego zapisu. Studio używa sesji testowej." end
	if s.saveStatus == "Unavailable" or s.lostLease then return false, "Poczekaj na przywrócenie zapisu." end
	if not integer(args.targetUserId, 1, 9007199254740991) or args.targetUserId == s.player.UserId then return false, "Wybierz innego znajomego." end
	if args.quantity ~= 1 or type(args.seed) ~= "string" or not Config.Seeds[args.seed] then return false, "Prezent to dokładnie jedno nasiono." end
	if s.data.giftLast >= day() or next(s.data.outbox) then return false, "Dzienny prezent został już wysłany lub czeka na dostarczenie." end
	if (s.data.inventory[args.seed] or 0) < 1 then return false, "Nie masz tego nasiona." end
	local recipient = Players:GetPlayerByUserId(args.targetUserId)
	local target = recipient and Profiles[recipient]
	if not target or not target.durable or target.busy then return false, "Znajomy musi być dostępny na tym serwerze." end
	if (target.data.inventory[args.seed] or 0) >= INVENTORY_CAP then return false, "Magazyn tego nasiona u znajomego jest pełny." end
	local ok, friends = pcall(function() return s.player:IsFriendsWithAsync(recipient.UserId) end)
	if not ok or not friends then return false, "Prezenty możesz wysłać znajomym Roblox na tym serwerze." end
	-- Friendship lookup yields; revalidate all mutable eligibility afterwards.
	if s.leaving or Closing or Profiles[recipient] ~= target or target.leaving or target.busy or s.data.giftLast >= day() or next(s.data.outbox) or (s.data.inventory[args.seed] or 0) < 1 then return false, "Stan prezentu zmienił się. Spróbuj ponownie." end
	if (target.data.inventory[args.seed] or 0) >= INVENTORY_CAP then return false, "Magazyn tego nasiona u znajomego jest pełny." end
	local id = HttpService:GenerateGUID(false)
	local tx = {target = recipient.UserId, seed = args.seed, created = os.time(), bonus = math.floor(tuning("GiftBonus", Config.GiftBonus, 0, 100000))}
	local candidate = copy(s.data)
	candidate.inventory[args.seed] -= 1; candidate.giftLast = day(); candidate.outbox[id] = tx
	if not persist(s, candidate, false) then return false, "Nie udało się zapisać prezentu. Nic nie pobrano." end
	s.data = candidate
	if deliverGift(s, id, tx) then return true, "Prezent dostarczony! Oboje otrzymujecie bonus." end
	return true, "Prezent bezpiecznie zapisany i czeka na dostarczenie. Bonus przyjdzie po dostawie."
end

local function teleport(s)
	local character = s.player.Character
	local spawn = s.farm and s.farm:FindFirstChild("Spawn")
	if character and character:FindFirstChild("HumanoidRootPart") and spawn and spawn:IsA("BasePart") then character:PivotTo(spawn.CFrame + Vector3.new(0, 4, 0)); return true end
	return false
end
local function commitDesign(s,candidate)
	local same=true
	for slot=1,DecorCatalog.MaxDesigns do
		local a=s.data.decorations.designs[tostring(slot)];local b=candidate.decorations.designs[tostring(slot)]
		if (a==nil)~=(b==nil)or(a and b and(a.shape~=b.shape or a.palette~=b.palette or a.scale~=b.scale))then same=false;break end
	end
	if same then for stand=1,DecorCatalog.MaxStands do if s.data.decorations.stands[tostring(stand)]~=candidate.decorations.stands[tostring(stand)]then same=false;break end end end
	if same then return true end
	if s.durable then
		if not blueprintBudget(true)then return false,"Stacja jest zajęta zapisem ogrodów. Spróbuj za chwilę."end
		if not persist(s,candidate,false)then return false,"Nie udało się zapisać projektu. Spróbuj ponownie."end
	end
	s.data=candidate
	return true
end
local function deliverBlueprint(s,code,tx)
	if not s.durable or s.lostLease or not BlueprintService.Available or not blueprintBudget(true)then return false end
	local published=BlueprintService:Publish(code,s.player.UserId,tx.design,tx.createdAt)
	if not published then return false end
	local candidate=copy(s.data)
	if not candidate.blueprintOutbox[code]then return true end
	candidate.blueprintOutbox[code]=nil
	if not persist(s,candidate,false)then return false end
	s.data=candidate
	return true
end
local function recoverBlueprints(s)
	if not s.durable or s.busy or s.leaving or s.lostLease or not next(s.data.blueprintOutbox)then return end
	s.busy=true
	for code,tx in pairs(copy(s.data.blueprintOutbox))do deliverBlueprint(s,code,tx)end
	s.busy=false
end
local function publishDesign(s,args)
	if not s.durable or not BlueprintService.Available then return false,"Kody projektów wymagają opublikowanej gry i trwałego zapisu."end
	if not integer(args.slot,1,DecorCatalog.MaxDesigns)then return false,"Wybierz zapisany projekt."end
	local now=os.clock()
	if now-(s.lastPublishAttempt or -100)<2 then return false,"Stacja potwierdza publikację. Spróbuj za chwilę."end
	s.lastPublishAttempt=now
	local pendingCode,pending=next(s.data.blueprintOutbox)
	if pendingCode then
		local delivered=deliverBlueprint(s,pendingCode,pending)
		return true,delivered and "Projekt opublikowany. Udostępnij kod znajomym."or"Publikacja pozostaje w kolejce; stacja ją ponowi.",pendingCode
	end
	local design=s.data.decorations.designs[tostring(args.slot)]
	if not design then return false,"Najpierw zapisz projekt w tym slocie."end
	resetDay(s.data)
	if s.data.blueprintsToday>=Config.BlueprintsPerDay then return false,"Dzienny limit publikacji projektów został wykorzystany."end
	if os.time()-s.data.blueprintLastAt<Config.BlueprintPublishCooldown then return false,"Między publikacjami odczekaj "..Config.BlueprintPublishCooldown.." sekund."end
	if not blueprintBudget(true)then return false,"Stacja jest zajęta zapisem ogrodów. Spróbuj za chwilę."end
	local code=string.lower(HttpService:GenerateGUID(false))
	local candidate=copy(s.data)
	candidate.blueprintsToday+=1;candidate.blueprintLastAt=os.time();candidate.lastBlueprintCode=code
	candidate.blueprintOutbox[code]={design=copy(design),createdAt=os.time()}
	if not persist(s,candidate,false)then return false,"Nie udało się zarezerwować kodu. Spróbuj ponownie."end
	s.data=candidate
	local delivered=deliverBlueprint(s,code,candidate.blueprintOutbox[code])
	return true,delivered and "Projekt opublikowany. Udostępnij kod znajomym."or"Kod zapisany. Publikacja czeka na potwierdzenie stacji.",code
end
local function designAction(s,action,args)
	if action=="PublishDesign"then return publishDesign(s,args)end
	local editNow=os.clock()
	if editNow-(s.lastDesignChange or -100)<Config.DesignEditCooldown then return false,"Odczekaj chwilę między zmianami projektu."end
	s.lastDesignChange=editNow
	local candidate=copy(s.data)
	if action=="SaveDesign"then
		if not integer(args.slot,1,DecorCatalog.MaxDesigns)then return false,"Nieprawidłowy slot projektu."end
		local design,reason=Decorations.Validate({shape=args.shape,palette=args.palette,scale=args.scale})
		if not design then return false,reason end
		candidate.decorations.designs[tostring(args.slot)]=design
	elseif action=="PlaceDesign"then
		if not integer(args.stand,1,DecorCatalog.MaxStands)or not integer(args.slot,1,DecorCatalog.MaxDesigns)then return false,"Wybierz podest i projekt."end
		if not candidate.decorations.designs[tostring(args.slot)]then return false,"Najpierw zapisz projekt w tym slocie."end
		candidate.decorations.stands[tostring(args.stand)]=args.slot
	elseif action=="RemoveDesign"then
		if not integer(args.stand,1,DecorCatalog.MaxStands)then return false,"Nieprawidłowy podest."end
		candidate.decorations.stands[tostring(args.stand)]=nil
	elseif action=="ImportDesign"then
		if not s.durable then return false,"Import kodów wymaga opublikowanej gry i trwałego zapisu."end
		if not integer(args.slot,1,DecorCatalog.MaxDesigns)then return false,"Wybierz slot docelowy."end
		local code=BlueprintModule.NormalizeCode(args.code)
		if not code then return false,"Kod projektu musi mieć format UUID (36 znaków)."end
		local now=os.clock()
		if now-(s.lastBlueprintFetch or -100)<Config.BlueprintFetchCooldown then return false,"Odczekaj chwilę przed kolejnym importem."end
		s.lastBlueprintFetch=now
		local record,reason=BlueprintService:Fetch(code)
		if not record then return false,reason end
		if s.leaving or Closing or s.lostLease then return false,"Trwa zamykanie sesji."end
		candidate.decorations.designs[tostring(args.slot)]=copy(record.design)
	else return false,"Nieznana operacja projektowania."end
	local ok,reason=commitDesign(s,candidate)
	if not ok then return false,reason end
	return true,action=="RemoveDesign"and"Dekoracja zdjęta z podestu."or action=="PlaceDesign"and"Dekoracja ustawiona w Twojej szklarni."or action=="ImportDesign"and"Projekt zaimportowany do wybranego slotu."or"Projekt zapisany."
end
local function dispatch(s, action, args)
	local d = s.data
	if action=="SaveDesign"or action=="PlaceDesign"or action=="RemoveDesign"or action=="PublishDesign"or action=="ImportDesign"then return designAction(s,action,args)end
	if action == "State" then return true end
	if action == "SelectSeed" then
		if type(args.seed) ~= "string" or not Config.Seeds[args.seed] then return false, "Nieznane nasiono." end
		d.selectedSeed = args.seed; return true
	elseif action == "Plant" then
		if not integer(args.index, 1, Config.MaxBeds) or type(args.seed) ~= "string" then return false, "Nieprawidłowa grządka." end
		return plant(s, args.index, args.seed)
	elseif action == "Harvest" then
		if not integer(args.index, 1, bedCount(d)) then return false, "Nieprawidłowa grządka." end
		local ok, amount = harvest(s, args.index)
		return ok, ok and ("Zebrano! +" .. amount .. " kredytów") or "Roślina jeszcze rośnie."
	elseif action == "HarvestAll" then
		local count, total = 0, 0
		for i = 1, bedCount(d) do local ok, value = harvest(s, i); if ok then count += 1; total += value end end
		return count > 0, count > 0 and ("Zebrano " .. count .. " upraw. +" .. total .. " kredytów") or "Nie ma jeszcze gotowych roślin."
	elseif action == "Water" then
		if not integer(args.index, 1, bedCount(d)) then return false, "Nieprawidłowa grządka." end
		return water(s, args.index)
	elseif action == "BuySeed" then
		if type(args.seed) ~= "string" or not Config.Seeds[args.seed] or not integer(args.quantity, 1, 100) then return false, "Nieprawidłowy zakup." end
		local seed = Config.Seeds[args.seed]
		if level(d) < seed.UnlockLevel then return false, "Wymagany poziom " .. seed.UnlockLevel .. "." end
		local cost = seedBalance(args.seed).Price * args.quantity
		if d.credits < cost then return false, "Za mało astralnych kredytów." end
		if (d.inventory[args.seed] or 0) + args.quantity > 1000000 then return false, "Magazyn nasion jest pełny." end
		d.credits -= cost; d.inventory[args.seed] = (d.inventory[args.seed] or 0) + args.quantity
		return true, "Kupiono nasiona: " .. seed.Name .. " ×" .. args.quantity
	elseif action == "Upgrade" then
		if type(args.key) ~= "string" or not Config.Upgrades[args.key] then return false, "Nieznane badanie." end
		local up = Config.Upgrades[args.key]; local current = d.upgrades[args.key]
		if current >= up.MaxLevel then return false, "Osiągnięto maksymalny poziom." end
		local cost = upgradeCost(args.key, current)
		if d.credits < cost then return false, "Za mało astralnych kredytów." end
		d.credits -= cost; d.upgrades[args.key] += 1
		return true, "Ulepszono: " .. up.Name
	elseif action == "Daily" then
		if d.dailyLast >= day() then return false, "Nagrodę odebrano. Wróć jutro (UTC)." end
		if (d.inventory.Lunar or 0) + Config.DailySeedCount > INVENTORY_CAP then return false, "Zwolnij miejsce na księżycowe nasiona przed odbiorem nagrody." end
		d.streak = d.dailyLast == day() - 1 and math.min(365, d.streak + 1) or 1; d.dailyLast = day()
		local reward = math.floor(tuning("DailyCredits", Config.DailyCredits, 0, 100000)) + math.min(6, d.streak - 1) * 15
		reward = grantCredits(d, reward); d.inventory.Lunar = (d.inventory.Lunar or 0) + Config.DailySeedCount
		return true, "Kosmiczny zbiórek! +" .. reward .. " kredytów i nasiona. Seria: " .. d.streak
	elseif action == "Quest" then
		resetDay(d)
		if d.questClaimed or d.questProgress < Config.DailyQuestGoal then return false, "Zbierz " .. Config.DailyQuestGoal .. " roślin, aby odebrać nagrodę." end
		if (d.inventory.Prism or 0) >= INVENTORY_CAP then return false, "Zwolnij miejsce na pryzmatyczne nasiono." end
		d.questClaimed = true; grantCredits(d, math.floor(tuning("DailyQuestReward", Config.DailyQuestReward, 0, 100000))); d.inventory.Prism = (d.inventory.Prism or 0) + 1
		return true, "Misja zakończona! Kredyty i pryzmatyczne nasiono są twoje."
	elseif action == "Season" then
		resetDay(d)
		if d.seasonClaimed or d.seasonProgress < Config.SeasonGoal then return false, "Ukończ wyzwanie zbiorów, aby odebrać nagrodę." end
		if (d.inventory.Void or 0) >= INVENTORY_CAP then return false, "Zwolnij miejsce na nasiono osobliwości." end
		d.seasonClaimed = true; grantCredits(d, Config.SeasonReward); d.inventory.Void = (d.inventory.Void or 0) + 1
		return true, "Mistrz Ogrodnictwa! Otrzymujesz kosmiczną nagrodę."
	elseif action == "GlobalSeason" then
		resetDay(d)
		local global = GlobalService:Snapshot()
		if not s.durable or not global.live or not global.season.available or global.season.period ~= seasonKey() then return false, "Nagroda galaktyczna wymaga aktualnego globalnego zapisu w opublikowanej grze." end
		if d.globalSeasonClaimed then return false, "Nagrodę galaktyczną odebrano już w tym miesiącu." end
		if d.seasonProgress < (Config.GlobalSeasonParticipation or 8) then return false, "Zbierz co najmniej " .. (Config.GlobalSeasonParticipation or 8) .. " roślin w tym miesiącu." end
		if global.season.total < (Config.GlobalSeasonGoal or 10000) then return false, "Galaktyczne wyzwanie jeszcze trwa. Wynik odświeża się co kilka minut." end
		local reward = Config.GlobalSeasonReward or 300
		if d.credits + reward > VALUE_CAP then return false, "Zwolnij miejsce w portfelu przed odbiorem nagrody." end
		local candidate = copy(d); candidate.globalSeasonClaimed = true; grantCredits(candidate, reward)
		if not persist(s, candidate, false) then return false, "Nie udało się bezpiecznie zapisać nagrody. Spróbuj ponownie." end
		s.data = candidate
		return true, "Wspólny sukces galaktyki! +" .. reward .. " kredytów."
	elseif action == "Theme" then
		if type(args.theme) ~= "string" or not Config.Themes[args.theme] then return false, "Nieznany motyw." end
		d.theme = args.theme; return true, "Zmieniono atmosferę ogrodu."
	elseif action == "Teleport" then
		return teleport(s), "Witaj w swoim ogrodzie."
	elseif action == "Gift" then
		return gift(s, args)
	elseif action == "Premium" then
		if not s.durable or s.saveStatus == "Unavailable" then return false, "Zakupy wymagają bezpiecznego trwałego zapisu." end
		if type(args.key) ~= "string" then return false, "Wybierz pakiet." end
		if args.key == "ExtraBeds" then
			if d.entitlements.ExtraBeds then return false, "Dodatkowe moduły są już odblokowane na Twoim koncie." end
			if bedCount(d) >= Config.MaxBeds then return false, "Masz już maksymalną liczbę grządek. Ten dodatek nie zwiększy pojemności ogrodu." end
		end
		local product = Config.Products[args.key]
		local pass = Config.Passes[args.key]
		if product and product > 0 then MarketplaceService:PromptProductPurchase(s.player, product); return true end
		if pass and pass > 0 then MarketplaceService:PromptGamePassPurchase(s.player, pass); return true end
		return false, "Płatne pakiety nie są jeszcze dostępne."
	elseif action == "UseBoost" then
		if d.boostTokens < 1 then return false, "Nie masz przyspieszacza." end
		local changed = false
		for _, crop in pairs(d.beds) do if crop.readyAt > os.time() then crop.readyAt = os.time(); changed = true end end
		if not changed then return false, "Najpierw posadź roślinę." end
		d.boostTokens -= 1
		return true, "Przyspieszono wszystkie aktywne uprawy."
	end
	return false, "Nieznana akcja."
end

local Schemas = {
	State = {}, SelectSeed = {seed = true}, Plant = {index = true, seed = true}, Harvest = {index = true}, HarvestAll = {},
	Water = {index = true}, BuySeed = {seed = true, quantity = true}, Upgrade = {key = true}, Daily = {},
	Quest = {}, Season = {}, GlobalSeason = {}, Theme = {theme = true}, Teleport = {}, Gift = {targetUserId = true, seed = true, quantity = true},
	Premium = {key = true}, UseBoost = {},
	SaveDesign={slot=true,shape=true,palette=true,scale=true},PlaceDesign={stand=true,slot=true},RemoveDesign={stand=true},PublishDesign={slot=true},ImportDesign={slot=true,code=true},
}
local function request(player, action, args)
	local s = Profiles[player]
	if not s or not s.farm then return {ok = false, message = "Ogród jest przygotowywany. Spróbuj za chwilę."} end
	if Closing or s.leaving or s.lostLease then return {ok = false, message = "Trwa bezpieczne zamykanie sesji."} end
	if type(action) ~= "string" or #action > 24 or (args ~= nil and type(args) ~= "table") then return {ok = false, message = "Nieprawidłowe żądanie."} end
	local schema = Schemas[action]
	if not schema then return {ok = false, message = "Nieznana akcja."} end
	local fieldCount = 0
	for key in pairs(args or {}) do
		fieldCount += 1
		if fieldCount > 4 or not schema[key] then return {ok = false, message = "Nieprawidłowe argumenty."} end
	end
	local now = os.clock()
	local throttle = Throttles[player] or {time = now, tokens = 12, state = -100}
	Throttles[player] = throttle
	throttle.tokens = math.min(12, throttle.tokens + (now - throttle.time) * 6); throttle.time = now
	if throttle.tokens < 1 or (action == "State" and now - throttle.state < 0.4) then return {ok = false, message = "Zwolnij na chwilę."} end
	throttle.tokens -= 1
	if action == "State" then throttle.state = now; return {ok = true, state = snapshot(s)} end
	if s.busy then return {ok = false, message = "Trwa zapis lub dostarczanie prezentu. Spróbuj za chwilę."} end
	s.busy = true
	resetDay(s.data)
	local success, ok, message, code = pcall(dispatch, s, action, args or {})
	s.busy = false
	if not success then warn("Space Garden action failed", action, ok); return {ok = false, message = "Akcja chwilowo niedostępna. Spróbuj ponownie."} end
	render(s)
	return {ok = ok == true, message = message, state = snapshot(s),code=type(code)=="string"and BlueprintModule.NormalizeCode(code)or nil}
end
Action.OnServerInvoke = request

local function makeStats(player)
	local stats = Instance.new("Folder"); stats.Name = "leaderstats"; stats.Parent = player
	for _, name in ipairs({"Kredyty", "Zbiory", "Poziom"}) do local v = Instance.new("IntValue"); v.Name = name; v.Parent = stats end
end
local function refreshFriendships(s)
	for player, other in pairs(Profiles) do
		if player ~= s.player then
			local ok, friend = pcall(function() return s.player:IsFriendsWithAsync(player.UserId) end)
			if ok then s.friends[player.UserId] = friend; other.friends[s.player.UserId] = friend end
		end
	end
end
local function grantPass(s, name)
	if not s.durable or s.data.entitlements[name] then return end
	s.passWorkers = s.passWorkers or {}
	if s.passWorkers[name] then return end
	s.passWorkers[name] = true
	task.spawn(function()
		while Profiles[s.player] == s and s.player.Parent and not s.leaving and not s.lostLease and not Closing do
			if s.data.entitlements[name] then break end
			local hasRoom = name ~= "StarterPack" or ((s.data.inventory.Nebula or 0) + 3 <= INVENTORY_CAP and s.data.credits + 250 <= VALUE_CAP)
			if s.busy or not hasRoom then
				task.wait(1)
			else
				s.busy = true
				local candidate = copy(s.data); candidate.entitlements[name] = true
				if name == "StarterPack" then candidate.inventory.Nebula = (candidate.inventory.Nebula or 0) + 3; grantCredits(candidate, 250) end
				local saved = persist(s, candidate, false)
				if saved then s.data = candidate; render(s) end
				s.busy = false
				if saved then break end
				task.wait(3)
			end
		end
		s.passWorkers[name] = nil
	end)
end
local function onPlayer(player)
	local s = load(player)
	if not s then return end
	if not player.Parent or Closing then if s.durable then persist(s, s.data, true) end; return end
	for i = 1, Config.MaxFarms do
		if not Assigned[i] and Farms:FindFirstChild("Farm" .. i) then s.farmIndex = i; s.farm = Farms["Farm" .. i]; Assigned[i] = player; break end
	end
	if not s.farm then
		if s.durable then persist(s, s.data, true) end
		player:Kick("Wszystkie ogrody są zajęte. Dołącz do innego serwera."); return
	end
	Profiles[player] = s
	makeStats(player)
	s.farm:SetAttribute("OwnerUserId", player.UserId)
	local label = s.farm:FindFirstChild("OwnerLabel", true)
	if label and label:IsA("TextLabel") then label.Text = player.DisplayName .. " • OGRÓD " .. s.farmIndex end
	for i = 1, Config.MaxBeds do
		local pad = s.farm.Beds:FindFirstChild("Bed" .. i)
		if pad and pad:IsA("BasePart") then
			local old = pad:FindFirstChild("GardenPrompt"); if old then old:Destroy() end
			local prompt = Instance.new("ProximityPrompt"); prompt.Name = "GardenPrompt"; prompt.HoldDuration = 0.18; prompt.MaxActivationDistance = 12; prompt.RequiresLineOfSight = false; prompt.KeyboardKeyCode = Enum.KeyCode.E; prompt.Parent = pad
			prompt.Triggered:Connect(function(trigger)
				if trigger ~= player or Profiles[player] ~= s then return end
				local root = trigger.Character and trigger.Character:FindFirstChild("HumanoidRootPart")
				if not root or (root.Position - pad.Position).Magnitude > 16 then return end
				local crop = s.data.beds[tostring(i)]
				local action = crop and (crop.readyAt <= os.time() and "Harvest" or "Water") or "Plant"
				local args = {index = i}; if action == "Plant" then args.seed = s.data.selectedSeed end
				request(player, action, args)
			end)
		end
	end
	local function positionCharacter(character)
		local root=character:WaitForChild("HumanoidRootPart",10)
		if not root then return end
		task.wait(.25)
		if Profiles[player]==s and player.Character==character then teleport(s) end
	end
	s.characterConnection=player.CharacterAdded:Connect(positionCharacter)
	if player.Character then task.spawn(positionCharacter,player.Character) end
	render(s)
	task.spawn(refreshFriendships, s)
	task.spawn(function()
		for name, id in pairs(Config.Passes) do
			if id > 0 then local ok, owned = pcall(function() return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id) end); if ok and owned then grantPass(s, name) end end
		end
		recoverGifts(s)
		recoverBlueprints(s)
	end)
end
Players.PlayerAdded:Connect(onPlayer)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(onPlayer, player) end

local function removePlayer(player)
	local s = Profiles[player]
	if not s then return end
	if s.removing then while not s.removed do task.wait(0.1) end; return end
	s.removing = true
	s.leaving = true
	while s.busy do task.wait(0.1) end
	if not s.busy then
		s.busy = true
		if s.durable and not s.lostLease then persist(s, s.data, true) end
		s.busy = false
	end
	Profiles[player] = nil; Throttles[player] = nil
	if s.characterConnection then s.characterConnection:Disconnect() end
	if s.farm then
		Decorations.Clear(s.farm)
		Assigned[s.farmIndex] = nil; s.farm:SetAttribute("OwnerUserId", 0)
		local label = s.farm:FindFirstChild("OwnerLabel", true); if label and label:IsA("TextLabel") then label.Text = "WOLNY OGRÓD • " .. s.farmIndex end
		for _, pad in ipairs(s.farm.Beds:GetChildren()) do
			local crop = pad:FindFirstChild("Crop"); if crop then crop:Destroy() end
			local prompt = pad:FindFirstChild("GardenPrompt"); if prompt then prompt:Destroy() end
			pad:SetAttribute("OwnerUserId", 0); pad:SetAttribute("Seed", ""); pad:SetAttribute("ReadyAt", 0)
		end
	end
	s.removed = true
end
Players.PlayerRemoving:Connect(removePlayer)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, id, purchased)
	if not purchased then return end
	local s = Profiles[player]; if not s then return end
	for name, configured in pairs(Config.Passes) do if configured > 0 and configured == id then grantPass(s, name) end end
end)
local function waitForReceiptProfile(player, s, options)
	-- An autosave or another receipt may briefly own this profile. Wait without
	-- holding its busy gate, then revalidate after every yield before granting.
	options = options or {}
	local clock = options.Clock or os.clock
	local now = options.Now or os.time
	local pause = options.Wait or task.wait
	local deadline = clock() + 5
	while true do
		if not player or not s or Profiles[player] ~= s or player.Parent ~= Players or not s.durable or s.lostLease or s.leaving or Closing then return false end
		if not integer(s.lastSave, 0, 9007199254740991) or s.lastSave + Config.SessionLease <= now() then return false end
		if not s.busy then return true end
		local remaining = deadline - clock()
		if remaining <= 0 then return false end
		pause(math.min(0.1, remaining))
	end
end
MarketplaceService.ProcessReceipt = function(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local s = player and Profiles[player]
	if not waitForReceiptProfile(player, s) then return Enum.ProductPurchaseDecision.NotProcessedYet end
	local productName
	for name, id in pairs(Config.Products) do if id > 0 and id == receipt.ProductId then productName = name end end
	if not productName then return Enum.ProductPurchaseDecision.NotProcessedYet end
	local receiptId = tostring(receipt.PurchaseId)
	if s.data.purchaseReceipts[receiptId] then return Enum.ProductPurchaseDecision.PurchaseGranted end
	s.busy = true
	local candidate = copy(s.data)
	if productName == "SeedPack" then
		if (candidate.inventory.Nebula or 0) + 3 > INVENTORY_CAP or (candidate.inventory.Prism or 0) + 5 > INVENTORY_CAP then s.busy = false; return Enum.ProductPurchaseDecision.NotProcessedYet end
		candidate.inventory.Nebula = (candidate.inventory.Nebula or 0) + 3; candidate.inventory.Prism = (candidate.inventory.Prism or 0) + 5
	elseif productName == "GrowthBoost" then
		-- Store tokens if no plants are active: the purchase never vanishes.
		local used = false
		for _, crop in pairs(candidate.beds) do if crop.readyAt > os.time() then crop.readyAt = os.time(); used = true end end
		if not used then
			if candidate.boostTokens >= VALUE_CAP then s.busy = false; return Enum.ProductPurchaseDecision.NotProcessedYet end
			candidate.boostTokens += 1
		end
	else s.busy = false; return Enum.ProductPurchaseDecision.NotProcessedYet end
	candidate.purchaseReceipts[receiptId] = os.time()
	local saved = persist(s, candidate, false)
	if saved then s.data = candidate; render(s) end
	s.busy = false
	return saved and Enum.ProductPurchaseDecision.PurchaseGranted or Enum.ProductPurchaseDecision.NotProcessedYet
end

task.spawn(function()
	while not Closing do
		task.wait(2)
		for _, s in pairs(Profiles) do if not s.busy then render(s) end end
	end
end)
task.spawn(function()
	while not Closing do
		task.wait(Config.AutosaveInterval)
		for _, s in pairs(Profiles) do
			if s.durable and not s.busy and not s.leaving and not s.lostLease then
				s.busy = true; persist(s, s.data, false); s.busy = false
				recoverGifts(s)
				recoverBlueprints(s)
			end
		end
	end
end)
game:BindToClose(function()
	Closing = true
	local remaining = 0
	for player in pairs(Profiles) do remaining += 1; task.spawn(function() removePlayer(player); remaining -= 1 end) end
	local deadline = os.clock() + 25
	while remaining > 0 and os.clock() < deadline do task.wait(0.1) end
	GlobalService:Close(deadline)
end)

if Studio then
	-- Server-only Studio QA surface. No debug remotes are shipped.
	_G.SpaceGardenTest = {
		Profiles = Profiles, Request = request, Sanitize = sanitize, NewData = newData,
		RunGlobalTests = GlobalModule.RunTests,
		RunDecorationTests=Decorations.RunValidationTests,
		RunBlueprintTests=BlueprintModule.RunTests,
		RunReceiptReadinessTests = function()
			-- No real waits, purchases, DataStores, or live Player profiles.
			local player = {Parent = Players}
			local s, tick, epoch, pauses, onPause
			local checks = {}
			local function fresh()
				tick, epoch, pauses, onPause = 0, 10000, 0, nil
				player.Parent = Players
				s = {durable = true, lastSave = epoch, busy = false}
				Profiles[player] = s
			end
			local adapters = {
				Clock = function() return tick end,
				Now = function() return epoch end,
				Wait = function(duration) tick += duration; pauses += 1; if onPause then onPause() end end,
			}
			local function check(condition, label) assert(condition, label); table.insert(checks, label) end
			local ok, result = pcall(function()
				fresh(); check(waitForReceiptProfile(player, s, adapters) and pauses == 0, "idle durable receipt profile proceeds immediately")
				fresh(); s.busy = true; onPause = function() if pauses == 2 then s.busy = false end end
				check(waitForReceiptProfile(player, s, adapters) and pauses == 2, "receipt waits for an in-flight autosave to release its gate")
				fresh(); s.busy = true
				check(not waitForReceiptProfile(player, s, adapters) and tick >= 5 and tick <= 5.001, "receipt busy wait is bounded to five seconds")
				fresh(); s.busy = true; onPause = function() Profiles[player] = {} end
				check(not waitForReceiptProfile(player, s, adapters), "replaced profile cannot receive a stale receipt grant")
				fresh(); s.busy = true; onPause = function() player.Parent = nil end
				check(not waitForReceiptProfile(player, s, adapters), "player departure aborts waiting receipt")
				fresh(); s.busy = true; onPause = function() epoch += Config.SessionLease end
				check(not waitForReceiptProfile(player, s, adapters), "expired durable lease aborts waiting receipt")
				fresh(); s.busy = true; onPause = function() s.lostLease = true end
				check(not waitForReceiptProfile(player, s, adapters), "lost lease aborts waiting receipt")
				fresh(); s.durable = false
				check(not waitForReceiptProfile(player, s, adapters) and pauses == 0, "session-only profiles cannot receive paid grants")
				fresh(); s.leaving = true
				check(not waitForReceiptProfile(player, s, adapters), "closing player profile cannot receive a paid grant")
				local premium = {durable = true, saveStatus = "Loaded", data = newData()}
				premium.data.upgrades.Beds = Config.Upgrades.Beds.MaxLevel
				local accepted, reason = dispatch(premium, "Premium", {key = "ExtraBeds"})
				check(not accepted and reason:find("maksymalną", 1, true), "ExtraBeds purchase prompt is rejected at maximum capacity")
				premium.data.upgrades.Beds = 0; premium.data.entitlements.ExtraBeds = true
				accepted, reason = dispatch(premium, "Premium", {key = "ExtraBeds"})
				check(not accepted and reason:find("już odblokowane", 1, true), "already-owned ExtraBeds purchase prompt is rejected")
				return {passed = #checks, checks = checks}
			end)
			Profiles[player] = nil
			if not ok then error(result) end
			return result
		end,
		RunBlueprintWorkflowTests=function()
			local oldStore,oldBlueprints,oldBudget=Store,BlueprintService,blueprintBudget
			local rows,publicRows={},{}
			local failProfile,publicTimeout=false,false
			local profileWrites,publicReads=0,0
			Store={UpdateAsync=function(_,key,fn)
				profileWrites+=1;if failProfile then error("Injected profile outage")end
				local result=fn(copy(rows[key]));if result then rows[key]=copy(result)end return copy(result)
			end}
			local external={}
			function external:UpdateAsync(key,fn)local result=fn(copy(publicRows[key]));if result then publicRows[key]=copy(result)end;if publicTimeout then error("Committed publication timeout")end;return copy(result)end
			function external:GetAsync(key)publicReads+=1;return copy(publicRows[key])end
			BlueprintService=BlueprintModule.new(external,Decorations.Validate)
			blueprintBudget=function()return true end
			local ok,result=pcall(function()
				local checks={}
				local function check(value,label)assert(value,label);table.insert(checks,label)end
				local s={player={UserId=700000000004},token="design-workflow",durable=true,saveStatus="Loaded"}
				local function fresh()
					s.data=newData();s.data.decorations.designs["1"]={shape="OrbitBloom",palette="Aurora",scale=1};s.lastPublishAttempt=-100;s.lastDesignChange=-100;s.lastBlueprintFetch=-100
					rows[keyFor(s.player.UserId)]={data=copy(s.data),lock={token=s.token,expires=os.time()+180}}
				end
				fresh()
				local published,_,code=dispatch(s,"PublishDesign",{slot=1})
				check(published and BlueprintModule.NormalizeCode(code)and publicRows["b_"..code],"publication follows durable code reservation")
				check(s.data.blueprintsToday==1 and not next(s.data.blueprintOutbox)and rows[keyFor(s.player.UserId)].data.lastBlueprintCode==code,"publication confirmation persists quota and code")
				check(not dispatch(s,"PublishDesign",{slot=1})and s.data.blueprintsToday==1,"rapid publish cannot consume another daily slot")
				for _=2,3 do s.lastPublishAttempt=-100;s.data.blueprintLastAt=0;check(dispatch(s,"PublishDesign",{slot=1}),"daily slot can publish after cooldown")end
				s.lastPublishAttempt=-100;s.data.blueprintLastAt=0
				check(not dispatch(s,"PublishDesign",{slot=1})and s.data.blueprintsToday==3,"three-publication daily limit enforced")
				local restored=sanitize(rows[keyFor(s.player.UserId)].data)
				check(restored.blueprintsToday==3 and restored.lastBlueprintCode~=nil,"publication quota survives profile reload")
				fresh();publicTimeout=true
				local queued,_,pendingCode=dispatch(s,"PublishDesign",{slot=1})
				check(queued and s.data.blueprintOutbox[pendingCode]and publicRows["b_"..pendingCode],"external commit timeout retains same reserved code")
				publicTimeout=false;failProfile=true;s.lastPublishAttempt=-100
				check(dispatch(s,"PublishDesign",{slot=1})and s.data.blueprintOutbox[pendingCode]and s.data.blueprintsToday==1,"failed confirmation keeps outbox without another quota charge")
				failProfile=false;s.lastPublishAttempt=-100
				local delivered,_,replayedCode=dispatch(s,"PublishDesign",{slot=1})
				check(delivered and replayedCode==pendingCode and not next(s.data.blueprintOutbox)and s.data.blueprintsToday==1,"retry confirms immutable publication exactly once")
				s.lastDesignChange=-100;s.lastBlueprintFetch=-100
				check(dispatch(s,"ImportDesign",{slot=2,code=pendingCode})and s.data.decorations.designs["2"].shape=="OrbitBloom","import stores sanitized design in selected slot")
				local readBefore=publicReads;s.lastDesignChange=-100;s.lastBlueprintFetch=-100
				check(not dispatch(s,"ImportDesign",{slot=2,code="javascript:injected"})and publicReads==readBefore,"invalid import never reaches public datastore")
				local writeBefore=profileWrites;s.lastDesignChange=-100
				check(dispatch(s,"SaveDesign",{slot=1,shape="OrbitBloom",palette="Aurora",scale=1})and profileWrites==writeBefore,"unchanged design does not write player profile")
				failProfile=true;s.lastDesignChange=-100
				check(not dispatch(s,"SaveDesign",{slot=1,shape="OrbitBloom",palette="Nebula",scale=1})and s.data.decorations.designs["1"].palette=="Aurora","failed design save exposes no uncommitted change")
				failProfile=false;blueprintBudget=function()return false end;s.lastDesignChange=-100
				check(not dispatch(s,"PlaceDesign",{stand=1,slot=1})and not s.data.decorations.stands["1"],"profile budget reserve protects autosaves")
				return{passed=#checks,checks=checks}
			end)
			Store,BlueprintService,blueprintBudget=oldStore,oldBlueprints,oldBudget
			if not ok then error(result)end
			return result
		end,
		RunGlobalRewardTests = function()
			-- The real dispatch/persist path with isolated non-yielding adapters.
			local previousStore, previousGlobal = Store, GlobalService
			local row, fail, afterCommit = nil, false, false
			local available, period, total = true, seasonKey(), Config.GlobalSeasonGoal or 10000
			Store = {UpdateAsync = function(_, _, transform)
				if fail then error("Injected global reward save failure") end
				local updated = transform(copy(row)); if updated then row = copy(updated) end
				if afterCommit then error("Injected reward commit timeout") end
				return updated
			end}
			GlobalService = {Submit = function() return true end, Snapshot = function() return {live = true, season = {available = available, period = period, total = total}} end}
			local ok, result = pcall(function()
				local s = {player = {UserId = 700000000003}, token = "global-reward-test", durable = true, data = newData()}
				local reward = Config.GlobalSeasonReward or 300
				local checks = {}
				local function check(condition, label) assert(condition, label); table.insert(checks, label) end
				local function fresh()
					s.data = newData(); s.data.seasonProgress = Config.GlobalSeasonParticipation or 8
					row = {data = copy(s.data), lock = {token = s.token, expires = os.time() + 180}}
				end
				fresh()
				check(dispatch(s, "GlobalSeason", {}) and s.data.credits == Config.StartCredits + reward and row.data.globalSeasonClaimed, "global reward is durably committed before exposure")
				check(not dispatch(s, "GlobalSeason", {}) and s.data.credits == Config.StartCredits + reward, "duplicate global reward request cannot mint twice")
				fresh(); fail = true
				check(not dispatch(s, "GlobalSeason", {}) and not s.data.globalSeasonClaimed and s.data.credits == Config.StartCredits, "failed reward save exposes no grant")
				fail = false
				check(dispatch(s, "GlobalSeason", {}) and s.data.credits == Config.StartCredits + reward, "failed reward save can retry once")
				fresh(); afterCommit = true
				check(not dispatch(s, "GlobalSeason", {}) and not s.data.globalSeasonClaimed, "commit timeout does not expose unacknowledged reward")
				afterCommit = false; s.data = sanitize(row.data)
				check(not dispatch(s, "GlobalSeason", {}) and s.data.credits == Config.StartCredits + reward, "rejoin after committed timeout preserves exactly-once reward")
				fresh(); available = false
				check(not dispatch(s, "GlobalSeason", {}) and not row.data.globalSeasonClaimed, "unavailable global state cannot authorize reward")
				available = true; period = "2000-01"
				check(not dispatch(s, "GlobalSeason", {}), "old-month cache cannot authorize current reward")
				period = seasonKey(); total = 0
				check(not dispatch(s, "GlobalSeason", {}), "incomplete shared challenge cannot grant reward")
				total = Config.GlobalSeasonGoal or 10000; s.data.seasonProgress = 0
				check(not dispatch(s, "GlobalSeason", {}), "personal monthly participation is required")
				s.data.seasonKey = "2000-01"; s.data.globalSeasonClaimed = true; resetDay(s.data)
				check(not s.data.globalSeasonClaimed and s.data.seasonProgress == 0, "monthly rollover clears claim without reusing old participation")
				return {passed = #checks, checks = checks}
			end)
			Store, GlobalService = previousStore, previousGlobal
			if not ok then error(result) end
			return result
		end,
		Ready = function(player, index)
			local s = Profiles[player]; local crop = s and s.data.beds[tostring(index)]
			if crop then crop.readyAt = os.time() - 1; render(s); return true end
			return false
		end,
		Snapshot = function(player) return Profiles[player] and snapshot(Profiles[player]) end,
		RunPersistenceTests = function()
			-- Isolated in-memory adapter; this never reads/writes live DataStores.
			-- No yield occurs while the adapter is installed.
			local originalStore = Store
			local rows, failures, afterCommitFailures = {}, {}, {}
			local fake = {}
			function fake:UpdateAsync(key, transform)
				if failures[key] then error("Injected persistence failure") end
				local updated = transform(copy(rows[key]))
				if updated ~= nil then rows[key] = copy(updated) end
				if afterCommitFailures[key] then error("Injected timeout after durable commit") end
				return copy(updated)
			end
			Store = fake
			local ok, result = pcall(function()
				local sourceId, targetId = 700000000001, 700000000002
				local source = {player = {UserId = sourceId}, token = "test-owner", durable = true, data = newData(), saveStatus = "Loaded"}
				rows[keyFor(sourceId)] = {data = copy(source.data), lock = {token = source.token, expires = os.time() + 180}}
				rows[keyFor(targetId)] = {data = newData()}
				local tx = {target = targetId, seed = "Cosmo", created = os.time(), bonus = 35}
				local candidate = copy(source.data); candidate.inventory.Cosmo -= 1; candidate.giftLast = day(); candidate.outbox["test-gift"] = tx
				assert(persist(source, candidate, false), "sender reservation")
				source.data = candidate
				failures[keyFor(targetId)] = true
				assert(not deliverGift(source, "test-gift", tx), "recipient outage must keep pending")
				assert(source.data.outbox["test-gift"] and source.data.credits == Config.StartCredits, "no sender bonus before delivery")
				failures[keyFor(targetId)] = nil
				assert(deliverGift(source, "test-gift", tx), "pending delivery recovery")
				assert(rows[keyFor(targetId)].data.inventory.Cosmo == Config.StartSeeds.Cosmo + 1, "recipient receives exactly one seed")
				assert(rows[keyFor(targetId)].data.credits == Config.StartCredits + 35, "recipient bonus once")
				assert(source.data.credits == Config.StartCredits + 35 and not next(source.data.outbox), "sender bonus after confirmation")
				deliverGift(source, "test-gift", tx)
				assert(rows[keyFor(targetId)].data.inventory.Cosmo == Config.StartSeeds.Cosmo + 1 and source.data.credits == Config.StartCredits + 35, "replay idempotent")
				local function reserve(id)
					local pending = copy(source.data); pending.inventory.Cosmo -= 1; pending.outbox[id] = copy(tx)
					assert(persist(source, pending, false), "additional gift reservation")
					source.data = pending
				end
				-- Recipient committed but sender confirmation is unavailable.
				reserve("sender-outage")
				local beforeSeed = rows[keyFor(targetId)].data.inventory.Cosmo
				local beforeSender = source.data.credits
				failures[keyFor(sourceId)] = true
				assert(not deliverGift(source, "sender-outage", tx), "sender confirmation outage")
				assert(rows[keyFor(targetId)].data.inventory.Cosmo == beforeSeed + 1 and source.data.outbox["sender-outage"] and source.data.credits == beforeSender, "recipient committed while sender remains pending")
				failures[keyFor(sourceId)] = nil
				-- Simulate a fresh server loading the pending source profile.
				source.data = sanitize(rows[keyFor(sourceId)].data); source.token = "rejoined-owner"
				rows[keyFor(sourceId)].lock = {token = source.token, expires = os.time() + 180}
				assert(deliverGift(source, "sender-outage", tx), "sender confirmation recovery after rejoin")
				assert(rows[keyFor(targetId)].data.inventory.Cosmo == beforeSeed + 1 and source.data.credits == beforeSender + 35, "partial-success replay awards exactly once")
				-- A full recipient cannot consume the seed or create a receipt.
				reserve("full-recipient")
				rows[keyFor(targetId)].data.inventory.Cosmo = INVENTORY_CAP
				assert(not deliverGift(source, "full-recipient", tx), "full recipient stays pending")
				assert(source.data.outbox["full-recipient"] and not rows[keyFor(targetId)].data.giftReceipts["full-recipient"], "full recipient receives no receipt")
				rows[keyFor(targetId)].data.inventory.Cosmo -= 1
				assert(deliverGift(source, "full-recipient", tx) and rows[keyFor(targetId)].data.inventory.Cosmo == INVENTORY_CAP, "full recipient recovery preserves seed")
				-- Current Unix timestamps must protect an active foreign lease.
				assert(activeForeignLease({lock = {token = "other", expires = os.time() + 180}}, source.token), "current-epoch active foreign lease")
				assert(not activeForeignLease({lock = {token = "other", expires = os.time() - 1}}, source.token), "expired foreign lease")
				reserve("locked-recipient")
				rows[keyFor(targetId)].data.inventory.Cosmo = 10
				rows[keyFor(targetId)].lock = {token = "another-server", expires = os.time() + 180}
				assert(not deliverGift(source, "locked-recipient", tx) and not rows[keyFor(targetId)].data.giftReceipts["locked-recipient"], "offline delivery respects foreign lease")
				rows[keyFor(targetId)].lock = nil
				assert(deliverGift(source, "locked-recipient", tx), "delivery resumes after lease release")
				-- A response can fail even when the recipient commit succeeded.
				reserve("recipient-timeout")
				beforeSeed = rows[keyFor(targetId)].data.inventory.Cosmo
				afterCommitFailures[keyFor(targetId)] = true
				assert(not deliverGift(source, "recipient-timeout", tx), "recipient commit timeout remains pending")
				afterCommitFailures[keyFor(targetId)] = nil
				assert(deliverGift(source, "recipient-timeout", tx) and rows[keyFor(targetId)].data.inventory.Cosmo == beforeSeed + 1, "recipient commit timeout replay does not duplicate")
				-- The sender can also commit the confirmation before timing out.
				reserve("sender-timeout")
				beforeSender = source.data.credits
				afterCommitFailures[keyFor(sourceId)] = true
				assert(not deliverGift(source, "sender-timeout", tx), "sender commit timeout reports pending locally")
				afterCommitFailures[keyFor(sourceId)] = nil
				source.data = sanitize(rows[keyFor(sourceId)].data)
				assert(not source.data.outbox["sender-timeout"] and source.data.credits == beforeSender + 35, "reloaded sender confirmation already finalized once")
				local large = newData(); large.credits = VALUE_CAP + 100; large.xp = VALUE_CAP + 200; large.inventory.Cosmo = INVENTORY_CAP + 1
				large = sanitize(large)
				assert(large.credits == VALUE_CAP and large.xp == VALUE_CAP and large.inventory.Cosmo == INVENTORY_CAP, "finite large loaded values clamp rather than reset")
				local invalid = newData(); invalid.credits = 0 / 0; invalid.xp = math.huge
				invalid = sanitize(invalid)
				assert(invalid.credits == Config.StartCredits and invalid.xp == 0, "NaN and infinity do not enter profiles")
				assert(persist(source, source.data, true) and rows[keyFor(sourceId)].lock == nil, "explicit lease release")
				rows[keyFor(sourceId)].lock = {token = "new-owner", expires = os.time() + 180}
				assert(not persist(source, source.data, false) and source.lostLease, "old owner cannot overwrite")
				local checks = {"durable sender reservation", "recipient outage", "no premature bonus", "pending recovery", "recipient award", "sender confirmation", "idempotent replay", "sender confirmation outage and rejoin", "full recipient pending and recovery", "current-epoch foreign lease", "offline delivery respects locks", "recipient commit timeout replay", "sender commit timeout reload", "large finite values clamp", "NaN and infinity rejection", "lease release and old-owner rejection"}
				return {passed = #checks, checks = checks}
			end)
			Store = originalStore
			if not ok then error(result) end
			return result
		end,
	}
end
print("Space Garden ready • " .. (Studio and "Studio session-only profiles" or "durable profiles"))
