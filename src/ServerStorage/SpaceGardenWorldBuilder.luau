-- Space Garden / original orbital conservatory. No external assets.
local WorldBuilder = {}
local Lighting = game:GetService("Lighting")
local C = {
    Night = Color3.fromRGB(10, 18, 36), Hull = Color3.fromRGB(24, 40, 60),
    Deck = Color3.fromRGB(38, 54, 72), Edge = Color3.fromRGB(61, 84, 103),
    Cyan = Color3.fromRGB(61, 232, 231), Lime = Color3.fromRGB(192, 255, 104),
    Purple = Color3.fromRGB(173, 114, 255), White = Color3.fromRGB(226, 244, 247),
    Soil = Color3.fromRGB(31, 46, 48), Amber = Color3.fromRGB(255, 190, 87),
}

function WorldBuilder.Build()
    local previous = workspace:FindFirstChild("SpaceGardenWorld")
    if previous then previous:Destroy() end
    local world = Instance.new("Model")
    world.Name = "SpaceGardenWorld"
    world:SetAttribute("Version", "1.0.0")
    world.Parent = workspace
    local partCount = 0

    local function folder(parent, name, class)
        local v = Instance.new(class or "Folder")
        v.Name = name
        v.Parent = parent
        return v
    end
    local function part(parent, name, size, cf, color, material, shape, transparency, collide)
        local p = Instance.new("Part")
        p.Name = name
        p.Anchored = true
        p.Size = size
        p.CFrame = typeof(cf) == "Vector3" and CFrame.new(cf) or cf
        p.Color = color or C.Hull
        p.Material = material or Enum.Material.SmoothPlastic
        p.TopSurface = Enum.SurfaceType.Smooth
        p.BottomSurface = Enum.SurfaceType.Smooth
        if shape then p.Shape = shape end
        p.Transparency = transparency or 0
        p.CanCollide = collide ~= false
        p.CanTouch = false
        p.CastShadow = p.Transparency < .5 and p.Material ~= Enum.Material.Neon
        if name == "SideGlow" or name == "BedStatusLight" or name == "DoorLight" or name == "RoofSpine" or name == "NutrientGlow" then
            p:SetAttribute("ThemeAccent", true)
        end
        p.Parent = parent
        partCount += 1
        return p
    end
    local function beam(parent, a, b, width, color, material)
        local middle = (a + b) / 2
        return part(parent, "Strut", Vector3.new(width, width, (b-a).Magnitude), CFrame.lookAt(middle, b), color, material, nil, 0, false)
    end
    local function cylinder(parent, name, center, diameter, height, color, material, transparency)
        return part(parent, name, Vector3.new(height, diameter, diameter), CFrame.new(center)*CFrame.Angles(0, 0, math.pi/2), color, material, Enum.PartType.Cylinder, transparency)
    end
    local function label(parent, text, color, size)
        local gui = Instance.new("SurfaceGui")
        gui.Name = "SurfaceGui"
        gui.Face = Enum.NormalId.Front
        gui.CanvasSize = Vector2.new(1200, 400)
        gui.LightInfluence = 0
        gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
        gui.Parent = parent
        local t = Instance.new("TextLabel")
        t.Name = "OwnerLabel"
        t.BackgroundTransparency = 1
        t.Size = UDim2.fromScale(.92, .82)
        t.Position = UDim2.fromScale(.04, .09)
        t.Text = text
        t.TextColor3 = color or C.White
        t.Font = Enum.Font.GothamBold
        t.TextSize = size or 62
        t.TextWrapped = true
        t.Parent = gui
        return t
    end
    local function topText(parent, text)
        local gui = Instance.new("SurfaceGui")
        gui.Face = Enum.NormalId.Top
        gui.CanvasSize = Vector2.new(600, 300)
        gui.LightInfluence = 0
        gui.Parent = parent
        local t = Instance.new("TextLabel")
        t.BackgroundTransparency = 1
        t.Size = UDim2.fromScale(1, 1)
        t.Text = text
        t.TextColor3 = C.Cyan
        t.Font = Enum.Font.GothamBold
        t.TextSize = 70
        t.Parent = gui
    end
    local function light(parent, brightness, range, color)
        local l = Instance.new("PointLight")
        l.Brightness = brightness
        l.Range = range
        l.Color = color
        l.Shadows = false
        l.Parent = parent
    end

    Lighting.ClockTime = 0
    Lighting.Brightness = 2
    Lighting.Ambient = Color3.fromRGB(125, 142, 165)
    Lighting.OutdoorAmbient = Color3.fromRGB(130, 155, 175)
    Lighting.GlobalShadows = true
    Lighting.ExposureCompensation = .45
    for _, n in ipairs({"SG_Bloom", "SG_Color", "SG_Atmosphere"}) do
        local old = Lighting:FindFirstChild(n)
        if old then old:Destroy() end
    end
    local bloom = Instance.new("BloomEffect")
    bloom.Name = "SG_Bloom"; bloom.Intensity = .3; bloom.Size = 24; bloom.Threshold = 1.4; bloom.Parent = Lighting
    local grade = Instance.new("ColorCorrectionEffect")
    grade.Name = "SG_Color"; grade.Contrast = .06; grade.Saturation = .08; grade.TintColor = Color3.fromRGB(244, 250, 255); grade.Parent = Lighting
    local atmosphere = Instance.new("Atmosphere")
    atmosphere.Name = "SG_Atmosphere"; atmosphere.Density = .08; atmosphere.Offset = .6
    atmosphere.Color = Color3.fromRGB(112, 132, 172); atmosphere.Decay = Color3.fromRGB(22, 29, 58)
    atmosphere.Glare = 0; atmosphere.Haze = 0; atmosphere.Parent = Lighting

    local hull = folder(world, "OrbitalDeck")
    part(hull, "StationFoundation", Vector3.new(278, 5, 202), Vector3.new(92, -2.5, 52), C.Night, Enum.Material.Metal)
    part(hull, "StationDeck", Vector3.new(274, 1.2, 198), Vector3.new(92, .6, 52), C.Hull, Enum.Material.Metal)
    for _, z in ipairs({-48, 152}) do
        part(hull, "HullEdge", Vector3.new(278, 1, 1.1), Vector3.new(92, .4, z), C.Cyan, Enum.Material.Neon)
        for x = -44, 228, 17 do
            part(hull, "PerimeterPost", Vector3.new(.5, 3.4, .5), Vector3.new(x, 2.9, z), C.Edge, Enum.Material.Metal)
        end
        part(hull, "SafetyRail", Vector3.new(274, .35, .35), Vector3.new(92, 4.5, z), C.Edge, Enum.Material.Metal)
    end
    for _, x in ipairs({-46, 230}) do
        part(hull, "HullEdge", Vector3.new(1.1, 1, 200), Vector3.new(x, .4, 52), C.Cyan, Enum.Material.Neon)
        for z = -48, 152, 16 do
            part(hull, "PerimeterPost", Vector3.new(.5, 3.4, .5), Vector3.new(x, 2.9, z), C.Edge, Enum.Material.Metal)
        end
        part(hull, "SafetyRail", Vector3.new(.35, .35, 200), Vector3.new(x, 4.5, 52), C.Edge, Enum.Material.Metal)
    end
    -- Broad central promenade; each greenhouse entrance opens directly onto it.
    part(hull, "Promenade", Vector3.new(268, .2, 22), Vector3.new(92, 1.3, 52), C.Deck, Enum.Material.Metal)
    for _, z in ipairs({42, 62}) do
        part(hull, "GuidanceStrip", Vector3.new(266, .06, .2), Vector3.new(92, 1.44, z), C.Cyan, Enum.Material.Neon, nil, 0, false)
    end
    for x = -28, 212, 24 do
        local arrow = part(hull, "NavigationMark", Vector3.new(3, .03, 2), CFrame.new(x, 1.46, 52), C.Deck, nil, nil, 0, false)
        topText(arrow, "›")
    end
    -- Arrival beacon lies at one end, leaving the promenade free for movement.
    local lobby = folder(world, "ArrivalConcourse")
    cylinder(lobby, "ArrivalPad", Vector3.new(-29, 1.45, 52), 16, .35, C.Edge, Enum.Material.Metal)
    cylinder(lobby, "ArrivalLight", Vector3.new(-29, 1.64, 52), 13, .06, C.Cyan, Enum.Material.Neon)
    cylinder(lobby, "ArrivalInset", Vector3.new(-29, 1.7, 52), 11.8, .08, C.Night, Enum.Material.Metal)
    local spawn = Instance.new("SpawnLocation")
    spawn.Name = "SpaceGardenSpawn"; spawn.Size = Vector3.new(8, .2, 8)
    spawn.Position = Vector3.new(-29, 1.85, 52); spawn.Anchored = true; spawn.Neutral = true
    spawn.Transparency = 1; spawn.CanCollide = false; spawn.Duration = 0; spawn.Parent = lobby
    local welcome = part(lobby, "WelcomeMonolith", Vector3.new(24, 9, 1), CFrame.new(-29, 8, 65)*CFrame.Angles(0, math.pi, 0), C.Night, Enum.Material.Metal)
    label(welcome, "SPACE GARDEN\nORBITAL CONSERVATORY  /  01", C.White, 65)
    part(lobby, "WelcomeUnderline", Vector3.new(23, .14, 1.1), Vector3.new(-29, 3.7, 65), C.Lime, Enum.Material.Neon, nil, 0, false)
    light(welcome, 2, 30, C.Cyan)
    local rearWelcome = part(lobby, "WelcomeReverse", Vector3.new(23.9, 8.9, .1), CFrame.new(-29, 8, 64.44), C.Night, nil, nil, 0, false)
    label(rearWelcome, "SPACE GARDEN\nSADŹ • ODKRYWAJ • DZIEL SIĘ", C.White, 62)

    local farms = folder(world, "Farms")
    for farmIndex = 1, 6 do
        local row = farmIndex <= 3 and 0 or 1
        local col = (farmIndex - 1) % 3
        local ox, oz = col * 92, row * 104
        local front = row == 0 and 1 or -1
        local accent = ({C.Cyan, C.Lime, C.Purple, C.Amber, C.Cyan, C.Lime})[farmIndex]
        local farm = folder(farms, "Farm"..farmIndex, "Model")
        farm:SetAttribute("OwnerUserId", 0)
        farm:SetAttribute("FarmIndex", farmIndex)
        part(farm, "Foundation", Vector3.new(80, 1.2, 74), Vector3.new(ox, 1.8, oz), C.Night, Enum.Material.Metal)
        part(farm, "Floor", Vector3.new(77, .25, 71), Vector3.new(ox, 2.5, oz), C.Deck, Enum.Material.Metal)
        for _, x in ipairs({-37.5, 37.5}) do
            part(farm, "SideKickplate", Vector3.new(.5, 1, 72), Vector3.new(ox+x, 3, oz), C.Edge, Enum.Material.Metal)
            part(farm, "SideGlass", Vector3.new(.2, 11, 71), Vector3.new(ox+x, 9, oz), accent, Enum.Material.Glass, nil, .88, false)
            part(farm, "SideGlow", Vector3.new(.25, .14, 71), Vector3.new(ox+x, 3.6, oz), accent, Enum.Material.Neon, nil, 0, false)
        end
        -- Rear window and front doors have a generous 16-stud entrance.
        part(farm, "RearGlass", Vector3.new(75, 11, .2), Vector3.new(ox, 9, oz-front*35.5), accent, Enum.Material.Glass, nil, .88, false)
        for _, x in ipairs({-23, 23}) do
            part(farm, "FrontGlass", Vector3.new(29, 11, .2), Vector3.new(ox+x, 9, oz+front*35.5), accent, Enum.Material.Glass, nil, .89, false)
            part(farm, "FrontRail", Vector3.new(29, .5, .5), Vector3.new(ox+x, 4, oz+front*35.5), C.Edge, Enum.Material.Metal)
        end
        for _, x in ipairs({-8.5, 8.5}) do
            part(farm, "DoorColumn", Vector3.new(.6, 13, .7), Vector3.new(ox+x, 9, oz+front*36), C.Edge, Enum.Material.Metal)
            part(farm, "DoorLight", Vector3.new(.18, 10, .76), Vector3.new(ox+x, 8, oz+front*36), accent, Enum.Material.Neon, nil, 0, false)
        end
        -- A low ramp connects the elevated floor and promenade.
        local ramp = Instance.new("WedgePart")
        ramp.Name = "EntryRamp"; ramp.Size = Vector3.new(16, 1.25, 6)
        ramp.CFrame = CFrame.new(ox, 1.99, oz+front*38.5)*CFrame.Angles(0, front == 1 and math.pi or 0, 0)
        ramp.Anchored = true; ramp.Color = C.Deck; ramp.Material = Enum.Material.Metal; ramp.Parent = farm
        -- Rounded conservatory ribs: wide open interior, decorative glazing overhead.
        for _, z in ipairs({-35.7, -17.8, 0, 17.8, 35.7}) do
            local last
            for seg = 0, 12 do
                local theta = math.pi * seg / 12
                local point = Vector3.new(ox + math.cos(theta)*37.5, 13.5 + math.sin(theta)*14, oz+z)
                if last then beam(farm, last, point, .5, C.Edge, Enum.Material.Metal) end
                last = point
            end
            for _, x in ipairs({-37.5, 37.5}) do
                part(farm, "RibColumn", Vector3.new(.5, 11, .5), Vector3.new(ox+x, 8, oz+z), C.Edge, Enum.Material.Metal)
            end
        end
        for seg = 0, 11 do
            local t1, t2 = math.pi*seg/12, math.pi*(seg+1)/12
            local a = Vector3.new(ox+math.cos(t1)*37.5, 13.5+math.sin(t1)*14, oz)
            local b = Vector3.new(ox+math.cos(t2)*37.5, 13.5+math.sin(t2)*14, oz)
            local mid = (a+b)/2
            local roof = part(farm, "RoofGlazing", Vector3.new((b-a).Magnitude, .1, 71), CFrame.new(mid)*CFrame.Angles(0,0,math.atan2(b.Y-a.Y,b.X-a.X)), accent, Enum.Material.Glass, nil, .94, false)
            roof.CastShadow = false
        end
        part(farm, "RoofSpine", Vector3.new(.6, .4, 73), Vector3.new(ox, 27.5, oz), accent, Enum.Material.Neon, nil, 0, false)
        local signCF = CFrame.new(ox, 17, oz+front*36.5)*CFrame.Angles(0, front==1 and math.pi or 0, 0)
        local sign = part(farm, "Sign", Vector3.new(23, 4, .6), signCF, C.Night, Enum.Material.Metal, nil, 0, false)
        label(sign, string.format("OGRÓD %02d  /  WOLNY", farmIndex), accent, 73)
        local inner = part(farm, "InteriorSign", Vector3.new(23, 4, .1), signCF*CFrame.new(0,0,.36)*CFrame.Angles(0,math.pi,0), C.Night, nil, nil, 0, false)
        label(inner, "SPACE GARDEN  /  "..string.format("%02d",farmIndex), accent, 74)
        local farmSpawn = part(farm, "Spawn", Vector3.new(6, .1, 4), Vector3.new(ox, 2.8, oz+front*30.5), C.Deck, nil, nil, 1, false)
        farmSpawn.CFrame = CFrame.lookAt(farmSpawn.Position, Vector3.new(ox, 2.8, oz))
        local beds = folder(farm, "Beds")
        for i = 1, 12 do
            local bx = ox + (((i-1)%3)-1)*23
            local bz = oz + (math.floor((i-1)/3)-1.5)*13.6
            part(farm, "HydroponicBase", Vector3.new(17, .65, 10.2), Vector3.new(bx, 3, bz), C.Night, Enum.Material.Metal)
            local bed = part(beds, "Bed"..i, Vector3.new(14.8, .4, 8.2), Vector3.new(bx, 3.55, bz), C.Soil, Enum.Material.SmoothPlastic)
            bed:SetAttribute("Index", i)
            bed:SetAttribute("OwnerUserId", 0)
            for _, dx in ipairs({-8, 8}) do
                part(farm, "PlanterRim", Vector3.new(.55, .55, 10.2), Vector3.new(bx+dx, 3.5, bz), C.Edge, Enum.Material.Metal)
            end
            for _, dz in ipairs({-4.85, 4.85}) do
                part(farm, "PlanterRim", Vector3.new(16.5, .55, .5), Vector3.new(bx, 3.5, bz+dz), C.Edge, Enum.Material.Metal)
            end
            part(farm, "BedStatusLight", Vector3.new(9, .08, .18), Vector3.new(bx, 3.8, bz+4.85), accent, Enum.Material.Neon, nil, 0, false)
            local num = part(farm, "BedNumber", Vector3.new(1.6,.04,1.3), Vector3.new(bx-6.6,3.8,bz+4.2), C.Night, nil, nil, 0, false)
            topText(num,string.format("%02d",i))
        end
        for _, x in ipairs({-34,34}) do
            local tank = cylinder(farm, "NutrientReservoir", Vector3.new(ox+x,4.2,oz-front*31), 3.5, 3, C.Hull, Enum.Material.Metal)
            cylinder(farm, "NutrientGlow", Vector3.new(ox+x,5.8,oz-front*31), 3.2, .25, accent, Enum.Material.Neon)
            part(farm, "ReservoirCap", Vector3.new(1, .3, 1), Vector3.new(ox+x,6.1,oz-front*31), C.Edge, Enum.Material.Metal)
            light(tank,.6,18,accent)
        end
        for _, z in ipairs({-17,17}) do
            local lamp = part(farm, "GrowLight", Vector3.new(18,.3,1),Vector3.new(ox,20,oz+z),C.White,Enum.Material.Neon,nil,0,false)
            light(lamp,1.6,42,Color3.fromRGB(187,241,255))
        end
        task.wait()
    end

    -- Central research kiosk and display gardens, kept beside pedestrian lanes.
    local displays = folder(world,"ResearchConcourse")
    for j = 1, 3 do
        local px = 41 + (j-1)*53
        cylinder(displays,"SpecimenPedestal",Vector3.new(px,2.1,52),5.5,1.5,C.Night,Enum.Material.Metal)
        cylinder(displays,"SpecimenHalo",Vector3.new(px,2.9,52),5,.12,C.Cyan,Enum.Material.Neon)
        local color = ({C.Cyan,C.Purple,C.Lime})[j]
        for k=1,4 do
            local a = k*math.pi/2 + j*.3
            local base=Vector3.new(px,3.1,52)
            local tip=base+Vector3.new(math.cos(a)*1.2,3.5+k*.35,math.sin(a)*1.2)
            beam(displays,base,tip,.28,color,Enum.Material.Neon)
            part(displays,"AlienBud",Vector3.new(1.2,1.8,1.2),CFrame.new(tip)*CFrame.Angles(.3*k,0,.5),color,Enum.Material.Neon,Enum.PartType.Ball,0,false)
        end
        local screen=part(displays,"ResearchScreen",Vector3.new(10,4,.5),CFrame.new(px,6.5,61.8)*CFrame.Angles(0,math.pi,0),C.Night,Enum.Material.Metal,nil,0,false)
        label(screen,({"KSENOBOTANIKA\nODKRYWAJ NOWE GATUNKI","LABORATORIUM\nROZWIJAJ SWOJĄ SZKLARNIĘ","GALAKTYCZNA MISJA\nRAZEM ZBIERAMY WIĘCEJ"})[j],color,49)
    end

    -- Orbital solar arrays hang below deck level so they never block the garden view.
    local utilities=folder(world,"StationUtilities")
    for _,side in ipairs({-1,1}) do
        for z=-20,124,48 do
            local x=92+side*163
            beam(utilities,Vector3.new(92+side*133,-1,z),Vector3.new(x,-6,z),1,C.Edge,Enum.Material.Metal)
            part(utilities,"SolarFrame",Vector3.new(38,1,31),Vector3.new(x,-6,z),C.Edge,Enum.Material.Metal)
            for cx=-1,1 do for rz=-1,1 do
                part(utilities,"PhotovoltaicPanel",Vector3.new(11.8,.2,9.5),Vector3.new(x+cx*12.4,-5.35,z+rz*9.8),Color3.fromRGB(28,50,111),Enum.Material.Glass)
                part(utilities,"PanelTrace",Vector3.new(10,.06,.12),Vector3.new(x+cx*12.4,-5.2,z+rz*9.8),C.Cyan,Enum.Material.Neon,nil,0,false)
            end end
        end
    end
    task.wait()

    local cosmos=folder(world,"Cosmos")
    local planetPosition=Vector3.new(112,180,-470)
    part(cosmos,"VerdantExoplanet",Vector3.new(290,290,290),planetPosition,Color3.fromRGB(36,89,108),Enum.Material.SmoothPlastic,Enum.PartType.Ball,0,false)
    -- Overlapping, tangent ellipsoids suggest original organic landmasses.
    -- They sit partly inside the sphere: shallow, irregular green islands at orbital scale.
    local landmasses = {
        {-5,-18,60,34,-.4},{8,-12,43,29,.1},{19,-3,54,27,.7},
        {30,7,37,29,.1},{39,18,44,24,-.4},{2,2,37,34,.4},
        {-19,6,40,22,-.5},{-29,15,27,20,.6},{-38,19,21,15,.2},
        {13,47,49,29,-.3},{24,57,40,25,.4},{36,62,25,20,.8},
        {-23,65,37,29,-.6},{-36,74,29,24,.2},{-45,66,23,15,.6},
        {47,-39,30,24,.5},{53,-26,39,19,-.3},{-6,-68,26,19,.3},
    }
    local landColors = {Color3.fromRGB(83,143,112),Color3.fromRGB(101,160,117),Color3.fromRGB(129,169,119)}
    for i, island in ipairs(landmasses) do
        local lat, lon = math.rad(island[1]), math.rad(island[2])
        local normal = Vector3.new(math.cos(lat)*math.sin(lon),math.sin(lat),math.cos(lat)*math.cos(lon))
        local pos = planetPosition+normal*143.7
        local tangent = CFrame.lookAt(pos,pos+normal)*CFrame.Angles(math.pi/2,island[5],0)
        part(cosmos,"ExoplanetContinent",Vector3.new(island[3],8,island[4]),tangent,landColors[(i-1)%3+1],Enum.Material.SmoothPlastic,Enum.PartType.Ball,0,false)
    end
    for i, cloud in ipairs({{54,3,65,11},{-4,26,76,9},{-43,-25,59,10},{26,-46,54,8}}) do
        local lat, lon = math.rad(cloud[1]), math.rad(cloud[2])
        local normal = Vector3.new(math.cos(lat)*math.sin(lon),math.sin(lat),math.cos(lat)*math.cos(lon))
        local pos = planetPosition+normal*146
        part(cosmos,"ExoplanetCloud",Vector3.new(cloud[3],3,cloud[4]),CFrame.lookAt(pos,pos+normal)*CFrame.Angles(math.pi/2,.2*i,0),Color3.fromRGB(204,230,220),Enum.Material.SmoothPlastic,Enum.PartType.Ball,.45,false)
    end
    part(cosmos,"PlanetAtmosphere",Vector3.new(299,299,299),planetPosition,Color3.fromRGB(80,224,214),Enum.Material.Neon,Enum.PartType.Ball,.89,false)
    local ringCF=CFrame.new(planetPosition)*CFrame.Angles(math.rad(20),0,math.rad(17))
    for i=1,100 do
        local a=2*math.pi*i/100
        local b=2*math.pi*(i+1)/100
        local radius=218
        local p1=(ringCF*CFrame.new(math.cos(a)*radius,0,math.sin(a)*radius)).Position
        local p2=(ringCF*CFrame.new(math.cos(b)*radius,0,math.sin(b)*radius)).Position
        local segment=beam(cosmos,p1,p2,3.5,Color3.fromRGB(136,179,173),Enum.Material.SmoothPlastic)
        segment.Size=Vector3.new(15,1.1,(p2-p1).Magnitude+.3)
        segment.Transparency=.25
    end
    part(cosmos,"LavenderMoon",Vector3.new(75,75,75),Vector3.new(-250,135,160),Color3.fromRGB(136,116,175),Enum.Material.SmoothPlastic,Enum.PartType.Ball,0,false)
    local random=Random.new(737)
    for i=1,160 do
        local a=random:NextNumber(0,math.pi*2)
        local elevation=random:NextNumber(.08,1.2)
        local radius=random:NextNumber(850,1400)
        local pos=Vector3.new(92+math.cos(a)*math.cos(elevation)*radius,math.sin(elevation)*radius,52+math.sin(a)*math.cos(elevation)*radius)
        local sz=random:NextNumber(.7,2.6)
        local star=part(cosmos,"Star",Vector3.new(sz,sz,sz),pos,i%6==0 and C.Cyan or C.White,Enum.Material.Neon,Enum.PartType.Ball,0,false)
        star.CastShadow=false
    end
    for i=1,28 do
        local pos=Vector3.new(random:NextNumber(-450,600),random:NextNumber(-150,-45),random:NextNumber(-330,430))
        local size=random:NextNumber(5,18)
        part(cosmos,"DriftingAsteroid",Vector3.new(size,size*.65,size*.85),CFrame.new(pos)*CFrame.Angles(random:NextNumber(),random:NextNumber(),random:NextNumber()),Color3.fromRGB(57,65,78),Enum.Material.Slate,Enum.PartType.Ball,0,false)
    end
    world:SetAttribute("StaticPartCount",partCount)
    world:SetAttribute("Layout","Farm centers: (0,0), (92,0), (184,0), (0,104), (92,104), (184,104). Deck top 1.2, greenhouse floor 2.625, bed top 3.75.")
    return world
end

return WorldBuilder
