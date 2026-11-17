-- Space Garden | shared catalog. Economy overrides are read on the server.
local Config = {}

Config.SeedOrder = {"Cosmo", "Lunar", "Prism", "Solar", "Nebula", "Void"}
Config.Seeds = {
	Cosmo = {Name="Kosmokaktus", Description="Turkusowe rozety z pasa asteroid. Idealne na pierwszy zbiór.", Price=12, GrowTime=25, Yield=26, XP=20, UnlockLevel=1, Color=Color3.fromRGB(83,237,197), Rarity="Zwykłe"},
	Lunar = {Name="Księżycowy Dzwon", Description="Bioluminescencyjne kielichy, które rozkwitają w niskiej grawitacji.", Price=38, GrowTime=65, Yield=85, XP=32, UnlockLevel=2, Color=Color3.fromRGB(116,171,255), Rarity="Niezwykłe"},
	Prism = {Name="Pryzmatowy Kwiat", Description="Krystaliczne płatki rozszczepiają światło odległych gwiazd.", Price=105, GrowTime=140, Yield=245, XP=50, UnlockLevel=3, Color=Color3.fromRGB(203,145,255), Rarity="Rzadkie"},
	Solar = {Name="Słoneczny Koral", Description="Złoty koral magazynujący energię gwiazdy wewnątrz pąków.", Price=260, GrowTime=280, Yield=640, XP=80, UnlockLevel=5, Color=Color3.fromRGB(255,193,92), Rarity="Epickie"},
	Nebula = {Name="Mgławicowa Meduza", Description="Unosi świetliste wąsy nad podłożem. Skarb galaktycznych botaników.", Price=650, GrowTime=540, Yield=1690, XP=125, UnlockLevel=8, Color=Color3.fromRGB(255,129,211), Rarity="Legendarne"},
	Void = {Name="Serce Osobliwości", Description="Rzadki kwiat otoczony orbitującymi pierścieniami. Ostatnia granica badań.", Price=1800, GrowTime=1080, Yield=4950, XP=200, UnlockLevel=12, Color=Color3.fromRGB(164,145,255), Rarity="Mityczne"},
}
Config.UpgradeOrder = {"Lamp", "Beds", "Yield"}
Config.Upgrades = {
	Lamp = {Name="Światło fotonowe", Description="Każdy poziom skraca wzrost o 12%. Maksymalnie 48% krótszy wzrost.", MaxLevel=4, BaseCost=150, CostMultiplier=2.35},
	Beds = {Name="Moduły hydroponiczne", Description="Każdy poziom otwiera dwa kolejne miejsca uprawy.", MaxLevel=4, BaseCost=200, CostMultiplier=2.5},
	Yield = {Name="Synteza astralna", Description="Każdy poziom zwiększa wartość zbiorów o 20%.", MaxLevel=5, BaseCost=220, CostMultiplier=2.6},
}
Config.Themes = {
	Aurora={Name="Aurora",Color=Color3.fromRGB(83,237,197)},
	Mars={Name="Mars",Color=Color3.fromRGB(255,158,109)},
	Eclipse={Name="Zaćmienie",Color=Color3.fromRGB(185,145,255)},
}
Config.ThemeOrder={"Aurora","Mars","Eclipse"}
Config.StartCredits=120
Config.StartSeeds={Cosmo=6,Lunar=2}
Config.InitialBeds=4
Config.MaxBeds=12
Config.MaxFarms=6
Config.DailyCredits=100
Config.DailySeedCount=2
Config.GiftBonus=35
Config.SeasonGoal=250
Config.SeasonReward=500
Config.GlobalSeasonGoal=10000
Config.GlobalSeasonReward=300
Config.GlobalSeasonParticipation=8
Config.BlueprintsPerDay=3
Config.BlueprintPublishCooldown=30
Config.BlueprintFetchCooldown=5
Config.DesignEditCooldown=1
Config.DailyQuestGoal=8
Config.DailyQuestReward=120
Config.WaterReduction=8
Config.WaterCooldown=20
Config.Products={SeedPack=3728080320,GrowthBoost=3728080406}
Config.Passes={ExtraBeds=2071278256,StarterPack=2071200256}
Config.SaveVersion=2
Config.DataStoreName="SpaceGarden_v1"
Config.SessionLease=180
Config.AutosaveInterval=45

function Config.GetUpgradeCost(key,level)
	local def=Config.Upgrades[key]
	return def and math.floor(def.BaseCost*def.CostMultiplier^level) or math.huge
end

return Config
