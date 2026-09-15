--[[
================================================================================
  CULL ZONE CREATOR  -  GTA San Andreas
  MoonLoader + MoonAdditions + Moon ImGui 1.1.5
================================================================================

  Cria, edita, testa e exporta CULL ZONES (as zonas onde o jogo pode desligar
  a chuva, a policia, os pedestres...). GUI in-game, visualizacao 3D em tempo
  real e exportacao para arquivo .IPL.

  O uso mais comum e o flag NO_RAIN (bit 8) = zona onde NAO CHOVE
  (e onde tambem nao aparece helicoptero da policia).

--------------------------------------------------------------------------------
  COMO USAR
--------------------------------------------------------------------------------
    ABRIR O MENU  : segure C + L (as duas juntas)
    FECHAR O MENU : clique no X no canto superior direito da janela

    Dentro do menu esta tudo, em botoes:
      - Nova zona no player (salva a posicao atual)
      - Aplicar no jogo (live apply)  -> efeito na hora, sem reiniciar
      - Overlay 3D + HUD
      - Exportar IPL / Pacote ModLoader
      - Ler as cull zones que o jogo ja tem e copiar como base
      - Salvar/carregar config, trocar as teclas do atalho...

    1) Va ate o lugar (de carro, helicoptero...).
    2) Abra o menu (C + L) e clique em "Nova zona no player".
    3) Ajuste centro, tamanho (metros) e altura (Z) e marque o flag NO_RAIN.
       Com o live apply ligado o efeito e imediato: ande para dentro e para
       fora e veja no HUD o aviso "SEM CHUVA".
    4) Clique em "Exportar IPL" (ou "Pacote ModLoader") e registre o .ipl no
       data\gta.dat - ou copie a pasta modloader\CullZoneCreator que o script
       gera com cull.ipl + gta.dat prontos.

--------------------------------------------------------------------------------
  FORMATO IPL - SECAO CULL
--------------------------------------------------------------------------------
    cull
    CenterX, CenterY, CenterZ, Unknown1, Length, Bottom, Width, Unknown2, Top, Flag, Unknown3
    end

    CenterX/Y/Z = centro da caixa (o jogo usa X/Y; CenterZ e ignorado pelo motor)
    Length      = metade do tamanho no eixo Y      | Width  = metade no eixo X
    Bottom/Top  = Z absoluto do mundo (inteiros)
    Unknown1/2  = "skew" (cisalhamento/rotacao) da caixa, 0 = caixa alinhada
    Flag        = bitmask de atributos (ver FLAGS abaixo)
    Unknown3    = 0

    O jogo guarda a zona como 8 shorts (CZoneDef):
        x1 = cx - Unknown1 - Width    x2 = 2 * Unknown1
        y1 = cy - Length   - Unknown2 y2 = 2 * Length
        x3 = 2 * Width                y3 = 2 * Unknown2
        z1 = Bottom                   z2 = Top
    ou seja: um PARALELOGRAMO centrado no centro informado, com arestas
    A = (x2, y2) e B = (x3, y3) - e exatamente isso que o script desenha.

--------------------------------------------------------------------------------
  OBSERVACOES IMPORTANTES
--------------------------------------------------------------------------------
  * Os enderecos de memoria usados pelo "live apply" sao do GTA SA 1.0 US.
    Em outra versao o script detecta e desliga a memoria sozinho (o IPL
    continua funcionando normalmente).
  * Cull zone de IPL so passa a valer quando o jogo carrega o mapa. O live
    apply existe justamente para testar na hora, sem reiniciar.
  * O live apply NAO e salvo no jogo: e temporario. O que fica salvo e o IPL.
================================================================================
]]

local VERSION = '1.0.0'

script_name('Cull Zone Creator')
script_author('Viniciaao')
script_version(VERSION)
script_description('Cria/edita/testa cull zones (ex.: zonas sem chuva) com GUI in-game, overlay 3D e exportacao IPL.')

--=============================================================================
-- MODULOS
--=============================================================================
local ok_imgui, imgui = pcall(require, 'imgui')          -- Moon ImGui (obrigatorio)
local ok_mad, mad = pcall(require, 'MoonAdditions')      -- opcional (preenchimento)
local ok_vkeys, vkeys = pcall(require, 'vkeys')
local ok_moon, moonlib = pcall(require, 'moonloader')
local ok_wm, wm = pcall(require, 'windows.message')

if not ok_vkeys or not vkeys then
    -- teclas usadas quando o modulo 'vkeys' nao esta disponivel
    vkeys = {
        VK_F1 = 0x70, VK_F2 = 0x71, VK_F3 = 0x72, VK_F4 = 0x73, VK_F5 = 0x74,
        VK_F6 = 0x75, VK_F7 = 0x76, VK_F8 = 0x77, VK_F9 = 0x78, VK_F10 = 0x79,
        VK_F11 = 0x7A, VK_F12 = 0x7B, VK_INSERT = 0x2D, VK_DELETE = 0x2E,
        VK_C = 0x43, VK_L = 0x4C, VK_A = 0x41, VK_M = 0x4D,
    }
end

-- mensagens do Windows usadas para capturar a tecla do atalho
local WM_KEYDOWN = (ok_wm and wm and wm.WM_KEYDOWN) or 0x100
local WM_SYSKEYDOWN = (ok_wm and wm and wm.WM_SYSKEYDOWN) or 0x104

-- nome das teclas (para mostrar no menu/HUD)
local VK_NAMES = {}
for i = 0, 25 do VK_NAMES[0x41 + i] = string.char(65 + i) end
for i = 0, 9 do VK_NAMES[0x30 + i] = tostring(i) end
for i = 1, 12 do VK_NAMES[0x70 + i - 1] = 'F' .. i end
VK_NAMES[0x20] = 'Espaco'
VK_NAMES[0x0D] = 'Enter'
VK_NAMES[0x09] = 'Tab'
VK_NAMES[0x10] = 'Shift'
VK_NAMES[0x11] = 'Ctrl'
VK_NAMES[0x12] = 'Alt'
VK_NAMES[0x1B] = 'ESC'
VK_NAMES[0x25] = 'Esquerda'
VK_NAMES[0x26] = 'Cima'
VK_NAMES[0x27] = 'Direita'
VK_NAMES[0x28] = 'Baixo'
VK_NAMES[0x2D] = 'Insert'
VK_NAMES[0x2E] = 'Delete'
VK_NAMES[0x24] = 'Home'
VK_NAMES[0x23] = 'End'
VK_NAMES[0x2C] = 'Print'

local function key_name(vk)
    if not vk or vk == 0 then return 'nenhuma' end
    return VK_NAMES[vk] or ('tecla ' .. tostring(vk))
end

local bit = bit or require 'bit'

local TAG = '[CullZoneCreator] '

--=============================================================================
-- ENDERECOS DE MEMORIA (GTA SA 1.0 US)
--=============================================================================
local A = {
    NUM_ATTR_ZONES   = 0xC87AC8,   -- int  CCullZones::NumAttributeZones
    ATTR_ZONES       = 0xC81F50,   -- CCullZone aAttributeZones[1300]  (18 bytes cada)
    NUM_MIRROR_ZONES = 0xC87AC4,   -- int  CCullZones::NumMirrorAttributeZones
    MIRROR_ZONES     = 0xC815C0,   -- CCullZoneReflection aMirrorAttributeZones[72] (24 bytes)
    FLAGS_PLAYER     = 0xC87AB8,   -- int  CCullZones::CurrentFlags_Player
    FLAGS_CAMERA     = 0xC87ABC,   -- int  CCullZones::CurrentFlags_Camera
    WEATHER_OLD      = 0xC81320,   -- short CWeather::OldWeatherType (clima atual)
    WEATHER_NEW      = 0xC8131C,   -- short CWeather::NewWeatherType
}

local ATTR_ZONES_MAX = 1300
local MIRROR_ZONES_MAX = 72

--=============================================================================
-- FLAGS (CCullZones::eZoneAttributes)
--=============================================================================
local FLAGS = {
    { bit = 0x0001, name = 'CamCloseIn',    short = 'CamCloseIn',   desc = 'Camera cola no jogador (bem perto); nao da para trocar de camera dentro da zona.' },
    { bit = 0x0002, name = 'CamStairs',     short = 'CamStairs',    desc = 'Camera travada: ela fica parada observando o jogador se afastar.' },
    { bit = 0x0004, name = 'Cam1stPerson',  short = 'Cam1stPerson', desc = 'Desliga a camera estilo GTA2 / abaixa o angulo em barcos.' },
    { bit = 0x0008, name = 'NoRain',        short = 'NoRain',       desc = 'SEM CHUVA dentro da zona (e tambem sem helicoptero da policia). O flag mais usado.' },
    { bit = 0x0010, name = 'NoPolice',      short = 'NoPolice',     desc = 'Policiais nao descem dos carros por vontade propria e nao perseguem a pe.' },
    { bit = 0x0040, name = 'DoINeedToLoadCollision', short = 'LoadCollision', desc = 'Carrega colisao dentro da zona (raro; nao usar sem saber o que faz).' },
    { bit = 0x0100, name = 'PoliceAbandonCars', short = 'PoliceAbandonCars', desc = 'Policiais sempre saem do carro quando spawnados (em perseguicao).' },
    { bit = 0x0200, name = 'InRoomsForAudio', short = 'InRoomsAudio', desc = 'Audio como se estivesse em um ambiente fechado (eco/abafado).' },
    { bit = 0x0400, name = 'InRoomsFewerPeds', short = 'FewerPeds',  desc = 'Menos pedestres aparecem na area.' },
    { bit = 0x1000, name = 'MilitaryZone',  short = 'MilitaryZone', desc = 'Zona militar: 5 estrelas de procurado se o jogador entrar.' },
    { bit = 0x4000, name = 'ExtraAirResistance', short = 'AirResist', desc = 'Veiculos nao chegam na velocidade maxima (mais resistencia do ar).' },
    { bit = 0x8000, name = 'FewerCars',     short = 'FewerCars',    desc = 'Spawna menos carros na area.' },
}

local FLAG_NORAIN = 0x0008
local FLAG_ALL = 0xFFFF

--=============================================================================
-- NOMES DO CLIMA (CWeather::eWeatherType)
--=============================================================================
local WEATHER_NAMES = {
    [0] = 'ExtraSunny LA', [1] = 'Sunny LA', [2] = 'ExtraSunny Smog LA',
    [3] = 'Sunny Smog LA', [4] = 'Cloudy LA', [5] = 'Sunny SF',
    [6] = 'ExtraSunny SF', [7] = 'Cloudy SF', [8] = 'Rainy SF',
    [9] = 'Foggy SF', [10] = 'Sunny LV', [11] = 'ExtraSunny LV',
    [12] = 'Cloudy LV', [13] = 'ExtraSunny Countryside', [14] = 'Sunny Countryside',
    [15] = 'Cloudy Countryside', [16] = 'Rainy Countryside',
    [17] = 'ExtraSunny Desert', [18] = 'Sunny Desert', [19] = 'Sandstorm Desert',
    [20] = 'Underwater', [21] = 'ExtraColours 1', [22] = 'ExtraColours 2',
}

--=============================================================================
-- UTILITARIOS
--=============================================================================
local function log(fmt, ...)
    if select('#', ...) > 0 then
        print(string.format(TAG .. fmt, ...))
    else
        print(TAG .. fmt)
    end
end

local function clamp(v, min, max)
    if v < min then return min end
    if v > max then return max end
    return v
end

-- truncagem igual ao cast (short) do C
local function ctrunc(v)
    if not v then return 0 end
    if v >= 0 then return math.floor(v) end
    return math.ceil(v)
end

local function has_flag(flags, b)
    return bit.band(ctrunc(flags), b) ~= 0
end

