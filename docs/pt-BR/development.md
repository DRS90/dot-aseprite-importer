# Desenvolvimento

[English](../development.md) | **Português (Brasil)**

A raiz do repositório é um projeto de demonstração (`examples/`). Verificações usadas no
desenvolvimento:

```
gdformat --check addons tests && gdlint addons tests
ASEPRITE_PATH=<aseprite> godot --headless --path . -s tests/test_runner.gd
ASEPRITE_PATH=<aseprite> godot --headless --path . --import
```

`tests/test_runner.gd` roda todas as verificações e imprime uma linha `PASS`/`FAIL` para cada uma;
as verificações de sincronização com o AnimationPlayer ficam em `tests/animation_sync_tests.gd`, que
ele chama.

`tests/tools/build_grid.lua` converte para o formato de grade um sprite desenhado com uma camada de
nível superior por direção (camadas com os nomes das células da grade):

```
<aseprite> -b --script-param src=<layers.aseprite> --script-param out=<grid.aseprite> --script tests/tools/build_grid.lua
```

`tests/tools/build_cases.lua` gera sprites para testes manuais a partir de um sprite em grade:
várias camadas e grupos (ocultos, excluídos, nomes que a lista não consegue oferecer), oito direções
com uma célula vazia numa tag, um canvas que não é múltiplo de 3, um arquivo sem tags e um sprite de
16x16 sem grade nenhuma, para `grid/directions` em `none`. O comentário
no topo do script lista o que cada um cobre:

```
<aseprite> -b --script-param src=<grid.aseprite> --script-param out=<folder> --script tests/tools/build_cases.lua
```

## Asset de exemplo

`examples/retro-top-down-character.aseprite` é feito a partir das spritesheets CC0 citadas nos
[créditos do README](../../README.pt-BR.md#créditos). Ele tem células de 48x48 (o tamanho do efeito
da espada) com o personagem de 16x16 centralizado em cada uma, duas camadas (`character` e
`weapon`) e uma tag por animação das spritesheets. As células das diagonais ficam vazias, e escalar
só está desenhado olhando para cima e para baixo. `tests/tools/build_retro_example.lua` o
reconstrói:

```
<aseprite> -b --script-param file=examples/retro-top-down-character.aseprite --script-param sheet=examples/rpg-type-retro-top-down-playable-character-spritesheett/16x16-rpg-topdown-playable-character-template.png --script-param attack=examples/rpg-type-retro-top-down-playable-character-spritesheett/48x48-attack.png --script tests/tools/build_retro_example.lua
```

O test runner compara cada frame importado com essas spritesheets, então o repositório não precisa
de tiras de referência.
