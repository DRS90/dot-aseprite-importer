# Aseprite Top-Down Grid Animations

[English](README.md) | **Português (Brasil)**

Um addon de editor para Godot 4.7 que importa sprites `.aseprite` / `.ase` desenhados como uma
**grade 3x3 de direções** e gera um recurso **SpriteFrames**: uma animação por direção e tag, com o
tempo igual ao do Aseprite. Atribua o arquivo a um AnimatedSprite2D e, se quiser, vincule um
AnimationPlayer que recebe as mesmas animações. Qualquer `.aseprite` também pode ser importado como
um **Texture2D** simples, para os sprites que não são animados.

```
character.aseprite (144x192)              SpriteFrames (frames de 48x64)
  +-----------+------+------------+         idle_left_up, idle_up, idle_right_up,
  | left_up   | up   | right_up   |         idle_left_down, idle_down, idle_right_down,
  | left      |      | right      |  ->     walk_left_up, walk_up, ...
  | left_down | down | right_down |
  +-----------+------+------------+
  tags: idle_loop, walk, ...
```

Uma célula sem pixels em nenhum frame de uma tag não gera animação: um personagem desenhado em seis
direções (sem `left` e `right` puros) simplesmente deixa essas células vazias.

Os sprites de um jogo top-down que não olham para lugar nenhum — a poeira de corrida, a faísca de
impacto, o brilho de um item — são importados pelo mesmo addon com `grid/directions` em `none`: o
frame vira uma célula única e as animações recebem só o nome da tag.

Os nomes de menus, painéis, docks, botões e opções aparecem como no editor em inglês.

## Screenshots

O personagem de exemplo no Aseprite: cada frame é uma grade 3x3 de direções (as guias em azul), com
as células das diagonais vazias, uma tag por animação na timeline e duas camadas.

![O personagem de exemplo no Aseprite, desenhado como uma grade 3x3 de direções](screenshots/aseprite-character.png)

O mesmo arquivo no Godot: as animações do SpriteFrames no painel de baixo e a seção
**AnimationPlayer** do inspetor do AnimatedSprite2D, à direita.

![O arquivo importado no editor do Godot, com as animações e a seção AnimationPlayer](screenshots/godot-editor.png)

## Requisitos

- Godot **4.7** (testado com 4.7.1).
- [Aseprite](https://www.aseprite.org/) 1.3 com suporte a scripts (testado com 1.3.18). Todo mundo
  que importa os arquivos precisa dele.

## Instalação

1. Copie `addons/aseprite_topdown_grid_animations` para a pasta `addons/` do seu projeto.
2. Ative **Aseprite Top-Down Grid Animations** em *Project > Project Settings > Plugins*.
3. Se o Aseprite não estiver no local padrão (uma instalação pela Steam, por exemplo), defina
   *Editor Settings > Aseprite Top-Down Grid Animations > General > Executable Path* ou a variável
   de ambiente `ASEPRITE_PATH`. Veja
   [Executável do Aseprite](docs/pt-BR/importing.md#executável-do-aseprite).
4. Para pixel art nítida, defina *Project Settings > Rendering > Textures > Canvas Textures >
   Default Texture Filter* como **Nearest**.

## Início rápido

1. No Aseprite, faça o canvas com três células de largura e três de altura, desenhe cada direção na
   sua célula e crie uma tag para cada animação. Uma tag terminada em `_loop` (`walk_loop`) fica em
   loop.
2. Salve o arquivo dentro do projeto Godot. Quando o editor do Godot recupera o foco, o arquivo é
   importado como SpriteFrames.
3. Arraste o arquivo para a propriedade **Sprite Frames** de um AnimatedSprite2D e reproduza uma
   animação: `$AnimatedSprite2D.play("walk_down")`.
4. Se quiser, vincule um AnimationPlayer na seção **AnimationPlayer** do inspetor do sprite para ter
   as mesmas animações nele e adicionar suas próprias trilhas.

[Primeiros passos](docs/pt-BR/getting-started.md) mostra esses passos em detalhe, com um script de
movimento.

## Documentação

- [Primeiros passos](docs/pt-BR/getting-started.md): de um arquivo vazio no Aseprite a um
  personagem andando, e o projeto de demonstração.
- [Desenhando o sprite](docs/pt-BR/drawing-the-sprite.md): grade, camadas, tags e loops.
- [Importação](docs/pt-BR/importing.md): o executável do Aseprite, quando os arquivos são
  importados, as opções do dock Import e outros importadores de Aseprite.
- [AnimatedSprite2D](docs/pt-BR/animated-sprite-2d.md): nomes, velocidade e loops das animações.
- [AnimationPlayer](docs/pt-BR/animation-player.md): vincular um player, sincronização, suas
  próprias trilhas e o arquivo da biblioteca de animações.
- [Limitações conhecidas](docs/pt-BR/limitations.md)
- [Desenvolvimento](docs/pt-BR/development.md): testes, ferramentas e o asset de exemplo.

## Créditos

O personagem de exemplo é feito a partir do
["RPG Type Retro Top-Down Playable Character Template" de 5yvalia](https://5yvalia.itch.io/rpg-type-retro-top-down-playable-character-template),
publicado como **CC0** (domínio público). As spritesheets estão em
`examples/rpg-type-retro-top-down-playable-character-spritesheett/`, com o `LICENSE.png` do
download.

## Licença

[MIT](LICENSE)
