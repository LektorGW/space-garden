-- Space Garden • native responsive interface, no external assets.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local StarterGui = game:GetService("StarterGui")
local SoundService = game:GetService("SoundService")
local MarketplaceService = game:GetService("MarketplaceService")
local player = Players.LocalPlayer
local playerGui=player:WaitForChild("PlayerGui")
local package = ReplicatedStorage:WaitForChild("SpaceGarden")
local Config = require(package:WaitForChild("Config"))
local Remote = package:WaitForChild("Action")
local C = {
	Bg=Color3.fromRGB(9,18,31), Panel=Color3.fromRGB(15,30,45), Card=Color3.fromRGB(22,42,57),
	Line=Color3.fromRGB(44,76,89), Text=Color3.fromRGB(236,247,242), Muted=Color3.fromRGB(149,178,187),
	Cyan=Color3.fromRGB(83,225,225), Lime=Color3.fromRGB(200,246,124), Gold=Color3.fromRGB(255,206,119),
	Danger=Color3.fromRGB(255,146,155), Dark=Color3.fromRGB(15,36,37),
}
local state, currentView, selectedSeed = nil, "Garden", "Cosmo"
local rankingScope="server"
local designerSlot,designerStand=1,1
local designerDraft,lastBlueprintCode,DecorCatalog
local designImportText=""
local reducedMotion, busy, panelOpen = false, false, true
local soundEnabled,chatEnabled=true,false
local uiSound
local coreRequests={}
local function setCoreGui(kind,value)
	local token=(coreRequests[kind] or 0)+1
	coreRequests[kind]=token
	task.spawn(function()
		for attempt=1,8 do
			if coreRequests[kind]~=token then return end
			local ok=pcall(function() StarterGui:SetCoreGuiEnabled(kind,value) end)
			if ok then return end
			task.wait(.25)
		end
	end)
end
-- Native overlays otherwise cover the station navigation and credit counter.
setCoreGui(Enum.CoreGuiType.Chat,false)
setCoreGui(Enum.CoreGuiType.PlayerList,false)
local function playUISound(volume)
	if not soundEnabled or not uiSound or not uiSound.Parent then return end
	uiSound.Volume=volume or .03
	uiSound.PlaybackSpeed=1.5
	uiSound.TimePosition=0
	uiSound:Play()
end
local updateView, buildView, layout
-- Query on the client so Roblox returns this account's regional/discounted price.
-- Current API: create.roblox.com/docs/reference/engine/classes/MarketplaceService#GetProductInfoAsync
local offerPriceCache={}
local function getOfferPrice(id,infoType)
	local key=tostring(infoType.Value)..":"..tostring(id)
	local cached=offerPriceCache[key]
	local clockNow=os.clock()
	if not cached then cached={expiresAt=0,loading=false}; offerPriceCache[key]=cached end
	if not cached.loading and clockNow>=cached.expiresAt then
		cached.loading=true
		-- An expired price is not shown while a replacement is being fetched.
		cached.price=nil
		task.spawn(function()
			local ok,info=pcall(function() return MarketplaceService:GetProductInfoAsync(id,infoType) end)
			local price=ok and type(info)=="table" and info.PriceInRobux or nil
			if type(price)=="number" and price==price and price>=0 and price<math.huge and price%1==0 then
				cached.price=price; cached.expiresAt=os.clock()+120
			else
				cached.price=nil; cached.expiresAt=os.clock()+30
			end
			cached.loading=false
		end)
	end
	return cached.price
end
local targetUserId, giftSignature = nil, ""
local uiUpdates, navButtons = {}, {}
local persistentConnections={}
local lastError, welcomeDismissed = 0, false
local serverOffset=0
local function now() return os.time()+serverOffset end

local function make(kind, props, parent)
	local item = Instance.new(kind)
	for k,v in pairs(props or {}) do item[k]=v end
	item.Parent=parent
	return item
end
local function corner(parent,r) make("UICorner",{CornerRadius=UDim.new(0,r or 12)},parent) end
local function stroke(parent,color,transparency)
	return make("UIStroke",{Color=color or C.Line,Thickness=1,Transparency=transparency or 0},parent)
end
local function text(parent, value, size, color, props)
	local p={Text=value or "",TextColor3=color or C.Text,Font=Enum.Font.Gotham,TextSize=size or 14,BackgroundTransparency=1,BorderSizePixel=0,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center}
	for k,v in pairs(props or {}) do p[k]=v end
	return make("TextLabel",p,parent)
end
local function frame(parent,props)
	local p={BorderSizePixel=0,BackgroundColor3=C.Card}
	for k,v in pairs(props or {}) do p[k]=v end
	return make("Frame",p,parent)
end
local function padding(parent,n)
	make("UIPadding",{PaddingTop=UDim.new(0,n),PaddingBottom=UDim.new(0,n),PaddingLeft=UDim.new(0,n),PaddingRight=UDim.new(0,n)},parent)
end
local function list(parent,gap)
	return make("UIListLayout",{Padding=UDim.new(0,gap or 10),SortOrder=Enum.SortOrder.LayoutOrder},parent)
end
local function number(n)
	n=tonumber(n) or 0
	if n>=1000000 then return string.format("%.1f mln",n/1000000) end
	if n>=10000 then return string.format("%.1f tys.",n/1000) end
	return tostring(math.floor(n))
end
local function duration(n)
	n=math.max(0,math.ceil(n or 0))
	if n>=3600 then return string.format("%dh %02dm",math.floor(n/3600),math.floor(n%3600/60)) end
	if n>=60 then return string.format("%dm %02ds",math.floor(n/60),n%60) end
	return tostring(n).."s"
end
local function button(parent,label,callback,props)
	local p={Text=label,TextSize=13,Font=Enum.Font.GothamBold,TextColor3=C.Dark,BackgroundColor3=C.Cyan,BorderSizePixel=0,AutoButtonColor=false,Selectable=true,Size=UDim2.new(1,0,0,44)}
	for k,v in pairs(props or {}) do p[k]=v end
	local b=make("TextButton",p,parent); corner(b,9)
	b.Activated:Connect(function() if b:GetAttribute("Disabled") then return end playUISound(.03); callback() end)
	b.MouseEnter:Connect(function() if not reducedMotion then TweenService:Create(b,TweenInfo.new(.12),{BackgroundTransparency=.15}):Play() end end)
	b.MouseLeave:Connect(function() b.BackgroundTransparency=0 end)
	return b
end
local function enabled(b,value,label)
	b:SetAttribute("Disabled",not value)
	b.TextColor3=value and C.Dark or C.Muted
	b.BackgroundColor3=value and C.Cyan or C.Line
	if label then b.Text=label end
end
local function track(fn) table.insert(uiUpdates,fn); return fn end

local old=playerGui:FindFirstChild("SpaceGardenUI"); if old then old:Destroy() end
local gui=make("ScreenGui",{Name="SpaceGardenUI",ResetOnSpawn=false,IgnoreGuiInset=false,ZIndexBehavior=Enum.ZIndexBehavior.Sibling,DisplayOrder=10},playerGui)
uiSound=make("Sound",{Name="SpaceGardenUIFeedback",SoundId="rbxasset://sounds/volume_slider.ogg",Volume=.03,PlaybackSpeed=1.5},SoundService)
local shell=frame(gui,{Name="Shell",Size=UDim2.fromScale(1,1),BackgroundTransparency=1})
local header=frame(shell,{Name="Header",Size=UDim2.new(1,-32,0,66),Position=UDim2.fromOffset(16,12),BackgroundColor3=C.Bg,BackgroundTransparency=.05})
corner(header,15); stroke(header)
local mark=frame(header,{Size=UDim2.fromOffset(35,35),Position=UDim2.fromOffset(15,15),BackgroundColor3=C.Cyan}); corner(mark,11)
text(mark,"S",24,C.Dark,{Font=Enum.Font.GothamBold,Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center})
local brand=text(header,"SPACE GARDEN",19,C.Text,{Font=Enum.Font.GothamBold,Position=UDim2.fromOffset(62,12),Size=UDim2.fromOffset(240,25)})
local subtitle=text(header,"ORBITALNA STACJA BOTANICZNA",9,C.Muted,{Position=UDim2.fromOffset(63,38),Size=UDim2.fromOffset(260,15)})
local creditLabel=text(header,"— AK",21,C.Lime,{Font=Enum.Font.GothamBold,AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-18,0,10),Size=UDim2.fromOffset(180,27),TextXAlignment=Enum.TextXAlignment.Right})
local levelLabel=text(header,"Łączenie ze stacją…",11,C.Muted,{AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-18,0,38),Size=UDim2.fromOffset(200,16),TextXAlignment=Enum.TextXAlignment.Right})
local nav=make("ScrollingFrame",{Name="Navigation",Position=UDim2.fromOffset(16,94),Size=UDim2.fromOffset(164,390),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=2,ScrollBarImageColor3=C.Cyan,CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y},shell)
local navLayout=list(nav,7)
local pages={
	{"Garden","01","Mój ogród"},{"Seeds","02","Nasiona"},{"Research","03","Badania"},{"Gifts","04","Prezenty"},
	{"Mission","05","Misje"},{"Ranking","06","Ranking"},{"Settings","07","Stacja"},
	{"Designer","08","Pracownia"},
}
for i,entry in ipairs(pages) do
		local b=button(nav,"",function() currentView=entry[1]; panelOpen=true; buildView(); layout() end,{Name=entry[1],Size=UDim2.new(1,0,0,44),BackgroundColor3=C.Panel,TextColor3=C.Text,LayoutOrder=i})
	text(b,entry[2],10,C.Cyan,{Position=UDim2.fromOffset(12,0),Size=UDim2.fromOffset(21,44),Font=Enum.Font.GothamBold})
	text(b,entry[3],12,C.Text,{Position=UDim2.fromOffset(40,0),Size=UDim2.new(1,-44,1,0),Font=Enum.Font.GothamMedium})
	navButtons[entry[1]]=b
end

