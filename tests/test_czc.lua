--[[
================================================================================
  Testes do CullZoneCreator.lua  (nao precisa do GTA)
================================================================================
  Roda com Lua 5.1 / LuaJIT / qualquer Lua. Ele monta um ambiente falso do
  MoonLoader (incluindo uma memoria simulada nos enderecos do GTA SA 1.0 US) e
  testa a logica pura do script: geometria, IPL, save, live apply e interface.

  Uso:  lua tests/test_czc.lua      (ou)   luajit tests/test_czc.lua
        python3 tests/run_tests.py  (usa lupa, se nao houver lua instalado)
================================================================================
]]

local SCRIPT_PATH = arg and arg[1] or 'moonloader/CullZoneCreator.lua'

--=============================================================================
-- 1. MEMORIA SIMULADA (endereco -> byte)
--=============================================================================
local mem = {}

local function mem_set(addr, size, value)
    value = value % 4294967296
    for i = 0, size - 1 do
        mem[addr + i] = value % 256
        value = math.floor(value / 256)
    end
end

local function mem_get(addr, size)
    local v = 0
    for i = size - 1, 0, -1 do
        v = v * 256 + (mem[addr + i] or 0)
    end
    return v
end

function readMemory(addr, size, virtual_protect)
    return mem_get(addr, size)
end

function writeMemory(addr, size, value, virtual_protect)
    mem_set(addr, size, value)
end

--=============================================================================
-- 2. STUBS DO MOONLOADER
--=============================================================================
local calls = { draw_line = 0, draw_text = 0, draw_box = 0, shapes = 0 }

function script_name(name) end
function script_author(author) end
function script_version(version) end
function script_description(desc) end

function printStringNow(text, time) end
function getWorkingDirectory() return '/tmp/czc_test/moonloader' end
function getGameDirectory() return '/tmp/czc_test/gta' end
function doesFileExist(path) return false end
function doesDirectoryExist(path) return true end
function createDirectory(path) return true end
function getScreenResolution() return 1280, 720 end
function localClock() return os.clock() end
function isPauseMenuActive() return false end
function isPlayerPlaying(player) return true end
function doesCharExist(ped) return true end
function getCharCoordinates(ped) return 100.0, 200.0, 12.0 end
function setCharCoordinates(ped, x, y, z) end
function isKeyJustPressed(key) return false end
KEY_DOWN = {}                     -- teclas seguradas (controlado pelos testes)
function isKeyDown(key) return KEY_DOWN[key] == true end
function printStyledString(text, time, style) end
function getDistanceBetweenCoords2d(x1, y1, x2, y2)
    local dx, dy = x1 - x2, y1 - y2
    return math.sqrt(dx * dx + dy * dy)
end
function getDistanceBetweenCoords3d(x1, y1, z1, x2, y2, z2)
    local dx, dy, dz = x1 - x2, y1 - y2, z1 - z2
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end
function setClipboardText(text) return true end
function getClipboardText() return '' end
function consumeWindowMessage(a, b) end
function addEventHandler(name, fn) end

-- projecao fake: mundo -> pixels (bem simples, so para testar o desenho)
function convert3DCoordsToScreen(x, y, z)
    return 640 + x * 0.5, 360 - y * 0.5
end

function renderCreateFont(font, height, flags) return 7 end
function renderGetFontDrawTextLength(font, text) return #text * 6 end
function renderGetFontDrawHeight(font) return 12 end
function renderDrawLine(x1, y1, x2, y2, w, color) calls.draw_line = calls.draw_line + 1 end
function renderDrawBox(x, y, w, h, color) calls.draw_box = calls.draw_box + 1 end
function renderDrawBoxWithBorder(x, y, w, h, color, bs, bc) calls.draw_box = calls.draw_box + 1 end
function renderFontDrawText(font, text, x, y, color) calls.draw_text = calls.draw_text + 1 end

PLAYER_HANDLE = 1
PLAYER_PED = 2

