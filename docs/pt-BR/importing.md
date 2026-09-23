# Importação

[English](../importing.md) | **Português (Brasil)**

## Executável do Aseprite

O caminho é procurado nesta ordem:

1. *Editor Settings > Aseprite Top-Down Grid Animations > General > Executable Path* (por máquina).
2. A variável de ambiente `ASEPRITE_PATH` (útil para CI e importações headless).
3. O padrão do sistema operacional:
   - Windows: `C:\Program Files\Aseprite\Aseprite.exe`
   - macOS: `/Applications/Aseprite.app/Contents/MacOS/aseprite`
   - Linux/outros: `aseprite` no `PATH`

Instalações pela Steam ficam em outro lugar, por exemplo
`C:\Program Files (x86)\Steam\steamapps\common\Aseprite\Aseprite.exe` ou
`~/.steam/steam/steamapps/common/Aseprite/aseprite`.

O caminho tem de apontar para o próprio executável: um wrapper `.bat` ou `.cmd` não pode ser
iniciado. Um nome solto como `aseprite` é procurado no `PATH`. Um caminho que não leva a nada é
avisado na importação do arquivo, sem iniciar nada.

## Como funciona a importação automática

O addon registra dois `EditorImportPlugin`, e todo `.aseprite` usa um deles:

| Importador | Gera | Serve para |
|---|---|---|
| **Aseprite Top-Down Grid Animations** | `SpriteFrames` | animações, num AnimatedSprite2D |
| **Aseprite Texture** | um `Texture2D` sem perdas | Sprite2D, TextureRect, uniform de shader, imagem-fonte de um TileSet |

Qual deles um arquivo quer depende de duas perguntas: ele é animado, e ele olha para algum lado?