local panel=frame(shell,{Name="Panel",AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-16,0,94),Size=UDim2.fromOffset(464,600),BackgroundColor3=C.Bg,BackgroundTransparency=.04})
corner(panel,16); stroke(panel)
local kicker=text(panel,"OSOBISTA BIOSFERA",9,C.Cyan,{Position=UDim2.fromOffset(20,15),Size=UDim2.new(1,-80,0,16),Font=Enum.Font.GothamBold})
local panelTitle=text(panel,"Mój ogród",24,C.Text,{Position=UDim2.fromOffset(20,35),Size=UDim2.new(1,-80,0,32),Font=Enum.Font.GothamBold})
local collapse=button(panel,"−",function() panelOpen=false; layout() end,{AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-16,0,18),Size=UDim2.fromOffset(44,44),BackgroundColor3=C.Card,TextColor3=C.Text,TextSize=21})
local divider=frame(panel,{Position=UDim2.fromOffset(20,78),Size=UDim2.new(1,-40,0,1),BackgroundColor3=C.Line})
local content=make("ScrollingFrame",{Name="Content",Position=UDim2.fromOffset(16,92),Size=UDim2.new(1,-32,1,-126),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=3,ScrollBarImageColor3=C.Cyan,CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y,ScrollingDirection=Enum.ScrollingDirection.Y},panel)
padding(content,4)
local saveLabel=text(panel,"Łączenie…",9,C.Muted,{Position=UDim2.new(0,20,1,-25),Size=UDim2.new(1,-40,0,15)})
local dock=frame(shell,{Name="Dock",AnchorPoint=Vector2.new(.5,1),Position=UDim2.new(.5,0,1,-18),Size=UDim2.fromOffset(340,56),BackgroundColor3=C.Bg,BackgroundTransparency=.06}); corner(dock,13); stroke(dock)
local toggle=button(dock,"PANEL OGRODU",function() panelOpen=not panelOpen; layout() end,{Position=UDim2.fromOffset(6,6),Size=UDim2.new(.54,-9,1,-12),TextSize=11})
local homeButton=button(dock,"DO OGRODU",function() end,{Position=UDim2.new(.54,3,0,6),Size=UDim2.new(.46,-9,1,-12),BackgroundColor3=C.Card,TextColor3=C.Text,TextSize=11})
local toast=frame(shell,{Name="Toast",AnchorPoint=Vector2.new(.5,0),Position=UDim2.new(.5,0,0,88),Size=UDim2.fromOffset(410,58),BackgroundColor3=C.Panel,Visible=false,ZIndex=30}); corner(toast,12); local toastStroke=stroke(toast,C.Cyan)
local toastText=text(toast,"",13,C.Text,{Position=UDim2.fromOffset(16,8),Size=UDim2.new(1,-32,1,-16),TextWrapped=true,ZIndex=31})
local toastGeneration=0
local function notify(message,ok)
	if not message or message=="" then return end
	if ok==true then playUISound(.08) end
	toastGeneration+=1; local id=toastGeneration
	toast.Visible=true; toastText.Text=message; toastStroke.Color=ok==false and C.Danger or C.Cyan
	task.delay(4.5,function() if id==toastGeneration then toast.Visible=false end end)
end
local function accept(newState)
	if type(newState)~="table" then return end
	state=newState
	if tonumber(state.serverTime) then serverOffset=state.serverTime-os.time() end
	selectedSeed=state.selectedSeed or selectedSeed
	creditLabel.Text=number(state.credits).." AK"
	levelLabel.Text="POZIOM "..tostring(state.level or 1).."  ·  "..number(state.xp).." XP"
	local status=state.saveStatus or "Unavailable"
	if status=="Studio" then saveLabel.Text="SESJA TESTOWA · postęp nie jest zapisywany"
	elseif status=="Unavailable" then saveLabel.Text="ZAPIS NIEDOSTĘPNY · prezenty wstrzymane"
	else saveLabel.Text="STACJA "..tostring(state.farmIndex or "—").." · zapis w chmurze aktywny" end
	if updateView then updateView() end
end
local function request(action,args,quiet)
	if busy and action~="State" then return end
	if action~="State" then busy=true end
	local ok,response=pcall(function() return Remote:InvokeServer(action,args or {}) end)
	if action~="State" then busy=false end
	if not ok or type(response)~="table" then
		if not quiet and os.clock()-lastError>3 then lastError=os.clock(); notify("Brak odpowiedzi stacji. Spróbuj za chwilę.",false) end
		return
	end
	if response.state then accept(response.state) end
	if not quiet and response.message then notify(response.message,response.ok) end
	return response
end
homeButton.Activated:Connect(function() request("Teleport") end)

local function card(height,color)
	local f=frame(content,{Size=UDim2.new(1,-3,0,height),BackgroundColor3=color or C.Panel}); corner(f,12); stroke(f,C.Line,.35)
	return f
end
local function paragraph(parent,value,y,height,size,color)
	return text(parent,value,size or 12,color or C.Muted,{Position=UDim2.fromOffset(14,y),Size=UDim2.new(1,-28,0,height),TextWrapped=true,TextYAlignment=Enum.TextYAlignment.Top})
end
local function heading(value)
	return text(content,value,11,C.Muted,{Size=UDim2.new(1,0,0,24),Font=Enum.Font.GothamBold})
end
local function plantIcon(parent,color,size,position,variant)
	local f=frame(parent,{Size=UDim2.fromOffset(size,size),Position=position,BackgroundColor3=color,BackgroundTransparency=.9}); corner(f,12)
	local stem=frame(f,{AnchorPoint=Vector2.new(.5,1),Position=UDim2.fromScale(.5,.8),Size=UDim2.fromScale(.075,.43),BackgroundColor3=C.Cyan}); corner(stem,3)
	for i=1,3 do
		local left=frame(f,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.36,.64-(i-1)*.13),Size=UDim2.fromScale(.26,.12),Rotation=28,BackgroundColor3=color}); corner(left,9)
		local right=frame(f,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.64,.57-(i-1)*.12),Size=UDim2.fromScale(.26,.12),Rotation=-28,BackgroundColor3=color}); corner(right,9)
	end
	local orb=frame(f,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.24),Size=UDim2.fromScale(.22,.22),BackgroundColor3=color,Rotation=(variant or 1)*15}); corner(orb,(variant or 1)%2==0 and 4 or 20)
	return f
end
local function bar(parent,y,color)
	local bg=frame(parent,{Position=UDim2.fromOffset(14,y),Size=UDim2.new(1,-28,0,5),BackgroundColor3=C.Line}); corner(bg,4)
	local fill=frame(bg,{Size=UDim2.fromScale(0,1),BackgroundColor3=color or C.Cyan}); corner(fill,4)
	return fill
end
local function refresh()
	for _,fn in ipairs(uiUpdates) do local ok,err=pcall(fn); if not ok then warn("Space Garden UI:",err) end end
end
updateView=refresh