--=============================================================================
-- 3. FAKE DO MOON IMGUI (registra as chamadas, devolve falsos)
--=============================================================================
local ui_calls = 0
local fake_imgui = setmetatable({}, {
    __index = function(t, key)
        local fn = function(...) ui_calls = ui_calls + 1 return false end
        rawset(t, key, fn)
        return fn
    end,
})
fake_imgui.ImBool = function(v) return { v = v and true or false } end
fake_imgui.ImFloat = function(v) return { v = v or 0 } end
fake_imgui.ImInt = function(v) return { v = v or 0 } end
fake_imgui.ImBuffer = function(size) return { v = '' } end
fake_imgui.ImVec2 = function(x, y) return { x = x or 0, y = y or 0 } end
fake_imgui.ImVec4 = function(x, y, z, w) return { x = x or 0, y = y or 0, z = z or 0, w = w or 0 } end
fake_imgui.Cond = { FirstUseEver = 4, Always = 1 }
fake_imgui.Process = false
fake_imgui.ShowCursor = false
fake_imgui.RenderInMenu = false
fake_imgui.OnDrawFrame = nil
package.loaded['imgui'] = fake_imgui

--=============================================================================
-- 4. FAKE DO MOONADDITIONS
--=============================================================================
local fake_shape = {
    clear = function(self) end,
    add_vertex = function(self, x, y, r, g, b, a) calls.shapes = calls.shapes + 1 end,
    draw = function(self, a, b, c, d) end,
    vertices_number = 0,
}
local fake_mad = {
    VERSION = 'test',
    shape = { new = function() return fake_shape end },
    primitive_type = { LINELIST = 1, TRIANGLELIST = 3 },
    blend_method = { SRCALPHA = 5, INVSRCALPHA = 6 },
    font_style = { GOTHIC = 1, SUBTITLES = 2, MENU = 3, PRICEDOWN = 4 },
    font_align = { CENTER = 1, LEFT = 2, RIGHT = 3 },
}
package.loaded['MoonAdditions'] = fake_mad

--=============================================================================
-- 5. CARREGA O SCRIPT
--=============================================================================
local hook
_G.CZC_TEST_HOOK = function(t) hook = t end

local chunk, err = loadfile(SCRIPT_PATH)
if not chunk then
    error('nao consegui carregar ' .. SCRIPT_PATH .. ': ' .. tostring(err))
end
local ok, loaderr = pcall(chunk)
if not ok then
    error('erro ao executar o script: ' .. tostring(loaderr))
end
if not hook then
    error('o hook de teste nao foi chamado')
end

--=============================================================================
-- 6. ASSERT
--=============================================================================
local passed, failed = 0, 0
local failures = {}

