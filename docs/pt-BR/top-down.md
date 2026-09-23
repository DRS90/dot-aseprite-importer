# Personagens top-down

[English](../top-down.md) | **Português (Brasil)**

Um personagem visto de cima olha para cima, para baixo e para os lados, e precisa de uma animação
para cada direção. Em vez de um arquivo por direção, desenhe cada frame como uma grade 3x3 de
células, uma por direção, e coloque `grid/directions` em `3x3`: cada tag gera uma animação por
direção desenhada. Os passos supõem que o addon está
[instalado e ativado](../../README.pt-BR.md#instalação) e encontra
[o executável do Aseprite](importing.md#executável-do-aseprite).

## 1. Ative a grade

`grid/directions` é `none` por padrão: o frame inteiro é uma célula. Ative a grade num destes dois
lugares:

- **Para um arquivo:** selecione-o no dock FileSystem, coloque `grid/directions` em `3x3` no dock
  **Import** e clique em **Reimport**. Dá para selecionar vários arquivos de uma vez.
- **Para o projeto inteiro:** abra *Project > Project Settings > Import Defaults*, escolha
  *Dot Aseprite SpriteFrames* na lista de importadores, coloque `grid/directions` em `3x3` e clique
  em **Save**. O menu **Preset** do dock Import faz o mesmo a partir de um arquivo que já está em
  `3x3`: *Set as Default for 'Dot Aseprite SpriteFrames'*. Todo `.aseprite` adicionado depois disso
  é importado como grade. Os arquivos que já estão no projeto mantêm a própria configuração,
  guardada no arquivo `.import` deles: mude esses no dock Import.

Um jogo top-down também tem sprites que não olham para lugar nenhum: a poeira de corrida, a faísca
de impacto, o brilho de um item. Num projeto com `3x3` como padrão, volte esses arquivos para `none`
no dock Import. Um sprite que não é múltiplo de 3 falha com uma mensagem que aponta as duas saídas:
um tamanho de célula, ou `none`.

## 2. Desenhe a grade no Aseprite

1. Crie um sprite com três células de largura e três de altura: para um personagem de 32x32,
   *File > New* com **96x96**.
2. Defina *View > Grid > Grid Settings* como **32x32** e ative *View > Show > Grid*, para que cada
   célula fique contornada.
3. Desenhe o personagem na célula de cada direção para a qual ele olha:

   ```
   left_up    up     right_up
   left     (vazia)  right
   left_down  down   right_down
   ```

   Deixe o centro vazio, e deixe vazias as células das direções que você não desenhar (as diagonais
   de um personagem de quatro direções, por exemplo).
4. Adicione frames e tags como em qualquer sprite ([Desenhando o sprite](drawing-the-sprite.md)):
   cada frame tem todas as direções, e uma tag como `walk_loop` cobre todas elas.
5. Salve o arquivo dentro do projeto Godot, por exemplo `characters/hero.aseprite`.

Pixels que atravessam a borda de uma célula acabam na animação da direção vizinha. `grid/cell_size`
em `(0, 0)` usa um terço do canvas (32x32 aqui); se o canvas não for múltiplo de 3, digite o tamanho
da célula no dock Import e clique em **Reimport**: as células começam no canto superior esquerdo e
os pixels que sobram à direita ou embaixo são ignorados.

## 3. Nomes das animações

As animações recebem o nome `{tag}_{direction}` (`sprite_frames/animation_name`), sem o sufixo de
loop: a tag `walk_loop` gera `walk_down`, `walk_left_up` e assim por diante. Uma célula sem pixels
em nenhum frame de uma tag não gera animação, então um personagem desenhado em quatro direções tem
só `walk_down`, `walk_left`, `walk_right` e `walk_up`.

## 4. Reproduza a direção para a qual o personagem olha

1. Crie uma cena com um **CharacterBody2D** como raiz (`Player`), adicione a ele um
   **AnimatedSprite2D** e um **CollisionShape2D** com uma forma *New RectangleShape2D*, e salve-a
   como `player.tscn`.
2. Arraste `hero.aseprite` do dock FileSystem para a propriedade **Sprite Frames** do
   AnimatedSprite2D.
3. Adicione um script ao `Player`:

   ```gdscript
   extends CharacterBody2D

   const SPEED := 60.0
   ## The grid directions clockwise from "right", 45 degrees apart (+y points down in Godot).
   const DIRECTIONS: Array[String] = [
   	"right", "right_down", "down", "left_down", "left", "left_up", "up", "right_up"
   ]

   @onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D


   func _physics_process(_delta: float) -> void:
   	var input := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
   	velocity = input * SPEED
   	move_and_slide()
   	if input == Vector2.ZERO:
   		_sprite.stop()
   		return
   	_sprite.play(_animation_for("walk", input))


   ## "walk" facing down-left gives "walk_left_down", or "walk_left" if that diagonal is not drawn.
   func _animation_for(action: String, facing: Vector2) -> String:
   	var sector := wrapi(roundi(facing.angle() / (PI / 4.0)), 0, DIRECTIONS.size())
   	var animation := "%s_%s" % [action, DIRECTIONS[sector]]
   	if _sprite.sprite_frames.has_animation(animation):
   		return animation
   	# Diagonal not drawn: use the side of the longer axis (horizontal on an exact diagonal).
   	if absf(facing.x) >= absf(facing.y):
   		return "%s_%s" % [action, "right" if facing.x > 0.0 else "left"]
   	return "%s_%s" % [action, "down" if facing.y > 0.0 else "up"]
   ```

4. Rode a cena e mova com as setas. O personagem anda na direção das teclas e para no primeiro frame
   da animação que estava reproduzindo.

Com um [AnimationPlayer](animation-player.md) vinculado, chame `_player.play()` com os mesmos nomes
e mantenha `_sprite.sprite_frames.has_animation()` como está.

## A demo

`examples/retro-top-down-character.aseprite`, no projeto de demonstração do repositório, é uma
grade: dez tags (`walk_loop`, `slash`, `swim_loop`, ...) desenhadas olhando para cima, para baixo,
para a esquerda e para a direita (escalar só para cima e para baixo), com as células das diagonais
vazias. O arquivo `.import` dele coloca `grid/directions` em `3x3`, e `examples/main.tscn` o mostra
andando para baixo. Veja [Experimente a demo](getting-started.md#experimente-a-demo).