local function garden()
	local intro=card(62)
	local introTitle=paragraph(intro,"Zasiej coś nie z tej planety.",11,18,14,C.Text); introTitle.Font=Enum.Font.GothamBold
	paragraph(intro,"Wybierz nasiono, posadź je i wróć po astralne kredyty.",35,18,10)
	local picker=card(80)
	local seedTitle=text(picker,"NASIONO",9,C.Muted,{Position=UDim2.fromOffset(12,9),Size=UDim2.new(1,-24,0,15),Font=Enum.Font.GothamBold})
	local seedName=text(picker,"",13,C.Text,{Position=UDim2.fromOffset(12,30),Size=UDim2.new(1,-106,0,28),Font=Enum.Font.GothamBold})
	button(picker,"Zmień",function()
		local position=table.find(Config.SeedOrder,selectedSeed) or 1
		for offset=1,#Config.SeedOrder do
			local key=Config.SeedOrder[(position+offset-1)%#Config.SeedOrder+1]
			if state and (state.inventory[key] or 0)>0 and (state.level or 1)>=Config.Seeds[key].UnlockLevel then request("SelectSeed",{seed=key}); return end
		end
		notify("Kup nasiona w zakładce Nasiona.",false)
	end,{AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-10,0,26),Size=UDim2.fromOffset(80,44),BackgroundColor3=C.Card,TextColor3=C.Cyan})
	track(function() local seed=Config.Seeds[selectedSeed]; seedName.Text=(seed and seed.Name or selectedSeed).."  ×"..tostring(state and state.inventory[selectedSeed] or 0); seedTitle.Text="WYBRANE NASIONO · kliknij grządkę, aby posadzić" end)
	local actions=frame(content,{Size=UDim2.new(1,-3,0,44),BackgroundTransparency=1})
	local harvest=button(actions,"ZBIERZ GOTOWE",function() request("HarvestAll") end,{Size=UDim2.new(.64,-4,1,0),BackgroundColor3=C.Lime})
	button(actions,"SKLEP →",function() currentView="Seeds"; buildView() end,{Position=UDim2.new(.64,4,0,0),Size=UDim2.new(.36,-4,1,0),BackgroundColor3=C.Card,TextColor3=C.Text,TextSize=11})
	heading("MODUŁY UPRAWY  /  wzrost trwa także poza grą")
	local bedGrid=frame(content,{Size=UDim2.new(1,-3,0,0),AutomaticSize=Enum.AutomaticSize.Y,BackgroundTransparency=1})
		make("UIGridLayout",{CellSize=UDim2.new(.5,-5,0,139),CellPadding=UDim2.fromOffset(10,10),SortOrder=Enum.SortOrder.LayoutOrder},bedGrid)
	for i=1,Config.MaxBeds do
		local index=i
		local b=frame(bedGrid,{Name="Bed"..i,Size=UDim2.fromOffset(190,139),LayoutOrder=i,BackgroundColor3=C.Panel}); corner(b,11); local border=stroke(b,C.Line,.3)
		local label=text(b,"MODUŁ "..string.format("%02d",i),9,C.Muted,{Position=UDim2.fromOffset(11,9),Size=UDim2.new(1,-22,0,14),Font=Enum.Font.GothamBold})
		local cropName=text(b,"",12,C.Text,{Position=UDim2.fromOffset(11,29),Size=UDim2.new(1,-22,0,17),Font=Enum.Font.GothamBold,TextTruncate=Enum.TextTruncate.AtEnd})
		local timer=text(b,"",10,C.Muted,{Position=UDim2.fromOffset(11,50),Size=UDim2.new(1,-22,0,16)})
		local grow=bar(b,73,C.Cyan)
		local action=button(b,"Posadź",function()
			local bed=state and state.beds[index]
			if not bed then return end
			if not bed.unlocked then currentView="Research"; buildView(); return end
			if bed.seed then request("Harvest",{index=index}) else request("Plant",{index=index,seed=selectedSeed}) end
		end,{Position=UDim2.fromOffset(9,87),Size=UDim2.new(1,-66,0,44),TextSize=11})
		local water=button(b,"H₂O",function() request("Water",{index=index}) end,{AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-9,0,87),Size=UDim2.fromOffset(44,44),TextSize=10,BackgroundColor3=C.Card,TextColor3=C.Cyan})
		track(function()
			local bed=state and state.beds[index]
			if not bed then cropName.Text="Łączenie…"; enabled(action,false); enabled(water,false); return end
			if not bed.unlocked then
				cropName.Text="Moduł zablokowany"; timer.Text="Rozbuduj szklarnię w Badaniach"; timer.TextSize=9; grow.Size=UDim2.fromScale(0,1); enabled(action,true,"Rozbuduj"); action.BackgroundColor3=C.Card; action.TextColor3=C.Cyan; enabled(water,false); border.Color=C.Line
			elseif not bed.seed then
				cropName.Text="Gotowy do sadzenia"; timer.Text=""; grow.Size=UDim2.fromScale(0,1); enabled(action,(state.inventory[selectedSeed] or 0)>0,"Posadź"); enabled(water,false); border.Color=C.Line
			else
				local definition=Config.Seeds[bed.seed]; local remaining=(bed.readyAt or 0)-now(); local ready=remaining<=0
				cropName.Text=definition and definition.Name or bed.seed; timer.Text=ready and "Gotowe do zbioru" or ("Zbiór za "..duration(remaining)); timer.TextSize=10; timer.TextColor3=ready and C.Lime or C.Muted
				local total=math.max(1,(bed.readyAt or 0)-(bed.plantedAt or 0)); grow.Size=UDim2.fromScale(math.clamp(1-remaining/total,0,1),1); grow.BackgroundColor3=ready and C.Lime or C.Cyan
				enabled(action,ready,ready and "Zbierz" or "Rośnie…"); if ready then action.BackgroundColor3=C.Lime end
				enabled(water,not ready and not bed.watered,bed.watered and "✓" or "H₂O"); border.Color=ready and C.Lime or C.Line
			end
		end)
	end
	track(function()
		local ready=0; if state then for _,b in ipairs(state.beds) do if b.seed and b.readyAt<=now() then ready+=1 end end end
		enabled(harvest,ready>0,"ZBIERZ GOTOWE  ·  "..tostring(ready)); if ready>0 then harvest.BackgroundColor3=C.Lime end
	end)
	if state and (state.boostTokens or 0)>0 then
		local boost=button(content,"",function()request("UseBoost")end,{Name="UseGrowthBoost",Size=UDim2.new(1,-3,0,44)})
		track(function()enabled(boost,(state.boostTokens or 0)>0,"Użyj przyspieszacza  ·  "..tostring(state.boostTokens or 0))end)
	end
end

local function seeds()
	heading("KOLEKCJA NASION  /  odkrywaj kolejne gatunki")
	for order,key in ipairs(Config.SeedOrder) do
		local seedKey=key; local def=Config.Seeds[key]; local row=card(172)
		plantIcon(row,def.Color,60,UDim2.fromOffset(13,14),order)
		text(row,def.Rarity or "BOTANIKA",9,def.Color,{Position=UDim2.fromOffset(85,12),Size=UDim2.new(1,-98,0,14),Font=Enum.Font.GothamBold})
		text(row,def.Name,17,C.Text,{Position=UDim2.fromOffset(85,30),Size=UDim2.new(1,-98,0,22),Font=Enum.Font.GothamBold})
		local own=text(row,"",10,C.Muted,{Position=UDim2.fromOffset(85,57),Size=UDim2.new(1,-98,0,16)})
		paragraph(row,def.Description or "Egzotyczne nasiono z odległego układu.",84,26,10)
		local buy=button(row,"",function() request("BuySeed",{seed=seedKey,quantity=1}) end,{Position=UDim2.fromOffset(13,115),Size=UDim2.new(.60,-18,0,44),TextSize=11})
		local select=button(row,"Wybierz",function() request("SelectSeed",{seed=seedKey}) end,{Position=UDim2.new(.60,3,0,115),Size=UDim2.new(.40,-16,0,44),BackgroundColor3=C.Card,TextColor3=C.Cyan,TextSize=11})
		track(function()
			local unlocked=state and (state.level or 1)>=def.UnlockLevel
			local balance=state and state.catalog and state.catalog[seedKey]
			if balance and type(balance.Price)=="number" and type(balance.EffectiveGrowTime)=="number" and type(balance.EffectiveYield)=="number" then
				own.Text="W plecaku: "..tostring(state.inventory[seedKey] or 0).."   ·   "..duration(balance.EffectiveGrowTime).."   ·   plon "..number(balance.EffectiveYield).." AK"
				enabled(buy,unlocked and state.credits>=balance.Price,unlocked and ("Kup 1  ·  "..number(balance.Price).." AK") or ("Od poziomu "..def.UnlockLevel))
			else
				own.Text="Pobieranie katalogu stacji…"
				enabled(buy,false,"Ładowanie…")
			end
			enabled(select,unlocked and (state.inventory[seedKey] or 0)>0,selectedSeed==seedKey and "Wybrane ✓" or "Wybierz")
			if selectedSeed==seedKey then select.BackgroundColor3=C.Lime end
		end)
	end
end
local function research()
	local intro=card(66); paragraph(intro,"Technologia daje Twoim roślinom przewagę.",12,20,13,C.Text); paragraph(intro,"Trwałe ulepszenia działają na wszystkie przyszłe uprawy.",38,18,10)
	for _,key in ipairs(Config.UpgradeOrder) do
		local upgradeKey=key; local def=Config.Upgrades[key]; local row=card(159)
		local badge=frame(row,{Position=UDim2.fromOffset(13,14),Size=UDim2.fromOffset(36,36),BackgroundColor3=C.Card}); corner(badge,10)
		text(badge,key=="Lamp" and "L" or key=="Beds" and "+" or "Y",20,C.Cyan,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center,Font=Enum.Font.GothamBold})
		text(row,def.Name,16,C.Text,{Position=UDim2.fromOffset(60,12),Size=UDim2.new(1,-75,0,22),Font=Enum.Font.GothamBold})
		local lvl=text(row,"",10,C.Cyan,{Position=UDim2.fromOffset(60,38),Size=UDim2.new(1,-75,0,16)})
		local descriptions={Lamp="Skraca czas wzrostu wszystkich przyszłych upraw.",Beds="Otwiera kolejne moduły uprawy w Twojej szklarni.",Yield="Zwiększa wartość plonów z Twojej biosfery."}
		paragraph(row,descriptions[upgradeKey] or def.Description,68,25,11)
		local buy=button(row,"",function() request("Upgrade",{key=upgradeKey}) end,{Position=UDim2.fromOffset(13,103),Size=UDim2.new(1,-26,0,44),TextSize=11})
		track(function()
			local level=state and state.upgrades[upgradeKey] or 0; local cost=state and state.upgradeCosts and state.upgradeCosts[upgradeKey]; local max=level>=def.MaxLevel
			lvl.Text="POZIOM "..level.." / "..def.MaxLevel
			if type(cost)=="number" then enabled(buy,not max and state.credits>=cost,max and "Ulepszenie maksymalne ✓" or ("Badaj  ·  "..number(cost).." AK"))
			else enabled(buy,false,"Ładowanie…") end
		end)
	end
