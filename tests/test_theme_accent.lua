-- The guild's colors: the same vectors as ngm-hub's test/accent.test.ts
local ns = {}
local ROOT = arg[1] or ".."
assert(loadfile(ROOT .. "/Core/Accent.lua"))("NootropicGuildManager", ns)
local A = ns.Accent
local function same(p, want, what)
    for k, v in pairs(want) do assert(p[k] == v, ("%s %s: got %s, want %s"):format(what, k, tostring(p[k]), tostring(v))) end
end
-- Nootropic: black cloth, purple band, green emblem
same(A.Palette("232323", "6d0077", "376700"), { accent = "85d629", accent2 = "aad629", bar = "7e2786", mgr = "cf47dc", cloth = "232323", band = "6d0077", herald = false }, "Nootropic")
same(A.Palette("2f6b34", "c99a3e", "ffffff"), { accent = "46b950", accent2 = "55b946", bar = "255529", mgr = "c79738" }, "green and gold")
same(A.Palette("f0f0f0", "1a3a8a", "1a3a8a"), { accent = "5c82e0", bar = "274286" }, "white and navy")
assert(A.Palette("f0f0f0", "1a3a8a", "1a3a8a").mgr == nil, "one hue: no managers' color")
same(A.Palette("101010", "101010", "c02020"), { accent = "df5858", bar = "862727" }, "all black, red emblem")
same(A.Palette("d8b030", "6a3a10", "202020"), { accent = "d6ad29", bar = "5b4c1a" }, "bright yellow")
-- no hue, no tabard, nonsense: herald blue
local blue = { accent = "5886cb", accent2 = "3d8ec2", bar = "294e84", herald = true }
same(A.Palette(nil, nil), blue, "no tabard"); same(A.Palette(nil, nil), { cloth = "2a4f86", band = "12264a" }, "no tabard")
same(A.Palette("f0f0f0", "111111", nil), blue, "no hue"); same(A.Palette("f0f0f0", "111111", nil), { cloth = "f0f0f0", band = "111111" }, "no hue")
same(A.Palette("zzzzzz", nil), blue, "nonsense")
-- the same answers as NGM Peon, for 40 random tabards (bg border emblem -> accent accent2 bar mgr)
local VECTORS = [[
68dadb b61980  31cdce 31ceae 195657 dd4bab
4e0b80 bc15c0 35f300 4fd629 73d629 5e2786 d73eda
02a700 034b00 411f00 d67b29 d96136 1a5719 30d629
2c6340 a3f200 8a3a00 d67229 da5f3e 265537 9ed629
86e240 de0500  74d629 98d629 345719 de5754
0e5100 c6ad00 4dd900 66d629 8bd629 245719 d6c029
439500 2ca100 0ebd00 36d629 5ad629 355719 
dca900 722540 738c00 b7d629 d6d129 5b4c1a cc6187
dacc00 510c00  d6cb29 d6a729 534f18 dc5d47
2a4c00 2a8c00 c5cc00 d0d629 d6b829 395318 5dd629
600c00 8d4c40 e52700 db5c43 df585d 863327 
73cb00 279f00 50e340 3ad629 5ed629 395318 
2e7200 82ba00  6fd629 93d629 325719 
556200 36ea00 add200 b8d629 d6d029 484f17 51d629
fe9a00 53c200 c5ca00 d2d629 d6b629 63471d 73d629
c33240 ec1500 eb2100 dc5c47 df5861 862730 
2b3d00 ff2900  a3d629 c7d629 425318 db5b43
22a500 067100 2c4d40 46b98c 46b974 265719 32d629
e69400 453400 4f5400 ccd629 d6bc29 634a1d d6ab29
5ef400 c61440 024f80 2993d6 29b7d6 315719 de5476
350980 7a3b80  996de3 8876e5 4a2786 bc64c4
2c8600 c93e00 939600 d3d629 d6b529 2e5719 d7622d
8b0e00 792600 295e00 74d629 99d629 863127 d7622d
413600 382e00 efc600 d6b829 d69429 574d19 
6b7e40 bc7100  96b946 aeb946 455328 d69129
aa4d00 f8f940 73d080 40bf52 49bf40 6f4420 d5d629
d6f600 7aee00 db8640 d67729 d95d36 484f17 82d629
dfd900 6d9500 0ea100 38d629 5cd629 4f4e17 a8d629
48bd39 b61f7c  4bc43b 67c43b 21561a dd4ba5
0b6000 181040 b29b80 b98446 bc724e 205719 8978dd
6d6600 a89e00 ef7600 d67e29 d86131 534f18 d6cc29
e96e00 e80640 325900 8ad629 afd629 6b431f de5477
8e1400 96b400  dc5c47 df5861 863427 b9d629
02d400 cc7400 659400 9fd629 c4d629 1a5719 d68b29
583400 665400 29f400 46d629 6ad629 63461d d6b829
351400 b1b440 156f00 4ad629 6ed629 734021 b9bc43
f27300 452740  d67b29 d96136 6b431f c360b2
e76600 9a9e00 f97640 d86231 de5b4f 6f4320 d2d629
bf0978 09c800 1a5800 5cd629 80d629 862761 
07a840 065300 fb8700 d68629 d66229 19572f 35d629
]]
local n = 0
for line in VECTORS:gmatch("[^\n]+") do
    local f = {}
    for w in (line .. " "):gmatch("(%x*) ") do f[#f + 1] = w end
    local p = A.Palette(f[1], f[2], f[3] ~= "" and f[3] or nil)
    same(p, { accent = f[4], accent2 = f[5], bar = f[6] }, line)
    assert((p.mgr or "") == f[7], line .. " mgr: got " .. tostring(p.mgr))
    n = n + 1
end
assert(n == 40, "vectors read: " .. n)
-- reads on any tabard
math.randomseed(7)
local function color() return ("%06x"):format(math.random(0, 16777215)) end
for _ = 1, 2000 do
    local p = A.Palette(color(), color(), math.random() < 0.2 and nil or color())
    assert(A.Contrast(p.accent, "121110") >= 5 and A.Contrast(p.accent2, "121110") >= 5, "accent reads")
    assert(not p.mgr or A.Contrast(p.mgr, "121110") >= 5, "managers' color reads")
    assert(A.Contrast("f2ecd9", p.bar) >= 7, "bar reads")
end
print("OK")
