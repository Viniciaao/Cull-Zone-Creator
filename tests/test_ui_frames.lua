--[[
================================================================================
  Teste de integracao da INTERFACE do Cull Zone Creator (nao precisa do GTA)
================================================================================
  Diferente do test_czc.lua (que testa a logica pura), este aqui carrega o
  script com um Moon ImGui FALSO E ESTRITO:

    * conta a pilha de janelas: Begin/End e BeginChild/EndChild tem que casar.
      Se sobrar janela pendurada, o teste falha - e exatamente esse desbalanco
      que faz o jogo morrer com "Mismatched Begin()/End() calls".
    * permite simular cliques ("clique no botao X") e checar o efeito no estado
      do script (criar zona, apagar zona, trocar de pagina, fechar o menu...).
    * permite injetar erros em widgets para garantir que a interface se recupera
      sem deixar o ImGui quebrado.

  Uso:  python3 tests/run_tests.py        (roda os dois testes)
        lua tests/test_ui_frames.lua moonloader/CullZoneCreator.lua
================================================================================
]]

local SCRIPT_PATH = arg and arg[1] or 'moonloader/CullZoneCreator.lua'

--=============================================================================
-- 1. MEMORIA E FUNCOES DO JOGO (falsas)
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

function readMemory(addr, size) return mem_get(addr, size) end
function writeMemory(addr, size, value) mem_set(addr, size, value) end

--=============================================================================
-- 2. STUBS
--=============================================================================
local GAME = {
    player = { x = 100.0, y = 200.0, z = 12.0 },
    camera = { x = 90.0, y = 190.0, z = 15.0 },
    behind = nil,              -- funcao(x,y,z) -> true = ponto atras da camera
    proj_calls = 0,
    lines = 0, texts = 0, boxes = 0, shape_verts = 0, errors = {},
}

function script_name(name) end
function script_author(author) end
function script_version(version) end
function script_description(desc) end
function printStringNow(text, time) end
function printStyledString(text, time, style)
    if GAME.print_styled_errors then error('printStyledString falhou (simulado)') end
end
function getWorkingDirectory() return '/tmp/czc_test/moonloader' end
function getGameDirectory() return '/tmp/czc_test/gta' end
function doesFileExist(path) return false end
function doesDirectoryExist(path) return true end
function createDirectory(path) return true end
function getScreenResolution() return 1280, 720 end
function localClock() return os.clock() end
function isPauseMenuActive() return GAME.paused or false end
function lockPlayerControl(lock) end
function isPlayerPlaying(player) return GAME.player ~= nil end
function doesCharExist(ped) return GAME.player ~= nil end
function getCharCoordinates(ped)
    local p = GAME.player
    return p.x, p.y, p.z
end
function setCharCoordinates(ped, x, y, z) end
function isKeyJustPressed(key) return false end
function isKeyDown(key) return KEY_DOWN[key] == true end
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
function addEventHandler(name, fn) GAME['event_' .. tostring(name)] = fn end
function getActiveCameraCoordinates()
    local c = GAME.camera
    return c.x, c.y, c.z
end
function convert3DCoordsToScreen(x, y, z)
    GAME.proj_calls = GAME.proj_calls + 1
    if GAME.behind and GAME.behind(x, y, z) then return nil end
    local c = GAME.camera
    return 2600 + (x - c.x) * 0.5, 360 - (y - c.y) * 0.5
end

function renderCreateFont(font, height, flags) return 7 end
function renderGetFontDrawTextLength(font, text) return #text * 6 end
function renderGetFontDrawHeight(font) return 12 end
function renderDrawLine(x1, y1, x2, y2, w, color) GAME.lines = GAME.lines + 1 end
function renderDrawBox(x, y, w, h, color) GAME.boxes = GAME.boxes + 1 end
function renderDrawBoxWithBorder(x, y, w, h, c, bs, bc) GAME.boxes = GAME.boxes + 1 end
function renderFontDrawText(font, text, x, y, color) GAME.texts = GAME.texts + 1 end

KEY_DOWN = {}
PLAYER_HANDLE = 1
PLAYER_PED = 2