end
local function missions()
	local daily=card(184)
	paragraph(daily,"CODZIENNY KOSMICZNY ZBIÓR",12,15,10,C.Cyan)
	local streak=paragraph(daily,"",37,25,20,C.Text); streak.Font=Enum.Font.GothamBold
	paragraph(daily,"Odbierz kredyty i paczkę nasion. Każdy kolejny dzień przedłuża serię.",75,36,12)
	local claimDaily=button(daily,"",function() request("Daily") end,{Position=UDim2.fromOffset(14,126),Size=UDim2.new(1,-28,0,44)})
	local quest=card(175)
	paragraph(quest,"MISJA DNIA",12,15,10,C.Cyan)
	paragraph(quest,"Botanik na orbicie",35,24,19,C.Text).Font=Enum.Font.GothamBold
	local questProgress=paragraph(quest,"",67,17,12); local qBar=bar(quest,94,C.Lime)
	local claimQuest=button(quest,"",function() request("Quest") end,{Position=UDim2.fromOffset(14,115),Size=UDim2.new(1,-28,0,44)})
	local season=card(218)
	paragraph(season,"MISJA EKSPEDYCYJNA",12,15,10,C.Gold)
	local seasonName=paragraph(season,"Uprawy na Marsie",35,24,19,C.Text); seasonName.Font=Enum.Font.GothamBold
	paragraph(season,"Zbuduj kolekcję zbiorów. Każda roślina przybliża Cię do nagrody ekspedycji.",69,32,11)
	local seasonProgress=paragraph(season,"",107,17,12); local sBar=bar(season,132,C.Gold)
	local personalNote=paragraph(season,"Nagroda za Twoje uprawy · raz w miesiącu",144,17,10,C.Gold)
	local claimSeason=button(season,"",function() request("Season") end,{Position=UDim2.fromOffset(14,165),Size=UDim2.new(1,-28,0,44),TextSize=11})
	local global=card(274)
	paragraph(global,"WSPÓLNE WYZWANIE GALAKTYCZNE",12,16,10,C.Cyan)
	paragraph(global,"Razem zazieleńmy Marsa",36,25,19,C.Text).Font=Enum.Font.GothamBold
	local globalSummary=paragraph(global,"Łączenie kolonii…",73,34,12)
	local globalBar=bar(global,116,C.Cyan)
	local globalFreshness=paragraph(global,"",132,30,10,C.Muted)
	local globalRequirement=paragraph(global,"",169,37,11,C.Muted)
	local claimGlobal=button(global,"Ładowanie…",function() request("GlobalSeason") end,{Name="ClaimGlobalSeason",Position=UDim2.fromOffset(14,216),Size=UDim2.new(1,-28,0,44),TextSize=11})
	track(function()
		if not state then return end
		local d=state.daily or {}; streak.Text="Seria: "..tostring(d.streak or 0).." dni"
		enabled(claimDaily,d.available,d.available and "Odbierz kosmiczny zbiór" or ("Kolejny za "..duration((d.nextAt or 0)-now())))
		local q=state.quest or {}; local goal=math.max(1,q.goal or Config.DailyQuestGoal); questProgress.Text="Zebrane rośliny: "..tostring(q.progress or 0).." / "..goal; qBar.Size=UDim2.fromScale(math.clamp((q.progress or 0)/goal,0,1),1)
		enabled(claimQuest,not q.claimed and (q.progress or 0)>=goal,q.claimed and "Nagroda odebrana ✓" or ("Odbierz  "..number(Config.DailyQuestReward).." AK"))
		local s=state.season or {}; local sg=math.max(1,s.goal or Config.SeasonGoal); seasonProgress.Text="Twoje zbiory: "..tostring(s.progress or 0).." / "..sg; sBar.Size=UDim2.fromScale(math.clamp((s.progress or 0)/sg,0,1),1)
		seasonName.Text=s.name or "Uprawy na Marsie"; personalNote.Text="Twoja ekspedycja"..(s.period and (" · "..tostring(s.period)) or " · ten miesiąc")
		enabled(claimSeason,not s.claimed and (s.progress or 0)>=sg,s.claimed and "Ekspedycja ukończona ✓" or ("Odbierz  "..number(Config.SeasonReward).." AK"))
		local trusted=s.globalAvailable==true and s.scope=="global"
		local globalGoal=math.max(1,s.sharedGoal or Config.GlobalSeasonGoal or 10000)
		local contribution=math.max(0,s.sharedProgress or 0)
		globalSummary.Text=(trusted and "Wszystkie kolonie: " or "Podgląd lokalny: ")..number(contribution).." / "..number(globalGoal).." zbiorów"
		globalBar.Size=UDim2.fromScale(math.clamp(contribution/globalGoal,0,1),1)
		local updated=tonumber(s.globalUpdatedAt) or 0
		if not trusted then globalFreshness.Text=s.scope=="studio" and "SESJA STUDIO · globalny postęp i nagroda są niedostępne." or "Brak potwierdzonych danych globalnych. Nagroda czeka na połączenie."
		else globalFreshness.Text="Zapisane zbiory ze wszystkich serwerów · "..(updated>0 and ("odświeżono "..duration(now()-updated).." temu") or "oczekiwanie na pierwsze dane") end
		local required=math.max(1,s.participationRequired or Config.GlobalSeasonParticipation or 8)
		globalRequirement.Text="Twój udział: "..tostring(s.progress or 0).." / "..required.." upraw. Nagroda wspólna jest oddzielna od Twojej ekspedycji."
		local available=trusted and contribution>=globalGoal and (s.progress or 0)>=required and not s.globalClaimed
		local label=s.globalClaimed and "Nagroda globalna odebrana ✓" or not trusted and "Globalny cel niedostępny" or contribution<globalGoal and "Wspólny cel jeszcze nieosiągnięty" or (s.progress or 0)<required and "Zbierz jeszcze "..tostring(required-(s.progress or 0)).." roślin" or ("Odbierz bonus wspólny · "..number(s.globalReward or Config.GlobalSeasonReward or 300).." AK")
		enabled(claimGlobal,available,label)
	end)
end
local function gifts()
	local intro=card(135)
	paragraph(intro,"DOBRE RZECZY ROSNĄ RAZEM",12,15,10,C.Cyan)
	paragraph(intro,"Podziel się kawałkiem galaktyki.",36,23,17,C.Text).Font=Enum.Font.GothamBold
	paragraph(intro,"Raz dziennie wyślij jedno nasiono znajomemu na tym serwerze. Oboje otrzymacie bonus. Prezent wymaga aktywnego zapisu.",71,50,11)
	local selection=card(90)
	paragraph(selection,"NASIONO DO WYSŁANIA",10,14,9,C.Muted)
	local selected=text(selection,"",13,C.Text,{Position=UDim2.fromOffset(14,33),Size=UDim2.new(1,-108,0,29),Font=Enum.Font.GothamBold})
	button(selection,"Zmień",function()
		local position=table.find(Config.SeedOrder,selectedSeed) or 1
		for offset=1,#Config.SeedOrder do local key=Config.SeedOrder[(position+offset-1)%#Config.SeedOrder+1]; if state and (state.inventory[key] or 0)>0 and (state.level or 1)>=Config.Seeds[key].UnlockLevel then request("SelectSeed",{seed=key}); return end end
	end,{AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-12,0,32),Size=UDim2.fromOffset(80,44),BackgroundColor3=C.Card,TextColor3=C.Cyan})
	heading("ZNAJOMI ONLINE  /  wybierz odbiorcę")
	local recipients=frame(content,{Size=UDim2.new(1,-3,0,0),AutomaticSize=Enum.AutomaticSize.Y,BackgroundTransparency=1}); list(recipients,7)
	local recipientButtons={}; giftSignature=""
	local send=button(content,"Wyślij prezent",function() if targetUserId then request("Gift",{targetUserId=targetUserId,seed=selectedSeed,quantity=1}) end end,{Size=UDim2.new(1,-3,0,44)})
	local status=text(content,"",11,C.Muted,{Size=UDim2.new(1,-3,0,48),TextWrapped=true,TextYAlignment=Enum.TextYAlignment.Top})
	track(function()
		if not state then return end
		local def=Config.Seeds[selectedSeed]; selected.Text=(def and def.Name or selectedSeed).."  ×"..tostring(state.inventory[selectedSeed] or 0)
		local entries={}; local ids={}
		for _,p in ipairs(state.players or {}) do if p.userId~=player.UserId and p.isFriend~=false then table.insert(entries,p); table.insert(ids,tostring(p.userId)..p.displayName) end end
		local signature=table.concat(ids,"|")
		if signature~=giftSignature or not recipients:FindFirstChild("Population") then
			giftSignature=signature; for _,child in ipairs(recipients:GetChildren()) do if not child:IsA("UIListLayout") then child:Destroy() end end
			recipientButtons={}
			if #entries==0 then text(recipients,"Zaproś znajomego do swojej stacji.",12,C.Muted,{Name="Population",Size=UDim2.new(1,0,0,44),TextWrapped=true})
			else
				for i,p in ipairs(entries) do local uid=p.userId; local b=button(recipients,p.displayName or p.name,function() targetUserId=uid; refresh() end,{Name=i==1 and "Population" or ("Recipient"..i),Size=UDim2.new(1,0,0,44),BackgroundColor3=C.Card,TextColor3=C.Text}); recipientButtons[uid]=b end
			end
		end
		local valid=false; for _,p in ipairs(entries) do if p.userId==targetUserId then valid=true end end; if not valid then targetUserId=nil end
		for uid,b in pairs(recipientButtons) do b.BackgroundColor3=uid==targetUserId and C.Cyan or C.Card; b.TextColor3=uid==targetUserId and C.Dark or C.Text end
		local g=state.gift or {}; local durable=state.saveStatus~="Studio" and state.saveStatus~="Unavailable"
			enabled(send,g.available and durable and g.enabled~=false and targetUserId~=nil and (state.inventory[selectedSeed] or 0)>0,"Wyślij 1 nasiono  ·  bonus dla Was obojga")
		if not durable or g.enabled==false then status.Text=g.reason or "Prezenty są wstrzymane w sesji testowej lub bez bezpiecznego zapisu."
		elseif g.pending then status.Text="Twój prezent jest w drodze. Stacja potwierdzi dostarczenie."
		elseif not g.available then status.Text="Dzisiejszy prezent wysłany. Kolejny za "..duration((g.nextAt or 0)-now()).."."
		else status.Text="Odbiorca musi być Twoim znajomym w Roblox i grać na tym samym serwerze." end
	end)