local function flag_list(flags)
    local out = {}
    for _, f in ipairs(FLAGS) do
        if has_flag(flags, f.bit) then out[#out + 1] = f.name end
    end
    if #out == 0 then return 'nenhum' end
    return table.concat(out, ' | ')
end

local function now_string()
    return os.date('%d/%m/%Y %H:%M')
end

-- converte UTF-8 (acentos) para ASCII: as fontes do jogo nao entendem UTF-8
local UTF8_MAP = {
    ['\195\160'] = 'a', ['\195\161'] = 'a', ['\195\162'] = 'a', ['\195\163'] = 'a', ['\195\164'] = 'a', ['\195\165'] = 'a',
    ['\195\128'] = 'A', ['\195\129'] = 'A', ['\195\130'] = 'A', ['\195\131'] = 'A', ['\195\132'] = 'A', ['\195\133'] = 'A',
    ['\195\167'] = 'c', ['\195\135'] = 'C',
    ['\195\168'] = 'e', ['\195\169'] = 'e', ['\195\170'] = 'e', ['\195\171'] = 'e',
    ['\195\136'] = 'E', ['\195\137'] = 'E', ['\195\138'] = 'E', ['\195\139'] = 'E',
    ['\195\172'] = 'i', ['\195\173'] = 'i', ['\195\174'] = 'i', ['\195\175'] = 'i',
    ['\195\140'] = 'I', ['\195\141'] = 'I', ['\195\142'] = 'I', ['\195\143'] = 'I',
    ['\195\178'] = 'o', ['\195\179'] = 'o', ['\195\180'] = 'o', ['\195\181'] = 'o', ['\195\182'] = 'o',
    ['\195\146'] = 'O', ['\195\147'] = 'O', ['\195\148'] = 'O', ['\195\149'] = 'O', ['\195\150'] = 'O',
    ['\195\185'] = 'u', ['\195\186'] = 'u', ['\195\187'] = 'u', ['\195\188'] = 'u',
    ['\195\153'] = 'U', ['\195\154'] = 'U', ['\195\155'] = 'U', ['\195\156'] = 'U',
    ['\195\177'] = 'n', ['\195\145'] = 'N',
    ['\194\186'] = 'o', ['\194\170'] = 'a',
}

local function to_ascii(text)
    if type(text) ~= 'string' then return '' end
    if not text:find('[\128-\255]') then return text end
    local out = text
    for k, v in pairs(UTF8_MAP) do out = out:gsub(k, v) end
    return out
end

local function read_file(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local data = f:read('*a')
    f:close()
    return data
end

local function write_file(path, content)
    local f, err = io.open(path, 'wb')
    if not f then return false, err end
    f:write(content)
    f:close()
    return true
end

local function join(a, b)
    if not a or a == '' then return b end
    if a:sub(-1) == '\\' or a:sub(-1) == '/' then return a .. b end
    return a .. '\\' .. b
end

local function dirname(path)
    return path:match('^(.*)[\\/][^\\/]-$')
end

local function ensure_dir(path)
    if not path or path == '' then return false end
    if type(createDirectory) ~= 'function' then return false end
    local ok, exists = pcall(doesDirectoryExist, path)
    if ok and exists then return true end
    local acc = ''
    for part in path:gmatch('[^\\/]+') do
        if acc == '' then
            acc = (path:sub(2, 2) == ':') and (part .. '\\') or part
        else
            acc = acc:sub(-1) == '\\' and (acc .. part) or (acc .. '\\' .. part)
        end
        pcall(createDirectory, acc)
    end
    return true
end

--=============================================================================
-- GEOMETRIA (igual ao motor do jogo)
--=============================================================================
--   x1 = cx - sx - hw      x2 = 2*sx      x3 = 2*hw
--   y1 = cy - hl - sy      y2 = 2*hl      y3 = 2*sy
--   z1 = zb                z2 = zt
local function engine_box(z)
    return ctrunc(z.cx - z.sx - z.hw), ctrunc(z.cy - z.hl - z.sy),
        ctrunc(2 * z.sx), ctrunc(2 * z.hl), ctrunc(2 * z.hw), ctrunc(2 * z.sy),
        ctrunc(z.zb), ctrunc(z.zt)
end

-- 4 cantos do paralelogramo no plano XY (ordem ciclica)
local function zone_corners(z)
    local x1, y1, x2, y2, x3, y3 = engine_box(z)
    return {
        { x = x1, y = y1 },
        { x = x1 + x2, y = y1 + y2 },
        { x = x1 + x2 + x3, y = y1 + y2 + y3 },
        { x = x1 + x3, y = y1 + y3 },
    }
end

local function zone_center_world(z)
    local x1, y1, x2, y2, x3, y3, z1, z2 = engine_box(z)
    return x1 + (x2 + x3) / 2, y1 + (y2 + y3) / 2, (z1 + z2) / 2
end

-- ponto dentro da zona (mesmo modelo do motor: paralelogramo)
local function zone_contains(z, px, py, pz)
    local x1, y1, x2, y2, x3, y3, z1, z2 = engine_box(z)
    if pz < z1 or pz > z2 then return false end
    local det = x2 * y3 - x3 * y2
    if math.abs(det) < 0.0001 then return false end
    local dx, dy = px - x1, py - y1
    local s = (dx * y3 - dy * x3) / det
    local t = (x2 * dy - y2 * dx) / det
    return s >= 0 and s <= 1 and t >= 0 and t <= 1
end

-- "modo simples" (retangulo + rotacao) <-> parametros do IPL.
-- O skew do motor emula rotacao usando x2/y2 = 2*sx, 2*sy.
local function native_to_view(z)
    local hx = math.sqrt(z.hw * z.hw + z.sy * z.sy)
    local hy = math.sqrt(z.hl * z.hl + z.sx * z.sx)
    local ang = 0
    if z.hl ~= 0 or z.sx ~= 0 then
        ang = math.deg(math.atan2(z.sx, z.hl))
    end
    return hx, hy, ang
end

local function view_to_native(hx, hy, ang_deg)
    local a = math.rad(ang_deg or 0)
    local s, c = math.sin(a), math.cos(a)
    return {
        hw = hx * c,
        hl = hy * c,
        sx = hy * s,
        sy = -hx * s,
    }
end

local function zone_size(z)
    local hx, hy = native_to_view(z)
    return hx * 2, hy * 2
end

local function zone_distance_to(z, px, py, pz)
    local cx, cy, cz = zone_center_world(z)
    return getDistanceBetweenCoords3d(px, py, pz, cx, cy, cz)
end

--=============================================================================
-- ZONA: CRIACAO / VALIDACAO
--=============================================================================
local zone_counter = 0

local function new_zone(fields)
    zone_counter = zone_counter + 1
    local z = {
        name = fields and fields.name or ('Zona ' .. zone_counter),
        enabled = true,
        live = true,
        mirror = false,
        cx = 0, cy = 0, zb = 0, zt = 30,
        hw = 20, hl = 20, sx = 0, sy = 0,
        flags = FLAG_NORAIN,
        vx = 0, vy = 1, vz = 0, cm = 0,
        comment = '',
        color = { r = 255, g = 200, b = 60 },
    }
    if type(fields) == 'table' then
        for k, v in pairs(fields) do z[k] = v end
    end
    if type(z.color) ~= 'table' then z.color = { r = 255, g = 200, b = 60 } end
    return z
end

local function zone_valid(z)
    local nums = { z.cx, z.cy, z.zb, z.zt, z.hw, z.hl, z.sx, z.sy }
    for _, v in ipairs(nums) do
        if type(v) ~= 'number' or v ~= v or v == math.huge or v == -math.huge then
            return false, 'valor invalido'
        end
    end
    if math.abs(z.hw) < 0.5 and math.abs(z.sx) < 0.5 then return false, 'largura zero' end
    if math.abs(z.hl) < 0.5 and math.abs(z.sy) < 0.5 then return false, 'comprimento zero' end
    if z.zt <= z.zb then return false, 'Top <= Bottom' end
    if (z.zt - z.zb) > 3000 then return false, 'altura absurda' end
    if math.abs(z.cx) > 6000 or math.abs(z.cy) > 6000 then return false, 'fora do mapa' end
    if math.abs(z.cx) > 3000 or math.abs(z.cy) > 3000 then return true, 'longe do centro do mapa (ok)' end
    return true
end

--=============================================================================
-- IPL: LEITURA E GERACAO
--=============================================================================
-- le uma linha da secao cull (11 campos, ou variante com espelho)
local function parse_cull_line(line)
    if type(line) ~= 'string' then return nil end
    line = line:gsub('#.*$', '')
    if not line:find('%d') then return nil end
    local nums = {}
    for token in line:gmatch('[^,%s]+') do
        local n = tonumber(token)
        if not n then return nil end
        nums[#nums + 1] = n
    end
    if #nums < 10 then return nil end
    local z = new_zone()
    z.cx, z.cy = nums[1], nums[2]
    z.sx, z.hl, z.zb, z.hw, z.sy, z.zt = nums[4], nums[5], nums[6], nums[7], nums[8], nums[9]
    z.flags = bit.band(ctrunc(nums[10]), FLAG_ALL)
    if #nums >= 14 then
        z.mirror = true
        z.vx, z.vy, z.vz, z.cm = nums[11], nums[12], nums[13], nums[14]
    end
    z.src = 'import'
    return z
end

-- le um texto IPL inteiro (aceita varias secoes cull)
local function parse_ipl_text(text)
    local zones = {}
    if type(text) ~= 'string' then return zones end
    local in_cull = false
    for line in text:gmatch('[^\r\n]+') do
        local trimmed = line:gsub('^%s+', ''):gsub('%s+$', '')
        local low = trimmed:lower()
        if low == 'cull' or low == 'cull:' then
            in_cull = true
        elseif low == 'end' then
            in_cull = false
        elseif in_cull and trimmed ~= '' and low:sub(1, 1) ~= '#' then
            local z = parse_cull_line(trimmed)
            if z then
                z.name = string.format('IPL %d (%.0f, %.0f)', #zones + 1, z.cx, z.cy)
                zones[#zones + 1] = z
            end
        end
    end
    return zones
end

-- gera a linha do IPL (uso no arquivo e no clipboard)
local function ipl_line(z, with_mirror)
    local cz = (z.zb + z.zt) / 2
    local line = string.format('%.3f, %.3f, %.3f, %.6f, %.6f, %.3f, %.6f, %.6f, %.3f, %d, 0',
        z.cx, z.cy, cz, z.sx, z.hl, z.zb, z.hw, z.sy, z.zt, bit.band(ctrunc(z.flags), FLAG_ALL))
    if with_mirror and z.mirror then
        line = line .. string.format(', %d, %d, %d, %.4f', ctrunc(z.vx), ctrunc(z.vy), ctrunc(z.vz), z.cm)
    end
    return line
end

-- gera o texto completo do IPL
local function build_ipl_text(zones, opts)
    opts = opts or {}
    local out = {}
    local function put(s) out[#out + 1] = s end

    local list = {}
    for _, z in ipairs(zones or {}) do
        local ok = zone_valid(z)
        if ok and (not opts.only_enabled or z.enabled) then
            list[#list + 1] = z
        end
    end

    put('# ============================================================')
    put('# CULL ZONES geradas pelo Cull Zone Creator')
    put('# ' .. now_string())
    put('# Zonas: ' .. #list)
    put('#')
    put('# Para instalar:')
    put('#   1. Coloque este arquivo na pasta do jogo, por ex.:')
    put('#      data\\maps\\cullzone.ipl')
    put('#   2. Abra data\\gta.dat e adicione a linha:')
    put('#      IPL DATA\\MAPS\\CULLZONE.IPL')
    put('#   Com ModLoader: coloque o .ipl + gta.dat em')
    put('#      modloader\\CullZoneCreator\\')
    put('#   (o botao "Pacote ModLoader" do script gera os dois)')
    put('#')
    put('# Formato: CenterX, CenterY, CenterZ, Unknown1, Length, Bottom,')
    put('#          Width, Unknown2, Top, Flag, Unknown3')
    put('# ============================================================')
    put('')
    put('cull')
    for i, z in ipairs(list) do
        if z.comment and z.comment ~= '' and opts.per_zone_comments ~= false then
            put('# ' .. z.comment)
        end
        put(ipl_line(z, opts.include_mirror))
    end
    put('end')
    return table.concat(out, '\r\n') .. '\r\n', #list
end

--=============================================================================
-- SERIALIZACAO DO SAVE (tabela Lua)
--=============================================================================
local function serialize_value(v, indent)
    local t = type(v)
    if t == 'number' then
        if v ~= v then return '0' end
        return string.format('%.6g', v)
    elseif t == 'string' then
        return string.format('%q', v)
    elseif t == 'boolean' then
        return tostring(v)
    elseif t == 'table' then
        local parts = {}
        local pad = string.rep(' ', indent + 2)
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            local key
            if type(k) == 'string' and k:match('^[%a_][%w_]*$') then
                key = k
            else
                key = '[' .. serialize_value(k, indent + 2) .. ']'
            end
            parts[#parts + 1] = pad .. key .. ' = ' .. serialize_value(v[k], indent + 2)
        end
        if #parts == 0 then return '{}' end
        return '{\n' .. table.concat(parts, ',\n') .. '\n' .. string.rep(' ', indent) .. '}'
    end
    return 'nil'
end

local function serialize(data)
    return 'return ' .. serialize_value(data, 0) .. '\n'
end

local function deserialize(text)
    if type(text) ~= 'string' then return nil end
    local chunkload = loadstring or load
    local chunk, err = chunkload(text, 'czc_save')
    if not chunk then
        log('erro no save: %s', tostring(err))
        return nil
    end
    if setfenv then pcall(setfenv, chunk, {}) end
    local ok, result = pcall(chunk)
    if not ok then
        log('erro ao ler o save: %s', tostring(result))
        return nil
    end
    if type(result) ~= 'table' then return nil end
    return result
end

--=============================================================================
-- ESTADO
--=============================================================================
local SAVE_FILE, EXPORT_DIR, EXPORT_FILE

local state = {
    zones = {},
    selected = 1,
    ui_show = false,
    live_apply = true,
    overlays = true,
    hud = true,
    show_labels = true,
    overlay_faces = true,          -- preencher as faces (aparencia solida)
    overlay_pillars = true,        -- linhas verticais nas quinas
    overlay_style = 'solid',       -- solid | glass | wire
    overlay_max_zones = 40,        -- quantas zonas desenhar por frame
    overlay_offset_x = 0,          -- ajuste fino da projecao (pixels)
    overlay_offset_y = 0,
    overlay_with_menu = false,     -- desenhar overlay/HUD com o menu aberto
    show_game_zones = false,
    only_selected_overlay = false,
    overlay_max_dist = 400,
    game_zones = {},
    game_zones_scan = 0,
    auto_scan_game = true,
    game_zone_radius = 300,
    game_zone_max = 80,
    only_enabled = true,
    per_zone_comments = true,
    include_mirror_export = false,
    auto_pack_modloader = true,
    font_height = 9,
    player = nil,
    dry_run = false,
    render_in_menu = false,
    auto_load_save = true,
    -- atalho principal: segurar as duas teclas abre o menu (padrao C + L)
    open_combo = { vkeys.VK_C or 0x43, vkeys.VK_L or 0x4C },
    open_combo_enabled = true,
    combo_was_down = false,
    lock_player = false,          -- trava os controles com o menu aberto
    capture = nil,                -- 'open1' / 'open2' enquanto escolhe a tecla
    -- atalhos extras (opcionais; por padrao nenhum, o menu tem tudo)
    keys = { menu = 0, new_zone = 0, live = 0, overlay = 0, export = 0 },
    last_msg = '',
    last_msg_color = { r = 220, g = 220, b = 220 },
}

local function msg(text, r, g, b)
    state.last_msg = tostring(text)
    state.last_msg_color = { r = ctrunc(r or 220), g = ctrunc(g or 220), b = ctrunc(b or 220) }
    log('%s', tostring(text))
end

local game_dirty = true
local function MarkLiveDirty() game_dirty = true end

-- a fonte do HUD so pode ser recriada fora do onD3DPresent
local font_dirty = false

local function selected_zone()
    return state.zones[state.selected]
end

local function add_zone(z)
    state.zones[#state.zones + 1] = z
    state.selected = #state.zones
    MarkLiveDirty()
    return z
end

--=============================================================================
-- MEMORIA DO JOGO (live apply + leitura do estado real)
--=============================================================================
local Game = {
    ok = false,
    error = nil,
    base_attr = nil,
    base_mirror = nil,
    applied = 0,
    last_apply = 0,
    last_status = nil,
}

local function mem_available()
    return type(readMemory) == 'function' and type(writeMemory) == 'function'
end

local function read_u32(addr)
    local ok, v = pcall(readMemory, addr, 4, false)
    if ok and type(v) == 'number' then return v end
    return nil
end

local function read_i32(addr)
    local v = read_u32(addr)
    if v and v >= 2147483648 then return v - 4294967296 end
    return v
end

local function read_u16(addr)
    local ok, v = pcall(readMemory, addr, 2, false)
    if ok and type(v) == 'number' then return v end
    return nil
end

local function read_s16(addr)
    local v = read_u16(addr)
    if v and v >= 32768 then return v - 65536 end
    return v
end

local function read_i8(addr)
    local ok, v = pcall(readMemory, addr, 1, false)
    if not ok or type(v) ~= 'number' then return nil end
    if v >= 128 then return v - 256 end
    return v
end

local function write_mem(addr, size, value)
    local v = ctrunc(value) % 4294967296
    local ok = pcall(writeMemory, addr, size, v, false)
    return ok
end

-- bits IEEE-754 de um float (para escrever o campo Cm dos espelhos)
local function float_bits(v)
    v = tonumber(v) or 0
    local sign = 0
    if v < 0 then sign = 2147483648 v = -v end
    if v == 0 then return sign end
    local mant, exp = math.frexp(v)
    if not mant then return sign end
    exp = exp + 126
    if exp <= 0 then return sign end
    if exp >= 255 then return sign + 2139095040 end
    mant = mant * 2 - 1
    local m = math.floor(mant * 8388608 + 0.5)
    if m >= 8388608 then
        m = 0
        exp = exp + 1
        if exp >= 255 then return sign + 2139095040 end
    end
    return sign + exp * 8388608 + m
end

-- escreve um CZoneDef (8 shorts) + flags
local function write_zone_def(base, z, flags)
    local x1, y1, x2, y2, x3, y3, z1, z2 = engine_box(z)
    local ok = true
    ok = write_mem(base + 0, 2, x1) and ok
    ok = write_mem(base + 2, 2, y1) and ok
    ok = write_mem(base + 4, 2, x2) and ok
    ok = write_mem(base + 6, 2, y2) and ok
    ok = write_mem(base + 8, 2, x3) and ok
    ok = write_mem(base + 10, 2, y3) and ok
    ok = write_mem(base + 12, 2, z1) and ok
    ok = write_mem(base + 14, 2, z2) and ok
    ok = write_mem(base + 16, 2, bit.band(ctrunc(flags), FLAG_ALL)) and ok
    return ok
end

local function init_memory()
    if state.dry_run then
        Game.ok, Game.error = false, 'modo seguro ligado'
        return false
    end
    if not mem_available() then
        Game.ok, Game.error = false, 'readMemory/writeMemory indisponiveis'
        return false
    end
    local count = read_i32(A.NUM_ATTR_ZONES)
    if not count or count < 1 or count > ATTR_ZONES_MAX then
        Game.ok = false
        Game.error = string.format('contagem de zonas inesperada (%s): jogo diferente de 1.0 US?', tostring(count))
        log('memoria desativada: %s', Game.error)
        return false
    end
    Game.ok, Game.error = true, nil
    Game.base_attr, Game.base_mirror = nil, nil
    log('memoria OK: %d zonas de cull carregadas', count)
    return true
end

local function live_reset()
    if not Game.ok or Game.base_attr == nil then return end
    write_mem(A.NUM_ATTR_ZONES, 4, Game.base_attr)
    if Game.base_mirror then write_mem(A.NUM_MIRROR_ZONES, 4, Game.base_mirror) end
    Game.applied = 0
end

local function live_apply(force)
    if not Game.ok then return end
    if not state.live_apply then
        live_reset()
        game_dirty = false
        return
    end
    local now = os.clock()
    if not force and (now - Game.last_apply) < 0.2 then return end
    Game.last_apply = now
    game_dirty = false

    if Game.base_attr == nil or Game.base_mirror == nil then
        Game.base_attr = clamp(ctrunc(read_i32(A.NUM_ATTR_ZONES) or 0), 0, ATTR_ZONES_MAX)
        Game.base_mirror = clamp(ctrunc(read_i32(A.NUM_MIRROR_ZONES) or 0), 0, MIRROR_ZONES_MAX)
    end

    live_reset()

    local n_attr, n_mirror = Game.base_attr, Game.base_mirror
    local added, skipped = 0, 0
    for _, z in ipairs(state.zones) do
        if z.enabled and z.live ~= false and zone_valid(z) then
            if z.mirror then
                if n_mirror < MIRROR_ZONES_MAX then
                    local base = A.MIRROR_ZONES + n_mirror * 24
                    write_zone_def(base, z, z.flags)
                    write_mem(base + 16, 4, float_bits(z.cm or 0))
                    write_mem(base + 20, 1, ctrunc(z.vx) % 256)
                    write_mem(base + 21, 1, ctrunc(z.vy) % 256)
                    write_mem(base + 22, 1, ctrunc(z.vz) % 256)
                    write_mem(base + 23, 1, bit.band(ctrunc(z.flags), 0xFF))
                    n_mirror = n_mirror + 1
                    added = added + 1
                else
                    skipped = skipped + 1
                end
            else
                if n_attr < ATTR_ZONES_MAX then
                    write_zone_def(A.ATTR_ZONES + n_attr * 18, z, z.flags)
                    n_attr = n_attr + 1
                    added = added + 1
                else
                    skipped = skipped + 1
                end
            end
        end
    end

    write_mem(A.NUM_ATTR_ZONES, 4, n_attr)
    write_mem(A.NUM_MIRROR_ZONES, 4, n_mirror)
    Game.applied = added

    if skipped > 0 then
        msg(string.format('Live: %d zona(s) aplicada(s), %d ignorada(s) (limite de %d do motor)',
            added, skipped, ATTR_ZONES_MAX), 255, 190, 80)
    end
end

-- le o que o jogo esta aplicando agora (flags, clima, contagens)
local function query_game_status()
    if not Game.ok then return nil end
    local st = {
        flags_player = read_i32(A.FLAGS_PLAYER) or 0,
        flags_camera = read_i32(A.FLAGS_CAMERA) or 0,
        weather = read_s16(A.WEATHER_OLD),
        weather_new = read_s16(A.WEATHER_NEW),
        attr_count = read_i32(A.NUM_ATTR_ZONES) or 0,
        mirror_count = read_i32(A.NUM_MIRROR_ZONES) or 0,
    }
    if st.weather == nil then st.weather = -1 end
    if st.weather_new == nil then st.weather_new = -1 end
    Game.last_status = st
    return st
end

-- le as zonas que o jogo ja tem carregadas
local function scan_game_zones(px, py, radius, limit)
    if not Game.ok then return 0 end
    radius = radius or state.game_zone_radius
    limit = limit or state.game_zone_max
    local list = {}

    local function push(base, flags, mirror, cm, vx, vy, vz)
        local x1, y1 = read_s16(base), read_s16(base + 2)
        local x2, y2 = read_s16(base + 4), read_s16(base + 6)
        local x3, y3 = read_s16(base + 8), read_s16(base + 10)
        local z1, z2 = read_s16(base + 12), read_s16(base + 14)
        if not (x1 and y1 and x2 and y2 and x3 and y3 and z1 and z2) then return end
        local cx = x1 + (x2 + x3) / 2
        local cy = y1 + (y2 + y3) / 2
        if px and py and getDistanceBetweenCoords2d(px, py, cx, cy) > radius then return end
        local z = new_zone()
        z.src = 'game'
        z.enabled = false
        z.live = false
        z.cx, z.cy = cx, cy
        z.zb, z.zt = z1, z2
        z.hw, z.hl = x3 / 2, y2 / 2
        z.sx, z.sy = x2 / 2, y3 / 2
        z.flags = flags or 0
        z.mirror = mirror and true or false
        if mirror then
            z.cm, z.vx, z.vy, z.vz = cm or 0, vx or 0, vy or 0, vz or 0
            z.name = string.format('Espelho #%d', #list + 1)
        else
            z.name = string.format('Jogo #%d', #list + 1)
        end
        list[#list + 1] = z
    end

    -- apenas o que o jogo carregou sozinho (sem contar as nossas)
    local count = clamp(ctrunc(Game.base_attr or read_i32(A.NUM_ATTR_ZONES) or 0), 0, ATTR_ZONES_MAX)
    for i = 0, count - 1 do
        if #list >= limit then break end
        local base = A.ATTR_ZONES + i * 18
        push(base, read_u16(base + 16), false)
    end

    local mcount = clamp(ctrunc(Game.base_mirror or read_i32(A.NUM_MIRROR_ZONES) or 0), 0, MIRROR_ZONES_MAX)
    for i = 0, mcount - 1 do
        if #list >= limit then break end
        local base = A.MIRROR_ZONES + i * 24
        push(base, read_i8(base + 23), true, nil, read_i8(base + 20), read_i8(base + 21), read_i8(base + 22))
    end

    state.game_zones = list
    state.game_zones_scan = os.time()
    return #list
end

--=============================================================================
-- CAMINHOS / EXPORTACAO / IMPORTACAO
--=============================================================================
local function default_paths()
    local workdir, gamedir
    local ok, wd = pcall(getWorkingDirectory)
    if ok and type(wd) == 'string' then workdir = wd end
    local ok2, gd = pcall(getGameDirectory)
    if ok2 and type(gd) == 'string' then gamedir = gd end

    if workdir then
        SAVE_FILE = join(join(workdir, 'config'), 'CullZoneCreator.lua')
    end
    if gamedir then
        EXPORT_DIR = join(join(gamedir, 'modloader'), 'CullZoneCreator')
        EXPORT_FILE = join(EXPORT_DIR, 'cull.ipl')
    elseif workdir then
        EXPORT_DIR = workdir
        EXPORT_FILE = join(workdir, 'cull.ipl')
    else
        EXPORT_DIR = '.'
        EXPORT_FILE = 'cull.ipl'
    end
end

local function export_ipl(path, opts)
    path = path or EXPORT_FILE
    if not path or path == '' then
        msg('Caminho do IPL invalido.', 255, 140, 120)
        return false
    end
    opts = opts or {}
    if opts.only_enabled == nil then opts.only_enabled = state.only_enabled end
    local text, n = build_ipl_text(state.zones, opts)
    if n == 0 then
        msg('Nada para exportar: nenhuma zona valida/ativa.', 255, 140, 120)
        return false
    end
    ensure_dir(dirname(path))
    local ok, err = write_file(path, text)
    if not ok then
        msg('Falha ao salvar ' .. tostring(path) .. ': ' .. tostring(err), 255, 120, 120)
        return false
    end
    msg(string.format('IPL exportado (%d zona(s)): %s', n, path), 130, 255, 130)
    return true, path, n
end

-- gera cull.ipl + gta.dat na pasta do ModLoader
local function export_modloader_package(dir)
    dir = dir or EXPORT_DIR
    if not dir or dir == '' then return false end
    ensure_dir(dir)
    local ipl_path = join(dir, 'cull.ipl')
    local ok, _, n = export_ipl(ipl_path, { only_enabled = state.only_enabled })
    if not ok then return false end

    local rel = 'MODLOADER\\CULLZONECREATOR'
    local ok2, gamedir = pcall(getGameDirectory)
    if ok2 and type(gamedir) == 'string' and gamedir ~= '' then
        local prefix = gamedir:lower():gsub('[\\/]+$', '')
        local full = dir:lower():gsub('[\\/]+$', '')
        if full:sub(1, #prefix) == prefix then
            rel = dir:sub(#prefix + 1):gsub('^[\\/]+', '')
        end
    end

    local gta = table.concat({
        '# gta.dat do ModLoader - gerado pelo Cull Zone Creator',
        '# ' .. now_string(),
        '#',
        '# Registra o IPL das cull zones. O caminho e relativo a pasta do jogo.',
        'IPL ' .. rel:upper() .. '\\CULL.IPL',
        '',
    }, '\r\n')
    local ok3, err = write_file(join(dir, 'gta.dat'), gta)
    if not ok3 then msg('gta.dat: ' .. tostring(err), 255, 150, 80) end

    local readme = table.concat({
        'CULL ZONE CREATOR - pacote para ModLoader',
        '=========================================',
        'Gerado em ' .. now_string(),
        'Zonas exportadas: ' .. tostring(n or 0),
        '',
        'Ja esta pronto para o ModLoader:',
        '  1. Os arquivos cull.ipl e gta.dat desta pasta sao lidos automaticamente',
        '     (ela esta dentro de modloader\\).',
        '  2. Inicie o jogo. As zonas valem sempre, mesmo sem o script.',
        '',
        'Sem ModLoader? Faca na mao:',
        '  - Copie cull.ipl para data\\maps\\cullzone.ipl',
        '  - Em data\\gta.dat adicione a linha:',
        '        IPL DATA\\MAPS\\CULLZONE.IPL',
        '',
        'Observacao: as cull zones entram em vigor quando o jogo carrega o mapa,',
        'ou seja: iniciar o jogo (ou sair e entrar de novo no single player).',
        'Para testar na hora, use o live apply do script (botao "Aplicar no jogo").',
        '',
    }, '\r\n')
    write_file(join(dir, 'LEIA-ME.txt'), readme)

    msg('Pacote ModLoader gerado em: ' .. dir, 130, 255, 130)
    return true
end

local function import_from_text(text)
    local zones = parse_ipl_text(text)
    if #zones == 0 then
        msg('Nenhuma zona cull encontrada no texto.', 255, 180, 90)
        return 0
    end
    for _, z in ipairs(zones) do add_zone(z) end
    msg(string.format('%d zona(s) importada(s) do IPL.', #zones), 140, 220, 255)
    return #zones
end

local function import_from_file(path)
    local data = read_file(path)
    if not data then
        msg('Nao consegui ler: ' .. tostring(path), 255, 120, 120)
        return 0
    end
    return import_from_text(data)
end

local function import_from_game()
    if not Game.ok then
        msg('Memoria do jogo indisponivel.', 255, 150, 90)
        return 0
    end
    local n = scan_game_zones(state.player and state.player.x, state.player and state.player.y)
    if n == 0 then
        msg('Nenhuma zona encontrada no raio de ' .. tostring(state.game_zone_radius) .. 'm.', 255, 180, 90)
        return 0
    end
    for _, gz in ipairs(state.game_zones) do
        add_zone(new_zone(gz))
    end
    msg(string.format('%d zona(s) do jogo copiada(s) para a lista.', n), 140, 220, 255)
    return n
end

local function copy_text(text)
    if type(setClipboardText) == 'function' then
        local ok = pcall(setClipboardText, text)
        if ok then return true end
    end
    return false
end

--=============================================================================
-- DESENHO (overlay 3D + HUD)
--
-- Tudo e desenhado de dentro do onD3DPresent com as funcoes render* do
-- MoonLoader, que usam coordenadas em PIXELS da janela - exatamente as mesmas
-- devolvidas pelo convert3DCoordsToScreen.
--
-- A caixa da zona e desenhada como um SOLIDO:
--   * 8 vertices (4 embaixo, 4 em cima) projetados na tela;
--   * as 6 faces viram quadrados preenchidos (mad.shape) desenhados de tras
--     para frente (ordem de pintura), com a opacidade caindo com a distancia;
--   * faces viradas para o lado oposto da camera sao descartadas (backface
--     culling), o que tira a "ilusao" de cubo de arame flutuante;
--   * os aneis de baixo e de cima sao desenhados por cima (renderDrawLine)
--     para a zona ficar bem marcada mesmo de longe.
--=============================================================================
local Draw = {
    lines = {},
    boxes = {},
    quads = {},
    texts = {},
    font = nil,
    font_height = nil,
    fonts = {},
    shape = nil,
    fills_ok = true,
    fails = 0,
}

local function argb(r, g, b, a)
    return bit.bor(bit.lshift(ctrunc(a or 255) % 256, 24), bit.lshift(ctrunc(r) % 256, 16),
        bit.lshift(ctrunc(g) % 256, 8), ctrunc(b) % 256)
end

local function argb_parts(color)
    return bit.band(bit.rshift(color, 16), 0xFF), bit.band(bit.rshift(color, 8), 0xFF),
        bit.band(color, 0xFF), bit.band(bit.rshift(color, 24), 0xFF)
end

local function fade(color, mul)
    if not mul or mul >= 1 then return color end
    local a = bit.band(bit.rshift(color, 24), 0xFF)
    a = ctrunc(a * mul)
    if a < 0 then a = 0 end
    return bit.bor(bit.lshift(a, 24), bit.band(color, 0x00FFFFFF))
end

local function draw_init()
    if type(renderCreateFont) == 'function' then
        local height = ctrunc(state.font_height or 9)
        local font = Draw.fonts[height]
        if not font then
            local flags = 5
            if moonlib and moonlib.font_flag then
                flags = (moonlib.font_flag.SHADOW or 0) + (moonlib.font_flag.BOLD or 0)
                if flags == 0 then flags = 5 end
            end
            local ok, created = pcall(renderCreateFont, 'Arial', height, flags)
            if ok and type(created) == 'number' then
                font = created
                Draw.fonts[height] = font
            end
        end
        Draw.font = font
        Draw.font_height = height
    end
    if ok_mad and mad and mad.shape then
        local ok, shp = pcall(function() return mad.shape.new() end)
        if ok and shp ~= nil then Draw.shape = shp end
    end
    log('desenho pronto: fonte=%s preenchimento=%s', Draw.font and 'ok' or 'nao', Draw.shape and 'ok' or 'nao')
end

local function draw_begin()
    Draw.lines = {}
    Draw.boxes = {}
    Draw.quads = {}
    Draw.texts = {}
end

local function draw_line(x1, y1, x2, y2, color, width)
    Draw.lines[#Draw.lines + 1] = { ctrunc(x1), ctrunc(y1), ctrunc(x2), ctrunc(y2), color, ctrunc(width or 1) }
end

local function draw_box(x, y, w, h, color, border_size, border_color)
    Draw.boxes[#Draw.boxes + 1] = { ctrunc(x), ctrunc(y), ctrunc(w), ctrunc(h), color,
        ctrunc(border_size or 0), border_color }
end

-- quadrilatero preenchido, na ordem em que for chamado (ordem de pintura).
-- O ultimo campo guarda a distancia da camera (usado nos testes).
local function draw_quad(p1, p2, p3, p4, color, distance)
    Draw.quads[#Draw.quads + 1] = { p1[1], p1[2], p2[1], p2[2], p3[1], p3[2], p4[1], p4[2], color, distance or 0 }
end

local function draw_text(text, x, y, color)
    Draw.texts[#Draw.texts + 1] = { text = to_ascii(text), x = ctrunc(x), y = ctrunc(y), color = color }
end

local function text_width(text)
    if Draw.font and type(renderGetFontDrawTextLength) == 'function' then
        local ok, w = pcall(renderGetFontDrawTextLength, Draw.font, to_ascii(text))
        if ok and type(w) == 'number' and w > 0 then return w end
    end
    return #tostring(text) * 6
end

local function text_height()
    if Draw.font and type(renderGetFontDrawHeight) == 'function' then
        local ok, h = pcall(renderGetFontDrawHeight, Draw.font)
        if ok and type(h) == 'number' and h > 0 then return h end
    end
    return 12
end

local function screen_size()
    local ok, sw, sh = pcall(getScreenResolution)
    if ok and type(sw) == 'number' and type(sh) == 'number' and sw > 0 and sh > 0 then
        return sw, sh
    end
    return 640, 480
end

-- projeta um ponto do mundo na tela (nil quando esta atras da camera/fora).
-- O ajuste fino (overlay_offset_*) existe para o caso de alguma configuracao de
-- video devolver as coordenadas deslocadas em alguns pixels.
local function project_point(x, y, z)
    local ok, px, py = pcall(convert3DCoordsToScreen, x, y, z)
    if not ok or type(px) ~= 'number' or type(py) ~= 'number' then return nil end
    if px ~= px or py ~= py then return nil end
    if state.overlay_offset_x or state.overlay_offset_y then
        px = px + (state.overlay_offset_x or 0)
        py = py + (state.overlay_offset_y or 0)
    end
    return px, py
end

-- posicao da camera (para a profundidade/ordem de pintura)
local function camera_position()
    if type(getActiveCameraCoordinates) == 'function' then
        local ok, x, y, z = pcall(getActiveCameraCoordinates)
        if ok and type(x) == 'number' and type(y) == 'number' then
            return { x = x, y = y, z = z or 0 }
        end
    end
    return state.player
end

local function dist2d(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

-- o lado de fora da parede (i -> j) esta virado para a camera?
local function wall_faces_camera(ax, ay, bx, by, camx, camy, winding)
    local dx, dy = bx - ax, by - ay
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.001 then return false end
    local nx, ny = winding * dy / len, -winding * dx / len
    return (camx - ax) * nx + (camy - ay) * ny > 0
end

-- desenha uma zona (caixa 3D). Devolve quantas arestas foram desenhadas.
local function draw_zone_box(z, selected, cam)
    local corners = zone_corners(z)
    local z1, z2 = ctrunc(z.zb), ctrunc(z.zt)
    if z2 < z1 then z1, z2 = z2, z1 end

    local bottom, top = {}, {}
    local visible = 0
    for i = 1, 4 do
        local c = corners[i]
        local bx, by = project_point(c.x, c.y, z1)
        local tx, ty = project_point(c.x, c.y, z2)
        if bx then bottom[i] = { bx, by } visible = visible + 1 end
        if tx then top[i] = { tx, ty } visible = visible + 1 end
    end
    if visible == 0 then return 0 end

    local player_inside = false
    if state.player then
        player_inside = zone_contains(z, state.player.x, state.player.y, state.player.z)
    end

    local r, g, b = z.color.r, z.color.g, z.color.b
    if player_inside then r, g, b = 90, 255, 90 end

    -- camera (usada para ordenar por profundidade e para o culling das faces)
    cam = cam or camera_position()
    local camx = cam and cam.x or 0
    local camy = cam and cam.y or 0
    local camz = cam and cam.z or 0
    local cam_inside = zone_contains(z, camx, camy, camz)
    local inside_any = cam_inside or player_inside

    local det = (corners[2].x - corners[1].x) * (corners[4].y - corners[1].y)
        - (corners[4].x - corners[1].x) * (corners[2].y - corners[1].y)
    local winding = det >= 0 and 1 or -1

    local range = math.max(state.overlay_max_dist or 400, 50)
    local style = state.overlay_style or 'solid'

    -------------------------------------- faces (preenchimento)
    if Draw.shape and state.overlay_faces ~= false and style ~= 'wire' then
        local faces = {}
        local function push(p1, p2, p3, p4, dist, alpha)
            if p1 and p2 and p3 and p4 then
                faces[#faces + 1] = { p1, p2, p3, p4, dist, alpha }
            end
        end

        local d1 = dist2d(corners[1].x, corners[1].y, camx, camy)
        local d2 = dist2d(corners[2].x, corners[2].y, camx, camy)
        local d3 = dist2d(corners[3].x, corners[3].y, camx, camy)
        local d4 = dist2d(corners[4].x, corners[4].y, camx, camy)
        local avg_all = (d1 + d2 + d3 + d4) / 4

        -- base e topo (no estilo vidro aparecem sempre, para dar volume)
        if inside_any or style == 'glass' or camz < z1 then
            push(bottom[1], bottom[2], bottom[3], bottom[4], avg_all, selected and 80 or 55)
        end
        if inside_any or style == 'glass' or camz > z2 then
            push(top[1], top[2], top[3], top[4], avg_all, selected and 55 or 35)
        end

        -- paredes: em 'solid' so as que estao viradas para a camera
        -- (o lado de fora da parede, calculado pela orientacao dos cantos)
        local wall_dist = { d1, d2, d3, d4 }
        for i = 1, 4 do
            local j = (i % 4) + 1
            if bottom[i] and bottom[j] and top[i] and top[j] then
                local facing = wall_faces_camera(corners[i].x, corners[i].y, corners[j].x, corners[j].y,
                    camx, camy, winding)
                if inside_any or style == 'glass' or facing then
                    local alpha = inside_any and 40 or (selected and 90 or 65)
                    if not facing then alpha = ctrunc(alpha * 0.45) end
                    push(bottom[i], bottom[j], top[j], top[i], (wall_dist[i] + wall_dist[j]) / 2, alpha)
                end
            end
        end

        -- desenha de tras para frente (ordem de pintura = profundidade)
        table.sort(faces, function(a, b) return a[5] > b[5] end)
        for _, f in ipairs(faces) do
            local t = math.min(f[5] / range, 1)
            local alpha = ctrunc(f[6] * (1 - 0.7 * t))
            if alpha > 4 then
                draw_quad(f[1], f[2], f[3], f[4], argb(r, g, b, alpha), f[5])
            end
        end
    end

    -------------------------------------- contornos
    local function edge_color(dist, base_alpha)
        local t = math.min(dist / range, 1)
        return argb(r, g, b, ctrunc(base_alpha * (1 - 0.55 * t)))
    end

    local alpha = selected and 255 or (player_inside and 230 or 190)
    local thickness = selected and 3 or 2
    local edges = 0
    for i = 1, 4 do
        local j = (i % 4) + 1
        local d = (dist2d(corners[i].x, corners[i].y, camx, camy) + dist2d(corners[j].x, corners[j].y, camx, camy)) / 2
        if bottom[i] and bottom[j] then
            draw_line(bottom[i][1], bottom[i][2], bottom[j][1], bottom[j][2], edge_color(d, alpha), thickness)
            edges = edges + 1
        end
        if top[i] and top[j] then
            draw_line(top[i][1], top[i][2], top[j][1], top[j][2], edge_color(d, ctrunc(alpha * 0.85)), thickness)
            edges = edges + 1
        end
        -- pilares: mais discretos, so para dar volume (opcional)
        if state.overlay_pillars ~= false and bottom[i] and top[i] then
            draw_line(bottom[i][1], bottom[i][2], top[i][1], top[i][2], edge_color(d, ctrunc(alpha * 0.55)), 1)
        end
    end

    -------------------------------------- nome / distancia
    if state.show_labels and edges > 0 then
        local cx, cy = zone_center_world(z)
        local lx, ly = project_point(cx, cy, z2 + 2)
        if lx then
            local text = z.name
            if player_inside then text = text .. '  [DENTRO]' end
            if selected then
                local dist = state.player and zone_distance_to(z, state.player.x, state.player.y, state.player.z) or 0
                text = string.format('%s  (%.0fm)  %s', text, dist, flag_list(z.flags))
            end
            draw_text(text, lx + 6, ly + 4, argb(r, g, b, 255))
        end
    end
    return edges
end

local function build_overlay()
    local cam = camera_position()
    local camx = cam and cam.x or 0
    local camy = cam and cam.y or 0

    -- monta a lista de zonas visiveis...
    local list = {}
    for i, z in ipairs(state.zones) do
        if z.enabled and (not state.only_selected_overlay or i == state.selected) then
            local near = true
            if state.player and i ~= state.selected then
                near = zone_distance_to(z, state.player.x, state.player.y, state.player.z) <= state.overlay_max_dist
            end
            if near then
                local cx, cy = zone_center_world(z)
                list[#list + 1] = { z = z, selected = (i == state.selected),
                    d = dist2d(cx, cy, camx, camy) }
            end
        end
    end

    if state.show_game_zones then
        for _, z in ipairs(state.game_zones) do
            local near = true
            if state.player then
                near = zone_distance_to(z, state.player.x, state.player.y, state.player.z) <= state.game_zone_radius
            end
            if near then
                local cx, cy = zone_center_world(z)
                list[#list + 1] = { z = z, selected = false, d = dist2d(cx, cy, camx, camy) }
            end
        end
    end

    -- ...e desenha de tras para frente (as zonas de longe primeiro)
    table.sort(list, function(a, b) return a.d > b.d end)
    local limit = math.min(#list, state.overlay_max_zones or 40)
    for i = 1, limit do
        draw_zone_box(list[i].z, list[i].selected, cam)
    end
end

local function build_hud()
    local player = state.player
    local st = Game.last_status
    local sel = selected_zone()
    local lines = {}

    local function L(text, r, g, b)
        lines[#lines + 1] = { text = text, color = argb(r or 230, g or 230, b or 230, 255) }
    end

    local live_txt, lr, lg, lb = 'LIVE OFF', 230, 200, 200
    if state.live_apply then
        if Game.ok then
            live_txt, lr, lg, lb = string.format('LIVE ON (%d zona(s) no jogo)', Game.applied), 120, 255, 120
        else
            live_txt, lr, lg, lb = 'LIVE OFF - sem memoria', 255, 190, 90
        end
    end
    L(string.format('CULL ZONE CREATOR v%s  -  %s', VERSION, live_txt), lr, lg, lb)

    if sel then
        local inside = player and zone_contains(sel, player.x, player.y, player.z) or false
        local dist = player and zone_distance_to(sel, player.x, player.y, player.z) or 0
        L(string.format('Zona %d: %s  %s  %.0fm', state.selected, sel.name,
            inside and 'VOCE ESTA DENTRO' or 'fora', dist), inside and 140 or 220, 220, inside and 140 or 220)
        L('Flags: ' .. flag_list(sel.flags), 180, 220, 255)
    else
        L('Sem zonas - crie uma em "Acoes > Nova zona no player"', 255, 190, 90)
    end

    if st then
        local extra = has_flag(st.flags_player, FLAG_NORAIN) and '  [SEM CHUVA]' or ''
        L(string.format('No jogador: %s%s', flag_list(st.flags_player), extra), 220, 255, 220)
        L(string.format('Clima: %s (%d)   Zonas no jogo: %d (+%d espelhos)',
            WEATHER_NAMES[st.weather] or '?', st.weather, st.attr_count, st.mirror_count), 200, 220, 255)
    end

    L(string.format('Zonas do script: %d   [%s + %s] abre o menu (fecha no X)',
        #state.zones, key_name(state.open_combo[1]), key_name(state.open_combo[2])), 180, 180, 180)

    local lh = text_height() + 3
    local width = 0
    for _, l in ipairs(lines) do
        local w = text_width(l.text)
        if w > width then width = w end
    end
    local sw = screen_size()
    local x, y = 12, 10
    local w = math.min(width + 14, sw - 24)
    local h = #lines * lh + 8
    draw_box(x - 6, y - 4, w, h, argb(0, 0, 0, 140), 1, argb(90, 170, 220, 200))
    for i, l in ipairs(lines) do
        draw_text(l.text, x, y + (i - 1) * lh, l.color)
    end
end

-- desenha tudo (chamado dentro do onD3DPresent)
local function draw_present()
    if state.render_in_menu == false then
        local ok, paused = pcall(isPauseMenuActive)
        if ok and paused then return end
    end

    -- nosso desenho sai por cima do menu do ImGui (a ordem dos eventos), entao
    -- com o menu aberto o overlay/HUD so aparece se o usuario quiser
    if state.ui_show and state.overlay_with_menu == false then return end
    local mul = state.ui_show and 0.5 or 1.0

    for _, b in ipairs(Draw.boxes) do
        pcall(renderDrawBox, b[1], b[2], b[3], b[4], fade(b[5], mul))
        if b[6] > 0 then
            pcall(renderDrawBoxWithBorder, b[1], b[2], b[3], b[4], fade(b[5], mul), b[6], fade(b[7] or b[5], mul))
        end
    end

    for _, l in ipairs(Draw.lines) do
        pcall(renderDrawLine, l[1], l[2], l[3], l[4], l[6], fade(l[5], mul))
    end

    if Draw.font then
        for _, t in ipairs(Draw.texts) do
            pcall(renderFontDrawText, Draw.font, t.text, t.x, t.y, fade(t.color, mul))
        end
    end

    if Draw.fills_ok and Draw.shape and #Draw.quads > 0 then
        local ok = pcall(function()
            local shp = Draw.shape
            shp:clear()
            for _, q in ipairs(Draw.quads) do
                local r, g, b, a = argb_parts(fade(q[9], mul))
                shp:add_vertex(q[1], q[2], r, g, b, a)
                shp:add_vertex(q[3], q[4], r, g, b, a)
                shp:add_vertex(q[5], q[6], r, g, b, a)
                shp:add_vertex(q[5], q[6], r, g, b, a)
                shp:add_vertex(q[7], q[8], r, g, b, a)
                shp:add_vertex(q[1], q[2], r, g, b, a)
            end
            shp:draw(mad.primitive_type.TRIANGLELIST, true, mad.blend_method.SRCALPHA, mad.blend_method.INVSRCALPHA)
        end)
        if not ok then
            Draw.fails = Draw.fails + 1
            if Draw.fails > 3 then
                Draw.fills_ok = false
                log('preenchimento do MoonAdditions falhou - seguindo sem ele')
            end
        end
    end
end

--=============================================================================
-- INTERFACE (Moon ImGui)
--
-- REGRA DE OURO: todo Begin/BeginChild tem o seu End/EndChild, SEMPRE - mesmo
-- se uma secao der erro. Se o ImGui ficar com uma janela pendurada na pilha o
-- jogo trava com "Mismatched Begin()/End() calls" (assertion failed). Por isso
-- cada secao roda dentro de pcall e o End/EndChild e chamado fora dele.
--=============================================================================
local save_config, load_config
local new_zone_at_player
local set_ui, toggle_ui          -- definidas mais abaixo (usadas no cabecalho)

local PAGES = {
    { id = 1, name = ' Zonas ' },
    { id = 2, name = ' Exportar ' },
    { id = 3, name = ' Jogo ' },
    { id = 4, name = ' Config ' },
    { id = 5, name = ' Ajuda ' },
}

-- o binding de Columns nem sempre existe/funciona em todas as builds
local columns_ok = type(imgui.Columns) == 'function'

local ui = {
    show = nil,
    bufs = {},
    floats = {},
    ints = {},
    bools = {},
    export_path = nil,
    import_path = nil,
    page = 1,
    error = nil,
    error_count = 0,
}

local function ui_error(where, err)
    ui.error = string.format('%s: %s', where, tostring(err))
    ui.error_count = ui.error_count + 1
    log('erro na interface (%s): %s', where, tostring(err))
end

-- roda uma parte da interface protegida: um erro aqui nao derruba o resto
local function ui_section(where, fn)
    local ok, err = pcall(fn)
    if not ok then ui_error(where, err) end
    return ok
end

-- child window com EndChild garantido
local function ui_child(name, size, fn)
    local open = imgui.BeginChild(name, size, true)
    local ok, err = pcall(function() if open then fn() end end)
    imgui.EndChild()
    if not ok then ui_error(name, err) end
end

local function read_buffer(buf)
    local ok, v = pcall(function() return buf.v end)
    if ok and type(v) == 'string' then return v end
    return ''
end

local function write_buffer(buf, text)
    local ok = pcall(function() buf.v = text end)
    if ok then return true end
    if type(imgui.StrCopy) == 'function' then pcall(imgui.StrCopy, buf, text) end
    return false
end

local function ui_float(key, value)
    local f = ui.floats[key]
    if not f then
        f = imgui.ImFloat(value or 0)
        ui.floats[key] = f
    end
    return f
end

local function ui_int(key, value)
    local i = ui.ints[key]
    if not i then
        i = imgui.ImInt(value or 0)
        ui.ints[key] = i
    end
    return i
end

local function ui_bool(key, value)
    local b = ui.bools[key]
    if not b then
        b = imgui.ImBool(value and true or false)
        ui.bools[key] = b
    end
    return b
end

-- devolve value, mudou  (o Im* guarda o valor editado pelo ImGui)
local function drag_float(key, label, value, speed, vmin, vmax, fmt)
    local f = ui_float(key, value)
    value = tonumber(value) or 0
    if not imgui.IsItemActive() and math.abs((tonumber(f.v) or value) - value) > 0.0005 then
        f.v = value
    end
    if imgui.DragFloat(label .. '##' .. key, f, speed, vmin, vmax, fmt or '%.2f') then
        return tonumber(f.v) or value, true
    end
    return value, false
end

local function slider_int(key, label, value, vmin, vmax)
    local i = ui_int(key, value)
    value = ctrunc(value)
    if not imgui.IsItemActive() and (tonumber(i.v) or value) ~= value then i.v = value end
    if imgui.SliderInt(label .. '##' .. key, i, vmin, vmax) then
        return tonumber(i.v) or value, true
    end
    return value, false
end

-- devolve o novo valor quando muda, senao nil
local function checkbox(key, label, value)
    local b = ui_bool(key, value)
    if b.v ~= (value and true or false) then b.v = value and true or false end
    if imgui.Checkbox(label .. '##' .. key, b) then return b.v and true or false end
    return nil
end

local function input_text(key, label, value, size)
    local b = ui.bufs[key]
    if not b then
        b = imgui.ImBuffer(size or 128)
        write_buffer(b, value or '')
        ui.bufs[key] = b
    end
    if imgui.InputText(label .. '##' .. key, b) then return read_buffer(b), true end
    return value, false
end

local function button(label, width)
    if width then return imgui.Button(label, imgui.ImVec2(width, 0)) end
    return imgui.Button(label)
end

local function same_line()
    imgui.SameLine(0, 6)
end

local function text_colored(text, r, g, b)
    imgui.TextColored(imgui.ImVec4(r, g, b, 1.0), text)
end

local function set_export_path(path)
    ui.export_path = path
    local b = ui.bufs['export_path']
    if b then write_buffer(b, path) end
end

function new_zone_at_player()
    local p = state.player
    if not p then
        msg('Jogador nao encontrado (o jogo ja carregou?)', 255, 150, 90)
        return nil
    end
    local z = new_zone()
    z.cx, z.cy = p.x, p.y
    z.zb, z.zt = ctrunc(p.z) - 2, ctrunc(p.z) + 25
    z.hw, z.hl = 30, 30
    z.name = string.format('Zona %d (%.0f, %.0f)', #state.zones + 1, p.x, p.y)
    add_zone(z)
    msg(string.format('Zona %d criada em %.0f, %.0f, %.0f', #state.zones, p.x, p.y, p.z), 130, 255, 130)
    return z
end

--=============================================================================
-- partes da interface
--=============================================================================
local function ui_header()
    -- linha 1: atalho + status rapido
    text_colored(string.format('Abrir: segure %s + %s   |   Fechar: X da janela',
        key_name(state.open_combo[1]), key_name(state.open_combo[2])), 0.62, 0.80, 1.0)

    local p = state.player
    local st = Game.last_status
    local parts = {}
    if p then
        parts[#parts + 1] = string.format('Jogador %.0f, %.0f, %.0f', p.x, p.y, p.z)
    else
        parts[#parts + 1] = 'Jogador: (carregando...)'
    end
    parts[#parts + 1] = 'zonas: ' .. #state.zones
    local live_txt = 'off'
    if state.live_apply then
        live_txt = Game.ok and (Game.applied .. ' no jogo') or 'sem memoria'
    end
    parts[#parts + 1] = 'live: ' .. live_txt
    if st then
        parts[#parts + 1] = string.format('clima %s%s', WEATHER_NAMES[st.weather] or '?',
            has_flag(st.flags_player, FLAG_NORAIN) and ' (SEM CHUVA)' or '')
    end
    imgui.Text(table.concat(parts, '   |   '))

    if not Game.ok then
        text_colored('Memoria do jogo: OFF (' .. tostring(Game.error or '?') ..
            ') - a zona funciona no jogo, mas o live apply esta desligado', 1.0, 0.65, 0.30)
    end

    -- linha 3: acoes principais, sempre a mao
    if button('Nova zona no player', 170) then new_zone_at_player() end
    same_line()
    if button('Aplicar no jogo: ' .. (state.live_apply and 'ON' or 'OFF'), 180) then
        state.live_apply = not state.live_apply
        MarkLiveDirty()
        msg('Aplicar no jogo: ' .. (state.live_apply and 'LIGADO' or 'DESLIGADO'), 140, 220, 255)
    end
    same_line()
    if button('Overlay 3D + HUD: ' .. (state.overlays and 'ON' or 'OFF'), 185) then
        state.overlays = not state.overlays
        state.hud = state.overlays
    end
    same_line()
    if button('Fechar menu (X)', 140) then set_ui(false) end

    if state.last_msg ~= '' then
        local c = state.last_msg_color
        text_colored(state.last_msg, c.r / 255, c.g / 255, c.b / 255)
    end
    if ui.error then
        text_colored('ERRO: ' .. ui.error, 1.0, 0.45, 0.45)
        same_line()
        if button('limpar##clearerr', 70) then ui.error = nil end
    end
end

local function ui_page_bar()
    for _, pg in ipairs(PAGES) do
        if imgui.Selectable(pg.name .. '##page' .. pg.id, ui.page == pg.id) then
            ui.page = pg.id
        end
        same_line()
    end
    imgui.NewLine()
end

local function ui_flags(z)
    imgui.Text('Flags (atributos da zona)')
    if button('Sem chuva', 100) then z.flags = FLAG_NORAIN MarkLiveDirty() end
    same_line()
    if button('Sem chuva + audio interno', 170) then z.flags = bit.bor(FLAG_NORAIN, 0x0200) MarkLiveDirty() end
    same_line()
    if button('Zona militar', 110) then z.flags = bit.bor(z.flags, 0x1000) MarkLiveDirty() end
    same_line()
    if button('Limpar', 70) then z.flags = 0 MarkLiveDirty() end

    local function flag_checkbox(f)
        local res = checkbox('flag' .. f.bit, f.name, has_flag(z.flags, f.bit))
        if res ~= nil then
            if res then
                z.flags = bit.bor(z.flags, f.bit)
            else
                z.flags = bit.band(z.flags, bit.bxor(FLAG_ALL, f.bit))
            end
            MarkLiveDirty()
        end
        if imgui.IsItemHovered() then imgui.SetTooltip(f.desc) end
    end

    -- duas colunas, se o binding de Columns existir e funcionar
    local used_columns = false
    if columns_ok then
        local okc = pcall(function()
            imgui.Columns(2, 'czc_flags', false)
            for _, f in ipairs(FLAGS) do
                flag_checkbox(f)
                imgui.NextColumn()
            end
            imgui.Columns(1)
        end)
        if okc then
            used_columns = true
        else
            columns_ok = false
            log('Columns do ImGui falhou - usando uma coluna')
        end
    end
    if not used_columns then
        for _, f in ipairs(FLAGS) do flag_checkbox(f) end
    end

    local v, changed = slider_int('flags_int', 'Flags (decimal)', bit.band(ctrunc(z.flags), FLAG_ALL), 0, FLAG_ALL)
    if changed then z.flags = bit.band(v, FLAG_ALL) MarkLiveDirty() end
    same_line()
    imgui.Text(string.format('= 0x%04X (%s)', bit.band(ctrunc(z.flags), FLAG_ALL), flag_list(z.flags)))
end

local function ui_editor()
    local z = selected_zone()
    if not z then
        imgui.Text('Nenhuma zona na lista.')
        if button('Criar zona na posicao do jogador', 260) then new_zone_at_player() end
        return
    end

    local name, changed_name = input_text('zone_name', 'Nome', z.name, 64)
    if changed_name then z.name = name end
    same_line()
    local en = checkbox('zone_enabled', 'Ativa', z.enabled)
    if en ~= nil then z.enabled = en MarkLiveDirty() end
    same_line()
    local lv = checkbox('zone_live', 'Ao vivo', z.live ~= false)
    if lv ~= nil then z.live = lv MarkLiveDirty() end

    imgui.Separator()
    local v, changed
    imgui.Text('Centro (mundo)')
    v, changed = drag_float('cz_cx', 'X', z.cx, 1.0, -6000, 6000, '%.2f')
    if changed then z.cx = v MarkLiveDirty() end
    same_line()
    v, changed = drag_float('cz_cy', 'Y', z.cy, 1.0, -6000, 6000, '%.2f')
    if changed then z.cy = v MarkLiveDirty() end
    same_line()
    if button('Usar posicao do jogador', 190) and state.player then
        z.cx, z.cy = state.player.x, state.player.y
        MarkLiveDirty()
    end

    imgui.Text('Tamanho: meia largura X / meia altura Y (metros)')
    local hx, hy, ang = native_to_view(z)
    local v2, v3, v4
    local ch1, ch2, ch3
    v2, ch1 = drag_float('cz_hx', 'Meia largura X', hx, 0.5, 0.5, 3000, '%.2f')
    same_line()
    v3, ch2 = drag_float('cz_hy', 'Meia altura Y', hy, 0.5, 0.5, 3000, '%.2f')
    same_line()
    v4, ch3 = drag_float('cz_ang', 'Rotacao (graus)', ang, 0.5, -90, 90, '%.2f')
    if ch1 or ch2 or ch3 then
        local nat = view_to_native(v2, v3, v4)
        z.hw, z.hl, z.sx, z.sy = nat.hw, nat.hl, nat.sx, nat.sy
        MarkLiveDirty()
    end
    same_line()
    if button('Zerar rotacao', 120) then z.sx, z.sy = 0, 0 MarkLiveDirty() end
    imgui.Text(string.format('Campos do IPL: Width=%.3f  Length=%.3f  Unknown1=%.3f  Unknown2=%.3f',
        z.hw, z.hl, z.sx, z.sy))

    imgui.Text('Altura (Z absoluto do mundo)')
    v, changed = drag_float('cz_zb', 'Bottom', z.zb, 0.5, -200, 1500, '%.2f')
    if changed then z.zb = v MarkLiveDirty() end
    same_line()
    v, changed = drag_float('cz_zt', 'Top', z.zt, 0.5, -200, 2000, '%.2f')
    if changed then z.zt = v MarkLiveDirty() end
    same_line()
    if button('Z do jogador (-2 / +25)', 190) and state.player then
        z.zb, z.zt = ctrunc(state.player.z) - 2, ctrunc(state.player.z) + 25
        MarkLiveDirty()
    end

    imgui.Separator()
    if imgui.CollapsingHeader('Espelho (experimental)##mirror') then
        local mir = checkbox('zone_mirror', 'Usar como zona de espelho', z.mirror)
        if mir ~= nil then z.mirror = mir MarkLiveDirty() end
        if z.mirror then
            v, changed = drag_float('cz_cm', 'Cm (posicao do plano)', z.cm, 1.0, -6000, 6000, '%.3f')
            if changed then z.cm = v MarkLiveDirty() end
            v, changed = drag_float('cz_vx', 'Vx', z.vx, 1.0, -1, 1, '%.0f')
            if changed then z.vx = ctrunc(v) MarkLiveDirty() end
            same_line()
            v, changed = drag_float('cz_vy', 'Vy', z.vy, 1.0, -1, 1, '%.0f')
            if changed then z.vy = ctrunc(v) MarkLiveDirty() end
            same_line()
            v, changed = drag_float('cz_vz', 'Vz', z.vz, 1.0, -1, 1, '%.0f')
            if changed then z.vz = ctrunc(v) MarkLiveDirty() end
        end
    end

    imgui.Separator()
    local comment, changed_comment = input_text('zone_comment', 'Comentario (# no IPL)', z.comment, 128)
    if changed_comment then z.comment = comment end
    imgui.Text('Linha do IPL:')
    text_colored(ipl_line(z, true), 0.55, 0.85, 1.0)
    if button('Copiar linha', 110) then
        if copy_text(ipl_line(z, true)) then msg('Linha copiada.', 140, 220, 255) end
    end
    same_line()
    if button('Duplicar zona', 120) then
        local copy = new_zone(z)
        copy.name = z.name .. ' (copia)'
        copy.cx = z.cx + 5
        add_zone(copy)
    end
    same_line()
    if button('Ir para a zona', 120) then
        local cx, cy, cz = zone_center_world(z)
        local ok = pcall(setCharCoordinates, PLAYER_PED, cx, cy, math.max(cz, z.zb) + 1.5)
        if ok then msg('Teleportado para a zona.', 140, 220, 255) end
    end
    same_line()
    if button('Remover zona', 120) then
        table.remove(state.zones, state.selected)
        if state.selected > #state.zones then state.selected = math.max(1, #state.zones) end
        MarkLiveDirty()
        msg('Zona removida.', 255, 190, 120)
    end
end

local function ui_list()
    imgui.Text('Lista de zonas (' .. #state.zones .. ')')
    local remove
    ui_child('czc_list', imgui.ImVec2(0, 110), function()
        for i, z in ipairs(state.zones) do
            -- os botoes vem primeiro: assim o X fica sempre no mesmo lugar,
            -- sem depender do tamanho do nome da zona
            if button('X##del' .. i, 24) then remove = i end
            same_line()
            if button('^##up' .. i, 24) then
                if i > 1 then
                    state.zones[i], state.zones[i - 1] = state.zones[i - 1], state.zones[i]
                    state.selected = i - 1
                    MarkLiveDirty()
                end
            end
            same_line()
            if imgui.Selectable(string.format('%d. %s [%s]%s##sel%d', i, z.name, flag_list(z.flags),
                z.enabled and '' or ' (off)', i), i == state.selected) then
                state.selected = i
            end
        end
    end)
    if remove then
        table.remove(state.zones, remove)
        if state.selected > #state.zones then state.selected = math.max(1, #state.zones) end
        MarkLiveDirty()
        msg('Zona removida.', 255, 190, 120)
    end
end

local function ui_page_zones()
    ui_child('czc_page_zonas', imgui.ImVec2(0, 0), function()
        ui_list()
        imgui.Separator()
        ui_editor()
        local z = selected_zone()
        if z then
            imgui.Separator()
            ui_flags(z)
        end
    end)
end

local function ui_page_export()
    ui_child('czc_page_export', imgui.ImVec2(0, 0), function()
        imgui.Text('Exportar')
        local path = ui.export_path or EXPORT_FILE or 'cull.ipl'
        local newpath, chp = input_text('export_path', 'Arquivo IPL', path, 260)
        if chp then ui.export_path = newpath end

        local en = checkbox('only_enabled', 'Somente zonas ativas', state.only_enabled)
        if en ~= nil then state.only_enabled = en end
        same_line()
        local pc = checkbox('per_zone_comments', 'Comentario por zona', state.per_zone_comments)
        if pc ~= nil then state.per_zone_comments = pc end
        same_line()
        local mi = checkbox('include_mirror_export', 'Exportar espelhos', state.include_mirror_export)
        if mi ~= nil then state.include_mirror_export = mi end

        if button('Exportar IPL', 130) then export_ipl(ui.export_path or path) end
        same_line()
        if button('Pacote ModLoader', 150) then
            export_modloader_package(dirname(ui.export_path or path or '') or EXPORT_DIR)
        end
        same_line()
        if button('Copiar IPL', 110) then
            local text, n = build_ipl_text(state.zones, { only_enabled = state.only_enabled,
                per_zone_comments = state.per_zone_comments, include_mirror = state.include_mirror_export })
            if copy_text(text) then
                msg(string.format('%d zona(s) copiada(s) para o clipboard.', n), 140, 220, 255)
            end
        end
        if EXPORT_DIR then imgui.TextWrapped('Pasta: ' .. EXPORT_DIR) end

        imgui.Separator()
        imgui.Text('Importar')
        local ipath = ui.import_path or (EXPORT_DIR and join(EXPORT_DIR, 'cull.ipl') or '')
        local nip, chi = input_text('import_path', 'Arquivo IPL de entrada', ipath, 260)
        if chi then ui.import_path = nip end
        if button('Importar arquivo', 140) then import_from_file(ui.import_path or ipath) end
        same_line()
        if button('Colar do clipboard', 150) then
            local text
            if type(getClipboardText) == 'function' then
                local ok, t = pcall(getClipboardText)
                if ok then text = t end
            end
            if text and #text > 0 then
                import_from_text(text)
            else
                msg('Nao consegui ler o clipboard.', 255, 180, 90)
            end
        end
        same_line()
        if button('Exemplo', 80) then
            local z = new_zone()
            z.name = 'Exemplo - sem chuva'
            z.flags = FLAG_NORAIN
            add_zone(z)
            msg('Zona de exemplo adicionada.', 140, 220, 255)
        end
        imgui.TextWrapped('O jogo le o IPL quando carrega o mapa. Para testar na hora, ligue "Aplicar no jogo".')
    end)
end

local function ui_page_game()
    ui_child('czc_page_game', imgui.ImVec2(0, 0), function()
        imgui.Text('Zonas de cull que o jogo ja tem carregadas (leitura da memoria)')
        local show = checkbox('show_game_zones', 'Mostrar no overlay', state.show_game_zones)
        if show ~= nil then state.show_game_zones = show end
        same_line()
        local auto = checkbox('auto_scan_game', 'Ler automaticamente', state.auto_scan_game)
        if auto ~= nil then state.auto_scan_game = auto end
        local r = slider_int('gz_radius', 'Raio de leitura (m)', state.game_zone_radius, 50, 2000)
        state.game_zone_radius = r
        same_line()
        local m = slider_int('gz_max', 'Maximo', state.game_zone_max, 10, 400)
        state.game_zone_max = m
        if button('Ler agora', 110) then
            local n = scan_game_zones(state.player and state.player.x, state.player and state.player.y)
            msg(string.format('%d zona(s) lida(s) da memoria.', n), 140, 220, 255)
        end
        same_line()
        if button('Copiar para a lista', 150) then import_from_game() end

        local st = Game.last_status
        imgui.Text(string.format('O jogo tem %d zonas (+%d espelhos) | lidas agora: %d',
            st and st.attr_count or 0, st and st.mirror_count or 0, #state.game_zones))
        if st then
            imgui.Text(string.format('Flags aplicadas no jogador agora: %s', flag_list(st.flags_player)))
        end
        imgui.TextWrapped('Os espelhos (reflexo no chao) usam Cm/direcao. Copiar uma zona do jogo traz ela pronta para editar.')
    end)
end

local function ui_page_config()
    ui_child('czc_page_config', imgui.ImVec2(0, 0), function()
        local changed
        imgui.Text('Overlay 3D')
        local lbl = checkbox('show_labels', 'Mostrar nomes', state.show_labels)
        if lbl ~= nil then state.show_labels = lbl end
        same_line()
        local fac = checkbox('overlay_faces', 'Preencher faces (solido)', state.overlay_faces ~= false)
        if fac ~= nil then state.overlay_faces = fac end
        same_line()
        local pil = checkbox('overlay_pillars', 'Pilares nas quinas', state.overlay_pillars ~= false)
        if pil ~= nil then state.overlay_pillars = pil end
        same_line()
        local wm = checkbox('overlay_with_menu', 'Mostrar com o menu aberto', state.overlay_with_menu)
        if wm ~= nil then state.overlay_with_menu = wm end

        imgui.Text('Estilo:')
        local styles = { { 'solid', ' Solido ' }, { 'glass', ' Vidro ' }, { 'wire', ' So contorno ' } }
        for _, s in ipairs(styles) do
            same_line()
            if imgui.Selectable(s[2] .. '##style' .. s[1], (state.overlay_style or 'solid') == s[1]) then
                state.overlay_style = s[1]
                if s[1] == 'wire' then state.overlay_faces = false else state.overlay_faces = true end
            end
        end
        local d = slider_int('ov_dist', 'Distancia maxima do overlay (m)', state.overlay_max_dist, 30, 2000)
        state.overlay_max_dist = d
        same_line()
        local only = checkbox('only_sel', 'So a zona selecionada', state.only_selected_overlay)
        if only ~= nil then state.only_selected_overlay = only end
        local mz = slider_int('ov_max_zones', 'Maximo de zonas desenhadas', state.overlay_max_zones, 1, 120)
        state.overlay_max_zones = mz
        local v
        v, changed = drag_float('ov_off_x', 'Ajuste fino X (px)', state.overlay_offset_x, 0.5, -200, 200, '%.1f')
        if changed then state.overlay_offset_x = v end
        same_line()
        v, changed = drag_float('ov_off_y', 'Ajuste fino Y (px)', state.overlay_offset_y, 0.5, -200, 200, '%.1f')
        if changed then state.overlay_offset_y = v end

        local z = selected_zone()
        if z then
            imgui.Text('Cor da zona selecionada')
            local rr = slider_int('col_r', 'R', z.color.r, 0, 255)
            if rr ~= z.color.r then z.color.r = rr end
            same_line()
            local gg = slider_int('col_g', 'G', z.color.g, 0, 255)
            if gg ~= z.color.g then z.color.g = gg end
            same_line()
            local bb = slider_int('col_b', 'B', z.color.b, 0, 255)
            if bb ~= z.color.b then z.color.b = bb end
        end

        imgui.Separator()
        imgui.Text('HUD')
        local hud = checkbox('hud', 'Mostrar HUD', state.hud)
        if hud ~= nil then state.hud = hud end
        same_line()
        local ov = checkbox('overlays', 'Mostrar overlay das zonas', state.overlays)
        if ov ~= nil then state.overlays = ov end
        same_line()
        local rim = checkbox('render_in_menu', 'Desenhar no menu de pausa', state.render_in_menu)
        if rim ~= nil then state.render_in_menu = rim end
        local fh = slider_int('font_height', 'Tamanho da fonte do HUD', state.font_height, 6, 16)
        if fh ~= state.font_height then
            state.font_height = fh
            font_dirty = true
        end

        imgui.Separator()
        imgui.Text('Atalho do menu (segurar as duas teclas)')
        local combo_on = checkbox('open_combo_enabled', 'Usar o atalho', state.open_combo_enabled)
        if combo_on ~= nil then state.open_combo_enabled = combo_on end
        same_line()
        imgui.Text(string.format('   %s + %s', key_name(state.open_combo[1]), key_name(state.open_combo[2])))
        if state.capture then
            text_colored('Pressione a tecla para ' .. (state.capture == 'open1' and 'a 1a' or 'a 2a') ..
                ' tecla do atalho (ESC cancela)...', 1.0, 0.85, 0.3)
        else
            if button('Trocar 1a tecla', 130) then state.capture = 'open1' end
            same_line()
            if button('Trocar 2a tecla', 130) then state.capture = 'open2' end
            same_line()
            if button('Voltar para C + L', 140) then
                state.open_combo = { vkeys.VK_C or 0x43, vkeys.VK_L or 0x4C }
                msg('Atalho do menu: segure C + L', 140, 220, 255)
            end
        end
        local lock = checkbox('lock_player', 'Travar os controles com o menu aberto', state.lock_player)
        if lock ~= nil then state.lock_player = lock end

        if imgui.CollapsingHeader('Atalhos extras (opcional - o menu ja tem tudo)##hotkeys') then
            local key_names = { 'menu', 'new_zone', 'live', 'overlay', 'export' }
            local labels = { menu = 'Menu', new_zone = 'Nova zona', live = 'Live apply',
                overlay = 'Overlay/HUD', export = 'Exportar' }
            local vks = { { 0, 'Nenhuma' }, { vkeys.VK_F1, 'F1' }, { vkeys.VK_F2, 'F2' },
                { vkeys.VK_F3, 'F3' }, { vkeys.VK_F4, 'F4' }, { vkeys.VK_F5, 'F5' }, { vkeys.VK_F6, 'F6' },
                { vkeys.VK_F7, 'F7' }, { vkeys.VK_F8, 'F8' }, { vkeys.VK_F9, 'F9' },
                { vkeys.VK_F10, 'F10' }, { vkeys.VK_F11, 'F11' }, { vkeys.VK_F12, 'F12' } }
            for _, key in ipairs(key_names) do
                imgui.Text(labels[key] .. ':')
                for _, vk in ipairs(vks) do
                    same_line()
                    if imgui.Selectable(vk[2] .. '##k' .. key .. vk[1], state.keys[key] == vk[1]) then
                        state.keys[key] = vk[1]
                    end
                end
            end
        end

        imgui.Separator()
        imgui.Text('Arquivos e memoria')
        local dry = checkbox('dry_run', 'Modo seguro (nao mexe na memoria)', state.dry_run)
        if dry ~= nil then
            state.dry_run = dry
            if dry then
                live_reset()
                Game.ok = false
                Game.error = 'modo seguro ligado'
            else
                init_memory()
            end
            MarkLiveDirty()
        end
        same_line()
        local ap = checkbox('auto_pack', 'Exportar pacote ModLoader', state.auto_pack_modloader)
        if ap ~= nil then state.auto_pack_modloader = ap end
        same_line()
        local al = checkbox('auto_load', 'Carregar save ao iniciar', state.auto_load_save)
        if al ~= nil then state.auto_load_save = al end

        if button('Salvar config', 130) then save_config() end
        same_line()
        if button('Carregar config', 130) then load_config() end
        same_line()
        if button('Limpar lista', 110) then
            state.zones = {}
            state.selected = 1
            MarkLiveDirty()
            msg('Lista de zonas limpa.', 255, 190, 120)
        end
        if SAVE_FILE then imgui.TextWrapped('Save: ' .. SAVE_FILE) end
    end)
end

local function ui_page_help()
    ui_child('czc_page_help', imgui.ImVec2(0, 0), function()
        imgui.TextWrapped('ABRIR: segure ' .. key_name(state.open_combo[1]) .. ' + ' ..
            key_name(state.open_combo[2]) .. '   |   FECHAR: clique no X da janela.')
        imgui.Separator()
        imgui.TextWrapped('1) Em "Zonas": clique em "Nova zona no player" - a posicao do jogador vira o centro da zona.')
        imgui.TextWrapped('2) Ajuste o tamanho (meia largura X / meia altura Y, em metros) e a altura (Bottom/Top, Z do mundo).')
        imgui.TextWrapped('3) Marque NO_RAIN para a zona nao ter chuva (e nem helicoptero de policia).')
        imgui.TextWrapped('4) Com "Aplicar no jogo" ligado o efeito vale na hora: ande para dentro e para fora e olhe o HUD.')
        imgui.TextWrapped('5) Em "Exportar": gere o .ipl (ou o Pacote ModLoader, que cria cull.ipl + gta.dat prontos).')
        imgui.Separator()
        imgui.TextWrapped('O overlay mostra a caixa da zona: as faces so ficam visiveis quando olhamos para o lado de fora ' ..
            'delas (como uma caixa de verdade), e o que esta mais longe fica mais transparente. ' ..
            'Ajuste o estilo em Config (Solido / Vidro / So contorno).')
        imgui.Separator()
        imgui.TextWrapped('O box usa MEIO tamanho: 30 = 60x60 metros. Bottom/Top sao Z absolutos do mundo.')
        imgui.TextWrapped('Cull zone de IPL so vale quando o jogo carrega o mapa - o live apply e para testar na hora.')
        imgui.TextWrapped('Em jogo que nao seja 1.0 US, deixe o "Modo seguro" ligado: a memoria nao e tocada.')
    end)
end

local function build_ui()
    local sw, sh = screen_size()
    local w = math.min(720, sw - 20)
    local h = math.min(700, sh - 30)
    imgui.SetNextWindowSize(imgui.ImVec2(w, h), imgui.Cond.FirstUseEver)
    imgui.SetNextWindowPos(imgui.ImVec2(sw / 2 - w / 2, 15), imgui.Cond.FirstUseEver)

    local open = imgui.Begin('Cull Zone Creator v' .. VERSION, ui.show)
    local ok, err = pcall(function()
        if not open then return end
        ui_section('cabecalho', ui_header)
        ui_section('paginas', ui_page_bar)
        ui_section('pagina', function()
            if ui.page == 1 then
                ui_page_zones()
            elseif ui.page == 2 then
                ui_page_export()
            elseif ui.page == 3 then
                ui_page_game()
            elseif ui.page == 4 then
                ui_page_config()
            else
                ui_page_help()
            end
        end)
    end)
    -- o End() NUNCA pode ser pulado: e isso que evita o crash
    -- "Mismatched Begin()/End() calls" do ImGui
    pcall(imgui.End)
    if not ok then ui_error('janela', err) end

    -- se o jogador fechou a janela no X, mantem o estado em sincronia
    if ui.show and ui.show.v ~= state.ui_show then
        state.ui_show = ui.show.v and true or false
    end
end

-- chamado pelo Moon ImGui a cada frame (de dentro do onD3DPresent da lib).
-- O build_ui ja protege cada secao e sempre fecha a janela; este pcall e a
-- ultima linha de defesa para nunca deixar o ImGui com Begin sem End.
local function draw_ui_frame()
    local ok, err = pcall(build_ui)
    if not ok then
        ui.error = tostring(err)
        log('erro na interface: %s', tostring(err))
    end
end

--=============================================================================
-- SAVE / LOAD
--=============================================================================
function save_config(silent)
    if not SAVE_FILE then return false end
    ensure_dir(dirname(SAVE_FILE))
    local data = {
        version = VERSION,
        settings = {
            live_apply = state.live_apply,
            overlays = state.overlays,
            hud = state.hud,
            show_labels = state.show_labels,
            overlay_faces = state.overlay_faces,
            overlay_pillars = state.overlay_pillars,
            overlay_style = state.overlay_style,
            overlay_max_zones = state.overlay_max_zones,
            overlay_offset_x = state.overlay_offset_x,
            overlay_offset_y = state.overlay_offset_y,
            overlay_with_menu = state.overlay_with_menu,
            show_game_zones = state.show_game_zones,
            only_selected_overlay = state.only_selected_overlay,
            overlay_max_dist = state.overlay_max_dist,
            auto_scan_game = state.auto_scan_game,
            game_zone_radius = state.game_zone_radius,
            game_zone_max = state.game_zone_max,
            only_enabled = state.only_enabled,
            per_zone_comments = state.per_zone_comments,
            include_mirror_export = state.include_mirror_export,
            auto_pack_modloader = state.auto_pack_modloader,
            font_height = state.font_height,
            render_in_menu = state.render_in_menu,
            auto_load_save = state.auto_load_save,
            dry_run = state.dry_run,
            open_combo = state.open_combo,
            open_combo_enabled = state.open_combo_enabled,
            lock_player = state.lock_player,
        },
        -- 'hotkeys' (novo): os atalhos extras ficam separados para saves antigos
        -- com F7/F8/... nao sobrescreverem o atalho C + L
        hotkeys = state.keys,
        export_path = ui.export_path or EXPORT_FILE,
        import_path = ui.import_path,
        zones = state.zones,
    }
    local ok, err = write_file(SAVE_FILE, serialize(data))
    if not ok then
        log('falha ao salvar config: %s', tostring(err))
        return false
    end
    if not silent then msg('Config salva em ' .. SAVE_FILE, 140, 255, 140) end
    return true
end

function load_config(silent)
    if not SAVE_FILE then return false end
    local text = read_file(SAVE_FILE)
    if not text then
        if not silent then msg('Save nao encontrado: ' .. SAVE_FILE, 255, 180, 90) end
        return false
    end
    local data = deserialize(text)
    if type(data) ~= 'table' then return false end

    local s = data.settings
    if type(s) == 'table' then
        for k, v in pairs(s) do
            if k ~= 'keys' and state[k] ~= nil and type(state[k]) == type(v) then
                state[k] = v
            end
        end
    end
    if type(data.hotkeys) == 'table' and type(state.keys) == 'table' then
        for k, v in pairs(data.hotkeys) do
            if state.keys[k] ~= nil and type(v) == 'number' and v >= 0 and v < 256 then state.keys[k] = v end
        end
    end
    if type(state.open_combo) ~= 'table' or #state.open_combo < 2 then
        state.open_combo = { vkeys.VK_C or 0x43, vkeys.VK_L or 0x4C }
    end
    if type(data.zones) == 'table' and #data.zones > 0 then
        state.zones = {}
        for _, z in ipairs(data.zones) do
            if type(z) == 'table' then add_zone(new_zone(z)) end
        end
        state.selected = 1
    end
    ui.export_path = data.export_path or ui.export_path
    ui.import_path = data.import_path or ui.import_path
    if ui.export_path then set_export_path(ui.export_path) end
    MarkLiveDirty()
    if not silent then msg(string.format('Config carregada (%d zonas).', #state.zones), 140, 255, 140) end
    return true
end

--=============================================================================
-- CAPTURA DA TECLA DO ATALHO (onWindowMessage)
--=============================================================================
local function handle_window_message(message, wparam)
    if not state.capture then return end
    if message ~= WM_KEYDOWN and message ~= WM_SYSKEYDOWN then return end
    local vk = ctrunc(wparam)
    if vk == 0x1B then
        state.capture = nil
        msg('Troca de tecla cancelada.', 255, 190, 120)
    elseif vk == 0x10 or vk == 0x11 or vk == 0x12 then
        return   -- Shift/Ctrl/Alt sozinhos nao valem como tecla do atalho
    else
        local which = state.capture
        state.capture = nil
        if which == 'open1' then
            state.open_combo[1] = vk
        elseif which == 'open2' then
            state.open_combo[2] = vk
        end
        state.combo_was_down = true   -- evita abrir o menu com a tecla recem-escolhida
        msg(string.format('Atalho do menu: segure %s + %s', key_name(state.open_combo[1]),
            key_name(state.open_combo[2])), 140, 220, 255)
    end
    if type(consumeWindowMessage) == 'function' then pcall(consumeWindowMessage, true, true) end
end

--=============================================================================
-- LOOP PRINCIPAL
--=============================================================================
local function key_just_pressed(vk)
    if not vk or vk == 0 then return false end
    if type(isKeyJustPressed) == 'function' then
        local ok, res = pcall(isKeyJustPressed, vk)
        if ok then return res end
    end
    if type(wasKeyPressed) == 'function' then
        local ok, res = pcall(wasKeyPressed, vk)
        if ok then return res end
    end
    return false
end

-- tecla esta sendo SEGURADA agora
local function key_held(vk)
    if not vk or vk == 0 then return false end
    if type(isKeyDown) == 'function' then
        local ok, res = pcall(isKeyDown, vk)
        if ok then return res end
    end
    return key_just_pressed(vk)
end

local function update_player()
    local playing = false
    local ok = pcall(function() playing = isPlayerPlaying(PLAYER_HANDLE) end)
    if ok and playing and doesCharExist(PLAYER_PED) then
        local x, y, z = getCharCoordinates(PLAYER_PED)
        if type(x) == 'number' then
            state.player = { x = x, y = y, z = z }
            return
        end
    end
    state.player = nil
end

function set_ui(show)
    show = show and true or false
    state.ui_show = show
    if ui.show then ui.show.v = show end
    if show then
        state.combo_was_down = true
        pcall(printStyledString, '[Cull Zone Creator] menu aberto - feche no X da janela', 1500, 4)
    else
        pcall(printStyledString, '[Cull Zone Creator] menu fechado - C + L abre de novo', 1500, 4)
    end
end

function toggle_ui()
    set_ui(not state.ui_show)
end

-- atalho principal: segurar as duas teclas abertas abre o menu
local function handle_open_combo()
    if state.ui_show then
        -- o menu ja esta aberto: e preciso SOLTAR as teclas antes de abrir de novo
        -- (assim fechar no X enquanto ainda segura C + L nao reabre na hora)
        state.combo_was_down = true
        return
    end
    local down = false
    if state.open_combo_enabled and not state.capture then
        local k1, k2 = state.open_combo[1], state.open_combo[2]
        down = (k1 ~= 0 and k2 ~= 0) and key_held(k1) and key_held(k2)
    end
    if down and not state.combo_was_down then
        set_ui(true)
    end
    state.combo_was_down = down or false
end

-- atalhos extras (todos desligados por padrao: o menu tem tudo em botoes)
local function handle_keys()
    if key_just_pressed(state.keys.menu) then toggle_ui() end
    if key_just_pressed(state.keys.new_zone) then new_zone_at_player() end
    if key_just_pressed(state.keys.live) then
        state.live_apply = not state.live_apply
        MarkLiveDirty()
        msg('Aplicar no jogo: ' .. (state.live_apply and 'LIGADO' or 'DESLIGADO'), 140, 220, 255)
    end
    if key_just_pressed(state.keys.overlay) then
        state.overlays = not state.overlays
        state.hud = state.overlays
    end
    if key_just_pressed(state.keys.export) then
        if state.auto_pack_modloader then
            export_modloader_package(dirname(ui.export_path or EXPORT_FILE or '') or EXPORT_DIR)
        else
            export_ipl(ui.export_path or EXPORT_FILE)
        end
    end
end

function main()
    if not ok_imgui or not imgui then
        log('ERRO: Moon ImGui nao encontrado (moonloader\\lib\\imgui.lua + MoonImGui.dll).')
        printStringNow('~r~Cull Zone Creator: instale o Moon ImGui', 8000)
        return
    end

    default_paths()
    if state.auto_load_save then load_config(true) end
    init_memory()
    draw_init()

    ui.show = imgui.ImBool(false)
    ui.export_path = ui.export_path or EXPORT_FILE
    ui.import_path = ui.import_path or (EXPORT_DIR and join(EXPORT_DIR, 'cull.ipl') or nil)
    if ui.export_path then set_export_path(ui.export_path) end

    imgui.OnDrawFrame = draw_ui_frame

    addEventHandler('onD3DPresent', function()
        local ok, err = pcall(draw_present)
        if not ok then log('erro no desenho: %s', tostring(err)) end
    end)

    -- le a lista de zonas do jogo na primeira vez
    if Game.ok then scan_game_zones(state.player and state.player.x, state.player and state.player.y) end

    -- captura de tecla para trocar o atalho de abrir o menu
    addEventHandler('onWindowMessage', function(message, wparam, lparam)
        local ok, err = pcall(handle_window_message, message, wparam, lparam)
        if not ok then log('onWindowMessage: %s', tostring(err)) end
    end)

    log('carregado: segure %s + %s para abrir o menu (fecha no X da janela)',
        key_name(state.open_combo[1]), key_name(state.open_combo[2]))
    printStringNow(string.format('~g~Cull Zone Creator ~w~v%s - segure ~b~%s + %s ~w~para o menu',
        VERSION, key_name(state.open_combo[1]), key_name(state.open_combo[2])), 6000)

    local last_status, last_scan = 0, 0
    while true do
        wait(0)
        local now = os.clock()
        local ok, err = pcall(function()
            update_player()
            handle_open_combo()
            handle_keys()

            if font_dirty then
                font_dirty = false
                draw_init()
            end

            if game_dirty then live_apply(false) end

            if Game.ok and (now - last_status) > 0.15 then
                last_status = now
                query_game_status()
            end

            if Game.ok and state.auto_scan_game and (now - last_scan) > 3.0
                and (state.show_game_zones or state.hud) then
                last_scan = now
                scan_game_zones(state.player and state.player.x, state.player and state.player.y)
            end

            imgui.Process = state.ui_show
            imgui.ShowCursor = state.ui_show
            imgui.RenderInMenu = state.render_in_menu
            imgui.LockPlayer = state.lock_player and state.ui_show or false

            draw_begin()
            if state.overlays then build_overlay() end
            if state.hud then build_hud() end
        end)
        if not ok then log('erro no loop: %s', tostring(err)) end
    end
end

function onExitScript()
    pcall(function() save_config(true) end)
    pcall(function() live_reset() end)
    log('finalizado.')
end

--=============================================================================
-- HOOK DE TESTE (nao afeta o jogo; usado pelo harness do repositorio)
--=============================================================================
if _G.CZC_TEST_HOOK then
    _G.CZC_TEST_HOOK({
        VERSION = VERSION,
        A = A,
        FLAGS = FLAGS,
        state = state,
        Game = Game,
        Draw = Draw,
        new_zone = new_zone,
        zone_valid = zone_valid,
        engine_box = engine_box,
        zone_corners = zone_corners,
        zone_contains = zone_contains,
        zone_center_world = zone_center_world,
        view_to_native = view_to_native,
        native_to_view = native_to_view,
        zone_size = zone_size,
        has_flag = has_flag,
        flag_list = flag_list,
        parse_cull_line = parse_cull_line,
        parse_ipl_text = parse_ipl_text,
        ipl_line = ipl_line,
        build_ipl_text = build_ipl_text,
        serialize = serialize,
        deserialize = deserialize,
        float_bits = float_bits,
        to_ascii = to_ascii,
        ctrunc = ctrunc,
        clamp = clamp,
        add_zone = add_zone,
        selected_zone = selected_zone,
        init_memory = init_memory,
        live_apply = live_apply,
        live_reset = live_reset,
        write_zone_def = write_zone_def,
        read_u16 = read_u16,
        read_u32 = read_u32,
        query_game_status = query_game_status,
        scan_game_zones = scan_game_zones,
        import_from_text = import_from_text,
        import_from_file = import_from_file,
        import_from_game = import_from_game,
        export_ipl = export_ipl,
        export_modloader_package = export_modloader_package,
        copy_text = copy_text,
        default_paths = default_paths,
        draw_init = draw_init,
        draw_begin = draw_begin,
        build_overlay = build_overlay,
        build_hud = build_hud,
        draw_present = draw_present,
        build_ui = build_ui,
        ui = ui,
        new_zone_at_player = new_zone_at_player,
        draw_ui_frame = draw_ui_frame,
        ui_child = ui_child,
        ui_section = ui_section,
        ui_page_bar = ui_page_bar,
        ui_page_zones = ui_page_zones,
        ui_page_export = ui_page_export,
        ui_page_game = ui_page_game,
        ui_page_config = ui_page_config,
        ui_page_help = ui_page_help,
        ui_header = ui_header,
        ui_editor = ui_editor,
        ui_list = ui_list,
        ui_flags = ui_flags,
        draw_zone_box = draw_zone_box,
        camera_position = camera_position,
        wall_faces_camera = wall_faces_camera,
        PAGES = PAGES,
        key_name = key_name,
        key_held = key_held,
        key_just_pressed = key_just_pressed,
        handle_keys = handle_keys,
        handle_open_combo = handle_open_combo,
        handle_window_message = handle_window_message,
        set_ui = set_ui,
        toggle_ui = toggle_ui,
        save_config = save_config,
        load_config = load_config,
    })
end
