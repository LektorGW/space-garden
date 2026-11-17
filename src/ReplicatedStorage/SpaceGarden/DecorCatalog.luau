-- Space Garden original in-game sculpture catalog. No external asset references.
local Catalog = {
    ShapeOrder = {"OrbitBloom", "PrismSpire", "HelixFern", "SatelliteLotus"},
    Shapes = {
        OrbitBloom = {Name="Orbitalny Kwiat", Description="Świetlisty pąk otoczony dwiema pochylonymi orbitami."},
        PrismSpire = {Name="Pryzmatyczna Iglica", Description="Pięć krystalicznych iglic tworzy małą konstelację."},
        HelixFern = {Name="Spiralna Paproć", Description="Pary listków wiją się spiralnie wokół świetlistej łodygi."},
        SatelliteLotus = {Name="Satelitarny Lotos", Description="Dwie warstwy płatków otulają orbitalne serce kwiatu."},
    },
    PaletteOrder = {"Aurora", "Nebula", "Solar", "Coral", "Glacier"},
    Palettes = {
        Aurora = {Name="Zorza", Color=Color3.fromRGB(83,237,197)},
        Nebula = {Name="Mgławica", Color=Color3.fromRGB(184,137,255)},
        Solar = {Name="Słońce", Color=Color3.fromRGB(255,194,97)},
        Coral = {Name="Koral", Color=Color3.fromRGB(255,135,180)},
        Glacier = {Name="Lodowiec", Color=Color3.fromRGB(121,195,255)},
    },
    MaxDesigns = 3,
    MaxStands = 3,
    MinScale = .7,
    MaxScale = 1.4,
    ScaleStep = .1,
}

for _, item in pairs(Catalog.Shapes) do table.freeze(item) end
for _, item in pairs(Catalog.Palettes) do table.freeze(item) end
table.freeze(Catalog.Shapes)
table.freeze(Catalog.Palettes)
table.freeze(Catalog.ShapeOrder)
table.freeze(Catalog.PaletteOrder)
return table.freeze(Catalog)