--=============================================================================
-- 3. MOON IMGUI FALSO E ESTRITO
--=============================================================================
local ImGuiFake = {
    stack = {},               -- pilha de janelas abertas
    depth = 0,
    max_depth = 0,
    click = nil,              -- label exato que deve ser "clicado"
    clicks_left = 0,
    break_end = false,        -- se true, End()/EndChild() nao chamam nada (simula bug)
    widget_error = nil,       -- label que deve dar erro ao ser desenhado
    errors = {},
    calls = 0,
    frame_checks = 0,
}

local function ig_push(kind, name)
    ImGuiFake.stack[#ImGuiFake.stack + 1] = { kind = kind, name = name }
    local d = #ImGuiFake.stack
    ImGuiFake.depth = d
    if d > ImGuiFake.max_depth then ImGuiFake.max_depth = d end
end

local function ig_pop(kind, name)
    local top = ImGuiFake.stack[#ImGuiFake.stack]
    if not top then
        error(string.format('ImGui: End(%s) sem Begin aberto (pilha vazia)', name or kind), 2)
    end
    if top.kind ~= kind then
        error(string.format('ImGui: %s fechou o que era %s ("%s" != "%s")', kind, top.kind, tostring(name), tostring(top.name)), 2)
    end
    table.remove(ImGuiFake.stack)
    ImGuiFake.depth = #ImGuiFake.stack
end

local function ig_label(label)
    if ImGuiFake.widget_error and label == ImGuiFake.widget_error then
        error('widget "' .. tostring(label) .. '" falhou (simulado)', 2)
    end
    ImGuiFake.calls = ImGuiFake.calls + 1
    if ImGuiFake.clicks_left > 0 and ImGuiFake.click == label then
        ImGuiFake.clicks_left = ImGuiFake.clicks_left - 1
        return true
    end
    return false
end

-- checa que o frame terminou com a pilha limpa
local function ig_check_balanced(where)
    if #ImGuiFake.stack ~= 0 then
        local names = {}
        for _, w in ipairs(ImGuiFake.stack) do names[#names + 1] = w.kind .. ':' .. tostring(w.name) end
        error(string.format('ImGui desbalanceado em %s: faltou End de [%s]', where, table.concat(names, ', ')), 2)
    end
    ImGuiFake.frame_checks = ImGuiFake.frame_checks + 1
end

local fake_imgui = {}
fake_imgui._VERSION = 'fake-1.1.5'
fake_imgui.Process = false
fake_imgui.ShowCursor = false
fake_imgui.RenderInMenu = false
fake_imgui.LockPlayer = false
fake_imgui.OnDrawFrame = nil
fake_imgui.Cond = { FirstUseEver = 4, Always = 1, Once = 2, Appearing = 8 }
fake_imgui.WindowFlags = { NoTitleBar = 1, NoResize = 2, NoMove = 4, NoScrollbar = 8, NoInputs = 512 }
fake_imgui.InputTextFlags = { EnterReturnsTrue = 32 }

function fake_imgui.ImBool(v) return { v = v and true or false } end
function fake_imgui.ImFloat(v) return { v = v or 0 } end
function fake_imgui.ImInt(v) return { v = v or 0 } end
function fake_imgui.ImBuffer(size) return { v = '' } end
function fake_imgui.ImVec2(x, y) return { x = x or 0, y = y or 0 } end
function fake_imgui.ImVec4(x, y, z, w) return { x = x or 0, y = y or 0, z = z or 0, w = w or 0 } end

function fake_imgui.Begin(name, p_open, flags)
    ig_label(name)
    ig_push('Begin', name)
    return true
end
function fake_imgui.End()
    ig_pop('Begin', 'End')
end
function fake_imgui.BeginChild(name, size, border, flags)
    ig_label(name)
    ig_push('BeginChild', name)
    return true
end
function fake_imgui.EndChild()
    ig_pop('BeginChild', 'EndChild')
end
function fake_imgui.Button(label, size) return ig_label(label) end
function fake_imgui.Selectable(label, selected, flags, size) return ig_label(label) end
function fake_imgui.Checkbox(label, b)
    if ig_label(label) then
        b.v = not b.v
        return true
    end
    return false
end
function fake_imgui.InputText(label, buf, flags, cb, data) return ig_label(label) end
function fake_imgui.DragFloat(label, f, speed, vmin, vmax, fmt, power) return ig_label(label) end
function fake_imgui.SliderInt(label, i, vmin, vmax) return ig_label(label) end
function fake_imgui.CollapsingHeader(label) return ig_label(label) end
function fake_imgui.Combo(label, i, items) return ig_label(label) end
function fake_imgui.Text(text) ImGuiFake.calls = ImGuiFake.calls + 1 end
function fake_imgui.TextColored(col, text) ImGuiFake.calls = ImGuiFake.calls + 1 end
function fake_imgui.TextWrapped(text) ImGuiFake.calls = ImGuiFake.calls + 1 end
function fake_imgui.SetTooltip(text) ImGuiFake.calls = ImGuiFake.calls + 1 end
function fake_imgui.SetNextWindowSize(size, cond) end
function fake_imgui.SetNextWindowPos(pos, cond) end
function fake_imgui.SameLine(x, spacing) end
function fake_imgui.NewLine() end
function fake_imgui.Separator()
    if ImGuiFake.widget_error == 'SEPARATOR' then
        error('Separator falhou (simulado)', 2)
    end
    ImGuiFake.calls = ImGuiFake.calls + 1
end
function fake_imgui.Columns(count, id, border)
    if count ~= 1 and (type(count) ~= 'number' or count < 1) then
        error('Columns recebeu um numero invalido: ' .. tostring(count), 2)
    end
    ImGuiFake.calls = ImGuiFake.calls + 1
end
function fake_imgui.NextColumn() end
function fake_imgui.IsItemActive() return false end
function fake_imgui.IsItemHovered(flags) return false end
function fake_imgui.IsItemClicked(button) return false end
function fake_imgui.PushItemWidth(w) end
function fake_imgui.PopItemWidth() end
function fake_imgui.SetCursorPos(x, y) end
function fake_imgui.GetContentRegionAvail() return fake_imgui.ImVec2(300, 300) end
function fake_imgui.CalcTextSize(text) return fake_imgui.ImVec2(#text * 6, 12) end

-- O script nao pode depender de widgets opcionais: Selectable (que se mostrou
-- sem resposta em algumas builds) e TextWrapped/SetTooltip. Se ele voltar a usar
-- algum desses, os testes abaixo quebram de proposito.
fake_imgui.Selectable = nil
fake_imgui.TextWrapped = nil
fake_imgui.SetTooltip = nil

package.loaded['imgui'] = fake_imgui

-- MoonAdditions falso
local fake_shape = {
    clear = function(self) end,
    add_vertex = function(self, x, y, r, g, b, a)
        GAME.shape_verts = GAME.shape_verts + 1
        if type(x) ~= 'number' or x ~= x then error('add_vertex recebeu x invalido: ' .. tostring(x), 2) end
        if type(y) ~= 'number' or y ~= y then error('add_vertex recebeu y invalido: ' .. tostring(y), 2) end
    end,
    draw = function(self, a, b, c, d) end,
    vertices_number = 0,
}
package.loaded['MoonAdditions'] = {
    VERSION = 'fake',
    shape = { new = function() return fake_shape end },
    primitive_type = { LINELIST = 1, TRIANGLELIST = 3 },
    blend_method = { SRCALPHA = 5, INVSRCALPHA = 6 },
    font_style = { GOTHIC = 1, SUBTITLES = 2, MENU = 3, PRICEDOWN = 4 },
    font_align = { CENTER = 1, LEFT = 2, RIGHT = 3 },
}

--=============================================================================
-- 4. CARREGA O SCRIPT
--=============================================================================
local hook
_G.CZC_TEST_HOOK = function(t) hook = t end

local chunk, err = loadfile(SCRIPT_PATH)
if not chunk then error('nao consegui carregar ' .. SCRIPT_PATH .. ': ' .. tostring(err)) end
local ok, loaderr = pcall(chunk)
if not ok then error('erro ao executar o script: ' .. tostring(loaderr)) end
if not hook then error('o hook de teste nao foi chamado') end

--=============================================================================
-- 5. ASSERT
--=============================================================================
local passed, failed = 0, 0
local failures = {}

local function ok(cond, label, extra)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        failures[#failures + 1] = label .. (extra ~= nil and ('  -> ' .. tostring(extra)) or '')
    end
end

--=============================================================================
-- 6. HELPERS DE FRAME
--=============================================================================
local function click(label, times)
    ImGuiFake.click = label
    ImGuiFake.clicks_left = times or 1
end

-- roda um frame completo igual o jogo faz: BeginFrame -> OnDrawFrame -> Render
-- (draw_ui_frame e exatamente a funcao que o script registra em imgui.OnDrawFrame)
local function frame(label)
    local okc, errc = pcall(hook.draw_ui_frame)
    if not okc then
        ok(false, 'frame "' .. label .. '": OnDrawFrame deu erro', errc)
        return false
    end
    ig_check_balanced('frame "' .. label .. '"')
    return true
end

--=============================================================================
-- 6b. CHECAGEM ESTATICA: funcao local usada antes de ser declarada
--
-- Esse foi exatamente o bug que derrubou o jogo com "Mismatched Begin()/End()
-- calls": o botao "Fechar menu" chamava uma funcao local declarada mais
-- abaixo (ou seja, um global nil) -> erro no meio do frame -> End() nao era
-- chamado -> assertion do ImGui no frame seguinte.
--=============================================================================
local function check_locals_defined_first(path)
    local src = io.open(path, 'rb')
    if not src then return end
    local text = src:read('*a')
    src:close()

    -- remove comentarios (-- e --[[ ]]) e strings, para nao confundir
    -- nome citado em texto com nome usado como funcao
    text = text:gsub('%-%-%[%[.-%]%]', '')
    text = text:gsub('%[%[.-%]%]', '')
    text = text:gsub('%-%-[^\n]*', '')
    text = text:gsub("'[^'\n]*'", "''")
    text = text:gsub('"[^"\n]*"', '""')

    local lines = {}
    for line in text:gmatch('[^\n]+') do lines[#lines + 1] = line end

    local declared = {}          -- nome -> linha da primeira declaracao local
    for i, line in ipairs(lines) do
        for name in line:gmatch('local%s+function%s+([%w_]+)') do
            declared[name] = declared[name] or i
        end
        -- 'local a, b = ...' (pega todos os nomes da lista)
        local list = line:match('^%s*local%s+([%w_%s,]+)=')
        if list then
            for name in list:gmatch('([%w_]+)') do
                declared[name] = declared[name] or i
            end
        end
        local single = line:match('^%s*local%s+([%w_]+)%s*$')
        if single then declared[single] = declared[single] or i end
    end

    -- NAME( mas nao metodo/chamada qualificada (t.remove(), obj:remove())
    local function calls_name(line, name)
        local init = 1
        while true do
            local s, e = line:find(name, init, true)
            if not s then return false end
            local before = s > 1 and line:sub(s - 1, s - 1) or ''
            local after = line:sub(e + 1)
            if not before:match('[%w_.:]') and after:match('^%s*%(') then return true end
            init = e + 1
        end
    end

    local problems = {}
    for name, line_no in pairs(declared) do
        if #name > 2 then
            for i = 1, line_no - 1 do
                if calls_name(lines[i], name) then
                    problems[#problems + 1] = string.format(
                        'linha %d chama "%s" antes de ser declarada (linha %d)', i, name, line_no)
                    break
                end
            end
        end
    end
    return problems
end

local problemas = check_locals_defined_first(SCRIPT_PATH) or {}
if #problemas > 0 then
    print('[test_ui_frames] funcoes locais usadas antes da declaracao:')
    for _, p in ipairs(problemas) do print('   ' .. p) end
end
ok(#problemas == 0, 'nenhuma funcao local e usada antes de ser declarada', problemas[1])

--=============================================================================
-- 7. SETUP
--=============================================================================
hook.state.auto_load_save = false
_G.czc_hook = hook             -- usado pelos testes abaixo
hook.draw_init()
hook.state.player = { x = GAME.player.x, y = GAME.player.y, z = GAME.player.z }
hook.ui.show = fake_imgui.ImBool(true)
hook.state.ui_show = true

--=============================================================================
-- 8. TESTES
--=============================================================================
-- 8.1 frames com a lista vazia, em todas as paginas
for _, page in ipairs({ 1, 2, 3, 4, 5 }) do
    hook.ui.page = page
    for i = 1, 3 do
        frame('pagina ' .. page .. ' vazia #' .. i)
    end
    ok(ImGuiFake.stack and #ImGuiFake.stack == 0, 'pagina ' .. page .. ' vazia: pilha do ImGui limpa')
end

-- 8.2 criar zonas pelos botoes do menu
hook.ui.page = 1
hook.state.zones = {}
click('Nova zona no player', 1)
frame('clique em Nova zona no player')
ok(#hook.state.zones == 1, 'botao "Nova zona no player" cria a zona', #hook.state.zones)
ok(hook.state.zones[1] ~= nil and hook.state.zones[1].cx == GAME.player.x,
    'a zona nasce na posicao do jogador', hook.state.zones[1] and hook.state.zones[1].cx)

click('Nova zona no player', 1)
frame('clique em Nova zona no player (2)')
click('Nova zona no player', 1)
frame('clique em Nova zona no player (3)')
ok(#hook.state.zones == 3, 'da para criar varias zonas em sequencia', #hook.state.zones)

-- 8.3 apagar zonas pela lista (o X de cada linha)
click('X##del2', 1)
frame('clique no X da zona 2')
ok(#hook.state.zones == 2, 'o X da lista apaga a zona', #hook.state.zones)
ok(hook.state.selected >= 1 and hook.state.selected <= #hook.state.zones,
    'a zona selecionada continua valida', hook.state.selected)

click('X##del2', 1)
frame('clique no X (de novo)')
click('X##del1', 1)
frame('clique no X da ultima zona')
ok(#hook.state.zones == 0, 'da para apagar todas as zonas', #hook.state.zones)

-- 8.4 criar + apagar + criar (o ciclo que estava travando)
hook.state.zones = {}
for i = 1, 5 do
    click('Nova zona no player', 1)
    frame('ciclo criar #' .. i)
    click('X##del1', 1)
    frame('ciclo apagar #' .. i)
end
ok(#hook.state.zones == 0, 'criar/apagar em sequencia funciona 5 vezes', #hook.state.zones)

-- 8.5 botao "Remover zona" do editor
click('Nova zona no player', 1)
frame('cria uma zona para o editor')
ok(#hook.state.zones == 1, 'zona criada para testar o editor')
click('Remover zona', 1)
frame('clique em Remover zona (editor)')
ok(#hook.state.zones == 0, 'botao "Remover zona" do editor funciona', #hook.state.zones)

-- 8.6 as acoes do cabecalho
hook.state.zones = {}
click('Nova zona no player', 1)
frame('zona para as acoes')
click('Aplicar no jogo: ON', 1)
frame('clique em Aplicar no jogo')
ok(hook.state.live_apply == false, 'o botao desliga o aplicar no jogo', tostring(hook.state.live_apply))
click('Aplicar no jogo: OFF', 1)
frame('clique em Aplicar no jogo (de novo)')
ok(hook.state.live_apply == true, 'o botao liga o aplicar no jogo de novo')

click('Overlay 3D + HUD: ON', 1)
frame('clique em Overlay 3D + HUD')
ok(hook.state.overlays == false, 'o botao desliga o overlay')
click('Overlay 3D + HUD: OFF', 1)
frame('clique em Overlay 3D + HUD (de novo)')
ok(hook.state.overlays == true, 'o botao liga o overlay de novo')

-- 8.7 trocar de pagina clicando
hook.ui.page = 1
click('Exportar##page2', 1)
frame('clique na aba Exportar')
ok(hook.ui.page == 2, 'a aba Exportar abre pelo clique', hook.ui.page)
click('Jogo##page3', 1)
frame('clique na aba Jogo')
ok(hook.ui.page == 3, 'a aba Jogo abre pelo clique', hook.ui.page)
click('Config##page4', 1)
frame('clique na aba Config')
ok(hook.ui.page == 4, 'a aba Config abre pelo clique', hook.ui.page)
click('Ajuda##page5', 1)
frame('clique na aba Ajuda')
ok(hook.ui.page == 5, 'a aba Ajuda abre pelo clique', hook.ui.page)

-- 8.7b selecionar uma zona pelo botao da lista (Labels: '> 1. A##sel1' quando ativa)
hook.ui.page = 1
hook.state.zones = {}
local zA = hook.new_zone()
zA.name = 'A'
hook.add_zone(zA)
local zB = hook.new_zone()
zB.name = 'B'
hook.add_zone(zB)
ok(hook.state.selected == 2, 'a ultima zona criada fica selecionada', hook.state.selected)
click(' 1. A [NoRain]##sel1', 1)
frame('clique na zona 1 da lista')
ok(hook.state.selected == 1, 'o botao da lista seleciona a zona clicada', hook.state.selected)
click(' 2. B [NoRain]##sel2', 1)
frame('clique na zona 2 da lista')
ok(hook.state.selected == 2, 'da para selecionar outra zona', hook.state.selected)

-- 8.8 marcar o flag NO_RAIN na zona pela interface
hook.ui.page = 1
hook.state.zones = {}
click('Nova zona no player', 1)
frame('zona para mexer nos flags')
hook.state.zones[1].flags = 0
click('NoRain##flag8', 1)
frame('clique no flag NoRain')
ok(hook.state.zones[1].flags == 8, 'o checkbox do flag NoRain marca o bit', hook.state.zones[1].flags)
click('NoRain##flag8', 1)
frame('clique no flag NoRain de novo')
ok(hook.state.zones[1].flags == 0, 'o checkbox desmarca o bit', hook.state.zones[1].flags)

-- 8.8b desenho com o menu aberto: quem desenha e o BeforeDrawFrame (fica atras
-- da janela) e o nosso onD3DPresent nao desenha no mesmo frame
hook.state.ui_show = true
hook.ui.show.v = true
hook.state.overlays = true
ok(hook.menu_esta_desenhando() == true, 'com o menu aberto o desenho vai pelo BeforeDrawFrame')

hook.setup_events()          -- registra o BeforeDrawFrame e o onD3DPresent
GAME.lines, GAME.texts, GAME.boxes = 0, 0, 0
hook.draw_begin()
hook.build_overlay()
hook.build_hud()
-- primeira chamada: o BeforeDrawFrame desenha
if type(hook.imgui.BeforeDrawFrame) == 'function' then
    hook.imgui.BeforeDrawFrame()
    ok(GAME.lines > 0, 'BeforeDrawFrame desenha o overlay com o menu aberto', GAME.lines)
    -- segunda chamada no mesmo frame nao pode desenhar de novo (sem duplicar)
    local antes = GAME.lines
    hook.imgui.BeforeDrawFrame()
    ok(GAME.lines == antes, 'o overlay nao e desenhado duas vezes no mesmo frame', GAME.lines - antes)
else
    ok(false, 'imgui.BeforeDrawFrame foi registrado pelo script')
end

-- agora um frame do evento do D3D: com o menu aberto ele NAO desenha
if GAME.event_onD3DPresent then
    GAME.lines, GAME.texts, GAME.boxes = 0, 0, 0
    hook.draw_begin()
    hook.build_overlay()
    hook.build_hud()
    GAME.event_onD3DPresent()
    ok(GAME.lines == 0, 'com o menu aberto o evento do D3D nao desenha por cima do menu', GAME.lines)
    -- com o menu fechado, o evento do D3D desenha normalmente
    hook.state.ui_show = false
    hook.ui.show.v = false
    GAME.lines, GAME.texts, GAME.boxes = 0, 0, 0
    hook.draw_begin()
    hook.build_overlay()
    hook.build_hud()
    GAME.event_onD3DPresent()
    ok(GAME.lines > 0, 'com o menu fechado o overlay e desenhado pelo evento do D3D', GAME.lines)
    hook.state.ui_show = true
    hook.ui.show.v = true
else
    ok(false, 'o script registrou o evento onD3DPresent')
end

-- 8.9 fechar o menu (o cenario do crash)
hook.ui.show.v = true
hook.state.ui_show = true
click('Fechar menu (X)', 1)
frame('clique em Fechar menu')
ok(hook.state.ui_show == false, 'o botao Fechar menu fecha o menu', tostring(hook.state.ui_show))
ok(hook.ui.show.v == false, 'o ImBool de abertura tambem vira false')
for i = 1, 3 do
    frame('depois de fechar #' .. i)
end
ok(true, 'os frames depois de fechar o menu rodam sem erro')

-- 8.10 fechar no X do ImGui e continuar vivo
hook.ui.show.v = true
hook.state.ui_show = true
frame('menu aberto de novo')
hook.ui.show.v = false          -- como o ImGui faz ao clicar no X
frame('frame em que o X do ImGui foi clicado')
ok(hook.state.ui_show == false, 'o X do ImGui sincroniza o estado do menu', tostring(hook.state.ui_show))
for i = 1, 3 do
    frame('frames com o menu fechado #' .. i)
end

-- 8.11 ERRO DENTRO DA INTERFACE: nao pode deixar o ImGui desbalanceado
hook.ui.show.v = true
hook.state.ui_show = true
hook.ui.error = nil
ImGuiFake.widget_error = 'SEPARATOR'
click('Nova zona no player', 1)
local okframe = frame('frame com um widget quebrado')
ImGuiFake.widget_error = nil
ok(okframe ~= false, 'frame com erro de widget nao derruba o script')
ok(hook.ui.error ~= nil, 'o erro aparece no menu (state/ui.error)', hook.ui.error)
ok(#ImGuiFake.stack == 0, 'mesmo com erro, a pilha do ImGui fica limpa')
frame('frame seguinte ao erro')
frame('mais um frame depois do erro')
ok(#ImGuiFake.stack == 0, 'a interface continua funcionando depois do erro')

-- 8.12 printStyledString quebrado (suspeito do crash relatado)
GAME.print_styled_errors = true
hook.state.ui_show = true
hook.ui.show.v = true
click('Fechar menu (X)', 1)
frame('clicar em Fechar menu com printStyledString quebrado')
GAME.print_styled_errors = false
ok(hook.state.ui_show == false, 'fechar o menu sobrevive a um printStyledString quebrado')
ok(#ImGuiFake.stack == 0, 'a pilha do ImGui continua limpa')
hook.state.ui_show = true
hook.ui.show.v = true
frame('menu aberto de novo depois do print quebrado')

-- 8.13 OVERLAY: ordem de pintura e culling
hook.state.ui_show = false
hook.state.overlays = true
hook.state.hud = false
hook.state.overlay_faces = true
hook.state.overlay_style = 'solid'
hook.state.zones = {}
hook.ui.page = 1

local z = hook.new_zone()
z.cx, z.cy, z.zb, z.zt = 100, 200, 0, 30
z.hw, z.hl, z.sx, z.sy = 20, 20, 0, 0
z.color = { r = 255, g = 200, b = 60 }
hook.state.zones = { z }
hook.state.selected = 1
GAME.camera = { x = 60, y = 160, z = 40 }        -- camera fora, acima do topo
GAME.player = { x = 60, y = 160, z = 12 }
hook.state.player = { x = 60, y = 160, z = 12 }

hook.draw_begin()
local edges = hook.draw_zone_box(z, true, GAME.camera)
ok(edges and edges > 0, 'draw_zone_box desenha as arestas', edges)
local quads = hook.Draw.quads
ok(#quads > 0, 'draw_zone_box gera faces preenchidas', #quads)

-- a ordem de pintura tem que ser de tras (maior distancia) para frente
local ordered = true
for i = 2, #quads do
    if (quads[i][10] or 0) > (quads[i - 1][10] or 0) + 0.001 then ordered = false end
end
ok(ordered, 'as faces sao desenhadas de tras para frente (ordem de pintura)')

-- com a camera fora e acima: base + topo + no maximo 3 paredes visiveis
ok(#quads <= 6, 'culling: nao desenha todas as faces de uma vez', #quads)
ok(#quads >= 3, 'culling: desenha as faces que estao viradas para a camera', #quads)

-- em 'glass' aparecem as 4 paredes + base + topo
hook.state.overlay_style = 'glass'
hook.draw_begin()
hook.draw_zone_box(z, true, GAME.camera)
ok(#hook.Draw.quads == 6, 'estilo vidro desenha as 6 faces', #hook.Draw.quads)
hook.state.overlay_style = 'solid'

-- em 'wire' nao desenha preenchimento nenhum
hook.state.overlay_style = 'wire'
hook.draw_begin()
hook.draw_zone_box(z, true, GAME.camera)
ok(#hook.Draw.quads == 0, 'estilo contorno nao preenche faces', #hook.Draw.quads)
ok(#hook.Draw.lines > 0, 'estilo contorno desenha as arestas', #hook.Draw.lines)
hook.state.overlay_style = 'solid'

-- 8.14 paredes viradas para a camera (culling de face)
local W = hook.wall_faces_camera
-- aresta (0,0)->(10,0): com orientacao anti-horaria (winding = 1) o lado de
-- fora da parede e -Y (o interior do poligono fica a esquerda da direcao)
ok(W(0, 0, 10, 0, 5, -5, 1) == true, 'wall_faces_camera: camera do lado de fora')
ok(W(0, 0, 10, 0, 5, 5, 1) == false, 'wall_faces_camera: camera do lado de dentro')
ok(W(0, 0, 10, 0, 5, 5, -1) == true, 'wall_faces_camera: respeita a orientacao dos cantos (CW)')
ok(W(0, 0, 10, 0, 5, -5, -1) == false, 'wall_faces_camera: CW virado para o lado oposto')
ok(W(0, 0, 0, 0, 5, 5, 1) == false, 'wall_faces_camera: aresta de tamanho zero nao quebra')

-- 8.15 pontos atras da camera nao quebram o desenho
GAME.behind = function(x, y, z) return y < 180 end
hook.draw_begin()
local okdraw, errdraw = pcall(hook.draw_zone_box, z, true, GAME.camera)
GAME.behind = nil
ok(okdraw, 'draw_zone_box nao quebra com pontos atras da camera', errdraw)
GAME.behind = function(x, y, z) return true end
hook.draw_begin()
local okall, errall = pcall(hook.draw_zone_box, z, true, GAME.camera)
GAME.behind = nil
ok(okall, 'draw_zone_box nao quebra quando nada esta visivel', errall)
ok(#hook.Draw.lines == 0, 'sem pontos visiveis nao desenha arestas', #hook.Draw.lines)

-- 8.16 overlay completo + HUD desenham sem erro (com o menu fechado)
hook.state.hud = true
hook.state.overlays = true
hook.state.zones = { z }
hook.state.game_zones = {}
GAME.player = { x = 100.0, y = 200.0, z = 12.0 }
hook.state.player = { x = 100.0, y = 200.0, z = 12.0 }
hook.draw_begin()
local okb1 = pcall(hook.build_overlay)
local okb2 = pcall(hook.build_hud)
local okp = pcall(hook.draw_present)
ok(okb1 and okb2 and okp, 'overlay + HUD + desenho rodam sem erro')

-- 8.17 um frame real de jogo: overlay montado, ImGui fechado, desenho feito
for i = 1, 5 do
    hook.draw_begin()
    hook.build_overlay()
    hook.build_hud()
    hook.draw_present()
end
ok(true, 'varios frames de desenho seguidos sem erro')

--=============================================================================
-- 9. RESULTADO
--=============================================================================
print(string.format('\n[test_ui_frames] %d checagens OK, %d falhas | frames simulados: %d | cliques: %d',
    passed, failed, ImGuiFake.frame_checks, ImGuiFake.calls))
if failed > 0 then
    for _, f in ipairs(failures) do
        print('  FALHOU: ' .. f)
    end
    error(string.format('%d checagem(ns) falharam', failed))
end
print('[test_ui_frames] todos os testes da interface passaram.')
