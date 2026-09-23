# Primeiros passos

[English](../getting-started.md) | **Português (Brasil)**

De um arquivo vazio no Aseprite a um personagem que corre e pula. Os passos supõem que o addon está
[instalado e ativado](../../README.pt-BR.md#instalação) e encontra
[o executável do Aseprite](importing.md#executável-do-aseprite). As outras páginas da
[documentação](../../README.pt-BR.md#documentação) explicam cada parte em detalhe, e
[Personagens top-down](top-down.md) trata de um personagem que olha para cima, para baixo e para os
lados.

## 1. Desenhe o sprite no Aseprite

1. Crie um sprite do tamanho do personagem: *File > New* com **32x32**, por exemplo.
2. Desenhe o personagem olhando para a direita. O jogo o espelha para olhar para a esquerda.
3. Adicione frames (*Frame > New Frame*) e defina quanto tempo cada um dura em
   *Frame > Frame Properties*.
4. Selecione os frames de uma animação na timeline e crie uma tag para eles
   (*Frame > Tags > New Tag*). Dê à tag o nome da ação e acrescente `_loop` no fim se ela ficar em
   loop: `idle_loop`, `run_loop`. Uma ação reproduzida uma vez só, como `jump`, fica sem sufixo.
   Crie uma tag para cada animação.
5. Salve o arquivo dentro do projeto Godot, por exemplo `characters/hero.aseprite`.

## 2. Confira a importação no Godot

1. Volte para o editor do Godot. Ele percebe o arquivo novo e o importa.
2. Selecione o arquivo no dock FileSystem e abra o dock **Import**: `grid/directions` em `none`
   importa o frame inteiro, uma animação por tag. Se o dock Import mostrar outro importador, escolha
   **Import As: Dot Aseprite SpriteFrames**. Um sprite que não é animado de jeito nenhum, como uma
   sombra, um prop ou uma página de tileset, fica melhor com *Import As: Dot Aseprite Texture*,
   descrito em [Importando como textura](importing.md#importando-como-textura).
3. Problemas (Aseprite não encontrado, uma tag que gera um nome já usado e assim por diante)
   aparecem no painel **Output**, começando com `[Dot Aseprite Importer]`.

## 3. Reproduza as animações com um AnimatedSprite2D

1. Crie uma cena com um **Node2D** como raiz (`Level`). Adicione um **StaticBody2D** com um
   **CollisionShape2D** cuja forma seja um *New RectangleShape2D* largo, como chão, e salve a cena
   como `level.tscn`.
2. Adicione um **CharacterBody2D** (`Player`) acima do chão, com um **AnimatedSprite2D** e um
   **CollisionShape2D** (*New RectangleShape2D*) como filhos.
3. Arraste `hero.aseprite` do dock FileSystem para a propriedade **Sprite Frames** do
   AnimatedSprite2D. O painel SpriteFrames, embaixo, agora lista `idle`, `jump` e `run`: uma
   animação por tag, sem o sufixo `_loop`.
4. Adicione um script ao `Player`:

   ```gdscript
   extends CharacterBody2D

   const SPEED := 120.0
   const JUMP_VELOCITY := -300.0

   @onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D


   func _physics_process(delta: float) -> void:
   	if not is_on_floor():
   		velocity += get_gravity() * delta
   	elif Input.is_action_just_pressed("ui_accept"):
   		velocity.y = JUMP_VELOCITY
   	var input := Input.get_axis("ui_left", "ui_right")
   	velocity.x = input * SPEED
   	move_and_slide()
   	if input != 0.0:
   		_sprite.flip_h = input < 0.0
   	if not is_on_floor():
   		_sprite.play("jump")
   	elif input != 0.0:
   		_sprite.play("run")
   	else:
   		_sprite.play("idle")
   ```

5. Rode a cena. As setas correm para a esquerda e para a direita, com o sprite espelhado pelo
   `flip_h`, e *Enter* ou *Espaço* pulam. `jump` não fica em loop, então para no último frame até o
   personagem tocar o chão.

## 4. Altere a arte

Edite o sprite no Aseprite, salve e volte para o Godot: o arquivo é importado de novo e as animações
no editor são atualizadas. Um jogo que já está rodando mantém as animações antigas até ser
reiniciado. Uma tag nova gera animações novas. Uma tag renomeada renomeia suas animações, então
atualize os nomes no seu código.

## 5. Opcional: controle o sprite com um AnimationPlayer

Vincule um AnimationPlayer quando outras coisas precisarem acompanhar os frames: um som de passo no
frame em que o pé toca o chão, uma hitbox durante um ataque, uma chamada de método no fim de uma
animação.

1. Adicione um **AnimationPlayer** como filho do `Player`.
2. Selecione o AnimatedSprite2D. No Inspector, em **AnimatedSprite2D**, clique em **Assign...** na
   seção **AnimationPlayer** e escolha o AnimationPlayer. A seção informa quantas animações
   sincronizou, e o AnimationPlayer agora tem `idle`, `jump` e `run`.
3. Salve a cena. As animações ficam em `level_animations.tres`, ao lado de `level.tscn`.
4. No script, adicione `@onready var _player: AnimationPlayer = $AnimationPlayer` e troque
   `_sprite.play(...)` por `_player.play(...)`: os nomes são os mesmos. Continue definindo
   `_sprite.flip_h`, que não faz parte das animações. Se você ativou *Autoplay on Load* no painel
   SpriteFrames, desative.
5. Selecione o AnimationPlayer, abra uma animação no painel **Animation** e adicione suas próprias
   trilhas (áudio, chamadas de método, propriedades de outros nós). Elas são mantidas quando as
   animações são sincronizadas de novo depois que você altera o sprite no Aseprite.

## Experimente a demo

O repositório é, ele mesmo, um projeto Godot. Abra o `project.godot` dele (com
[o executável do Aseprite](importing.md#executável-do-aseprite) configurado) e rode:
`examples/main.tscn` mostra `examples/retro-top-down-character.aseprite` andando para baixo,
reproduzido pelo AnimationPlayer. Ele é um [personagem top-down](top-down.md), importado com
`grid/directions` em `3x3`: dez tags (`walk_loop`, `slash`, `swim_loop`, ...) desenhadas olhando
para cima, para baixo, para a esquerda e para a direita (escalar só para cima e para baixo), com as
células das diagonais vazias.

A mesma cena também mostra o importador de textura: `examples/shadow.aseprite` é importado com
*Import As: Dot Aseprite Texture* e desenhado por um Sprite2D comum, e o
`examples/tileset.aseprite`, importado do mesmo jeito, é a textura de um TileSetAtlasSource cujos
tiles são pintados num TileMapLayer. A demo só existe no repositório, não no download da Asset
Library.
