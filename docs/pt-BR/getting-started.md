# Primeiros passos

[English](../getting-started.md) | **Português (Brasil)**

De um arquivo vazio no Aseprite a um personagem que anda em todas as direções em que foi desenhado.
Os passos supõem que o addon está [instalado e ativado](../../README.pt-BR.md#instalação) e encontra
[o executável do Aseprite](importing.md#executável-do-aseprite). As outras páginas da
[documentação](../../README.pt-BR.md#documentação) explicam cada parte em detalhe.

## 1. Desenhe o sprite no Aseprite

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
4. Adicione frames (*Frame > New Frame*) e desenhe todas as direções em cada um. Defina quanto tempo
   cada frame dura em *Frame > Frame Properties*.
5. Selecione os frames de uma animação na timeline e crie uma tag para eles
   (*Frame > Tags > New Tag*). Dê à tag o nome da ação e acrescente `_loop` no fim se ela ficar em
   loop: `walk_loop`. Uma ação reproduzida uma vez só, como `attack`, fica sem sufixo. Crie uma tag
   para cada animação.
6. Salve o arquivo dentro do projeto Godot, por exemplo `characters/hero.aseprite`.

## 2. Confira a importação no Godot

1. Volte para o editor do Godot. Ele percebe o arquivo novo e o importa.
2. Selecione o arquivo no dock FileSystem e abra o dock **Import**. `grid/cell_size` em `(0, 0)` usa
   um terço do canvas (32x32 aqui). Se o seu canvas não for múltiplo de 3, digite o tamanho da
   célula e clique em **Reimport**. Se o dock Import mostrar outro importador, escolha
   **Import As: Aseprite Top-Down Grid Animations**. Um sprite que não olha para lugar nenhum, como
   um efeito ou o brilho de um item, é importado com `grid/directions` em **none**: o frame inteiro
   vira uma célula. Um sprite que não é animado de jeito nenhum, como uma sombra, um prop ou uma
   página de tileset, fica melhor com *Import As: Aseprite Texture*, descrito em
   [Importando como textura](importing.md#importando-como-textura).

3. Problemas (Aseprite não encontrado, uma tag que gera um nome já usado e assim por diante)
   aparecem no painel **Output**, começando com `[Aseprite Top-Down Grid Animations]`.

## 3. Reproduza as animações com um AnimatedSprite2D

1. Crie uma cena com um **CharacterBody2D** como raiz (`Player`), adicione a ele um
   **AnimatedSprite2D** e um **CollisionShape2D** com uma forma *New RectangleShape2D*, e salve-a
   como `player.tscn`.
2. Arraste `hero.aseprite` do dock FileSystem para a propriedade **Sprite Frames** do
   AnimatedSprite2D. O painel SpriteFrames, embaixo, agora lista `walk_down`, `walk_left` e assim
   por diante: uma animação por tag e direção desenhada.
3. Adicione um script ao `Player`:

   ```gdscript
   extends CharacterBody2D

   const SPEED := 60.0
   ## As direções da grade em sentido horário a partir de "right", a cada 45 graus (+y aponta para
   ## baixo no Godot).
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


   ## "walk" olhando para baixo e à esquerda dá "walk_left_down", ou "walk_left" se essa diagonal
   ## não foi desenhada.
   func _animation_for(action: String, facing: Vector2) -> String:
   	var sector := wrapi(roundi(facing.angle() / (PI / 4.0)), 0, DIRECTIONS.size())
   	var animation := "%s_%s" % [action, DIRECTIONS[sector]]
   	if _sprite.sprite_frames.has_animation(animation):
   		return animation
   	# Diagonal não desenhada: usa o lado do eixo maior (o horizontal numa diagonal exata).
   	if absf(facing.x) >= absf(facing.y):
   		return "%s_%s" % [action, "right" if facing.x > 0.0 else "left"]
   	return "%s_%s" % [action, "down" if facing.y > 0.0 else "up"]
   ```

4. Rode a cena e mova com as setas. O personagem anda na direção das teclas e para no primeiro frame
   da animação que estava reproduzindo.

## 4. Altere a arte

Edite o sprite no Aseprite, salve e volte para o Godot: o arquivo é importado de novo e as animações
no editor são atualizadas. Um jogo que já está rodando mantém as animações antigas até ser
reiniciado. Uma tag nova gera animações novas. Uma tag renomeada renomeia suas animações, então
atualize os nomes no seu código.

## 5. Opcional: controle o sprite com um AnimationPlayer

Vincule um AnimationPlayer quando outras coisas precisarem acompanhar os frames: um som de passo no
frame em que o pé toca o chão, uma hitbox durante um ataque, uma chamada de método no fim de uma
animação.

1. Adicione um **AnimationPlayer** à cena `Player`.
2. Selecione o AnimatedSprite2D. No Inspector, em **AnimatedSprite2D**, clique em **Assign...** na
   seção **AnimationPlayer** e escolha o AnimationPlayer. A seção informa quantas animações
   sincronizou, e o AnimationPlayer agora tem `walk_down`, `walk_left` e assim por diante.
3. Salve a cena. As animações ficam em `player_animations.tres`, ao lado de `player.tscn`.
4. No script, adicione `@onready var _player: AnimationPlayer = $AnimationPlayer` e troque
   `_sprite.play(...)` por `_player.play(...)` e `_sprite.stop()` por `_player.stop()`: os nomes são
   os mesmos, e parar o player também deixa o sprite no primeiro frame. Mantenha
   `_sprite.sprite_frames.has_animation()` como está. Se você ativou *Autoplay on Load* no painel
   SpriteFrames, desative.
5. Selecione o AnimationPlayer, abra uma animação no painel **Animation** e adicione suas próprias
   trilhas (áudio, chamadas de método, propriedades de outros nós). Elas são mantidas quando as
   animações são sincronizadas de novo depois que você altera o sprite no Aseprite.

## Experimente a demo

O repositório é, ele mesmo, um projeto Godot. Abra o `project.godot` dele (com
[o executável do Aseprite](importing.md#executável-do-aseprite) configurado) e rode:
`examples/main.tscn` mostra `examples/retro-top-down-character.aseprite` andando para baixo,
reproduzido pelo AnimationPlayer. O sprite tem dez tags (`walk_loop`, `slash`, `swim_loop`, ...)
desenhadas olhando para cima, para baixo, para a esquerda e para a direita (escalar só para cima e
para baixo), com as células das diagonais vazias.

A mesma cena também mostra o importador de textura: `examples/shadow.aseprite` é importado com
*Import As: Aseprite Texture* e desenhado por um Sprite2D comum. O `examples/shadow_tint.gdshader`
está ali para a outra metade: coloque-o no material de um nó e passe o mesmo arquivo para o uniform
`aseprite_texture` dele, e ele recolore a sombra a partir do alpha. A demo só existe no repositório,
não no download da Asset Library.