| O sprite | Import As | Gera |
|---|---|---|
| animado, uma célula por direção | **Aseprite Top-Down Grid Animations** (o padrão) | uma animação por direção e tag |
| animado, sem direção, como uma poeira de corrida ou uma faísca | o mesmo importador, com [`grid/directions`](#opções-de-importação) em `none` | uma animação por tag |
| sem animação, como uma sombra, um prop ou uma página de tileset | **Aseprite Texture** | um `Texture2D` da tela |

Os dois primeiros mantêm as durações de frame, os loops e o ping-pong do Aseprite, e conseguem
dirigir um AnimationPlayer; o terceiro é uma imagem e não carrega nada disso. Um arquivo para o qual
ninguém escolheu cai no primeiro; escolha o outro por arquivo com **Import As** no dock Import.

O Godot reimporta um arquivo de origem quando o conteúdo dele muda, o que ele percebe **quando a
janela do editor do Godot recupera o foco** (ou num *Reimport* manual).

- Cada importação abre o Aseprite uma vez só, não importa quantas direções e tags o arquivo tenha,
  para exportar todas as animações. O tamanho, as camadas, as tags e as durações dos frames são
  lidos do próprio arquivo em poucos milissegundos. O que custa tempo é abrir o Aseprite e o
  arquivo (cerca de 200 ms mais o tempo de abrir o arquivo), não as animações.
- O Aseprite exporta uma tira por animação para uma pasta de cache fora do projeto. O addon junta
  todos os frames numa folha por arquivo, cada frame cortado aos próprios pixels e frames repetidos
  guardados uma vez só, e embute a folha como uma única textura sem perda no recurso importado (em
  `.godot/imported/`).
  Cada frame mantém o tamanho da célula, então o sprite não se desloca, e todos os sprites que usam
  o arquivo desenham a mesma textura. Nada é gravado no projeto, e exportar uma cena que usa o
  arquivo exporta a textura junto.

*Project > Tools > Aseprite Top-Down Grid Animations: Reimport all* força a reimportação de todos os
arquivos que usam qualquer um dos dois importadores, por exemplo depois de mudar o caminho do
executável ou uma configuração padrão do projeto, ou depois de atualizar o addon.

## Opções de importação

As opções abaixo são do importador **Aseprite Top-Down Grid Animations**; o de textura tem as suas,
[mais adiante](#importando-como-textura). Todas podem ser alteradas por arquivo no dock Import. Os
padrões de `layers/exclude_pattern`, `tags/exclude_pattern`, `sprite_frames/animation_name` e
`sprite_frames/loop_suffix` vêm de
*Project Settings > Aseprite Top-Down Grid Animations > Defaults*; o `layers/exclude_pattern`
alimenta os dois importadores.

| Opção | Padrão | Descrição |
|---|---|---|
| `grid/directions` | `3x3` | `3x3`: cada frame é uma grade 3x3 de direções. `none`: o frame é uma única célula e o sprite não tem direção, para os acompanhantes de um personagem top-down (a poeira de corrida, a faísca de impacto, o brilho de um item). |
| `grid/cell_size` | `(0, 0)` | Tamanho de uma célula em pixels. `0` num eixo significa o sprite dividido pelas células da grade nesse eixo: um terço com `grid/directions` em `3x3`, e aí o sprite precisa ser múltiplo de 3, e o sprite inteiro em `none`. Uma célula menor recorta o canto superior esquerdo e ignora os pixels que sobram à direita ou embaixo. |
| `layers/layer` | `[all]` | Lista suspensa com `[all]` e as camadas e grupos de nível superior do arquivo. `[all]` combina todas as camadas que não casam com `layers/exclude_pattern`; qualquer outra escolha importa só aquela camada ou grupo. Coloque camadas num grupo para importá-las juntas. |
| `layers/exclude_pattern` | `^_` | Expressão regular; as camadas que casam ficam de fora quando `layers/layer` é `[all]`. |
| `layers/only_visible` | `false` | Usa só as camadas visíveis no Aseprite. Por padrão, as camadas ocultas também são importadas. |
| `tags/exclude_pattern` | `^_` | Expressão regular; as tags que casam não são importadas. |
| `sprite_frames/animation_name` | `{tag}_{direction}` | Nome da animação. `{tag}` é o nome da tag sem o sufixo de loop; `{direction}` é `left_up`, `up`, `right_up`, `left`, `right`, `left_down`, `down` ou `right_down`, e nada com `grid/directions` em `none`. |
| `sprite_frames/loop_suffix` | `_loop` | Uma tag que termina com este texto fica em loop, e o texto sai de `{tag}`. Vazio: nenhuma animação fica em loop. |

Um placeholder sem nada para colocar no lugar leva junto um separador vizinho, então
`{tag}_{direction}` gera `run`, e não `run_`, num sprite sem direções; os separadores dentro do nome
da tag ficam como estão. Um arquivo sem tags e sem direções para nomear sua única animação recebe
`default`.

Os caracteres `/`, `:`, `,` e `[` viram `_` nos nomes das animações, porque o AnimationPlayer os
rejeita. Quando duas tags geram o mesmo nome — `idle` e `idle_loop`, ou duas tags com o mesmo nome
no Aseprite — a importação falha e o erro cita as duas tags. Não é uma importação parcial de
propósito: descartar a segunda animação substituiria as que ainda funcionavam por um recurso
incompleto, enquanto uma importação que falha mantém as animações anteriores até os nomes serem
corrigidos.

A lista de `layers/layer` é preenchida com as camadas do arquivo, lidas do próprio arquivo quando o
dock Import o mostra, então funciona antes mesmo de o Aseprite estar configurado. Uma camada
escolhida que não existe mais (renomeada ou removida) faz a importação falhar com um erro e mantém
as animações anteriores. A
escolha pode ser uma camada que casa com `layers/exclude_pattern`, então uma camada `_shadow` fica
fora de `[all]` e ainda pode ser importada sozinha.

## Importando como textura

Coloque **Import As** em *Aseprite Texture* para receber um `Texture2D` simples em vez de animações.
A tela inteira é exportada com todos os frames da timeline lado a lado, então um sprite de um frame
gera exatamente a sua imagem, e um de vários gera o layout que `Sprite2D.hframes` e os tiles
animados de um TileSet esperam. Arraste o arquivo em qualquer propriedade `Texture2D`.

Tags, durações de frame e a grade de direções são **ignoradas** aqui: elas descrevem animações, e
este importador gera uma imagem. As opções dele são só as de camada:

| Opção | Padrão | Descrição |
|---|---|---|
| `layers/layer` | `[all]` | A mesma lista de cima: `[all]`, ou uma única camada ou grupo de nível superior. |
| `layers/exclude_pattern` | `^_` | Expressão regular; as camadas que casam ficam fora de `[all]`. |
| `layers/only_visible` | `false` | Usa só as camadas visíveis no Aseprite. |

Um arquivo **usa um importador de cada vez**: um `.aseprite` gera um recurso, de um tipo só. Trocar
o *Import As* substitui, não acrescenta, então uma cena que referenciava o arquivo como SpriteFrames
precisa ser reapontada depois. Se você precisa da mesma arte nos dois formatos, mantenha dois
arquivos `.aseprite`.

## Convivência com outros importadores de Aseprite

Outros addons também registram importadores para `.aseprite`, e o Godot entrega um arquivo novo
para o que declara a maior prioridade. Este addon declara **1.0** no importador de SpriteFrames, o
padrão do Godot, e **0.9** no *Aseprite Texture*, então o de textura nunca é escolhido sozinho. Ele
também não disputa com outros addons: com outro importador de Aseprite instalado, a escolha é sua,
arquivo por arquivo.

O Aseprite Wizard declara **2.0** para o importador que estiver configurado como padrão dele, e de
fábrica esse padrão é o **Aseprite (No Import)**. Num projeto com os dois addons, um `.aseprite`
recém-adicionado é portanto importado pelo *Aseprite (No Import)* e não gera nada — sem erro e sem
aviso, o que parece um addon quebrado e não é.

Para importar um arquivo desses com este addon:

1. Selecione o arquivo no dock FileSystem; dá para selecionar vários de uma vez.
2. No dock **Import**, coloque **Import As** em *Aseprite Top-Down Grid Animations*.
3. Clique em **Reimport**.

A escolha fica gravada no `.import` de cada arquivo, então ela sobrevive a reimportações, ao
*Reimport all* e à próxima pessoa que abrir o projeto. Trocar de importador nunca altera o arquivo
de origem.