local function ok(cond, label, extra)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        failures[#failures + 1] = label .. (extra and ('  -> ' .. tostring(extra)) or '')
    end
end

local function near(a, b, eps, label)
    eps = eps or 0.001
    ok(type(a) == 'number' and math.abs(a - b) <= eps, label, string.format('%s ~= %s', tostring(a), tostring(b)))
end

--=============================================================================
-- 7. GEOMETRIA
--=============================================================================
do
    local z = hook.new_zone()
    z.cx, z.cy = -1940.89, 138.005
    z.zb, z.zt = 25.1618, 34.3618
    z.sx, z.sy = 0, 0
    z.hw, z.hl = 19.575, 27.2647

    local x1, y1, x2, y2, x3, y3, z1, z2 = hook.engine_box(z)
    ok(x1 == -1960 and y1 == 110, 'engine_box: x1/y1 truncados como no motor', x1 .. ',' .. y1)
    ok(x2 == 0 and y2 == 54, 'engine_box: x2/y2 = 2*skew / 2*Length', x2 .. ',' .. y2)
    ok(x3 == 39 and y3 == 0, 'engine_box: x3 = 2*Width', x3)
    ok(z1 == 25 and z2 == 34, 'engine_box: z1/z2 = Bottom/Top absolutos', z1 .. ',' .. z2)

    local corners = hook.zone_corners(z)
    ok(#corners == 4, 'zone_corners devolve 4 cantos')
    -- cantos: (-1960,110), (-1960,164), (-1921,164), (-1921,110)
    near(corners[1].x, -1960, 0.001, 'canto 1 x')
    near(corners[1].y, 110, 0.001, 'canto 1 y')
    near(corners[3].x, -1921, 0.001, 'canto 3 x')
    near(corners[3].y, 164, 0.001, 'canto 3 y')

    -- centro calculado pelo motor
    local cx, cy, cz = hook.zone_center_world(z)
    near(cx, -1940.5, 0.001, 'centro x (calculado)')
    near(cz, 29.5, 0.001, 'centro z (media de bottom/top)')

    -- ponto dentro/fora
    ok(hook.zone_contains(z, -1940, 138, 29), 'zone_contains: ponto dentro')
    ok(not hook.zone_contains(z, -1940, 138, 100), 'zone_contains: Z fora')
    ok(not hook.zone_contains(z, -1800, 138, 29), 'zone_contains: X fora')

    -- caixa com skew: mesmo modelo do motor (paralelogramo)
    local skew = hook.new_zone()
    skew.cx, skew.cy, skew.zb, skew.zt = 0, 0, 0, 10
    skew.hw, skew.hl, skew.sx, skew.sy = 20, 20, 40, 0
    ok(hook.zone_contains(skew, 0, 0, 5), 'skew: centro dentro')
    -- o skew joga a caixa para o lado: (30, 10) esta dentro dela...
    ok(hook.zone_contains(skew, 30, 10, 5), 'skew: ponto deslocado pelo skew dentro')
    -- ...mas estaria fora de uma caixa alinhada de 20x20
    local flat = hook.new_zone()
    flat.cx, flat.cy, flat.zb, flat.zt = 0, 0, 0, 10
    flat.hw, flat.hl, flat.sx, flat.sy = 20, 20, 0, 0
    ok(not hook.zone_contains(flat, 30, 10, 5), 'skew: o mesmo ponto esta fora da caixa alinhada')
    ok(not hook.zone_contains(skew, -60, 0, 5), 'skew: lado oposto fora')

    -- conversao retangulo+rotacao <-> parametros do IPL
    local nat = hook.view_to_native(30, 30, 0)
    near(nat.hw, 30, 0.001, 'view_to_native: sem rotacao hw = hx')
    near(nat.sx, 0, 0.001, 'view_to_native: sem rotacao sx = 0')
    local nat2 = hook.view_to_native(30, 30, 45)
    local hx, hy, ang = hook.native_to_view(nat2)
    near(hx, 30, 0.01, 'native_to_view: volta hx')
    near(hy, 30, 0.01, 'native_to_view: volta hy')
    near(ang, 45, 0.01, 'native_to_view: volta o angulo')
end

--=============================================================================
-- 8. IPL
--=============================================================================
do
    -- linha real do cull.ipl (zona sem chuva da versao original)
    local line = '-1940.89, 138.005, 25.1618, 0, 27.2647, 25.1618, 19.575, 0, 34.3618, 8, 0'
    local z = hook.parse_cull_line(line)
    ok(z ~= nil, 'parse_cull_line: leu a linha')
    near(z.cx, -1940.89, 0.001, 'parse: CenterX')
    near(z.cy, 138.005, 0.001, 'parse: CenterY')
    near(z.sx, 0, 0.001, 'parse: Unknown1 -> sx')
    near(z.hl, 27.2647, 0.001, 'parse: Length -> hl')
    near(z.zb, 25.1618, 0.001, 'parse: Bottom')
    near(z.hw, 19.575, 0.001, 'parse: Width -> hw')
    near(z.zt, 34.3618, 0.001, 'parse: Top')
    ok(z.flags == 8, 'parse: Flag = 8 (NoRain)', z.flags)
    ok(hook.has_flag(z.flags, hook.FLAGS[4].bit), 'flag NoRain reconhecido')

    -- linha com comentario e espacos
    local z2 = hook.parse_cull_line('  10, -20, 5, 0, 15, 0, 15, 0, 30, 8, 0  # teste')
    ok(z2 ~= nil and z2.cx == 10 and z2.flags == 8, 'parse_cull_line ignora comentario')

    -- variante sem o campo Unknown3 (10 campos)
    local z3 = hook.parse_cull_line('5, 6, 7, 0, 10, 0, 10, 0, 20, 8')
    ok(z3 ~= nil and z3.flags == 8 and z3.zt == 20, 'parse_cull_line: aceita 10 campos')

    -- linha invalida
    ok(hook.parse_cull_line('cull') == nil, 'parse_cull_line: texto sem numeros = nil')
    ok(hook.parse_cull_line('1, 2, 3') == nil, 'parse_cull_line: campos de menos = nil')

    -- geracao
    local zone = hook.new_zone()
    zone.cx, zone.cy, zone.zb, zone.zt = 100, 200, 10, 40
    zone.hw, zone.hl, zone.sx, zone.sy = 20, 30, 0, 0
    zone.flags = 8
    local out = hook.ipl_line(zone, false)
    ok(out:find('^100%.000, 200%.000, 25%.000'), 'ipl_line: centro e Z medio', out)
    ok(out:find(', 8, 0$') ~= nil, 'ipl_line: termina com o flag e Unknown3', out)
    local reparsed = hook.parse_cull_line(out)
    ok(reparsed ~= nil, 'ipl_line: a linha gerada e re-legivel')
    near(reparsed.hw, 20, 0.001, 'round-trip: Width')
    near(reparsed.zb, 10, 0.001, 'round-trip: Bottom')
    ok(reparsed.flags == 8, 'round-trip: flags')

    -- texto completo
    hook.state.zones = {}
    hook.add_zone(hook.new_zone(zone))
    local text, n = hook.build_ipl_text(hook.state.zones, { only_enabled = true })
    ok(n == 1, 'build_ipl_text: contou 1 zona', n)
    ok(text:find('\r\ncull\r\n') ~= nil, 'build_ipl_text: tem a secao cull')
    ok(text:find('\r\nend') ~= nil, 'build_ipl_text: fecha com end')
    ok(text:find('CULL ZONES') ~= nil, 'build_ipl_text: cabecalho')

    -- secao completa lida de volta
    local full = 'cull\n' .. line .. '\n10, -20, 5, 0, 15, 0, 15, 0, 30, 8, 0\nend\n'
    local zones = hook.parse_ipl_text(full)
    ok(#zones == 2, 'parse_ipl_text: 2 zonas', #zones)
    ok(zones[1].flags == 8 and zones[2].flags == 8, 'parse_ipl_text: flags')
end

--=============================================================================
-- 9. SAVE (serialize / deserialize)
--=============================================================================
do
    local data = {
        version = '1.0.0',
        settings = { live_apply = true, font_height = 9, keys = { menu = 118 } },
        zones = {
            { name = 'Zona "teste"', cx = 1.5, cy = -2.25, zb = 0, zt = 30, hw = 10, hl = 10, sx = 0, sy = 0, flags = 8 },
        },
    }
    local text = hook.serialize(data)
    ok(text:find('^return'), 'serialize: comeca com return')
    local back = hook.deserialize(text)
    ok(type(back) == 'table', 'deserialize: devolveu tabela')
    ok(back.settings.live_apply == true, 'deserialize: booleano')
    ok(back.settings.keys.menu == 118, 'deserialize: tabela aninhada')
    ok(back.zones[1].name == 'Zona "teste"', 'deserialize: string com aspas')
    near(back.zones[1].cy, -2.25, 0.0001, 'deserialize: numero negativo')
    ok(back.zones[1].flags == 8, 'deserialize: flags')
end

--=============================================================================
-- 10. UTILITARIOS
--=============================================================================
do
    ok(hook.to_ascii('Coracao') == 'Coracao', 'to_ascii: texto ascii passa igual')
    ok(hook.to_ascii('Posição: São Paulo') == 'Posicao: Sao Paulo', 'to_ascii: remove acentos',
        hook.to_ascii('Posição: São Paulo'))
    ok(hook.ctrunc(3.9) == 3 and hook.ctrunc(-3.1) == -3, 'ctrunc: truncagem igual ao cast do C')
    ok(hook.float_bits(1.0) == 0x3F800000, 'float_bits(1.0)', hook.float_bits(1.0))
    ok(hook.float_bits(-1.0) % 4294967296 == 0xBF800000, 'float_bits(-1.0)', hook.float_bits(-1.0))
    ok(hook.float_bits(0) == 0, 'float_bits(0)')
    ok(hook.float_bits(0.5) == 0x3F000000, 'float_bits(0.5)', hook.float_bits(0.5))

    -- escrever um float negativo na memoria nao pode estourar
    mem_set(0x1000, 4, hook.float_bits(-2.5) % 4294967296)
    local bits = hook.read_u32(0x1000)
    ok(bits % 4294967296 == hook.float_bits(-2.5) % 4294967296, 'float_bits: escrita na memoria', bits)
end

--=============================================================================
-- 11. LIVE APPLY (escrevendo na memoria simulada)
--=============================================================================
do
    local A = hook.A
    -- o "jogo" ja tem 2 zonas carregadas
    mem_set(A.NUM_ATTR_ZONES, 4, 2)
    mem_set(A.NUM_MIRROR_ZONES, 4, 0)
    mem_set(A.FLAGS_PLAYER, 4, 8)
    mem_set(A.WEATHER_OLD, 2, 8)
    for i = 0, 1 do
        local base = A.ATTR_ZONES + i * 18
        mem_set(base + 0, 2, -100 + i * 10)
        mem_set(base + 2, 2, -100)
        mem_set(base + 4, 2, 0)
        mem_set(base + 6, 2, 90)
        mem_set(base + 8, 2, 80)
        mem_set(base + 10, 2, 0)
        mem_set(base + 12, 2, 5)
        mem_set(base + 14, 2, 40)
        mem_set(base + 16, 2, 8)
    end

    ok(hook.init_memory() == true, 'init_memory: memoria reconhecida', hook.Game.error)

    -- cria 1 zona normal + 1 espelho
    local z = hook.new_zone()
    z.cx, z.cy, z.zb, z.zt = 100, 200, 10, 40
    z.hw, z.hl, z.sx, z.sy = 20, 30, 0, 0
    z.flags = 8
    local m = hook.new_zone()
    m.cx, m.cy, m.zb, m.zt = -50, -60, 0, 20
    m.hw, m.hl = 10, 10
    m.mirror = true
    m.cm = 2.5
    m.vx, m.vy, m.vz = 1, 0, 0
    m.flags = 8

    hook.state.zones = {}
    hook.add_zone(z)
    hook.add_zone(m)
    hook.state.live_apply = true
    hook.live_apply(true)

    ok(hook.Game.applied == 2, 'live_apply: aplicou 2 zonas', hook.Game.applied)
    ok(hook.read_u32(A.NUM_ATTR_ZONES) == 3, 'live_apply: contador do motor = 2 + 1',
        hook.read_u32(A.NUM_ATTR_ZONES))
    ok(hook.read_u32(A.NUM_MIRROR_ZONES) == 1, 'live_apply: contador de espelhos = 1',
        hook.read_u32(A.NUM_MIRROR_ZONES))

    -- a zona foi escrita no formato do motor?
    local base = A.ATTR_ZONES + 2 * 18
    local function rs16(a)
        local v = mem_get(a, 2)
        if v >= 32768 then v = v - 65536 end
        return v
    end
    ok(rs16(base + 0) == 80, 'live_apply: x1 = cx - sx - hw', rs16(base + 0))
    ok(rs16(base + 2) == 170, 'live_apply: y1 = cy - hl - sy', rs16(base + 2))
    ok(rs16(base + 4) == 0, 'live_apply: x2 = 2*sx')
    ok(rs16(base + 6) == 60, 'live_apply: y2 = 2*Length')
    ok(rs16(base + 8) == 40, 'live_apply: x3 = 2*Width')
    ok(rs16(base + 10) == 0, 'live_apply: y3 = 2*sy')
    ok(rs16(base + 12) == 10 and rs16(base + 14) == 40, 'live_apply: Bottom/Top')
    ok(mem_get(base + 16, 2) == 8, 'live_apply: flags = 8', mem_get(base + 16, 2))

    -- escrita com coordenadas negativas (complemento de dois)
    local neg = hook.new_zone()
    neg.cx, neg.cy, neg.zb, neg.zt = -1500.7, -800.2, -5.5, 20.5
    neg.hw, neg.hl = 12.5, 25.5
    neg.flags = 8
    hook.add_zone(neg)
    hook.state.live_apply = true
    hook.live_apply(true)
    local nbase = A.ATTR_ZONES + 3 * 18
    ok(rs16(nbase + 0) == -1513, 'live_apply: x1 negativo truncado', rs16(nbase + 0))
    ok(rs16(nbase + 2) == -825, 'live_apply: y1 negativo truncado', rs16(nbase + 2))
    ok(rs16(nbase + 6) == 51, 'live_apply: y2 = 2*Length', rs16(nbase + 6))
    ok(rs16(nbase + 8) == 25, 'live_apply: x3 = 2*Width', rs16(nbase + 8))
    ok(rs16(nbase + 12) == -5, 'live_apply: Bottom negativo', rs16(nbase + 12))
    table.remove(hook.state.zones)
    hook.live_apply(true)

    -- o espelho: Cm em float (bits) + direcao + flags
    local mbase = A.MIRROR_ZONES + 0 * 24
    ok(mem_get(mbase + 16, 4) == hook.float_bits(2.5), 'live_apply: Cm gravado como float',
        mem_get(mbase + 16, 4))
    ok(mem_get(mbase + 20, 1) == 1 and mem_get(mbase + 21, 1) == 0 and mem_get(mbase + 22, 1) == 0,
        'live_apply: direcao do espelho')
    ok(mem_get(mbase + 23, 1) == 8, 'live_apply: flags do espelho')
    ok(rs16(mbase + 8) == 20, 'live_apply: espelho x3 = 2*Width', rs16(mbase + 8))

    -- status lido da memoria
    local st = hook.query_game_status()
    ok(st ~= nil and st.flags_player == 8, 'query_game_status: flags do jogador', st and st.flags_player)
    ok(st and st.weather == 8, 'query_game_status: clima', st and st.weather)
    ok(st and st.attr_count == 3, 'query_game_status: contagem', st and st.attr_count)

    -- leitura das zonas do jogo (nao deve incluir as nossas)
    local n = hook.scan_game_zones(0, 0, 100000, 100)
    ok(n == 2, 'scan_game_zones: leu as 2 zonas originais', n)
    ok(hook.state.game_zones[1].flags == 8, 'scan_game_zones: flags lidas')
    near(hook.state.game_zones[1].hw, 40, 0.001, 'scan_game_zones: Width = x3/2')

    -- desligar o live volta tudo ao original
    hook.state.live_apply = false
    hook.live_apply(true)
    ok(hook.read_u32(A.NUM_ATTR_ZONES) == 2, 'live_reset: contador voltou a 2', hook.read_u32(A.NUM_ATTR_ZONES))
    ok(hook.read_u32(A.NUM_MIRROR_ZONES) == 0, 'live_reset: espelhos voltaram a 0', hook.read_u32(A.NUM_MIRROR_ZONES))

    -- modo seguro nao mexe em nada
    hook.state.dry_run = true
    ok(hook.init_memory() == false, 'dry_run: memoria desligada no modo seguro')
    hook.state.dry_run = false
    ok(hook.init_memory() == true, 'init_memory: volta a ligar depois do modo seguro')

    -- jogo com enderecos esquisitos (versao diferente) -> desliga sozinho
    mem_set(A.NUM_ATTR_ZONES, 4, 99999)
    ok(hook.init_memory() == false, 'init_memory: detecta uma versao de jogo diferente')
    mem_set(A.NUM_ATTR_ZONES, 4, 2)
    hook.init_memory()
end

--=============================================================================
-- 12. DESENHO + INTERFACE (smoke test)
--=============================================================================
do
    hook.draw_init()
    ok(hook.Draw.font ~= nil, 'draw_init: fonte criada')
    ok(hook.Draw.shape ~= nil, 'draw_init: shape do MoonAdditions')

    hook.state.player = { x = 100.0, y = 200.0, z = 12.0 }
    hook.state.overlays = true
    hook.state.hud = true
    hook.state.show_ground = true
    hook.state.zones = {}
    local z = hook.new_zone()
    z.cx, z.cy, z.zb, z.zt = 100, 200, 0, 40
    z.hw, z.hl = 25, 25
    z.flags = 8
    hook.add_zone(z)
    hook.state.game_zones = {}

    hook.draw_begin()
    local ok_overlay = pcall(hook.build_overlay)
    ok(ok_overlay, 'build_overlay: rodou sem erro')
    local ok_hud = pcall(hook.build_hud)
    ok(ok_hud, 'build_hud: rodou sem erro')

    calls.draw_line, calls.draw_text, calls.draw_box, calls.shapes = 0, 0, 0, 0
    local ok_present = pcall(hook.draw_present)
    ok(ok_present, 'draw_present: rodou sem erro')
    ok(calls.draw_line > 0, 'draw_present: desenhou linhas da caixa', calls.draw_line)
    ok(calls.draw_text > 0, 'draw_present: desenhou textos do HUD', calls.draw_text)
    ok(calls.draw_box > 0, 'draw_present: desenhou o painel do HUD', calls.draw_box)
    ok(calls.shapes > 0, 'draw_present: preencheu a area (MoonAdditions)', calls.shapes)

    -- interface
    hook.state.ui_show = true
    hook.ui.show = fake_imgui.ImBool(true)
    ui_calls = 0
    local ok_ui = pcall(hook.build_ui)
    ok(ok_ui, 'build_ui: rodou sem erro', ok_ui and '' or tostring(select(2, pcall(hook.build_ui))))
    ok(ui_calls > 0, 'build_ui: chamou funcoes do ImGui', ui_calls)

    -- zona sem nome / sem lista tambem nao pode quebrar
    hook.state.zones = {}
    ok(pcall(hook.build_ui), 'build_ui: funciona com a lista vazia')
    hook.state.zones = { z }
end

--=============================================================================
-- 13. EXPORTACAO EM ARQUIVO (ida e volta)
--=============================================================================
do
    local TMP = '/tmp/czc_test_export.ipl'
    hook.state.zones = {}
    local z = hook.new_zone()
    z.name = 'Zona de teste'
    z.cx, z.cy, z.zb, z.zt = 1.5, 2.5, 3.5, 40.5
    z.hw, z.hl, z.sx, z.sy = 15, 25, 0, 0
    z.flags = 8
    hook.add_zone(z)
    hook.state.only_enabled = true

    local okk, path, n = hook.export_ipl(TMP)
    ok(okk == true, 'export_ipl: gravou o arquivo', path)
    ok(n == 1, 'export_ipl: contou 1 zona', n)

    local f = io.open(path, 'rb')
    local data = f and f:read('*a') or nil
    if f then f:close() end
    ok(data ~= nil, 'export_ipl: arquivo ilegivel')
    ok(data and data:find('\r\ncull\r\n') ~= nil, 'export_ipl: secao cull no arquivo')
    ok(data and data:find('\r\n1%.500, 2%.500, 22%.000, 0%.000000, 25%.000000, 3%.500, 15%.000000, 0%.000000, 40%.500, 8, 0') ~= nil,
        'export_ipl: linha com os campos na ordem do IPL', data and data:match('([^\r\n]+)%.000, 8, 0'))

    hook.state.zones = {}
    local imported = hook.import_from_text(data)
    ok(imported == 1, 'import_from_text: releu a zona exportada', imported)
    ok(hook.state.zones[1] ~= nil and hook.state.zones[1].flags == 8, 'import_from_text: flags preservadas')
    ok(hook.state.zones[1] ~= nil and hook.state.zones[1].hw == 15, 'import_from_text: Width preservado',
        hook.state.zones[1] and hook.state.zones[1].hw)

    ok(pcall(hook.import_from_file, TMP), 'import_from_file: rodou sem erro')
    os.remove(TMP)
end

--=============================================================================
-- 14. ATALHO C + L / ABRIR E FECHAR O MENU
--=============================================================================
do
    local C, L = 0x43, 0x4C
    KEY_DOWN = {}
    hook.state.open_combo = { C, L }
    hook.state.open_combo_enabled = true
    hook.state.ui_show = false
    hook.ui.show = fake_imgui.ImBool(false)

    ok(hook.key_name(C) == 'C' and hook.key_name(L) == 'L', 'key_name: C e L', hook.key_name(C) .. hook.key_name(L))
    ok(hook.key_name(0) == 'nenhuma', 'key_name: 0 = nenhuma')
    ok(hook.key_name(0x70) == 'F1', 'key_name: F1')

    -- soh C ou soh L nao abre
    KEY_DOWN[C] = true
    hook.handle_open_combo()
    ok(hook.state.ui_show == false, 'só C (ou só L) NAO abre o menu')
    KEY_DOWN[L] = true
    hook.handle_open_combo()
    ok(hook.state.ui_show == true, 'C + L abre o menu')
    ok(hook.ui.show.v == true, 'o X/ImGui fica sabendo que o menu esta aberto')

    -- continuar segurando nao fica reabrindo
    hook.handle_open_combo()
    hook.handle_open_combo()
    ok(hook.state.ui_show == true, 'segurar C + L nao fica alternando o menu')

    -- fecha no X segurando C + L ainda: nao pode reabrir na hora
    KEY_DOWN[C] = true
    KEY_DOWN[L] = true
    hook.handle_open_combo()
    hook.ui.show.v = false
    hook.state.ui_show = false
    hook.handle_open_combo()
    ok(hook.state.ui_show == false, 'fechar no X com C + L segurado nao reabre o menu')
    hook.handle_open_combo()
    ok(hook.state.ui_show == false, 'segurando C + L o menu continua fechado')

    -- solta e aperta de novo: abre
    KEY_DOWN = {}
    hook.handle_open_combo()
    ok(hook.state.ui_show == false, 'menu fechado continua fechado')
    KEY_DOWN[C] = true
    KEY_DOWN[L] = true
    hook.handle_open_combo()
    ok(hook.state.ui_show == true, 'soltar C + L e apertar de novo reabre o menu')
    hook.set_ui(false)
    KEY_DOWN = {}

    -- solta as teclas (um frame) e aperta de novo: abre outra vez
    hook.handle_open_combo()
    ok(hook.state.ui_show == false, 'com as teclas soltas o menu continua fechado')
    KEY_DOWN[C] = true
    KEY_DOWN[L] = true
    hook.handle_open_combo()
    ok(hook.state.ui_show == true, 'soltar e apertar C + L de novo abre o menu')

    -- desligar o atalho: C + L nao abre mais
    hook.set_ui(false)
    KEY_DOWN = {}
    hook.handle_open_combo()
    hook.state.open_combo_enabled = false
    KEY_DOWN[C] = true
    KEY_DOWN[L] = true
    hook.handle_open_combo()
    ok(hook.state.ui_show == false, 'atalho desligado nao abre o menu')
    hook.state.open_combo_enabled = true

    -- toggle (usado pelo atalho extra) e o botao "Fechar menu"
    hook.set_ui(false)
    hook.toggle_ui()
    ok(hook.state.ui_show == true, 'toggle_ui abre')
    hook.toggle_ui()
    ok(hook.state.ui_show == false, 'toggle_ui fecha')

    -- atalhos extras desligados por padrao nao quebram
    KEY_DOWN = {}
    ok(pcall(hook.handle_keys), 'handle_keys: sem atalhos configurados nao quebra')
    ok(hook.state.keys.menu == 0 and hook.state.keys.new_zone == 0, 'atalhos extras comecam desligados')
    ok(hook.key_just_pressed(0) == false, 'tecla 0 (nenhuma) nunca dispara')
end

--=============================================================================
-- 15. TROCAR A TECLA DO ATALHO (onWindowMessage)
--=============================================================================
do
    local WM_KEYDOWN, WM_KEYUP, WM_LBUTTONDOWN = 0x100, 0x101, 0x201
    hook.state.open_combo = { 0x43, 0x4C }

    -- sem captura, nada acontece
    hook.state.capture = nil
    hook.handle_window_message(WM_KEYDOWN, 0x4B)
    ok(hook.state.open_combo[1] == 0x43, 'sem captura o atalho nao muda')

    -- captura a 1a tecla: aperta K
    hook.state.capture = 'open1'
    hook.handle_window_message(WM_KEYDOWN, 0x4B)
    ok(hook.state.capture == nil, 'captura terminou')
    ok(hook.state.open_combo[1] == 0x4B, 'primeira tecla trocada para K', hook.state.open_combo[1])
    ok(hook.state.combo_was_down == true, 'nao abre o menu com a tecla recem escolhida')

    -- so WM_KEYDOWN vale (KEYUP e clique de mouse sao ignorados)
    hook.state.capture = 'open2'
    hook.handle_window_message(WM_KEYUP, 0x50)
    hook.handle_window_message(WM_LBUTTONDOWN, 0x50)
    ok(hook.state.capture == 'open2', 'ignora KEYUP e mouse na captura')
    -- Shift/Ctrl/Alt sozinhos tambem sao ignorados
    hook.handle_window_message(WM_KEYDOWN, 0x10)
    ok(hook.state.capture == 'open2', 'ignora Shift sozinho')
    hook.handle_window_message(WM_KEYDOWN, 0x50)
    ok(hook.state.open_combo[2] == 0x50, 'segunda tecla trocada para P', hook.state.open_combo[2])

    -- ESC cancela
    hook.state.capture = 'open1'
    hook.handle_window_message(WM_KEYDOWN, 0x1B)
    ok(hook.state.capture == nil and hook.state.open_combo[1] == 0x4B, 'ESC cancela a troca de tecla')

    hook.state.open_combo = { 0x43, 0x4C }
end

--=============================================================================
-- 16. RESULTADO
--=============================================================================
print(string.format('\n[test_czc] %d testes OK, %d falhas', passed, failed))
if failed > 0 then
    for _, f in ipairs(failures) do
        print('  FALHOU: ' .. f)
    end
    error(string.format('%d teste(s) falharam', failed))
end
print('[test_czc] todos os testes passaram.')
