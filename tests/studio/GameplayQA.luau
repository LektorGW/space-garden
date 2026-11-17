-- Run in a regular Studio server Script, passing _G.SpaceGardenTest and a player.
return function(api, player)
	local Config=require(game:GetService("ReplicatedStorage").SpaceGarden.Config)
	local checks={}
	local function check(name,condition) assert(condition,name);table.insert(checks,name) end
	local function request(action,args)
		task.wait(.23)
		return api.Request(player,action,args or {})
	end
	local s=api.Profiles[player]
	s.data=api.NewData()
	local r=request("Plant",{index=1,seed="Cosmo"})
	check("plant consumes one seed",r.ok and r.state.inventory.Cosmo==5)
	local ready=r.state.beds[1].readyAt
	r=request("Plant",{index=1,seed="Cosmo"});check("occupied bed rejects duplicate",not r.ok and r.state.inventory.Cosmo==5)
	r=request("Plant",{index=5,seed="Cosmo"});check("locked bed rejected",not r.ok)
	r=request("Harvest",{index=1});check("early harvest rejected",not r.ok and r.state.credits==120)
	r=request("Water",{index=1});check("watering shortens growth",r.ok and r.state.beds[1].readyAt<=ready-Config.WaterReduction)
	r=request("Water",{index=1});check("duplicate watering rejected",not r.ok)
	api.Ready(player,1);r=request("Harvest",{index=1})
	check("harvest awards authoritative yield and XP",r.ok and r.state.credits==146 and r.state.xp==20 and r.state.harvested==1)
	r=request("Harvest",{index=1});check("duplicate harvest rejected",not r.ok and r.state.credits==146)
	r=request("BuySeed",{seed="Cosmo",quantity=2});check("shop debits authoritative price",r.ok and r.state.credits==122 and r.state.inventory.Cosmo==7)
	for _,qty in ipairs({-1,0,1.5,101})do
		r=request("BuySeed",{seed="Cosmo",quantity=qty});check("invalid quantity "..qty,not r.ok and r.state.credits==122)
	end
	for _,index in ipairs({0,13,1.5,"1",0/0,math.huge})do
		r=request("Plant",{index=index,seed="Cosmo"});check("malformed index "..tostring(index),not r.ok and r.state.inventory.Cosmo==7)
	end
	r=request("BuySeed",{seed="Lunar",quantity=1});check("locked species rejected",not r.ok)
	r=request("Daily");check("daily reward",r.ok and r.state.credits==222 and r.state.daily.streak==1)
	r=request("Daily");check("daily cannot replay",not r.ok and r.state.credits==222)
	r=request("Upgrade",{key="Lamp"});check("research cost and level",r.ok and r.state.upgrades.Lamp==1 and r.state.credits==72)
	r=request("Upgrade",{key="Beds"});check("unaffordable research rejected",not r.ok)
	r=request("Gift",{targetUserId=123,seed="Cosmo",quantity=1});check("Studio gifts fail closed",not r.ok)
	r=request("Premium",{key="SeedPack"});check("unconfigured purchases disabled",not r.ok)
	r=request("Theme",{theme="Mars"});check("theme action",r.ok and r.state.theme=="Mars")
	local changed=0
	for _,v in ipairs(s.farm:GetDescendants())do
		if v:IsA("BasePart")and v:GetAttribute("ThemeAccent")and v.Color==Config.Themes.Mars.Color then changed+=1 end
	end
	check("theme changes 3D accents",changed>10)
	check("catalog includes authoritative economy",r.state.catalog.Cosmo.Price==12 and r.state.upgradeCosts.Lamp==Config.GetUpgradeCost("Lamp",1))
	s.data=api.NewData();s.data.xp=1400;s.data.credits=100000;s.data.upgrades={Lamp=2,Beds=4,Yield=1}
	local expected=0
	for i,key in ipairs(Config.SeedOrder)do
		s.data.inventory[key]=10
		r=request("Plant",{index=i,seed=key})
		check("plant species "..key,r.ok and r.state.beds[i].seed==key)
		check("growth research affects "..key,r.state.beds[i].readyAt-r.state.beds[i].plantedAt==math.max(3,math.floor(Config.Seeds[key].GrowTime*.76)))
		api.Ready(player,i);expected+=math.floor(Config.Seeds[key].Yield*1.2)
	end
	r=request("HarvestAll");check("all species harvest and yield research",r.ok and r.state.credits==100000+expected and r.state.harvested==6)
	check("all twelve beds unlocked",r.state.beds[12].unlocked)
	s.data.beds["1"]={seed="Cosmo",plantedAt=os.time()-100,readyAt=os.time()-1,watered=false}
	s.data=api.Sanitize(s.data);r=request("Harvest",{index=1});check("offline mature timestamp harvests",r.ok)
	s.data.questProgress=Config.DailyQuestGoal;s.data.questClaimed=false
	local before=s.data.credits;r=request("Quest");check("daily quest claim",r.ok and s.data.credits==before+Config.DailyQuestReward)
	r=request("Quest");check("daily quest cannot replay",not r.ok and s.data.credits==before+Config.DailyQuestReward)
	s.data.seasonProgress=Config.SeasonGoal;s.data.seasonClaimed=false
	before=s.data.credits;r=request("Season");check("season reward",r.ok and s.data.credits==before+Config.SeasonReward)
	r=request("Season");check("season cannot replay",not r.ok)
	s.data.seasonKey="2020-01";s.data.seasonProgress=Config.SeasonGoal;s.data.seasonClaimed=true
	r=request("Season");check("monthly season resets",not r.ok and r.state.season.progress==0 and not r.state.season.claimed)
	s.data.dailyLast=math.floor(os.time()/86400)-1;s.data.streak=6
	r=request("Daily");check("daily streak advances",r.ok and r.state.daily.streak==7)
	for i=1,30 do api.Request(player,"SelectSeed",{seed="Cosmo"}) end
	r=api.Request(player,"Plant",{index=12,seed="Cosmo"});check("spam throttled",not r.ok)
	s.data=api.NewData();s.render={};task.wait(2)
	return {passed=#checks,checks=checks}
end
