# Cull Zone Creator

Mod/criador de **Cull Zones** para **GTA San Andreas**, feito em Lua para
**MoonLoader + MoonAdditions + Moon ImGui 1.1.5**.

Serve principalmente para criar zonas onde **não chove** (flag `NO_RAIN`), mas
também edita qualquer outro atributo de cull zone (sem polícia, zona militar,
áudio de interior, menos carros/pedestres...).

* GUI in-game (Moon ImGui) com lista de zonas e edição de tudo
* Visualização 3D em tempo real: a caixa da zona é desenhada no mundo, com nome,
  distância, flags e destaque quando o jogador está dentro
* Botões que salvam a posição (do jogador, do centro, dos tamanhos, do Z...)
* **Live apply**: escreve as zonas na memória do GTA SA 1.0 US e mostra o efeito
  na hora (sem reiniciar o jogo)
* **Exportar IPL**: gera o arquivo `.ipl` (e um pacote pronto para o ModLoader)
* Importar IPL (arquivo ou clipboard) e ler as cull zones que o jogo já tem

---

## Arquivos

| Arquivo | O que é |
|---|---|
| `moonloader/CullZoneCreator.lua` | o script (copie para `GTA San Andreas\moonloader\`) |
| `tests/test_czc.lua` | testes da lógica (geometria, IPL, save, live apply, GUI) |
| `tests/run_tests.py` | roda os testes com `lua`/`luajit` do PATH ou com `lupa` |

## Requisitos

* GTA San Andreas **1.0 US** (o live apply só funciona nessa versão; nas outras o
  script desliga a memória sozinho e continua exportando IPL)
* [MoonLoader](https://www.blast.hk/threads/1753/) 0.26+
* [Moon ImGui](https://www.blast.hk/threads/19292/) 1.1.5 (`moonloader/lib/imgui.lua` + `MoonImGui.dll`)
* [MoonAdditions](https://github.com/THE-FYP/MoonAdditions) (usado para preencher
  a área das zonas; o script funciona sem ele, só não desenha o preenchimento)

## Instalação

1. Copie `moonloader/CullZoneCreator.lua` para `GTA San Andreas\moonloader\`.
2. Entre no jogo e carregue um save. O menu abre com **F7**.

## Uso

| Tecla | Ação |
|---|---|
| `F7` | abre/fecha o menu |
| `F8` | cria uma zona na posição do jogador |
| `F9` | liga/desliga o **live apply** (aplica no jogo na hora) |
| `F10` | liga/desliga o overlay 3D + HUD |
| `F11` | exporta (IPL ou pacote ModLoader) |

Fluxo típico para uma zona sem chuva:

1. Vá até o lugar (de carro, de helicóptero...).
2. `F8` cria a zona; no menu ajuste **centro**, **tamanho** (meia largura X e
   meia altura Y, em metros) e **altura** (`Bottom`/`Top`, Z absoluto do mundo).
3. Marque `NoRain` (ou clique em "Sem chuva").
4. Com "Aplicar no jogo" ligado, ande para dentro e para fora: o HUD mostra
   `SEM CHUVA` quando o efeito está ativo e a caixa fica verde quando você está
   dentro da zona.
5. Exporte:
   * **Exportar IPL** → gera `modloader\CullZoneCreator\cull.ipl`;
   * **Pacote ModLoader** → gera também o `gta.dat` e um `LEIA-ME.txt`, já
     pronto para o ModLoader ler as zonas sozinho.

Sem ModLoader: copie o `.ipl` para `data\maps\` e adicione em `data\gta.dat`:

```
IPL DATA\MAPS\CULLZONE.IPL
```

As cull zones de IPL passam a valer **quando o jogo carrega o mapa** (ou seja,
ao iniciar / recarregar o save). Para testar sem reiniciar, use o live apply.

---

## Formato da cull zone (referência)

Seção do IPL (GTA SA) — 11 campos:

```
cull
CenterX, CenterY, CenterZ, Unknown1, Length, Bottom, Width, Unknown2, Top, Flag, Unknown3
end
```

Exemplo real de uma zona sem chuva do jogo:

```
-1940.89, 138.005, 25.1618, 0, 27.2647, 25.1618, 19.575, 0, 34.3618, 8, 0
```

| Campo | Significado |
|---|---|
| `CenterX`, `CenterY` | centro da caixa no plano XY (o motor usa esses dois valores) |
| `CenterZ` | ignorado pelo motor (o script grava a média de Bottom/Top por leitura) |
| `Length` | **metade** do tamanho no eixo Y |
| `Width` | **metade** do tamanho no eixo X |
| `Bottom`, `Top` | Z absoluto (mundo) da base e do topo |
| `Unknown1`, `Unknown2` | *skew* X/Y (cisalhamento que emula rotação); `0` = caixa alinhada |
| `Flag` | bitmask de atributos (tabela abaixo) |
| `Unknown3` | `0` |

O motor guarda a zona como 8 shorts (`CZoneDef`):

```
x1 = cx - Unknown1 - Width      x2 = 2 * Unknown1
y1 = cy - Length   - Unknown2   y2 = 2 * Length
x3 = 2 * Width                  y3 = 2 * Unknown2
z1 = Bottom                     z2 = Top
```

Ou seja: **não é um AABB**, e sim um paralelogramo centrado no centro informado,
com arestas `A = (x2, y2)` e `B = (x3, y3)` (o script desenha exatamente isso).
O menu trabalha no "modo simples" (largura/altura + ângulo) e converte para esses
campos.

### Flags (`CCullZones::eZoneAttributes`)

| Bit | Nome | Efeito |
|---|---|---|
| `0x0001` | CamCloseIn | câmera cola no jogador (perto) |
| `0x0002` | CamStairs | câmera fixa observando o jogador |
| `0x0004` | Cam1stPerson | desliga câmera GTA2 / ângulo em barcos |
| **`0x0008`** | **NoRain** | **sem chuva** (e sem helicóptero da polícia) |
| `0x0010` | NoPolice | polícia não desce do carro / não persegue a pé |
| `0x0040` | DoINeedToLoadCollision | carrega colisão na zona (raro) |
| `0x0100` | PoliceAbandonCars | polícia sempre sai do carro |
| `0x0200` | InRoomsForAudio | áudio em ambiente fechado (eco/abafado) |
| `0x0400` | InRoomsFewerPeds | menos pedestres |
| `0x1000` | MilitaryZone | zona militar (5 estrelas) |
| `0x4000` | ExtraAirResistance | veículos não atingem velocidade máxima |
| `0x8000` | FewerCars | menos carros |

`65535` (todos os bits) = todos os atributos.

As zonas de **espelho** (reflexo no chão) têm campos extras: `Vx, Vy, Vz`
(direção, normalmente `-1`/`0`/`1` num eixo) e `Cm` (posição absoluta do plano
de reflexão). O script suporta espelhos no live apply (formato do motor) e a
exportação é experimental.

---

## Live apply: como funciona

As cull zones carregadas ficam em arrays do próprio motor (GTA SA 1.0 US):

| Endereço | Conteúdo |
|---|---|
| `0xC81F50` | `aAttributeZones[1300]` (`CZoneDef` 16 bytes + flags 2) |
| `0xC87AC8` | `NumAttributeZones` |
| `0xC815C0` | `aMirrorAttributeZones[72]` (24 bytes cada) |
| `0xC87AC4` | `NumMirrorAttributeZones` |
| `0xC87AB8` | `CurrentFlags_Player` (flags que o jogo está aplicando) |

O script guarda a contagem original, escreve as zonas marcadas como "ao vivo"
logo depois das zonas do jogo e atualiza o contador. Como o
`CCullZones::Update()` lê esses arrays continuamente, o efeito aparece na hora.
Ao desligar o live apply (ou sair do script) a contagem original é restaurada.

Detalhes:

* A checagem de sanidade em `init_memory()` confere se a contagem de zonas é
  plausível; se não for, a memória é desligada e o script avisa no menu/HUD.
* A opção **Modo seguro** (Configurações) desliga completamente qualquer acesso
  à memória.
* O live apply é só para teste: ele **não** é salvo no jogo. O que persiste é o IPL.

## Testes

```bash
python3 tests/run_tests.py      # usa lua/luajit do PATH ou o modulo lupa
```

Os testes montam um MoonLoader falso (com memória simulada nos endereços reais),
carregam o script e verificam geometria, leitura/geração de IPL, save/load, a
escrita do live apply (inclusive `Cm` em float), a leitura das zonas do jogo e a
sequência de chamadas da GUI.

## Limites / o que conferir no jogo

O código foi escrito a partir do formato documentado do IPL, dos endereços do
GTA SA 1.0 US e da API real do Moon ImGui/MoonAdditions, e a lógica está coberta
pelos testes — mas o comportamento em jogo depende do seu setup. Se algo não
sair como esperado, comece por aqui:

* **Overlay/HUD vazio**: confira se MoonAdditions e Moon ImGui estão instalados e
  se o `Draw` funciona no seu build (o HUD usa `renderFontDrawText`, as caixas
  usam `renderDrawLine`).
* **Live apply não muda nada**: veja se aparece "Memoria OK" no log
  (`moonloader.log`) — em jogo que não seja 1.0 US a memória é desligada e resta
  o IPL.
* **Preenchimento da área torto**: desligue "Preencher área" nas Configurações
  (o MoonAdditions recebe coordenadas em pixels; se a sua configuração de vídeo
  mudar isso, as linhas continuam corretas).

## Créditos

* Formato CULL/IPL: [GTAMods Wiki - CULL](https://gtamods.com/wiki/CULL)
* Endereços e estruturas: [plugin-sdk](https://github.com/DK22Pac/plugin-sdk)
* APIs: [MoonLoader](https://www.blast.hk/threads/1753/),
  [Moon ImGui](https://www.blast.hk/threads/19292/),
  [MoonAdditions](https://github.com/THE-FYP/MoonAdditions)