end
local function ranking()
	local intro=card(97)
	paragraph(intro,"MISTRZOWIE OGRODNICTWA",12,15,10,C.Gold)
	local scopeTitle=paragraph(intro,"Ranking tej stacji",36,26,22,C.Text); scopeTitle.Font=Enum.Font.GothamBold
	paragraph(intro,"Łączna liczba zebranych roślin",72,16,11)
	local switches=frame(content,{Size=UDim2.new(1,-3,0,44),BackgroundTransparency=1})
	local serverButton=button(switches,"Ta stacja",function() rankingScope="server"; refresh() end,{Name="ServerRanking",Size=UDim2.new(.5,-5,1,0),TextSize=12})
	local globalButton=button(switches,"Cała galaktyka",function() rankingScope="global"; refresh() end,{Name="GlobalRanking",Position=UDim2.new(.5,5,0,0),Size=UDim2.new(.5,-5,1,0),TextSize=12})
	local sourceLabel=text(content,"Ładowanie rankingu…",11,C.Muted,{Size=UDim2.new(1,-3,0,45),TextWrapped=true,TextYAlignment=Enum.TextYAlignment.Top})
	local rows=frame(content,{Size=UDim2.new(1,-3,0,0),AutomaticSize=Enum.AutomaticSize.Y,BackgroundTransparency=1}); list(rows,8)
	local signature=""
	track(function()
		serverButton.BackgroundColor3=rankingScope=="server" and C.Cyan or C.Card; serverButton.TextColor3=rankingScope=="server" and C.Dark or C.Text
		globalButton.BackgroundColor3=rankingScope=="global" and C.Cyan or C.Card; globalButton.TextColor3=rankingScope=="global" and C.Dark or C.Text
		if not state then return end
		local gr=state.globalRanking or {}
		local realGlobal=rankingScope=="global" and gr.available==true and gr.scope=="global"
		local source=realGlobal and gr.entries or state.players or {}
		local sorted=table.clone(source); table.sort(sorted,function(a,b) return (a.harvested or 0)>(b.harvested or 0) end)
		scopeTitle.Text=realGlobal and "Ranking galaktyki" or "Ranking tej stacji"
		if rankingScope=="server" then sourceLabel.Text="Gracze obecni na tym serwerze · wyniki z bieżącej sesji."
		elseif realGlobal then
			local updated=tonumber(gr.updatedAt) or 0
			sourceLabel.Text=(gr.loading and "Odświeżanie · " or "TOP 20 · ").."zapisany postęp wszystkich serwerów. "..(updated>0 and ("Dane sprzed "..duration(now()-updated)..".") or "Oczekiwanie na pierwsze wyniki.")
		elseif gr.loading then sourceLabel.Text="Ładowanie rankingu globalnego. Tymczasowo pokazujemy graczy tej stacji."
		elseif gr.scope=="studio" then sourceLabel.Text="SESJA STUDIO · globalny ranking niedostępny. Poniżej wyniki tej stacji."
		else sourceLabel.Text="Ranking globalny jest chwilowo niedostępny. Poniżej wyniki tej stacji." end
		local parts={realGlobal and "global" or "server"}; for _,p in ipairs(sorted) do table.insert(parts,tostring(p.userId)..":"..tostring(p.harvested)..":"..tostring(p.displayName or p.name)) end
		local nextSignature=table.concat(parts,"|"); if nextSignature==signature then return end; signature=nextSignature
		for _,child in ipairs(rows:GetChildren()) do if not child:IsA("UIListLayout") then child:Destroy() end end
		if #sorted==0 then text(rows,realGlobal and "Pierwsze zapisane zbiory pojawią się tutaj po odświeżeniu." or "Stacja oczekuje na pierwszego botanika.",12,C.Muted,{Size=UDim2.new(1,0,0,70),TextWrapped=true}) end
		for i,p in ipairs(sorted) do
			local row=frame(rows,{Size=UDim2.new(1,0,0,66),BackgroundColor3=p.userId==player.UserId and C.Dark or C.Panel,LayoutOrder=i}); corner(row,10); stroke(row,p.userId==player.UserId and C.Cyan or C.Line,.3)
			text(row,string.format("%02d",i),20,i==1 and C.Gold or C.Muted,{Position=UDim2.fromOffset(15,0),Size=UDim2.fromOffset(42,66),Font=Enum.Font.GothamBold})
			text(row,p.displayName or p.name or ("Botanik "..tostring(p.userId)),13,C.Text,{Position=UDim2.fromOffset(67,10),Size=UDim2.new(1,-150,0,22),Font=Enum.Font.GothamBold,TextTruncate=Enum.TextTruncate.AtEnd})
			text(row,i==1 and (realGlobal and "Mistrz galaktyki" or "Mistrz tej stacji") or (p.userId==player.UserId and "Twój ogród" or "Kosmiczny botanik"),10,i==1 and C.Gold or C.Muted,{Position=UDim2.fromOffset(67,34),Size=UDim2.new(1,-140,0,18)})
			text(row,number(p.harvested),19,C.Lime,{AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-14,0,0),Size=UDim2.fromOffset(76,66),TextXAlignment=Enum.TextXAlignment.Right,Font=Enum.Font.GothamBold})
		end
	end)
