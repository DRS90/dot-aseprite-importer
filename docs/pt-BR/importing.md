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

## Como funciona a importação automática

O addon é um `EditorImportPlugin` comum. O Godot reimporta um arquivo de origem quando o conteúdo
dele muda, o que ele percebe **quando a janela do editor do Godot recupera o foco** (ou num
*Reimport* manual).

- Cada importação abre o Aseprite duas vezes, não importa quantas direções e tags o arquivo tenha:
  uma para ler o tamanho, as camadas, as tags e as durações dos frames, e outra para exportar todas
  as animações. O que custa tempo é abrir o Aseprite (cerca de 200 ms), não as animações.
- O Aseprite exporta uma tira por animação para uma pasta de cache fora do projeto. As tiras viram
  texturas sem perdas embutidas no recurso importado (em `.godot/imported/`), então nada é gravado
  no projeto, e exportar uma cena que usa o arquivo exporta as texturas junto.

*Project > Tools > Aseprite Top-Down Grid Animations: Reimport all* força a reimportação de todos os
arquivos que usam este importador, por exemplo depois de mudar o caminho do executável ou um padrão
do projeto, ou depois de atualizar o addon.

## Opções de importação

Todas as opções podem ser alteradas por arquivo no dock Import. Os padrões de
`layers/exclude_pattern`, `tags/exclude_pattern`, `sprite_frames/animation_name` e
`sprite_frames/loop_suffix` vêm de
*Project Settings > Aseprite Top-Down Grid Animations > Defaults*.

| Opção | Padrão | Descrição |
|---|---|---|
| `grid/cell_size` | `(0, 0)` | Tamanho de uma célula em pixels. `0` num eixo significa um terço do sprite nesse eixo, que então precisa ser múltiplo de 3. Uma célula menor que um terço ignora os pixels que sobram à direita ou embaixo. |
| `layers/layer` | `[all]` | Lista com `[all]` e as camadas e grupos de nível superior do arquivo. `[all]` combina todas as camadas que não casam com `layers/exclude_pattern`; qualquer outra escolha importa só aquela camada ou grupo. Coloque camadas num grupo para importá-las juntas. |
| `layers/exclude_pattern` | `^_` | Expressão regular; as camadas que casam ficam de fora quando `layers/layer` é `[all]`. |
| `layers/only_visible` | `false` | Usa só as camadas visíveis no Aseprite. Por padrão, as camadas ocultas também são importadas. |
| `tags/exclude_pattern` | `^_` | Expressão regular; as tags que casam não são importadas. |
| `sprite_frames/animation_name` | `{tag}_{direction}` | Nome da animação. `{tag}` é o nome da tag sem o sufixo de loop; `{direction}` é `left_up`, `up`, `right_up`, `left`, `right`, `left_down`, `down` ou `right_down`. |
| `sprite_frames/loop_suffix` | `_loop` | Uma tag que termina com este texto repete, e o texto sai de `{tag}`. Vazio: nenhuma animação repete. |

Os caracteres `/`, `:`, `,` e `[` viram `_` nos nomes das animações, porque o AnimationPlayer os
rejeita. Quando duas tags geram o mesmo nome (`idle` e `idle_loop`), a segunda é informada como erro
e ignorada.

A lista de `layers/layer` é preenchida perguntando ao Aseprite as camadas do arquivo quando o dock
Import mostra o arquivo. A listagem fica em cache pelo conteúdo do arquivo e é reaproveitada pela
importação, então não abre nenhum processo extra do Aseprite. Uma camada escolhida que não existe
mais (renomeada ou removida) faz a importação falhar com um erro e mantém as animações anteriores. A
escolha pode ser uma camada que casa com `layers/exclude_pattern`, então uma camada `_shadow` fica
fora de `[all]` e ainda pode ser importada sozinha.

## Convivência com outros importadores de Aseprite

Outros addons (por exemplo, o Aseprite Wizard) também registram importadores para `.aseprite`. O
Godot usa o importador de maior prioridade para arquivos novos; escolha o importador de cada arquivo
com **Import As** no dock Import. Trocar de importador não altera o arquivo de origem.