end
local function designer()
	if not DecorCatalog then
		local module=package:FindFirstChild("DecorCatalog")
		if module and module:IsA("ModuleScript") then local ok,value=pcall(require,module); if ok and type(value)=="table" then DecorCatalog=value end end
	end
	if not DecorCatalog then
		local missing=card(154)
		paragraph(missing,"Pracownia oczekuje na połączenie",15,26,17,C.Text)
		paragraph(missing,"Katalog dekoracji jest chwilowo niedostępny. Twój ogród pozostaje aktywny.",55,40,12)
		button(missing,"Spróbuj ponownie",function() buildView() end,{Position=UDim2.fromOffset(14,99),Size=UDim2.new(1,-28,0,44)})
		return
	end
	local catalog=DecorCatalog
	local function savedDesign(slot)
		local decorations=state and state.decorations
		for _,entry in ipairs(decorations and decorations.designs or {}) do if entry.slot==slot then return entry.design end end
		return nil
	end
	local function standDesign(stand)
		local decorations=state and state.decorations
		for _,entry in ipairs(decorations and decorations.stands or {}) do if entry.stand==stand then return entry.designSlot end end
		return nil
	end
	local function draftFrom(raw)
		if type(raw)=="table" and catalog.Shapes[raw.shape] and catalog.Palettes[raw.palette] and type(raw.scale)=="number" then
			return {shape=raw.shape,palette=raw.palette,scale=math.clamp(raw.scale,catalog.MinScale,catalog.MaxScale)}
		end
		return {shape=catalog.ShapeOrder[1],palette=catalog.PaletteOrder[1],scale=1}
	end
	if not designerDraft or not catalog.Shapes[designerDraft.shape] or not catalog.Palettes[designerDraft.palette] then designerDraft=draftFrom(savedDesign(designerSlot)) end
	local intro=card(82)
	paragraph(intro,"Twoja własna dekoracja",12,24,18,C.Text).Font=Enum.Font.GothamBold
	paragraph(intro,"Zapisz projekt, ustaw go w szklarni i podziel się kodem. Twoje projekty działają w Space Garden.",43,34,11)
	local previewCard=card(240)
	local previewTitle=paragraph(previewCard,"",12,22,16,C.Text); previewTitle.Font=Enum.Font.GothamBold
	local viewport=make("ViewportFrame",{Name="DesignerPreview",Position=UDim2.fromOffset(10,42),Size=UDim2.new(1,-20,0,174),BackgroundColor3=C.Bg,BorderSizePixel=0,Ambient=Color3.fromRGB(170,185,199),LightColor=Color3.fromRGB(225,255,246),LightDirection=Vector3.new(-1,-1,-1)},previewCard); corner(viewport,10)
	local previewFooter=paragraph(previewCard,"",220,15,10,C.Muted)
	local world=make("WorldModel",{Name="Sculpture"},viewport)
	local camera=make("Camera",{FieldOfView=33,CFrame=CFrame.lookAt(Vector3.new(7,5,8),Vector3.new(0,1.9,0))},viewport); viewport.CurrentCamera=camera
	local function drawPreview()
		world:ClearAllChildren()
		local draft=designerDraft; local scale=draft.scale; local color=catalog.Palettes[draft.palette].Color
		previewTitle.Text=catalog.Shapes[draft.shape].Name
		previewFooter.Text=catalog.Palettes[draft.palette].Name.."  ·  skala "..string.format("%.1f",scale).."×  ·  podgląd projektu"
		local function part(size,cf,tint,shape)
			local obj=make("Part",{Anchored=true,CanCollide=false,CanTouch=false,CanQuery=false,CastShadow=false,Material=Enum.Material.SmoothPlastic,Color=tint or color,Size=size*scale,CFrame=CFrame.new(cf.Position*scale)*(cf-cf.Position)},world)
			if shape then obj.Shape=shape end
			return obj
		end
		part(Vector3.new(.16,4.7,4.7),CFrame.new(0,0,0)*CFrame.Angles(0,0,math.pi/2),C.Line,Enum.PartType.Cylinder)
		local dark=color:Lerp(C.Bg,.5)
		if draft.shape=="OrbitBloom" then
			part(Vector3.new(.18,2.6,.18),CFrame.new(0,1.4,0),dark)
			part(Vector3.new(1.15,1.15,1.15),CFrame.new(0,2.8,0),color,Enum.PartType.Ball)
			for ring=1,2 do
				local transform=CFrame.new(0,2.8,0)*CFrame.Angles(math.rad(ring==1 and 26 or -38),0,math.rad(ring==1 and 20 or -25))
				for i=1,24 do
					local a=i/24*math.pi*2; local b=(i+1)/24*math.pi*2
					local p=(transform*CFrame.new(math.cos(a)*1.3,0,math.sin(a)*1.3)).Position
					local q=(transform*CFrame.new(math.cos(b)*1.3,0,math.sin(b)*1.3)).Position
					part(Vector3.new(.09,.09,(p-q).Magnitude+.03),CFrame.lookAt((p+q)/2,q),ring==1 and color or C.Cyan)
				end
			end
		elseif draft.shape=="PrismSpire" then
			for i=1,5 do
				local angle=i*math.pi*2/5; local height=i==1 and 3.7 or 2.1+(i%3)*.45
				local cf=CFrame.new(math.cos(angle)*.64,height/2+.14,math.sin(angle)*.64)*CFrame.Angles(math.rad(8),angle,math.rad(i%2==0 and 10 or -9))
				part(Vector3.new(.48,height,.48),cf,i%2==0 and color or color:Lerp(C.Text,.2))
				part(Vector3.new(.52,.52,.52),cf*CFrame.new(0,height/2,0)*CFrame.Angles(0,0,math.rad(45)),color)
			end
		elseif draft.shape=="HelixFern" then
			part(Vector3.new(.14,3.7,.14),CFrame.new(0,1.9,0),dark)
			for i=1,9 do
				local angle=i*.85; local y=.45+i*.34; local radius=.85-(i/9)*.27
				for side=-1,1,2 do
					local transform=CFrame.new(0,y,0)*CFrame.Angles(0,angle+(side==-1 and math.pi or 0),math.rad(20))
					part(Vector3.new(radius*1.9,.15,.42),transform*CFrame.new(radius*.57,0,0),i%2==0 and color or color:Lerp(C.Cyan,.25),Enum.PartType.Ball)
				end
			end
		else
			part(Vector3.new(.25,1.3,.25),CFrame.new(0,.75,0),dark)
			for layer=1,2 do for i=1,8 do
				local angle=i/8*math.pi*2+(layer==2 and .4 or 0)
				local transform=CFrame.new(0,1.3+layer*.18,0)*CFrame.Angles(0,angle,math.rad(layer==1 and -12 or 24))
				part(Vector3.new(2.1,.28,.66),transform*CFrame.new(.92,0,0),layer==1 and color or color:Lerp(C.Text,.2),Enum.PartType.Ball)
			end end
			part(Vector3.new(.95,.95,.95),CFrame.new(0,1.9,0),C.Gold,Enum.PartType.Ball)
		end
	end
	local controlLabels={}
	local function selector(label,key,previous,nextValue)
		local row=card(91)
		paragraph(row,label,10,16,10,C.Muted)
		button(row,"‹",previous,{Name=key.."Previous",Position=UDim2.fromOffset(12,35),Size=UDim2.fromOffset(44,44),TextSize=24,BackgroundColor3=C.Card,TextColor3=C.Text})
		controlLabels[key]=text(row,"",13,C.Text,{Position=UDim2.fromOffset(65,35),Size=UDim2.new(1,-130,0,44),TextXAlignment=Enum.TextXAlignment.Center,Font=Enum.Font.GothamBold,TextTruncate=Enum.TextTruncate.AtEnd})
		button(row,"›",nextValue,{Name=key.."Next",AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-12,0,35),Size=UDim2.fromOffset(44,44),TextSize=24,BackgroundColor3=C.Card,TextColor3=C.Text})
	end
	local function cycle(order,key,delta)
		local at=table.find(order,designerDraft[key]) or 1
		designerDraft[key]=order[(at+delta-1)%#order+1]; drawPreview(); refresh()
	end
	selector("FORMA", "Shape",function() cycle(catalog.ShapeOrder,"shape",-1) end,function() cycle(catalog.ShapeOrder,"shape",1) end)
	selector("PALETA", "Palette",function() cycle(catalog.PaletteOrder,"palette",-1) end,function() cycle(catalog.PaletteOrder,"palette",1) end)
	local function scaleBy(delta) designerDraft.scale=math.clamp(math.floor((designerDraft.scale+delta)*10+.5)/10,catalog.MinScale,catalog.MaxScale); drawPreview(); refresh() end
	selector("SKALA", "Scale",function() scaleBy(-.1) end,function() scaleBy(.1) end)
	heading("TWOJE PROJEKTY  /  wybierz kapsułę zapisu")
	local slots=frame(content,{Size=UDim2.new(1,-3,0,44),BackgroundTransparency=1})
	local slotButtons={}
	for i=1,catalog.MaxDesigns do local slot=i
		slotButtons[i]=button(slots,tostring(i),function()
			designerSlot=slot; local saved=savedDesign(slot); if saved then designerDraft=draftFrom(saved) end
			drawPreview(); refresh()
		end,{Name="DesignSlot"..i,Position=UDim2.new((i-1)/catalog.MaxDesigns,3,0,0),Size=UDim2.new(1/catalog.MaxDesigns,-6,1,0),TextSize=11})
	end
	local save=button(content,"Zapisz projekt",function() end,{Name="SaveDesign",Size=UDim2.new(1,-3,0,44)})
	save.Activated:Connect(function()
		if busy or save:GetAttribute("Disabled") then return end
		enabled(save,false,"Zapisywanie…")
		request("SaveDesign",{slot=designerSlot,shape=designerDraft.shape,palette=designerDraft.palette,scale=designerDraft.scale}); refresh()
	end)
	heading("EKSPOZYCJA  /  trzy podesty przy Twoim ogrodzie")
	local stands=frame(content,{Size=UDim2.new(1,-3,0,44),BackgroundTransparency=1})
	local standButtons={}
	for i=1,catalog.MaxStands do local stand=i
		standButtons[i]=button(stands,"Podest "..i,function() designerStand=stand; refresh() end,{Name="DesignStand"..i,Position=UDim2.new((i-1)/catalog.MaxStands,3,0,0),Size=UDim2.new(1/catalog.MaxStands,-6,1,0),TextSize=11})
	end
	local standStatus=text(content,"",11,C.Muted,{Size=UDim2.new(1,-3,0,30),TextWrapped=true})
	local standActions=frame(content,{Size=UDim2.new(1,-3,0,44),BackgroundTransparency=1})
	local place=button(standActions,"Ustaw projekt",function() request("PlaceDesign",{stand=designerStand,slot=designerSlot}) end,{Name="PlaceDesign",Size=UDim2.new(.62,-4,1,0),TextSize=11})
	local remove=button(standActions,"Zdejmij",function() request("RemoveDesign",{stand=designerStand}) end,{Name="RemoveDesign",Position=UDim2.new(.62,4,0,0),Size=UDim2.new(.38,-4,1,0),TextSize=11,BackgroundColor3=C.Card,TextColor3=C.Text})
	heading("KODY PROJEKTÓW  /  podziel się dekoracją")
	local publish=button(content,"Udostępnij zapisany projekt",function() end,{Name="PublishDesign",Size=UDim2.new(1,-3,0,44),TextSize=12})
	local codeCard=card(122)
	paragraph(codeCard,"TWÓJ OSTATNI KOD · zaznacz i skopiuj",10,16,9,C.Cyan)
	local codeBox=make("TextBox",{Name="BlueprintCode",Position=UDim2.fromOffset(12,35),Size=UDim2.new(1,-24,0,44),BackgroundColor3=C.Bg,TextColor3=C.Text,Font=Enum.Font.RobotoMono,TextSize=11,Text="",PlaceholderText="Kod pojawi się po udostępnieniu",PlaceholderColor3=C.Muted,ClearTextOnFocus=false,TextEditable=false,BorderSizePixel=0},codeCard); corner(codeBox,8)
	paragraph(codeCard,"Kopia dekoracji w Space Garden · bez nagród za kopiowanie",86,25,9)
	local sharingStatus=text(content,"",11,C.Muted,{Size=UDim2.new(1,-3,0,60),TextWrapped=true,TextYAlignment=Enum.TextYAlignment.Top})
	local importCard=card(140)
	paragraph(importCard,"MASZ KOD OD ZNAJOMEGO?",10,16,10,C.Cyan)
	local codeInput=make("TextBox",{Name="ImportBlueprintCode",Position=UDim2.fromOffset(12,34),Size=UDim2.new(1,-24,0,44),BackgroundColor3=C.Bg,TextColor3=C.Text,Font=Enum.Font.RobotoMono,TextSize=11,Text=designImportText,PlaceholderText="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",PlaceholderColor3=C.Muted,ClearTextOnFocus=false,BorderSizePixel=0},importCard); corner(codeInput,8)
	local importing=false
	local import=button(importCard,"Importuj do kapsuły "..designerSlot,function() end,{Name="ImportDesign",Position=UDim2.fromOffset(12,87),Size=UDim2.new(1,-24,0,44),TextSize=12})
	codeInput:GetPropertyChangedSignal("Text"):Connect(function()
		local cleaned=codeInput.Text:gsub("[^%x%-]",""):sub(1,64):lower()
		if codeInput.Text~=cleaned then codeInput.Text=cleaned end
		designImportText=cleaned; refresh()
	end)
	local function durable() return state and state.saveStatus~="Studio" and state.saveStatus~="Unavailable" and state.decorations and state.decorations.sharingEnabled==true end
	publish.Activated:Connect(function()
		if busy or publish:GetAttribute("Disabled") then return end
		enabled(publish,false,"Tworzenie kodu…")
		local response=request("PublishDesign",{slot=designerSlot})
		if response and response.ok and type(response.code)=="string" then lastBlueprintCode=response.code end
		refresh()
	end)
	import.Activated:Connect(function()
		if busy or import:GetAttribute("Disabled") then return end
		importing=true; enabled(import,false,"Pobieranie projektu…")
		local response=request("ImportDesign",{slot=designerSlot,code=designImportText})
		if response and response.ok then
			local importedSlot=response.slot or designerSlot
			if type(importedSlot)=="number" and importedSlot>=1 and importedSlot<=catalog.MaxDesigns then designerSlot=importedSlot end
			local saved=savedDesign(designerSlot); if saved then designerDraft=draftFrom(saved); drawPreview() end
			designImportText=""; codeInput.Text=""
		end
		importing=false; refresh()
	end)
	track(function()
		controlLabels.Shape.Text=catalog.Shapes[designerDraft.shape].Name
		controlLabels.Palette.Text=catalog.Palettes[designerDraft.palette].Name; controlLabels.Palette.TextColor3=catalog.Palettes[designerDraft.palette].Color
		controlLabels.Scale.Text=string.format("%.1f",designerDraft.scale).."×"
		for slot,b in ipairs(slotButtons) do
			b.Text=string.format("%02d",slot)..(savedDesign(slot) and " · zapisany" or " · pusty")
			b.BackgroundColor3=slot==designerSlot and C.Cyan or C.Card; b.TextColor3=slot==designerSlot and C.Dark or C.Text
		end
		for stand,b in ipairs(standButtons) do b.BackgroundColor3=stand==designerStand and C.Cyan or C.Card; b.TextColor3=stand==designerStand and C.Dark or C.Text end
		local onStand=standDesign(designerStand)
		standStatus.Text="Podest "..designerStand..(onStand and (" · projekt z kapsuły "..onStand) or " · czeka na dekorację")
		enabled(save,state~=nil and not busy,"Zapisz w kapsule "..designerSlot)
		enabled(place,savedDesign(designerSlot)~=nil and not busy,"Ustaw projekt "..designerSlot)
		enabled(remove,onStand~=nil and not busy,"Zdejmij")
		local decorations=state and state.decorations or {}
		local limit=(decorations.publishedToday or 0)>=3 and not decorations.pending
		enabled(publish,durable() and savedDesign(designerSlot)~=nil and not busy and not limit,limit and "Dzienny limit wykorzystany"or"Udostępnij projekt "..designerSlot)
		local code=lastBlueprintCode or (state and state.lastBlueprintCode) or decorations.blueprint
		if type(code)=="string" and codeBox.Text~=code then codeBox.Text=code end
		sharingStatus.Text=durable() and (decorations.pending and "Publikacja kodu czeka na potwierdzenie stacji. Zostanie ponowiona automatycznie."or"Udostępniaj maksymalnie 3 projekty dziennie. Kody kopiują samą dekorację, bez przenoszenia przedmiotów.") or "Zapisywanie i ustawianie działa w tej sesji. Kody wymagają aktywnego zapisu w opublikowanej grze."
		local validCode=#designImportText==36 and designImportText:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$")~=nil
		enabled(import,durable() and validCode and not busy and not importing,importing and "Pobieranie…" or "Importuj do kapsuły "..designerSlot)
	end)
	drawPreview()
end

local function settings()
	heading("PERSONALIZACJA  /  kolor Twojej biosfery")
	for _,key in ipairs(Config.ThemeOrder) do
		local themeKey=key; local def=Config.Themes[key]; local row=card(70)
		local swatch=frame(row,{Position=UDim2.fromOffset(14,17),Size=UDim2.fromOffset(36,36),BackgroundColor3=def.Color}); corner(swatch,11)
		text(row,def.Name,14,C.Text,{Position=UDim2.fromOffset(64,0),Size=UDim2.new(1,-170,1,0),Font=Enum.Font.GothamBold})
		local choose=button(row,"Wybierz",function() request("Theme",{theme=themeKey}) end,{AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-12,0,19),Size=UDim2.fromOffset(90,44),TextSize=11})
		track(function() choose.Text=state and state.theme==themeKey and "Aktywny ✓" or "Wybierz"; choose.BackgroundColor3=state and state.theme==themeKey and C.Lime or C.Cyan end)
	end
	heading("KOMFORT GRY")
	local motion=card(92)
	paragraph(motion,"Ogranicz animacje interfejsu",13,20,13,C.Text)
	paragraph(motion,"Zmiana dotyczy tej sesji.",43,16,10)
	local motionButton=button(motion,reducedMotion and "WŁ." or "WYŁ.",function() reducedMotion=not reducedMotion; buildView() end,{AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-12,0,35),Size=UDim2.fromOffset(67,44),TextSize=11})
	local audio=card(92)
	paragraph(audio,"Dźwięki interfejsu",13,20,13,C.Text)
	paragraph(audio,"Delikatny sygnał kliknięć i nagród.",43,16,10)
	button(audio,soundEnabled and "WŁ." or "WYŁ.",function() soundEnabled=not soundEnabled; buildView() end,{Name="SoundToggle",AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-12,0,35),Size=UDim2.fromOffset(67,44),TextSize=11})
	local chat=card(109)
	paragraph(chat,"Czat Roblox",13,20,13,C.Text)
	local chatDescription=paragraph(chat,"Włącz, aby rozmawiać ze znajomymi. Panel ogrodu zostanie schowany.",43,54,10)
	chatDescription.Size=UDim2.new(1,-110,0,54)
	button(chat,chatEnabled and "WŁ." or "WYŁ.",function()
		chatEnabled=not chatEnabled
		setCoreGui(Enum.CoreGuiType.Chat,chatEnabled)
		if chatEnabled then panelOpen=false end
		buildView(); layout()
	end,{Name="ChatToggle",AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-12,0,43),Size=UDim2.fromOffset(67,44),TextSize=11})
	local info=card(143)
	paragraph(info,"JAK DZIAŁA SPACE GARDEN",12,15,10,C.Cyan)
	paragraph(info,"E · interakcja przy grządce\nH · zbierz gotowe rośliny\nG · otwórz / schowaj panel\nRośliny rosną także, gdy jesteś poza grą.\nAK = Astralne Kredyty",39,93,11,C.Muted)
	if state and state.premiumAvailable then
		heading("GALAKTYCZNE DODATKI")
		text(content,"Aktualną cenę i zakup potwierdzisz w oknie Roblox.",11,C.Muted,{Size=UDim2.new(1,-3,0,35),TextWrapped=true,TextYAlignment=Enum.TextYAlignment.Top})
		local offers={
			SeedPack={Name="Pakiet nasion",Description="3× Mgławicowa Meduza — sadzenie od poziomu 8.\n5× Pryzmatowy Kwiat — sadzenie od poziomu 3."},
			GrowthBoost={Name="Przyspieszenie upraw",Description="Natychmiast kończy wzrost wszystkich rosnących upraw. Jeśli nic nie rośnie: 1 token do użycia później w ogrodzie."},
			ExtraBeds={Name="Dwa dodatkowe moduły",Description="Na stałe +2 miejsca uprawy. Maksymalnie 12 miejsc w Twoim ogrodzie."},
			StarterPack={Name="Galaktyczny zestaw startowy",Description="3× Mgławicowa Meduza i 250 Astralnych Kredytów.\nMeduzy zasadzisz od poziomu 8. Zestaw odbierasz raz."},
		}
		local function offerEligibility(key)
			if not state then return false,false,false end
			local pass=key=="ExtraBeds" or key=="StarterPack"
			local ownershipKnown=not pass or type(state.entitlements)=="table"
			local owned=pass and ownershipKnown and state.entitlements[key]==true
			local count=tonumber(state.bedCount)
			if not count then count=0; for _,bed in ipairs(state.beds or {}) do if bed.unlocked then count+=1 end end end
			local full=key=="ExtraBeds" and count>=math.min(12,tonumber(state.maxBeds) or Config.MaxBeds or 12)
			return ownershipKnown,owned,full
		end
		for _,key in ipairs({"SeedPack","GrowthBoost","ExtraBeds","StarterPack"}) do
			local productKey=key
			local productId=Config.Products[key]
			local isProduct=type(productId)=="number" and productId>0
			local id=isProduct and productId or Config.Passes[key]
			if type(id)=="number" and id>0 then
				local offer=offers[key]; local row=card(218)
				text(row,offer.Name,15,C.Text,{Position=UDim2.fromOffset(14,12),Size=UDim2.new(1,-28,0,35),TextWrapped=true,Font=Enum.Font.GothamBold})
				paragraph(row,offer.Description,54,78,12,C.Muted)
				local priceLabel=paragraph(row,"Cena w oknie Roblox",139,18,11,C.Cyan)
				local buy=button(row,"Zobacz w Roblox",function()
					local known,owned,full=offerEligibility(productKey)
					if not known or owned or full or busy then return end
					request("Premium",{key=productKey})
				end,{Name="Premium"..key,Position=UDim2.fromOffset(14,164),Size=UDim2.new(1,-28,0,44),TextSize=12})
				track(function()
					local known,owned,full=offerEligibility(productKey)
					row.Visible=not (productKey=="ExtraBeds" and (owned or full))
					if not row.Visible then return end
					if owned then
						priceLabel.Text="Zestaw już odebrany"; priceLabel.TextColor3=C.Lime
						enabled(buy,false,"Posiadasz ✓")
					elseif not known then
						priceLabel.Text="Sprawdzanie posiadanych dodatków…"; priceLabel.TextColor3=C.Muted
						enabled(buy,false,"Sprawdzanie…")
					else
						local price=getOfferPrice(id,isProduct and Enum.InfoType.Product or Enum.InfoType.GamePass)
						priceLabel.Text=price~=nil and ("Cena: "..tostring(price).." Robux") or "Cena w oknie Roblox"
						priceLabel.TextColor3=C.Cyan
						local durable=state and state.saveStatus~="Studio" and state.saveStatus~="Unavailable"
						enabled(buy,durable and not busy,durable and "Zobacz w Roblox" or "Zakup wymaga aktywnego zapisu")
					end
				end)
			end
		end
	end
end

buildView=function()
	uiUpdates={}
	for _,child in ipairs(content:GetChildren()) do if not child:IsA("UIPadding") then child:Destroy() end end
	list(content,10); content.CanvasPosition=Vector2.zero
	local titles={Garden={"OSOBISTA BIOSFERA","Mój ogród"},Seeds={"GALAKTYCZNY BANK NASION","Nasiona"},Research={"LABORATORIUM STACJI","Badania"},Gifts={"MIĘDZYGWIEZDNA POCZTA","Prezenty"},Mission={"DZIENNIK EKSPEDYCJI","Misje i nagrody"},Ranking={"SPOŁECZNOŚĆ ORBITALNA","Ranking"},Settings={"KONTROLA STACJI","Twoja stacja"},Designer={"AUTORSKIE DEKORACJE","Pracownia"}}
	local title=titles[currentView] or titles.Garden; kicker.Text=title[1]; panelTitle.Text=title[2]
	for key,b in pairs(navButtons) do b.BackgroundColor3=key==currentView and C.Dark or C.Panel; local s=b:FindFirstChildOfClass("UIStroke"); if s then s:Destroy() end; if key==currentView then stroke(b,C.Cyan,.2) end end
	local renderers={Garden=garden,Seeds=seeds,Research=research,Gifts=gifts,Mission=missions,Ranking=ranking,Settings=settings,Designer=designer}
	local renderer=renderers[currentView] or garden
	renderer()
	refresh()
	if UserInputService.GamepadEnabled and not GuiService.SelectedObject then GuiService.SelectedObject=navButtons[currentView] end
end

local welcome=frame(shell,{Name="Welcome",AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(430,290),BackgroundColor3=C.Bg,ZIndex=20}); corner(welcome,18); stroke(welcome,C.Cyan)
local welcomeScroll=make("ScrollingFrame",{Position=UDim2.fromOffset(0,0),Size=UDim2.new(1,0,1,-65),BackgroundTransparency=1,BorderSizePixel=0,CanvasSize=UDim2.fromOffset(0,214),ScrollBarThickness=3,ZIndex=21},welcome)
text(welcomeScroll,"WITAJ NA ORBICIE",10,C.Cyan,{Position=UDim2.fromOffset(24,22),Size=UDim2.new(1,-48,0,18),Font=Enum.Font.GothamBold,ZIndex=21})
text(welcomeScroll,"Twój ogród.\nCała galaktyka.",29,C.Text,{Position=UDim2.fromOffset(24,48),Size=UDim2.new(1,-48,0,76),Font=Enum.Font.GothamBold,TextYAlignment=Enum.TextYAlignment.Top,ZIndex=21})
text(welcomeScroll,"01  Posadź pierwsze nasiono\n02  Podlej, poczekaj i zbierz plon\n03  Rozbuduj szklarnię i dziel się nasionami",12,C.Muted,{Position=UDim2.fromOffset(24,139),Size=UDim2.new(1,-48,0,64),TextYAlignment=Enum.TextYAlignment.Top,ZIndex=21})
button(welcome,"ROZPOCZNIJ UPRAWĘ  →",function() welcomeDismissed=true; welcome.Visible=false; currentView="Garden"; panelOpen=true; buildView(); layout() end,{AnchorPoint=Vector2.new(0,1),Position=UDim2.new(0,24,1,-14),Size=UDim2.new(1,-48,0,44),BackgroundColor3=C.Lime,ZIndex=21})

layout=function()
	local size=shell.AbsoluteSize -- available area after Roblox/device safe insets
	local width,height=size.X,size.Y
	if width<200 or height<150 then return end -- Studio/background windows may report a transient 1x1 viewport.
	local compact=width<820
	local landscape=compact and height<430
	header.Position=UDim2.fromOffset(12,8); header.Size=UDim2.new(1,-24,0,landscape and 40 or compact and 60 or 66)
	kicker.Position=UDim2.fromOffset(20,15);panelTitle.Position=UDim2.fromOffset(20,35);panelTitle.TextSize=24
	divider.Position=UDim2.fromOffset(20,78);content.Position=UDim2.fromOffset(16,92);content.Size=UDim2.new(1,-32,1,-126);collapse.Position=UDim2.new(1,-16,0,18)
	mark.Position=UDim2.fromOffset(16,14);mark.Size=UDim2.fromOffset(36,36)
	brand.TextSize=compact and 14 or 19; brand.Size=UDim2.fromOffset(compact and 160 or 240,25)
	subtitle.Visible=width>=560 and not landscape; mark.Visible=width>=450
	brand.Position=UDim2.fromOffset(width>=450 and 62 or 14,compact and 16 or 12)
	creditLabel.TextSize=compact and 16 or 21; creditLabel.Size=UDim2.fromOffset(compact and 120 or 180,27); creditLabel.Position=UDim2.new(1,-14,0,compact and 8 or 10)
	levelLabel.TextSize=compact and 9 or 11; levelLabel.Position=UDim2.new(1,-14,0,compact and 34 or 38)
	panel.Visible=panelOpen
	if landscape then
		mark.Position=UDim2.fromOffset(14,7);mark.Size=UDim2.fromOffset(26,26);brand.Position=UDim2.fromOffset(width>=450 and 50 or 14,6)
		creditLabel.Position=UDim2.new(1,-14,0,0);levelLabel.Position=UDim2.new(1,-14,0,23)
		kicker.Position=UDim2.fromOffset(16,7);panelTitle.Position=UDim2.fromOffset(16,25);panelTitle.TextSize=20
		divider.Position=UDim2.fromOffset(16,57);content.Position=UDim2.fromOffset(12,64);content.Size=UDim2.new(1,-24,1,-94);collapse.Position=UDim2.new(1,-12,0,7)
		nav.Position=UDim2.fromOffset(12,58); nav.Size=UDim2.fromOffset(132,math.max(88,height-(panelOpen and 70 or 186))); nav.AutomaticCanvasSize=Enum.AutomaticSize.Y; nav.ScrollingDirection=Enum.ScrollingDirection.Y;nav.ScrollBarThickness=2
		navLayout.FillDirection=Enum.FillDirection.Vertical
		for _,b in pairs(navButtons) do b.Size=UDim2.new(1,0,0,44) end
		panel.AnchorPoint=Vector2.new(1,0); panel.Position=UDim2.new(1,-12,0,58); panel.Size=UDim2.fromOffset(math.min(464,width-168),math.max(140,height-70))
		dock.AnchorPoint=Vector2.new(0,1); dock.Position=UDim2.new(0,12,1,-12); dock.Size=UDim2.fromOffset(132,108); dock.Visible=not panelOpen
		toggle.Position=UDim2.fromOffset(6,6); toggle.Size=UDim2.new(1,-12,0,44); homeButton.Position=UDim2.fromOffset(6,56); homeButton.Size=UDim2.new(1,-12,0,44)
	elseif compact then
		nav.Position=UDim2.new(0,12,1,-57); nav.Size=UDim2.new(1,-24,0,45); nav.AutomaticCanvasSize=Enum.AutomaticSize.X; nav.ScrollingDirection=Enum.ScrollingDirection.X
		navLayout.FillDirection=Enum.FillDirection.Horizontal
		for _,b in pairs(navButtons) do b.Size=UDim2.fromOffset(132,44) end
		panel.AnchorPoint=Vector2.new(.5,1); panel.Position=UDim2.new(.5,0,1,-128); panel.Size=UDim2.fromOffset(math.min(width-24,480),math.max(140,math.min(height-207,math.floor(height*.65))))
		dock.AnchorPoint=Vector2.new(.5,1); dock.Position=UDim2.new(.5,0,1,-65); dock.Size=UDim2.fromOffset(math.min(width-24,340),56); dock.Visible=true
	else
		nav.Position=UDim2.fromOffset(16,94); nav.Size=UDim2.fromOffset(164,math.min(390,height-180)); nav.AutomaticCanvasSize=Enum.AutomaticSize.Y; nav.ScrollingDirection=Enum.ScrollingDirection.Y
		navLayout.FillDirection=Enum.FillDirection.Vertical
		for _,b in pairs(navButtons) do b.Size=UDim2.new(1,0,0,44) end
		panel.AnchorPoint=Vector2.new(1,0); panel.Position=UDim2.new(1,-16,0,94); panel.Size=UDim2.fromOffset(math.min(464,width*.45),height-112)
		dock.AnchorPoint=Vector2.new(.5,1); dock.Position=UDim2.new(.39,0,1,-18); dock.Size=UDim2.fromOffset(math.min(310,width*.26),56); dock.Visible=true
	end
	if not landscape then toggle.Position=UDim2.fromOffset(6,6); toggle.Size=UDim2.new(.54,-9,1,-12); homeButton.Position=UDim2.new(.54,3,0,6); homeButton.Size=UDim2.new(.46,-9,1,-12) end
	welcome.Size=UDim2.fromOffset(math.min(430,width-32),math.max(160,math.min(290,height-32)))
	toast.Size=UDim2.fromOffset(math.min(410,width-32),58); toast.Position=UDim2.new(.5,0,0,compact and 76 or 88)
	toggle.Text=panelOpen and "SCHOWAJ PANEL" or "PANEL OGRODU"
end

task.spawn(function()
	local inputs=ReplicatedStorage:WaitForChild("Inputs"):WaitForChild("SpaceGarden")
	table.insert(persistentConnections,inputs:WaitForChild("TogglePanel").Pressed:Connect(function()
		if UserInputService:GetFocusedTextBox() or GuiService.MenuIsOpen then return end
		panelOpen=not panelOpen; layout()
	end))
	table.insert(persistentConnections,inputs:WaitForChild("HarvestAll").Pressed:Connect(function()
		if UserInputService:GetFocusedTextBox() or GuiService.MenuIsOpen then return end
		request("HarvestAll")
	end))
end)
local cameraConnection
local function connectCamera()
	if cameraConnection then cameraConnection:Disconnect() end
	if workspace.CurrentCamera then cameraConnection=workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layout) end
	layout()
end
table.insert(persistentConnections,workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(connectCamera))
table.insert(persistentConnections,shell:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout))
buildView(); connectCamera()
if UserInputService.GamepadEnabled and not UserInputService.TouchEnabled then
	GuiService.SelectedObject=welcome:FindFirstChildOfClass("TextButton") or navButtons.Garden
end
task.spawn(function()
	while gui.Parent do
		request("State",{},true)
		task.wait(2)
	end
end)
task.spawn(function()
	while gui.Parent do refresh(); task.wait(.5) end
end)
-- Simple ambient UI liveliness respects reduced-motion preference.
local elapsed=0
table.insert(persistentConnections,RunService.RenderStepped:Connect(function(dt)
	elapsed+=dt
	if not reducedMotion then mark.Rotation=math.sin(elapsed*.55)*2 else mark.Rotation=0 end
end))
gui.Destroying:Connect(function()
	if cameraConnection then cameraConnection:Disconnect() end
	if uiSound then uiSound:Destroy(); uiSound=nil end
	for _,connection in ipairs(persistentConnections) do connection:Disconnect() end
	table.clear(persistentConnections)
end)

-- Local Studio-only inspection bridge; never replicated as a remote endpoint.
if RunService:IsStudio() then
	local qa=make("BindableFunction",{Name="SpaceGardenClientQA"},gui)
	local validViews={Garden=true,Seeds=true,Research=true,Gifts=true,Mission=true,Ranking=true,Settings=true,Designer=true}
	qa.OnInvoke=function(command,arg)
		if command=="View" and type(arg)=="string" and validViews[arg] then
			currentView=arg; panelOpen=true; welcome.Visible=false; welcomeDismissed=true
			buildView(); layout()
			return panelTitle.Text
		elseif command=="Panel" then
			if type(arg)=="boolean" then panelOpen=arg else panelOpen=not panelOpen end
			layout()
			return panelOpen
		end
		return currentView
	end
end
